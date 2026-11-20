#!/usr/bin/env bash
#
# Tests for campsite.sh. Builds throwaway repos under a temp dir, stubs the
# GitHub CLI, and asserts the outcome of every path.
#
# Run:  ./campsite.test.sh
#
# Each case asserts the exit status (0 CLEANED / 10 PARTIAL / 20 DEFERRED /
# 1 error) and, where it matters, that work which should have survived did.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAMPSITE="$SCRIPT_DIR/campsite.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/campsite-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0

ok() {
	PASS=$((PASS + 1))
	printf '  ok    %s\n' "$1"
}

no() {
	FAIL=$((FAIL + 1))
	printf '  FAIL  %s\n' "$1"
	[ -n "${2:-}" ] && printf '        %s\n' "$2"
	# Must return 0: callers use `cond && no "..." || ok "..."`, so a non-zero
	# return here would run the ok arm too and print both for one assertion.
	return 0
}

expect_status() {
	local want="$1" got="$2" what="$3"
	if [ "$want" = "$got" ]; then
		ok "$what (exit $got)"
	else
		no "$what" "expected exit $want, got $got"
	fi
}

# A fake `gh`. Reads its answers from the environment so each test can decide
# what GitHub reports back.
make_gh_stub() {
	local dir="$1" state="$2" head_oid="$3" default_branch="${4:-main}"
	mkdir -p "$dir"
	cat >"$dir/gh" <<EOF
#!/usr/bin/env bash
# stub gh
if [ "\$1" = "repo" ]; then printf '%s\n' "$default_branch"; exit 0; fi
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
  case "\$*" in
    *headRefOid*) [ -n "$head_oid" ] && printf '%s\n' "$head_oid"; exit 0 ;;
    *state*)      [ -n "$state" ]    && printf '%s\n' "$state";    exit 0 ;;
  esac
fi
exit 1
EOF
	chmod +x "$dir/gh"
}

# A fake `git` that fails only `ls-remote`, to simulate a network blip while
# every other git call still works.
REAL_GIT="$(command -v git)"
make_git_shim_failing_lsremote() {
	local dir="$1"
	mkdir -p "$dir"
	cat >"$dir/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  [ "\$a" = "ls-remote" ] && exit 128
done
exec "$REAL_GIT" "\$@"
EOF
	chmod +x "$dir/git"
}

# Build an origin + primary clone with one feature branch.
# Echoes the primary checkout path. The caller decides how GitHub answers.
# $2 sets the default branch name — pass something other than "main" to prove a
# test isn't just agreeing with a hardcoded default.
new_repo() {
	local name="$1" trunk="${2:-main}"
	local root="$TMP_ROOT/$name"
	mkdir -p "$root"
	git init -q --bare "$root/origin.git"
	git clone -q "$root/origin.git" "$root/primary" 2>/dev/null
	(
		cd "$root/primary"
		git config user.email t@test.com
		git config user.name Test
		git config advice.detachedHead false
		git checkout -q -b "$trunk" 2>/dev/null || git branch -qm "$trunk"
		echo base >base.txt
		# Committed on the base so every branch and worktree inherits it —
		# otherwise "ignored" files are merely untracked, and any test aiming at
		# the ignored-file path would silently exercise the dirty path instead.
		printf 'node_modules/\n.env\n' >.gitignore
		git add .
		git commit -qm init
		git push -q origin "HEAD:$trunk"
		git remote set-head origin -a >/dev/null 2>&1

		git checkout -qb feature/1-work
		echo work >work.txt
		git add .
		git commit -qm "the work"
		git push -q -u origin feature/1-work
	)
	printf '%s\n' "$root/primary"
}

remote_has_branch() {
	git -C "$1" ls-remote --heads origin feature/1-work 2>/dev/null | grep -q .
}

# Simulate GitHub merging the PR: does the merge on origin, out of band, the way
# the server would — the local checkout learns nothing until it fetches.
# Simulate GitHub merging the PR, out of band, the way the server would.
# delete_remote defaults to NO: leaving the remote branch in place is what forces
# the tests to assert that campsite.sh deletes it. (Auto-delete-on-merge is
# opt-in per repo, so "still there" is also the more common real state.)
server_merge() {
	local root="$1" style="${2:-merge}" delete_remote="${3:-no}" trunk="${4:-main}"
	local sim="$root/../ghsim"
	rm -rf "$sim"
	git clone -q "$root/../origin.git" "$sim" 2>/dev/null
	(
		cd "$sim"
		git config user.email t@test.com
		git config user.name Test
		git checkout -q "$trunk"
		case "$style" in
		merge) git merge -q --no-ff -m "Merge PR #1" origin/feature/1-work ;;
		squash)
			git merge --squash -q origin/feature/1-work >/dev/null 2>&1
			git commit -qm "Squash PR #1"
			;;
		rebase)
			git cherry-pick -q origin/feature/1-work >/dev/null 2>&1
			;;
		*)
			printf 'test bug: unknown merge style "%s"\n' "$style" >&2
			exit 1
			;;
		esac
		git push -q origin "$trunk"
		[ "$delete_remote" = yes ] && git push -q origin --delete feature/1-work
		true
	) || {
		printf 'test bug: server_merge failed\n' >&2
		exit 1
	}
	rm -rf "$sim"
}

run_campsite() {
	local dir="$1" stub="$2"
	shift 2
	(cd "$dir" && PATH="$stub:$PATH" GH_BIN="$stub/gh" "$CAMPSITE" "$@" >/tmp/campsite-out.$$ 2>&1)
	local rc=$?
	OUTPUT="$(cat /tmp/campsite-out.$$)"
	rm -f /tmp/campsite-out.$$
	return $rc
}

printf '\ncampsite.sh\n\n'

# --- 1. Happy path: plain merge commit, primary checkout ----------------------
primary="$(new_repo happy)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
make_gh_stub "$TMP_ROOT/happy/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/happy/bin" --branch feature/1-work
expect_status 0 $? "happy path reports CLEANED"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	no "happy path deletes the local branch" || ok "happy path deletes the local branch"
remote_has_branch "$primary" &&
	no "happy path deletes the REMOTE branch" || ok "happy path deletes the REMOTE branch"
[ "$(cd "$primary" && git branch --show-current)" = main ] &&
	ok "happy path lands on the default branch" || no "happy path lands on the default branch"
grep -q "Leftovers" <<<"$OUTPUT" && ok "happy path prints a leftover report" ||
	no "happy path prints a leftover report"

# --- 1b. Remote already deleted server-side is reported, not treated as error --
primary="$(new_repo autodel)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge yes
make_gh_stub "$TMP_ROOT/autodel/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/autodel/bin" --branch feature/1-work
expect_status 0 $? "auto-deleted remote still reports CLEANED"
grep -q "already gone" <<<"$OUTPUT" && ok "auto-deleted remote is reported as already gone" ||
	no "auto-deleted remote is reported as already gone"

# --- 2. Squash merge: -d refuses, -D is justified by the tip proof ------------
primary="$(new_repo squash)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" squash no
make_gh_stub "$TMP_ROOT/squash/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/squash/bin" --branch feature/1-work
expect_status 0 $? "squash merge reports CLEANED"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	no "squash merge deletes the local branch" || ok "squash merge deletes the local branch"
remote_has_branch "$primary" &&
	no "squash merge deletes the remote branch" || ok "squash merge deletes the remote branch"

# --- 2b. Rebase merge -------------------------------------------------------
primary="$(new_repo rebase)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" rebase no
make_gh_stub "$TMP_ROOT/rebase/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/rebase/bin" --branch feature/1-work
expect_status 0 $? "rebase merge reports CLEANED"

# --- 3. P1: dirty checkout must not strand the branch ------------------------
# Three reviewers found the prose version deleted the remote while the local
# delete refused, leaving a branch with no upstream.
primary="$(new_repo dirty)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
make_gh_stub "$TMP_ROOT/dirty/bin" MERGED "$sha"
echo "uncommitted" >"$primary/scratch.txt"
run_campsite "$primary" "$TMP_ROOT/dirty/bin" --branch feature/1-work
expect_status 10 $? "dirty checkout reports PARTIAL"
[ -f "$primary/scratch.txt" ] && ok "dirty checkout preserves uncommitted work" ||
	no "dirty checkout preserves uncommitted work"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	ok "dirty checkout keeps the local branch" || no "dirty checkout keeps the local branch"
(cd "$primary" && git ls-remote --exit-code --heads origin feature/1-work >/dev/null 2>&1) &&
	ok "dirty checkout keeps the remote branch (no stranding)" ||
	no "dirty checkout keeps the remote branch (no stranding)"

# --- 4. Unpushed local commits must never be deleted --------------------------
primary="$(new_repo unpushed)"
sha="$(cd "$primary" && git rev-parse feature/1-work)" # what GitHub merged
server_merge "$primary" merge yes
(cd "$primary" && echo extra >extra.txt && git add . && git commit -qm "never pushed")
make_gh_stub "$TMP_ROOT/unpushed/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/unpushed/bin" --branch feature/1-work
expect_status 10 $? "unpushed commits report PARTIAL"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	ok "unpushed commits survive" || no "unpushed commits survive"
grep -q "not part of the merge" <<<"$OUTPUT" && ok "unpushed commits are explained" ||
	no "unpushed commits are explained"

# --- 5. PR not merged yet -> DEFERRED ----------------------------------------
primary="$(new_repo deferred)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
make_gh_stub "$TMP_ROOT/deferred/bin" OPEN "$sha"
run_campsite "$primary" "$TMP_ROOT/deferred/bin" --branch feature/1-work
expect_status 20 $? "open PR reports DEFERRED"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	ok "open PR keeps the branch" || no "open PR keeps the branch"

# --- 6. Clean worktree is removed --------------------------------------------
primary="$(new_repo wt)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
(cd "$primary" && git checkout -q main && git worktree add -q "$TMP_ROOT/wt/tree" feature/1-work)
server_merge "$primary" merge yes
make_gh_stub "$TMP_ROOT/wt/bin" MERGED "$sha"
run_campsite "$TMP_ROOT/wt/tree" "$TMP_ROOT/wt/bin" --branch feature/1-work
expect_status 0 $? "clean worktree reports CLEANED"
[ -d "$TMP_ROOT/wt/tree" ] && no "clean worktree is removed" || ok "clean worktree is removed"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	no "worktree path deletes the branch" || ok "worktree path deletes the branch"

# --- 7. Dirty worktree is left alone, and says what's in it -------------------
primary="$(new_repo wtdirty)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
(cd "$primary" && git checkout -q main && git worktree add -q "$TMP_ROOT/wtdirty/tree" feature/1-work)
server_merge "$primary" merge no
make_gh_stub "$TMP_ROOT/wtdirty/bin" MERGED "$sha"
echo "in progress" >"$TMP_ROOT/wtdirty/tree/wip.txt"
run_campsite "$TMP_ROOT/wtdirty/tree" "$TMP_ROOT/wtdirty/bin" --branch feature/1-work
expect_status 10 $? "dirty worktree reports PARTIAL"
[ -d "$TMP_ROOT/wtdirty/tree" ] && ok "dirty worktree survives" || no "dirty worktree survives"
[ -f "$TMP_ROOT/wtdirty/tree/wip.txt" ] && ok "dirty worktree keeps its work" ||
	no "dirty worktree keeps its work"
grep -q "wip.txt" <<<"$OUTPUT" && ok "dirty worktree names the uncommitted file" ||
	no "dirty worktree names the uncommitted file"

# --- 8. Paths containing spaces ----------------------------------------------
# The space must be in the PRIMARY checkout's path, not just the worktree's:
# the code parses the primary path out of `git worktree list`, so that is the
# spot where naive whitespace splitting would truncate. (Matt has real repos
# like ~/Development/2nd Brain.)
primary="$(new_repo "space dir")"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
case "$primary" in
*" "*) ok "fixture: the primary checkout path contains a space" ;;
*) no "fixture: the primary checkout path contains a space" "$primary" ;;
esac
(cd "$primary" && git checkout -q main &&
	git worktree add -q "$TMP_ROOT/space dir/tree with space" feature/1-work)
server_merge "$primary" merge no
make_gh_stub "$TMP_ROOT/space dir/bin" MERGED "$sha"
run_campsite "$TMP_ROOT/space dir/tree with space" "$TMP_ROOT/space dir/bin" --branch feature/1-work
expect_status 0 $? "spaces in the primary and worktree paths report CLEANED"
[ -d "$TMP_ROOT/space dir/tree with space" ] && no "worktree with a space is removed" ||
	ok "worktree with a space is removed"

# --- 8b. A worktree git refuses to release is reported, never forced ----------
# Locking is the simplest realistic refusal. Without it, every guard above fires
# first and `git worktree remove` only ever sees a clean worktree — so its
# refusal path, and the decision not to pass --force, would be untested.
primary="$(new_repo wtlocked)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
(cd "$primary" && git checkout -q main &&
	git worktree add -q "$TMP_ROOT/wtlocked/tree" feature/1-work &&
	git worktree lock "$TMP_ROOT/wtlocked/tree")
server_merge "$primary" merge no
make_gh_stub "$TMP_ROOT/wtlocked/bin" MERGED "$sha"
run_campsite "$TMP_ROOT/wtlocked/tree" "$TMP_ROOT/wtlocked/bin" --branch feature/1-work
expect_status 10 $? "a worktree git will not release reports PARTIAL"
[ -d "$TMP_ROOT/wtlocked/tree" ] && ok "the locked worktree survives" ||
	no "the locked worktree survives"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	ok "locked worktree: its branch is kept" || no "locked worktree: its branch is kept"

# --- 9. P1: default branch must be resolvable without origin/HEAD -------------
# The default branch here is 'trunk', not 'main', so this test can tell a real
# fallback from a hardcoded value — with 'main' fixtures the two coincide and
# the test passes either way.
primary="$(new_repo nohead trunk)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no trunk
(cd "$primary" && git symbolic-ref -d refs/remotes/origin/HEAD 2>/dev/null)
make_gh_stub "$TMP_ROOT/nohead/bin" MERGED "$sha" trunk
run_campsite "$primary" "$TMP_ROOT/nohead/bin" --branch feature/1-work
expect_status 0 $? "missing origin/HEAD falls back to the GitHub default branch"
[ "$(cd "$primary" && git branch --show-current)" = trunk ] &&
	ok "non-'main' default branch is honoured" || no "non-'main' default branch is honoured"

# --- 10. Empty branch name is refused ----------------------------------------
primary="$(new_repo empty)"
make_gh_stub "$TMP_ROOT/empty/bin" MERGED abc123
run_campsite "$primary" "$TMP_ROOT/empty/bin" --branch ""
expect_status 1 $? "empty --branch is refused"
run_campsite "$primary" "$TMP_ROOT/empty/bin"
expect_status 1 $? "missing --branch is refused"

# --- 11. Refuses to clean up the default branch itself ------------------------
primary="$(new_repo selfharm)"
make_gh_stub "$TMP_ROOT/selfharm/bin" MERGED abc123
run_campsite "$primary" "$TMP_ROOT/selfharm/bin" --branch main
expect_status 1 $? "refuses to clean up the default branch"

# --- 12. Non-default branch that is clean but parked --------------------------
primary="$(new_repo parked)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
(cd "$primary" && git checkout -qb unrelated/other main)
make_gh_stub "$TMP_ROOT/parked/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/parked/bin" --branch feature/1-work
expect_status 10 $? "clean checkout parked on unrelated work reports PARTIAL"
[ "$(cd "$primary" && git branch --show-current)" = unrelated/other ] &&
	ok "parked checkout is not moved" || no "parked checkout is not moved"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	no "parked checkout still deletes the merged branch" ||
	ok "parked checkout still deletes the merged branch"

# --- 13. P1: remote moved after the merge must not be deleted ----------------
primary="$(new_repo remoteahead)"
sha="$(cd "$primary" && git rev-parse feature/1-work)" # what GitHub merged
server_merge "$primary" merge no
# A teammate pushes to the branch after the merge; our local ref is stale.
(
	cd "$TMP_ROOT/remoteahead" && git clone -q origin.git tm 2>/dev/null && cd tm &&
		git config user.email t@test.com && git config user.name T &&
		git checkout -q feature/1-work && echo late >late.txt && git add . &&
		git commit -qm "pushed after the merge" && git push -q origin feature/1-work
)
make_gh_stub "$TMP_ROOT/remoteahead/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/remoteahead/bin" --branch feature/1-work
expect_status 10 $? "remote ahead of the merged tip reports PARTIAL"
remote_has_branch "$primary" && ok "remote ahead: the remote branch survives" ||
	no "remote ahead: the remote branch survives"
grep -q "has moved since the merge" <<<"$OUTPUT" && ok "remote ahead is explained" ||
	no "remote ahead is explained"

# --- 14. P1: no local branch + remote ahead must still not delete the remote --
primary="$(new_repo nolocal)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
(
	cd "$TMP_ROOT/nolocal" && git clone -q origin.git tm 2>/dev/null && cd tm &&
		git config user.email t@test.com && git config user.name T &&
		git checkout -q feature/1-work && echo late >late.txt && git add . &&
		git commit -qm "pushed after the merge" && git push -q origin feature/1-work
)
# Local branch gone (e.g. a previous partial run deleted it)
(cd "$primary" && git checkout -q main && git branch -qD feature/1-work)
make_gh_stub "$TMP_ROOT/nolocal/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/nolocal/bin" --branch feature/1-work
expect_status 10 $? "absent local branch + moved remote reports PARTIAL"
remote_has_branch "$primary" &&
	ok "absent local branch: someone else's commits survive on origin" ||
	no "absent local branch: someone else's commits survive on origin"

# --- 15. P1: a failed remote lookup is not 'already gone' --------------------
primary="$(new_repo lsfail)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
make_gh_stub "$TMP_ROOT/lsfail/bin" MERGED "$sha"
make_git_shim_failing_lsremote "$TMP_ROOT/lsfail/bin"
run_campsite "$primary" "$TMP_ROOT/lsfail/bin" --branch feature/1-work
expect_status 10 $? "unreachable origin reports PARTIAL, not CLEANED"
grep -q "could not reach origin" <<<"$OUTPUT" &&
	ok "unreachable origin is reported honestly" || no "unreachable origin is reported honestly"
remote_has_branch "$primary" && ok "unreachable origin leaves the remote branch" ||
	no "unreachable origin leaves the remote branch"

# --- 16. P1: a worktree's gitignored .env must never be silently destroyed ----
primary="$(new_repo ignored)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
(cd "$primary" && git checkout -q main && git worktree add -q "$TMP_ROOT/ignored/tree" feature/1-work)
echo "SUPABASE_SERVICE_KEY=live-secret" >"$TMP_ROOT/ignored/tree/.env"
# Guard the guard: this must be an IGNORED file, not an untracked one, or the
# test would pass via the dirty-worktree path and never reach the ignore check.
[ -z "$(git -C "$TMP_ROOT/ignored/tree" status --short)" ] &&
	ok "fixture: the .env reads as ignored, not untracked" ||
	no "fixture: the .env reads as ignored, not untracked" "$(git -C "$TMP_ROOT/ignored/tree" status --short)"
server_merge "$primary" merge no
make_gh_stub "$TMP_ROOT/ignored/bin" MERGED "$sha"
run_campsite "$TMP_ROOT/ignored/tree" "$TMP_ROOT/ignored/bin" --branch feature/1-work
expect_status 10 $? "worktree holding an ignored .env reports PARTIAL"
[ -f "$TMP_ROOT/ignored/tree/.env" ] && ok "the .env secret survives" || no "the .env secret survives"
grep -q "\.env" <<<"$OUTPUT" && ok "the .env is named in the report" || no "the .env is named in the report"

# --- 17. Ignored build directories are not a reason to refuse ----------------
primary="$(new_repo ignoredir)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
(cd "$primary" && git checkout -q main && git worktree add -q "$TMP_ROOT/ignoredir/tree" feature/1-work)
mkdir -p "$TMP_ROOT/ignoredir/tree/node_modules/pkg"
echo junk >"$TMP_ROOT/ignoredir/tree/node_modules/pkg/index.js"
[ -z "$(git -C "$TMP_ROOT/ignoredir/tree" status --short)" ] &&
	ok "fixture: node_modules reads as ignored, not untracked" ||
	no "fixture: node_modules reads as ignored, not untracked"
server_merge "$primary" merge no
make_gh_stub "$TMP_ROOT/ignoredir/bin" MERGED "$sha"
run_campsite "$TMP_ROOT/ignoredir/tree" "$TMP_ROOT/ignoredir/bin" --branch feature/1-work
expect_status 0 $? "worktree with only node_modules/ still reports CLEANED"
[ -d "$TMP_ROOT/ignoredir/tree" ] && no "build-only worktree is removed" ||
	ok "build-only worktree is removed"

# --- 18. A same-named tag must not stand in for the branch -------------------
primary="$(new_repo tagdupe)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
# Tag pointing at the merged tip, while the branch carries an unpushed commit.
(cd "$primary" && git tag feature/1-work "$sha" 2>/dev/null &&
	echo more >more.txt && git add . && git commit -qm "unpushed work")
make_gh_stub "$TMP_ROOT/tagdupe/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/tagdupe/bin" --branch feature/1-work
expect_status 10 $? "a same-named tag does not satisfy the proof"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	ok "tag case: the unpushed commit survives" || no "tag case: the unpushed commit survives"

# --- 19. Requirement 4: leftovers are named, not just headed ------------------
# The report must list what it left alone. Asserting only that the "Leftovers"
# header prints would pass even if the reporting were entirely broken.
primary="$(new_repo leftovers)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
(
	cd "$primary"
	# A stash to report.
	echo scratch >stashme.txt && git add stashme.txt && git stash -q
	# A branch whose upstream is gone, to report.
	git branch -q stale/orphan main
	git push -q origin stale/orphan
	git branch -q --set-upstream-to=origin/stale/orphan stale/orphan 2>/dev/null
	git push -q origin --delete stale/orphan
)
make_gh_stub "$TMP_ROOT/leftovers/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/leftovers/bin" --branch feature/1-work
expect_status 0 $? "leftovers present still reports CLEANED"
grep -q "stash: " <<<"$OUTPUT" && ok "the stash is named in the report" ||
	no "the stash is named in the report" "$OUTPUT"
grep -q "stale/orphan" <<<"$OUTPUT" && ok "the stale branch is named in the report" ||
	no "the stale branch is named in the report" "$OUTPUT"

# --- 20. Dirty files are named in the report, not just counted ---------------
primary="$(new_repo dirtyreport)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
echo wip >"$primary/unfinished.txt"
make_gh_stub "$TMP_ROOT/dirtyreport/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/dirtyreport/bin" --branch feature/1-work
expect_status 10 $? "dirty checkout reports PARTIAL"
grep -q "unfinished.txt" <<<"$OUTPUT" && ok "the dirty file is named in the report" ||
	no "the dirty file is named in the report" "$OUTPUT"

# --- 21. Default branch held by another worktree ------------------------------
# Common when a long-lived worktree keeps the default branch checked out. git
# will not hand that branch to this checkout, which leaves us standing on the
# shipped branch — undeletable. Must report PARTIAL, not exit 1 with no report.
primary="$(new_repo trunkheld)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
(cd "$primary" && git worktree add -q "$TMP_ROOT/trunkheld/mainwt" main)
make_gh_stub "$TMP_ROOT/trunkheld/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/trunkheld/bin" --branch feature/1-work
expect_status 10 $? "default branch held elsewhere reports PARTIAL, not an error"
grep -q "another worktree" <<<"$OUTPUT" && ok "default branch held elsewhere is explained" ||
	no "default branch held elsewhere is explained" "$OUTPUT"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	ok "default branch held elsewhere: the branch is kept" ||
	no "default branch held elsewhere: the branch is kept"
remote_has_branch "$primary" &&
	ok "default branch held elsewhere: the remote is kept (no stranding)" ||
	no "default branch held elsewhere: the remote is kept (no stranding)"

# --- 22. Detached HEAD is handled without confusion ---------------------------
primary="$(new_repo detached)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
(cd "$primary" && git checkout -q --detach HEAD)
make_gh_stub "$TMP_ROOT/detached/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/detached/bin" --branch feature/1-work
expect_status 10 $? "detached HEAD reports PARTIAL"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	no "detached HEAD still deletes the merged branch" ||
	ok "detached HEAD still deletes the merged branch"

# --- 23. Uncommitted work elsewhere does not keep a merged branch alive -------
# Case 3 covers standing ON the shipped branch with a dirty tree, where nothing
# can move. Here the checkout is on the default branch with a half-written file
# and the shipped branch is not checked out at all: the tip proof holds, so the
# branch and its remote go; only the fast-forward of the default branch is
# skipped. /cleanup-branches relies on this — the primary checkout is routinely
# dirty mid-session.
primary="$(new_repo dirtyelsewhere)"
sha="$(cd "$primary" && git rev-parse feature/1-work)"
server_merge "$primary" merge no
(cd "$primary" && git checkout -q main && echo "half-written" >draft.txt)
make_gh_stub "$TMP_ROOT/dirtyelsewhere/bin" MERGED "$sha"
run_campsite "$primary" "$TMP_ROOT/dirtyelsewhere/bin" --branch feature/1-work
expect_status 10 $? "dirty checkout not on the branch reports PARTIAL (default branch not refreshed)"
(cd "$primary" && git show-ref --verify --quiet refs/heads/feature/1-work) &&
	no "dirty checkout elsewhere: the merged branch is still deleted" ||
	ok "dirty checkout elsewhere: the merged branch is still deleted"
remote_has_branch "$primary" &&
	no "dirty checkout elsewhere: the merged remote branch is still deleted" ||
	ok "dirty checkout elsewhere: the merged remote branch is still deleted"
[ -f "$primary/draft.txt" ] && ok "dirty checkout elsewhere: the uncommitted file survives" ||
	no "dirty checkout elsewhere: the uncommitted file survives"
[ "$(cd "$primary" && git rev-parse main)" != "$(cd "$primary" && git rev-parse origin/main)" ] &&
	ok "dirty checkout elsewhere: the default branch is not pulled over uncommitted work" ||
	no "dirty checkout elsewhere: the default branch is not pulled over uncommitted work"
grep -q "not refreshed" <<<"$OUTPUT" && ok "dirty checkout elsewhere: the skipped refresh is explained" ||
	no "dirty checkout elsewhere: the skipped refresh is explained" "$OUTPUT"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
