#!/usr/bin/env bash
#
# campsite.sh — leave the repo clean after a pull request merges.
#
# Deletes the merged branch locally and on origin, removes the worktree the work
# was done in, returns the checkout to a freshly pulled default branch, and
# reports what it deliberately left alone. Implements GitHub issue #125.
#
# The rule that governs every decision: never destroy anything that isn't already
# safe on GitHub. When anything looks unsafe, this leaves it alone and says so
# rather than guessing. Each ref is deleted only against its own proof — the local
# branch against the local tip, the remote branch against the tip origin actually
# holds — because either can differ from the other. It never uses --force on a
# worktree, and it never treats a failed lookup as an absent branch.
#
# Usage:  campsite.sh --branch <branch-name>
#
# Exit:   0  CLEANED   branch gone (local + origin), checkout on a fresh default branch
#         10 PARTIAL   something was deliberately left behind; see the report
#         20 DEFERRED  the PR hasn't merged yet, so there is nothing to clean up
#         1  error     bad usage, or a precondition that can't be established
#
# Testing: set GH_BIN to a stub executable to avoid live GitHub calls.

set -euo pipefail

GH_BIN="${GH_BIN:-gh}"

usage() {
	cat >&2 <<'EOF'
usage: campsite.sh --branch <branch-name>

Cleans up after <branch-name>'s pull request has merged.

exit codes: 0 CLEANED | 10 PARTIAL | 20 DEFERRED | 1 error
EOF
	exit 1
}

branch=""
while [ $# -gt 0 ]; do
	case "$1" in
	--branch)
		branch="${2:-}"
		shift 2 || usage
		;;
	-h | --help) usage ;;
	*)
		printf 'campsite: unknown argument: %s\n' "$1" >&2
		usage
		;;
	esac
done

# An empty branch name is the single most dangerous input here: it turns the
# remote-branch lookup into a false "already deleted" result. Refuse it up front
# so no later command can ever run with one.
[ -n "$branch" ] || {
	printf 'campsite: --branch is required and must not be empty\n' >&2
	usage
}

die() {
	printf 'campsite: %s\n' "$1" >&2
	exit 1
}

status="CLEANED"
actions=()
notes=()

did() { actions+=("$1"); }

# Record something left behind. Any call to this downgrades the run to PARTIAL.
left() {
	status="PARTIAL"
	notes+=("$1")
}

# Print the report and exit with the code matching the status. Every path that
# reaches a CLEANED or PARTIAL outcome ends here. The DEFERRED exit and the die()
# paths report for themselves and do not come through here.
finish() {
	git fetch --prune origin >/dev/null 2>&1 || true

	printf '\n=== CAMPSITE: %s ===\n' "$status"

	if [ ${#actions[@]} -gt 0 ]; then
		printf '\nDone:\n'
		printf '  %s\n' "${actions[@]}"
	fi

	if [ ${#notes[@]} -gt 0 ]; then
		printf '\nLeft alone (deliberately):\n'
		printf '  %s\n' "${notes[@]}"
	fi

	printf '\nLeftovers (not touched):\n'
	local found=0

	local stashes
	stashes="$(git stash list 2>/dev/null || true)"
	if [ -n "$stashes" ]; then
		found=1
		printf '%s\n' "$stashes" | while IFS= read -r line; do
			printf '  stash: %s\n' "$line"
		done
	fi

	local gone
	gone="$(git branch -vv 2>/dev/null | grep ': gone\]' || true)"
	if [ -n "$gone" ]; then
		found=1
		printf '%s\n' "$gone" | while IFS= read -r line; do
			printf '  stale branch:%s\n' "$line"
		done
	fi

	local dirty
	dirty="$(git status --short 2>/dev/null || true)"
	if [ -n "$dirty" ]; then
		found=1
		printf '%s\n' "$dirty" | while IFS= read -r line; do
			printf '  dirty: %s\n' "$line"
		done
	fi

	[ "$found" -eq 1 ] || printf '  none\n'

	case "$status" in
	CLEANED) exit 0 ;;
	*) exit 10 ;;
	esac
}

# --- Establish the facts -----------------------------------------------------

git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

# Resolve the default branch. The -z guard is load-bearing: piping through sed
# masks git's exit code, so testing the pipeline's status here would silently
# accept an empty answer and every later checkout would fail.
default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
if [ -z "$default_branch" ]; then
	default_branch="$("$GH_BIN" repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)"
fi
[ -n "$default_branch" ] || die "could not determine the default branch (is origin/HEAD set?)"

[ "$branch" != "$default_branch" ] || die "refusing to clean up the default branch itself"

pr_state="$("$GH_BIN" pr view "$branch" --json state -q .state 2>/dev/null || true)"
[ -n "$pr_state" ] || die "no pull request found for branch '$branch'"

if [ "$pr_state" != "MERGED" ]; then
	printf '\n=== CAMPSITE: DEFERRED ===\n\n'
	printf "  The pull request for '%s' is %s, not MERGED.\n" "$branch" "$pr_state"
	printf '  Nothing to clean up yet. Re-run once it merges.\n'
	exit 20
fi

# The tip of the branch as GitHub recorded it when the PR merged.
#
# This is the head-branch tip GitHub consumed, NOT the resulting merge commit,
# and not necessarily an ancestor of the default branch — squash and rebase
# rewrite the commits. What it proves is narrower but exactly what's needed: if
# the local tip equals it, every local commit was included in what GitHub
# merged, so deleting the branch loses nothing.
merged_sha="$("$GH_BIN" pr view "$branch" --json headRefOid -q .headRefOid 2>/dev/null || true)"
[ -n "$merged_sha" ] || die "could not read the merged tip of '$branch' from GitHub"

# --- Prove nothing would be lost ---------------------------------------------

if git show-ref --verify --quiet "refs/heads/$branch"; then
	# Fully-qualified: a bare name would let a same-named tag win over the branch,
	# since rev-parse searches refs/tags before refs/heads.
	local_head="$(git rev-parse "refs/heads/$branch")"
	if [ "$local_head" != "$merged_sha" ]; then
		left "branch '$branch' has local commits that were not part of the merge — branch and remote left alone"
		notes+=("    local tip:  $local_head")
		notes+=("    merged tip: $merged_sha")
		finish
	fi
fi

# --- Remove the worktree, if the work happened in one -------------------------

git_dir="$(git rev-parse --path-format=absolute --git-dir)"
common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"

if [ "$git_dir" != "$common_dir" ]; then
	old_path="$(pwd)"

	# Read the worktree's state while still standing in it — after the cd below,
	# this checkout is no longer the one being described.
	wt_dirty="$(git status --short)"
	if [ -n "$wt_dirty" ]; then
		left "worktree at $old_path has uncommitted work — left in place, along with branch '$branch':"
		while IFS= read -r line; do notes+=("    $line"); done <<<"$wt_dirty"
		finish
	fi

	# `git worktree remove` refuses on untracked files but deletes ignored ones
	# without complaint, and ignored files are by definition not on GitHub — a
	# .env holding a live secret exists nowhere else. Refuse on loose ignored
	# files; whole ignored directories (node_modules/, dist/) collapse to a
	# single trailing-slash entry and are build output worth removing.
	wt_ignored="$(git status --porcelain --ignored=traditional 2>/dev/null | sed -n 's|^!! ||p' || true)"
	wt_ignored_files="$(printf '%s' "$wt_ignored" | grep -v '/$' || true)"
	if [ -n "$wt_ignored_files" ]; then
		left "worktree at $old_path holds ignored files that are not on GitHub and would be destroyed — left in place, along with branch '$branch':"
		while IFS= read -r line; do notes+=("    $line"); done <<<"$wt_ignored_files"
		finish
	fi

	# sed, not awk: worktree paths contain spaces (e.g. ~/Development/2nd Brain)
	# and splitting on whitespace would truncate the path.
	primary="$(git worktree list --porcelain | sed -n '1s|^worktree ||p')"
	if [ -z "$primary" ] || [ ! -d "$primary" ]; then
		left "could not locate the primary checkout — worktree at $old_path left in place"
		finish
	fi

	cd "$primary"

	# No --force, ever. A refusal here means the worktree still holds something
	# git considers worth protecting; that is a report, not an obstacle.
	if git worktree remove "$old_path" 2>/dev/null; then
		did "removed worktree $old_path"
	else
		left "worktree at $old_path could not be removed cleanly — left in place, along with branch '$branch'"
		finish
	fi
fi

# --- Land on the default branch ----------------------------------------------

dest="$(pwd)"
current="$(git branch --show-current 2>/dev/null || true)"
dirty="$(git status --short)"

if [ -n "$dirty" ] && [ "$current" = "$branch" ]; then
	# Uncommitted work here means we can't switch branches without dragging it
	# onto the default branch. And since we're standing on the shipped branch we
	# can't delete it either, since git refuses to delete the current branch.
	# Deleting only the remote would strand the local branch with no upstream,
	# so the correct move is to touch nothing.
	left "checkout at $dest has uncommitted work — left as-is; branch '$branch' and its remote left alone"
	finish
fi

if [ -n "$dirty" ]; then
	# Uncommitted work on some other branch, or on the default branch itself, is
	# no reason to keep a merged branch we are not standing on: the tip proof
	# above still holds. Only the switch-and-pull has to be skipped, since it
	# would drag the work along or fail on it.
	left "checkout at $dest has uncommitted work — left as-is; '$default_branch' not refreshed"
elif [ "$current" = "$branch" ] || [ "$current" = "$default_branch" ]; then
	if git checkout "$default_branch" >/dev/null 2>&1; then
		if git pull --ff-only origin "$default_branch" >/dev/null 2>&1; then
			did "checked out $default_branch and pulled"
		else
			left "'$default_branch' could not be fast-forwarded — left at its current commit"
		fi
	else
		# Most often: the default branch is checked out in another worktree, so
		# git won't hand it to this one. That leaves us standing on the shipped
		# branch, which git also won't let us delete — and deleting only the
		# remote would strand it. A real state to report, not an error.
		left "could not switch to '$default_branch' — it may be checked out in another worktree; branch '$branch' and its remote left alone"
		finish
	fi
else
	# Clean, but parked on unrelated work. Moving it would be a surprise; the
	# branch can still be deleted safely from here since we aren't standing on it.
	left "checkout at $dest is on unrelated branch '$current' — left there; '$default_branch' not refreshed"
fi

# --- Delete the merged branch ------------------------------------------------

if git show-ref --verify --quiet "refs/heads/$branch"; then
	# -D is required, not a shortcut: squash and rebase merges rewrite the
	# commits, so -d reports "not fully merged" even though the work is safely
	# on the default branch. It's justified here only because the tip comparison
	# above proved every local commit was in what GitHub merged.
	if git branch -d "$branch" >/dev/null 2>&1; then
		did "deleted local branch '$branch'"
	elif git branch -D "$branch" >/dev/null 2>&1; then
		did "deleted local branch '$branch' (squash/rebase merge)"
	else
		left "local branch '$branch' could not be deleted"
		finish
	fi
fi

# The remote branch needs its own proof. The local comparison above says nothing
# about what origin holds: the local branch may not exist here at all, or someone
# may have pushed to the branch after the merge. Ask origin what the ref actually
# points at, and only delete it if that is exactly what GitHub merged.
#
# `ls-remote` (without --exit-code) exits 0 with no output when the ref is absent,
# and non-zero only on a real failure — unreachable host, auth, bad remote. Those
# must never be read as "already gone": that would report CLEANED while the remote
# branch quietly survives.
if remote_line="$(git ls-remote --heads origin "$branch" 2>/dev/null)"; then
	if [ -z "$remote_line" ]; then
		did "remote branch origin/$branch was already gone"
	else
		remote_sha="${remote_line%%$'\t'*}"
		if [ "$remote_sha" = "$merged_sha" ]; then
			if git push origin --delete "$branch" >/dev/null 2>&1; then
				did "deleted remote branch origin/$branch"
			else
				left "remote branch origin/$branch could not be deleted"
			fi
		else
			left "origin/$branch has moved since the merge — remote branch left alone"
			notes+=("    origin now: $remote_sha")
			notes+=("    merged:     $merged_sha")
		fi
	fi
else
	left "could not reach origin to check '$branch' — remote branch left alone"
fi

finish
