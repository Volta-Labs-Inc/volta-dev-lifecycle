---
name: ship-it
version: 1.1.0
description: "Use when the user asks to ship completed local code changes: verify branch safety, run build/tests, select the commit file scope automatically, draft the commit message, update changelog when appropriate, push the branch, create a GitHub PR, review the PR and fix the defects the scope already decides, get its checks green, automatically merge conflict-free PRs without bypassing required checks, clean up the merged branch, record live production verification on the GitHub issue, and end with an explicit verdict on whether the session is safe to archive. Do not use for reviewing or editing this skill itself."
---

# /ship-it - Commit, Push, Create PR, and Merge

Ship your completed work with proper commits, PR creation, and cleanup guidance. Before merging,
it reviews the pull request, fixes the defects it finds and gets the checks green, and asks you
about any choice the scope leaves open (Step 10A). Once checks pass, it merges the pull request into the default branch itself; if that branch has no required
reviews or checks and the user doesn't administer the repository, it says so and asks before
merging (Step 11). Every run ends
by telling the user, in one line, whether this session is safe to archive (Step 16).

## Usage

```
/ship-it
/ship-it "fix(auth): preserve login redirect"
```

No arguments - operates on current branch and drafts the commit message from the diff.

Optional argument - use as the starting commit message. The final message is reported but does not require separate approval.

---

## Pre-Conditions

**This command will STOP if:**
- You're on `main` or the repository's actual default branch
- Build fails
- There is no issue work to commit, no unshipped branch work, and no open or merged PR to resume (classify the state in Step 1 first)
- The security gate in Step 5 comes back `BLOCKED` and the user has not waived it

A stop still ends with the Step 16 archive verdict, as the last line of the reply.

---

## Workflow Steps

Follow the state-specific route in Step 1. Steps 3–4 select checks; Step 7 runs them after all
content changes. A failed required gate stops the dependent action. Complete safe, independent
preparation before requesting any missing approval; an optional skipped step is not a failure.

### Step 1: Verify Branch and Classify Shipping State

```bash
current_branch=$(git branch --show-current)
default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
```

Stop on detached HEAD, an unresolved default branch, or a checkout on `main` or the actual
default branch. Report the branch and use `/orchestrate <issue>` (its `/start-work` workers prepare a feature
branch).

Read status, the full branch history relative to the default branch, the remote branch tip,
and any PR for this branch. Capture the repository, branch, PR URL/state, and commit IDs for
later steps. A clean working tree does not mean there is nothing to ship. Treat only a confirmed
absence as no PR; an authentication or network error is not permission to create another one.

| Observed state | Route |
|---|---|
| Uncommitted issue work, with no merged PR for this branch | Steps 2–11; reuse an existing open PR if present. |
| Clean issue scope with unshipped commits, no PR | Steps 2–7 to inspect the full branch and verify it; skip an empty commit, push if needed, then create the PR. |
| Open PR, including a clean working tree | Steps 2–7 to establish the current scope and proof; commit/push only new issue work, reuse the PR, then resume Step 10A. |
| Merged PR, no new issue work or post-merge commits | Cleanup-only re-entry below. |
| Merged PR with new issue work or post-merge commits | Preserve it and report that it needs a new branch; do not ship it through the merged PR or classify it as cleanup-only. |
| No issue work, unshipped commits, or resumable PR | Report nothing to ship. |

Inspect untracked files for ownership without staging them during discovery. Unrelated files
do not create shipping work; all cleanup safeguards still apply. Never create an empty commit
or duplicate PR to make a resumed run fit the numbered steps. Re-establish applicable security
and verification evidence on resume; a pre-existing PR is not proof that those gates passed.

**Cleanup-only re-entry.** If this branch's PR has already merged and there is nothing new to ship, the only thing left to do is the campsite phase:

```bash
git status --short --untracked-files=no    # tracked changes worth shipping?
gh pr view --json state -q '.state'        # resolves the PR from the current branch
```

If there are no tracked changes, no new issue work or post-merge commits, and the PR state is `MERGED`: set `MERGE_STATUS = MERGED`, run Step 2 to capture the issue number, then jump to Step 12 (Campsite Cleanup) and continue through Steps 13–15. Do not stop with "no changes to commit" here — this is how a `DEFERRED` cleanup from an earlier run gets finished. Let `campsite.sh` establish merge containment; do not infer containment solely from an ancestry check, which can misread squash or rebase merges.

Untracked files are excluded from this test on purpose. A stray `.DS_Store` or build artifact is not work to ship, and treating it as one would block the recovery path that a `DEFERRED` report explicitly promises. Step 12 still refuses to touch a checkout with *any* uncommitted state, tracked or not, so nothing is deleted on the strength of this check alone.

Because Steps 3–11 are skipped on this path, `PR_URL`, build, test, commit, and changelog results are unknown. Re-derive the PR fields for the report:

```bash
gh pr view --json number,url,mergedAt
```

and render the skipped rows in Step 15 as `not run (cleanup-only re-entry)` rather than inventing values.

One thing is **not** skippable on this path: re-derive the Step 5 security-gate classification from the merged PR's actual content (`gh pr diff <number>`) against the same trigger list. If it is not `N/A`, Step 13's production access verification (Part A) still applies in full — the merge having already landed makes it more urgent, not less. A merged access change whose production checks never ran is an open question in production, not a finished ship.

### Step 2: Extract Issue Number from Branch

```bash
# Branch format: type/123-description
# Extract: 123
issue_number=$(git branch --show-current | grep -oE '[0-9]+' | head -1)
```

**If no issue number found:**
> "Could not detect issue number from branch name."
> Ask user: "What issue number is this work for? (or 'none')"

### Step 3: Select the Build Check

**Detect the project's build command.** Prefer the command the repository already documents or uses in CI. Check for:
1. `package.json` in the project root or relevant app directory
   - Use the matching package manager from the lockfile: `pnpm`, `yarn`, `npm`, or `bun`
   - If a `build` script exists, run it from the package/app that owns the changes
2. `Makefile` with a `build` target — use `make build`
3. Other common build systems when present, such as `deno task build`, `cargo build`, `go build ./...`, or documented project commands

Record the exact command and working directory. Run it during final verification in Step 7,
after approved changelog and public-page edits. If no build system exists, record
`Build: SKIPPED — No build step detected.`

### Step 4: Select the Test Checks

**Detect the project's test command.** Prefer the repository's documented or CI command. Check for:
1. `package.json` with a `test` script, using the matching package manager from the lockfile
2. `pytest.ini` or `pyproject.toml` — use `pytest`
3. Other test runners as appropriate, such as `deno test`, `cargo test`, `go test ./...`, or documented project commands

Select the repository-required checks and meaningful tests for the changed behavior. Reuse
existing tests when they cover it; do not create tests merely to repeat the implementation.
Record the commands, directories, and any `/start-work` baseline. Run them in Step 7 after the
final content changes. If no test system exists, record `Tests: SKIPPED — No test runner detected.`

### Step 5: Gather Changes

```bash
# Staged, unstaged, and untracked changes
git status --short

# Diff summary
git diff HEAD --stat

# Tracked file diff for commit message
git diff HEAD

# Untracked files are not included in git diff HEAD.
git ls-files --others --exclude-standard

# Everything the PR will contain: commits already on this branch PLUS the working tree.
# The security gate below runs on THIS diff. Work committed in an earlier session is
# invisible to `git diff HEAD` and must not escape the gate.
default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$default_branch" ] || default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git diff "$(git merge-base "origin/$default_branch" HEAD)" --stat
git diff "$(git merge-base "origin/$default_branch" HEAD)"
```

**Inspect untracked files before staging.** If there are untracked files, open or summarize them enough to know whether they belong in the commit. Do not stage secrets, logs, local fixtures, generated caches, or unrelated files unless the user explicitly approves them.

#### Security gate

Run this against the **full branch diff** — the merge-base diff gathered above plus uncommitted changes — before selecting the commit file scope. Work committed in an earlier session is still this ship's work; `git diff HEAD` alone does not see it. It is a gate, not a note: a change that trips it does not ship until the check is answered.

**Does this change affect who can reach data?** It does when the branch diff touches any of:

- migrations, schema, row-level security, grants, or database functions;
- a schema change that alters an object other consumers may read — renames, drops, type or constraint changes;
- storage buckets or their rules;
- authentication, sessions, or role handling;
- platform configuration that changes exposure — for example, when the project uses Supabase: the exposed-schema list, bucket public flags, an edge function's JWT verification setting, key handling in `supabase/config.toml`;
- any environment variable, key, or credential;
- a new or changed path that reads or writes a table.

**If none of these are touched:** record `SECURITY_GATE = N/A` with a one-line reason and continue.

**If any are touched:**

1. Run the repository's security review over the pending changes — the `/security-review` skill where the harness provides one. Where it does not, review the branch diff yourself against the failure modes the project's own security guidance names; when the project uses Supabase, use the shared standard, [`supabase-database-security.md`](../document/references/supabase-database-security.md). Report what was found either way.
2. Confirm the access proof exists. `/start-work` posts its proof table on the issue; read it. The stored-data-and-access obligation must show both halves — the declared audience reaching the data, and the roles it excludes not reaching it. Both halves are judged against the object's **declared audience**: "anon gets nothing" is the wrong assertion for an intentionally public read surface, and quietly waving anon access through without a recorded declaration is the wrong response. A positive-only proof is not proof, and neither is a proof run with an admin key.
3. When the project uses Supabase, read the pre-change advisor baseline from the GitHub issue comments (posted by `/start-work` Step 7) and compare item-by-item — finding names and objects, not counts. No new finding may appear. **A missing baseline is `BLOCKED`**, waivable like a missing proof — do not treat today's advisor output as clean, and do not present a post-change capture as a baseline.
4. Confirm no secret, admin key, or service-role key appears in code the browser can load, in a client-published environment variable, or inlined in the database side of the diff — migration SQL, trigger definitions, scheduled-job commands, function bodies. Grep the diff's `.sql` for JWT-shaped literals (`eyJ`) and the platform's secret-key prefixes (on Supabase, `sb_secret_`).
5. When the diff moves in the **lockdown direction** — enables protection, changes which role a view or function runs as, revokes execute, tightens storage rules, or drops or renames objects — confirm a consumer enumeration exists (in the delivery contract or the proof table) and name the consumers it checked. Locking down without knowing the readers is how a security fix becomes an outage: admin-key consumers survive row rules but break on revokes, drops, and renames. A missing enumeration is `BLOCKED` on the same terms as a missing proof.

Set `SECURITY_GATE` to `PASS`, `N/A`, or `BLOCKED`. **`BLOCKED` stops the ship.** Report which check failed and what would resolve it — do not proceed to commit and leave the finding for the PR description to mention.

A `BLOCKED` may be waived only by the user. The waiver request must name each specific check that did not run and the concrete blocker for each — no proof table on the issue, no baseline captured, no test tenant to probe with. Report the observable fact ("the issue has no proof table"), not a guess about why. Record any granted waiver, check by check, in the PR description.

**Report the selected commit scope as a progress update (do not pause for approval):**
```
Changes to be committed:
  [file list with status]

Untracked files excluded:
  [file list or "None"]

Summary:
  [X] files changed
  [Y] insertions(+)
  [Z] deletions(-)

Security gate: [PASS / N-A] — [one line: what access changed and how it was proven,
                               or why the gate does not apply]
```

Include every file that belongs to the issue work. Exclude secrets, `.env.local`, logs, caches, and unrelated dirty files. Pause only when ownership of a changed file is genuinely ambiguous (related vs unrelated) and including the wrong set would mix workstreams — one concrete question, then continue.

### Step 6: Compose Commit Message

**Analyze changes and draft conventional commit message.**

The selected file scope authorizes committing those files with a best-fit message. Do not pause for separate commit-message approval.

If the user supplied an optional commit message argument, use it as the starting point, but adjust only when the diff shows a clear mismatch. Tell the user if you changed it.

**Determine type from changes:**
| Change Type | Commit Type |
|-------------|-------------|
| New feature | `feat` |
| Bug fix | `fix` |
| Documentation | `docs` |
| Refactoring | `refactor` |
| Tests only | `test` |
| Build/deps | `build` |
| Maintenance | `chore` |

**Draft message format:**
```
type(scope): description

[Body explaining what and why]

Closes #[issue-number]
```

**Report the chosen message as a progress update:**
```
Commit message:
---
feat(reminders): add email reminder scheduling

Implement scheduled email reminders for company update forms.
- Add reminder scheduler script
- Add template variable replacement
- Add Resend email integration
- Add GitHub Actions workflow for daily execution

Closes #198

[Optional trailers only if requested or project-standard]
---
```

Continue automatically. If the user proactively edits or rejects the message before the commit runs, honor that instruction.

### Step 7: Finalize Changelog and Verify the Final Content

**Determine if changelog entry is needed based on commit type:**

| Commit Type | Changelog Action |
|-------------|------------------|
| `feat` | Always generate entry |
| `fix` (user-facing bug) | Generate entry |
| `fix` (internal/dev bug) | Skip unless the user requests an entry or the repository requires one |
| `refactor`, `chore`, `test`, `build`, `ci`, `docs` | Skip unless the user requests an entry or the repository requires one |

**If changelog entry IS needed:**

1. **Check for CHANGELOG.md** in the project root. If it exists, read it to find the insertion point.

2. **Determine insertion point:**
   - If today's date section exists → append to it
   - If today's date section doesn't exist → create new date header
   - If current month section doesn't exist → create new month header

3. **Transform the commit message into a changelog entry** written for the people who read
   the changelog, not for developers. Follow the format, headings, and voice the existing
   entries already use; when there are none, describe what changed for the user in one or two
   plain sentences. If the `changelog-writer` skill is installed and the project has no
   established style of its own, its patterns may be used.

   **For a security change**, describe it by its effect ("added validation", "tightened access
   controls") rather than naming the weakness, unless the project's own policy is to publish
   security detail in its release notes. A public changelog should not advertise a weakness
   to someone who has not yet updated.

   **That discretion applies to the public changelog only.** The commit message, PR description,
   and GitHub issue must describe the security problem accurately — what was
   exposed, to whom, and what now prevents it. Those are the records someone reads during the
   next incident. A changelog that says "enhanced access controls" is discretion; a PR that
   says it is a lost fact.

4. **Present changelog entry to user for approval.**

5. **If approved:** Insert entry at correct position in CHANGELOG.md.

6. **Check for a public release-notes surface** the repository also maintains (for example, a changelog page in the app or the docs). If found, update it to match.

**If changelog entry is NOT needed:**
Record `Changelog: SKIPPED — No user-facing release note required` and continue without a question.

**If CHANGELOG.md doesn't exist:**
Use the repository's existing public release-note location when there is one. If there is no
release-note surface, skip unless the user requests one or the repository requires it; prepare
any required new entry for approval before creating it. On resume, read the existing entry and
approval evidence for this release; do not duplicate the note or ask again for unchanged,
already-approved wording. Changed public wording still needs approval.

#### Final verification

After all selected files and approved release-note changes are final, run the build and tests
selected in Steps 3–4 against that content. Record the exact commands and results. Preserve the
test runner's exit code if truncating output, for example:

```bash
set -o pipefail
npm test 2>&1 | tee /tmp/ship-it-test.log | tail -30
```

- **Build failure:** show the error and stop shipping.
- **Test failure:** compare the specific failures with the recorded baseline. Without evidence,
  call their origin unknown, not pre-existing. New or unexplained failures stop shipping unless
  the user explicitly waives those failures. Record any waiver and the command/output in the PR.
- **Established pre-existing failures:** follow the repository's acceptance policy; if it does
  not permit shipping with them, obtain a specific waiver. Never bypass required GitHub checks.
- **Checks pass or are legitimately inapplicable:** continue to Step 8. Do not broaden or repeat
  them without changed content, a failure, or a specific unresolved concern.

If any selected content changes after verification, rerun the affected checks before shipping.
Reapply the security gate if the final edits affect its classification or access proof. Early
checks or a pass on the pre-changelog tree cannot establish that the final tree passes.

### Step 8: Stage and Commit

If the selected issue scope has no uncommitted changes, record the existing branch tip as the
commit being shipped and continue to Step 9 without creating another commit. Leave unrelated
staged or dirty work alone. Otherwise stage and commit only the selected issue files below.

```bash
# Stage the selected issue files (includes CHANGELOG.md if updated)
git add -- [file-1] [file-2]

# Show the exact staged changes before committing
git diff --cached --stat
git diff --cached
git status --short

# Commit with the chosen message
git commit -m "$(cat <<'EOF'
[chosen commit message here]
EOF
)"
```

**If deleted files are part of the selected scope:** use a staging command that records deletions for those paths, such as `git add -A -- [path]`.

**Before committing:** Verify no unexpected files are staged (especially secrets). If anything unexpected is staged, unstage it and show the corrected staged diff.

### Step 9: Push Branch

Compare the current branch tip with the remote tip. If the same commit is already published,
record that fact and continue. Otherwise push the branch:

```bash
git push -u origin $(git branch --show-current)
```

**If push fails because the remote branch already exists or has new commits:**
- STOP and show the push error.
- Run `git fetch origin` and summarize whether the local branch is behind, ahead, or diverged.
- Prefer rebasing or pulling remote changes when appropriate.
- Ask for explicit approval before any history rewrite.

Only after approval, use:
```bash
git push --force-with-lease origin $(git branch --show-current)
```

### Step 10: Create Pull Request

On resume, reuse the open PR captured in Step 1. Confirm its repository, base, head branch, and
published head commit match the intended release. Update its description only when the current
scope or verification evidence requires it, then proceed to Step 11. Create a PR only when no
PR exists for this unshipped work; never create a duplicate after an ambiguous provider result.

**Compose PR description:**

```markdown
## Summary
[2-3 bullet points from commit]

## Changes
[List of significant changes]

## Test Plan
- [x] Build: `[exact command]` — PASS/SKIPPED/FAILED
- [x] Tests: `[exact command]` — PASS/SKIPPED/KNOWN FAILURES
- [x] Manual verification: [what was checked, or "Not run: reason"]
- [x] Security gate: PASS/N-A/WAIVED — [what changed about data access, both halves of the access proof, advisor comparison (Supabase projects), or the reason it does not apply]

## Related Issues
Closes #[issue-number]
```

**Create PR** against the repository's actual default branch, which is not always `main`:

```bash
default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
[ -n "$default_branch" ] || default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)

gh pr create \
  --title "type(scope): description" \
  --body "[PR description]" \
  --base "$default_branch"
```

### Step 10A: Review the Pull Request and Fix What It Finds

Before anything merges, review the change as it stands on the pull request, fix the problems
the approved scope already decides, and get its checks green. This is the same loop Claude
Code's typed `/ship` command runs, done inside `/ship-it` so one command still carries the work
to production. `/ship-it` cannot start `/ship` (Claude Code only starts it from a line the user
types); never run both on the same pull request, since both push to the branch.

Skip this step on the cleanup-only re-entry. On a resumed PR that already has GitHub auto-merge
enabled from an earlier run, turn it off first (`gh pr merge "$PR_URL" --disable-auto`) so
nothing merges mid-review; Step 11 turns it back on.

**1. Review.** Review the pull request's diff against its base (`gh pr diff "$PR_URL"`) for
correctness bugs: wrong results, broken edge cases, missed requirements from the issue, and
tests that do not prove what they claim. In Claude Code, run the built-in `/code-review` skill
at `high` effort on the branch (`/code-review high <base>...HEAD`); elsewhere, do the review
yourself with the same focus. Confirm each finding before acting on it: run the failing case or
read the failing check's log. An unconfirmed suspicion is a note, not a fix.

**2. Sort each confirmed finding by one bar: does the approved scope already say what is right?**

| Finding | Action |
|---|---|
| A defect the issue's requirements, acceptance examples or plain intent already decide (the code does the wrong thing) | Fix it |
| Thin tests, a misleading name or a misplaced line, inside the changed lines | Fix it when the fix is small; otherwise note it |
| A choice the scope does not make, where either answer changes what users get (rounding rules, rejecting versus clamping input, a new limit) | Do not decide it. Ask the user one question with your recommended answer and its reason. The merge waits for the answer |
| Anything else (style preference, a larger refactor, work outside the issue) | Note it; it does not block |

**3. Fix.** Fix behaviour test-first: a test that fails for the finding, then the change that
makes it pass. Stay inside the issue's scope. Re-run Step 7's build and tests, re-run the
Step 5 security gate if a fix touches anything on its trigger list, then commit and push to the
same branch (`git push origin "$current_branch"`). Never force-push.

**4. Checks.** When the repository runs checks on pull requests, wait for those on the new head
commit, running this with a 10-minute time limit on the command:

```bash
gh pr checks "$PR_URL" --watch --fail-fast --interval 20
```

Checks still running after 10 minutes are left to Step 11, whose auto-merge waits for required
checks; say so in the report.

A failure caused by this change is a finding: read its log (`gh run view <run-id> --log-failed`),
then fix and push as in step 3. A failure that is clearly not this change (a runner outage, a
flaky network call) gets one re-run (`gh run rerun <run-id> --failed`). A repository with no
checks skips this wait.

**5. Budget: two fix rounds.** One round is a push of fixes and the checks that follow it.
Findings still open after two rounds do not buy a third: a defect still present is a stop
(`REVIEW_STATUS = BLOCKED`, no merge, report what fails and why); anything else is recorded in
the comment below and the work proceeds.

**6. Record it on the pull request.** Post one comment summarising the review: each finding with
its file and line, `Fixed in <commit>` or `Left:` with the reason, and any question waiting on
the user. Read it back (`gh pr view "$PR_URL" --comments`). Update the PR description's Test
Plan when fixes changed what was tested.

Record `REVIEW_STATUS`:

- `CLEAN` — no confirmed findings, checks green or none.
- `FIXED` — every finding that blocks was fixed, checks green or none; notes may remain.
- `WAITING` — a question is with the user. Do not merge; Step 11 sets `MERGE_STATUS = BLOCKED`
  (reason: waiting on the user's answer). Re-running `/ship-it` after the answer resumes here.
- `BLOCKED` — a defect or failing check survived two rounds. Do not merge.

### Step 11: Merge Conflict-Free Pull Request

Merge only when `REVIEW_STATUS` is `CLEAN` or `FIXED`. Otherwise set `MERGE_STATUS = BLOCKED`
with the review's reason and continue to Step 12, which defers cleanup.

Inspect the PR after creation:

```bash
gh pr view "$PR_URL" --json number,url,state,mergeable,mergeStateStatus,statusCheckRollup
```

- If `mergeable` is `CONFLICTING`, STOP and report the conflict. Do not merge.
- If `mergeable` is `UNKNOWN`, re-check briefly until GitHub resolves it. If it remains unknown, STOP and report that mergeability could not be confirmed.
- If `mergeable` is `MERGEABLE`, check whether the target branch requires anything before a merge:

```bash
gh api "repos/{owner}/{repo}/branches/$default_branch/protection" 2>/dev/null \
  | jq '{reviews: .required_pull_request_reviews.required_approving_review_count, checks: .required_status_checks.contexts}'
gh api "repos/{owner}/{repo}/rules/branches/$default_branch" --jq '[.[].type]' 2>/dev/null  # rulesets
```

If neither shows a required review or a required check (including when the calls fail), nothing on GitHub stops unreviewed changes going straight into the default branch. Unless the user already said to merge, or administers the repository (`gh repo view --json viewerPermission -q .viewerPermission` prints `ADMIN`, so the branch rules are theirs to set), tell them that and ask one question: merge now, or leave the PR open for review? If they choose to leave it open, set `MERGE_STATUS = BLOCKED` (reason: left open for review at the user's request) and continue; Step 12 defers cleanup as for any unmerged PR.

Pick the merge method the repository allows, preferring merge, then squash, then rebase:

```bash
gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
# MERGE_FLAG is --merge, --squash or --rebase: the first one allowed
```

Enable GitHub auto-merge with that method:

```bash
gh pr merge "$PR_URL" --auto "$MERGE_FLAG"
```

This merges immediately when requirements are already satisfied, or waits for required checks and reviews. Never use `--admin`, bypass branch protection, or merge a conflicting PR.

If auto-merge is unavailable, run `gh pr merge "$PR_URL" "$MERGE_FLAG"` only when the PR is conflict-free and every required check has passed. Otherwise STOP and report the unmet requirement.

**Wait for the merge to land before concluding.** When a repository has no required checks — the common case — the merge completes within seconds, but GitHub often still reports `OPEN` on an immediate read. Concluding from that first read would defer the cleanup that Step 12 exists to perform. Poll briefly instead:

```bash
for i in $(seq 1 10); do
  state=$(gh pr view "$PR_URL" --json state -q .state)
  [ "$state" = "MERGED" ] && break
  sleep 3
done
gh pr view "$PR_URL" --json state,mergedAt,autoMergeRequest,url
```

Record `MERGE_STATUS`:

- `MERGED` — `state` is `MERGED`. Continue to Step 12; the campsite phase runs.
- `AUTO_MERGE_ENABLED` — still `OPEN` after polling, with an `autoMergeRequest` present. Real required checks are pending; cleanup is deferred.
- `BLOCKED` — anything else (conflicts, unmet requirements, auto-merge unavailable).

Roughly 30 seconds of polling separates "checks are genuinely running" from "GitHub hasn't caught up yet". Do not extend it into a long wait for a slow CI suite — that's what `AUTO_MERGE_ENABLED` and the cleanup-only re-entry in Step 1 are for.

### Step 12: Campsite Cleanup

**Only runs when `MERGE_STATUS == MERGED`** (set in Step 11, or by the cleanup-only re-entry in Step 1). If the PR is `AUTO_MERGE_ENABLED` or `BLOCKED`, skip this step — there is nothing to clean up yet — and set `CAMPSITE_STATUS = DEFERRED`.

The cleanup itself is a tested script that ships with this skill, not a sequence of commands to improvise. Run it from the checkout you did the work in, passing the branch you just shipped:

```bash
"$SKILL_DIR/campsite.sh" --branch "$(git branch --show-current)"
```

`$SKILL_DIR` is this skill's own directory — the "Base directory for this skill" given at invocation. Run the command exactly as written: it reads the branch name from git itself, so there is no value to substitute and no way for an empty one to slip through.

The script deletes the merged branch locally and on origin, removes the worktree if the work was done in one, returns the checkout to a freshly pulled default branch, and prints what it deliberately left alone. It refuses — reporting instead of deleting — whenever work could be lost: uncommitted changes on the branch being cleaned up, a branch holding commits GitHub never merged, or a worktree git won't release. Uncommitted work on some other branch only stops it from refreshing the default branch; the merged branch still goes. It never uses `--force`, and it never deletes a remote branch it couldn't also delete locally.

Read `CAMPSITE_STATUS` from the exit code, and pass the script's output through to Step 15 as the campsite report:

| Exit | `CAMPSITE_STATUS` | Meaning |
|------|-------------------|---------|
| 0 | `CLEANED` | Branch gone locally and on origin; checkout on a fresh default branch. |
| 10 | `PARTIAL` | Something was deliberately left behind. The output says what and why. |
| 20 | `DEFERRED` | The PR had not merged yet, so nothing was cleaned up. |
| 1 | — | Bad usage or an unestablished precondition. Report the error; change nothing by hand. |

Do not work around a `PARTIAL` or an error by running the underlying git commands yourself. Both mean the script found a reason not to delete something, and that reason is the point.

**Changing this behavior:** edit `campsite.sh`, then run `campsite.test.sh` — 75 assertions covering merge/squash/rebase, worktrees (clean, dirty, locked, ignored files, paths with spaces), unpushed commits, a remote that moved after the merge, an unreachable origin, a default branch held by another worktree, detached HEAD, a non-`main` default branch, uncommitted work on and off the shipped branch, and the leftover report's contents. It sandboxes under `$TMPDIR` and touches no real repo. Do not reimplement the logic in this file. If the `/cleanup-branches` skill is installed, it runs the same script once per merged branch, so also run its `cleanup.test.sh`.

### Step 13: Production Verification

First establish that the release is deployed. Capture the production environment, the merged
commit, and deployment or version evidence tying each affected production surface to that
release, including changed migrations, functions, or jobs when applicable. The live version
must be the release or a verified later version containing it; merge state or a healthy old
deployment is insufficient. Deployment identity establishes which release can be tested, not
whether its behavior works.

If merge or deployment is pending, or release identity cannot be established, set
`PRODUCTION_STATUS = NOT_VERIFIED` and `PRODUCTION_ACCESS_STATUS = NOT_RUN`. Skip Part A, post
the `NOT_VERIFIED` result in Part B naming the missing gate, make no other writes, and report
it. Checks against the old or unidentified deployment cannot count as release proof.

Once that deployment gate passes, **Part A is required** whenever `SECURITY_GATE` is not `N/A`,
including a gate re-derived on the cleanup-only path. Do not skip it.

#### Part A: Production access verification

A change that accidentally opened a table to the public passes an intended-behavior check perfectly, because the feature it shipped works exactly as designed. User confirmation that "it works" does not cover this. Before any reporting:

- Re-run the negative access checks against **production**, as the roles the declared audience excludes. Read probes only — never a mutating probe against production.
- When the project uses Supabase, re-run the security advisors against production and compare item-by-item with the pre-merge baseline: no new finding.
- When the change moved in the lockdown direction, spot-check that the enumerated consumer surfaces still return data in production — a lockdown that zeroes another app's reads is the outage this check exists to catch.

A new finding or a zeroed consumer read after deployment is a live incident, not a follow-up ticket. Report it immediately and treat rolling back as the default. Do not report the release complete while it stands. Record the result as `PRODUCTION_ACCESS_STATUS = CLEAN / INCIDENT / NOT_RUN`.

#### Part B: Verify the behavior and record it on the GitHub issue

Count production as `PRODUCTION_STATUS = VERIFIED` only when the deployment gate passed and one of these is true for the identified release:

- This session exercised the intended behavior at the live production URL and observed the expected result.
- The user explicitly confirmed that the intended behavior works in production after this release.

When `SECURITY_GATE` was not `N/A`, neither is sufficient on its own: `VERIFIED` additionally requires Part A complete and `CLEAN`, because a change that opened data to the wrong audience passes an intended-behavior check perfectly. A successful deployment, passing build, automated test, localhost run, preview environment, source inspection, or an old comment is not production proof; without one of the two facts above, `PRODUCTION_STATUS = NOT_VERIFIED`. If the verification covers only part of the issue's acceptance scope, name the `SR-*`, `AC-*`, or `TR-*` identifiers it covers and the ones it does not; a partly covered release is reported as `SHIP FOLLOW-UP REQUIRED`, never `SHIP COMPLETED`.

Then post the result as a comment on the issue the pull request closes (`gh pr view <pr> --json closingIssuesReferences`; fall back to the Step 2 issue number only when the PR references none, and say so), so the evidence lives beside the proof table and any orchestrate sign-off:

```bash
gh issue comment <issue-number> --body-file <file>
```

```text
PRODUCTION VERIFICATION #<issue>: <VERIFIED | NOT_VERIFIED>

Release:   PR #<pr>, merge commit <sha>; live on <environment> as <deployment or version evidence>
Exercised: <what was driven at the live URL and what it showed, or "user confirmed: <their words>">
Covers:    <SR-*/AC-*/TR-* identifiers verified>; not covered: <identifiers, or none>
Missing:   <the gate that kept this NOT_VERIFIED, or none>
Access:    <CLEAN / INCIDENT / NOT_RUN, with the advisor comparison (Supabase projects) and the negative probes re-run; N/A when the security gate was N/A>
Campsite:  <CAMPSITE_STATUS>
```

List under `Covers` only identifiers proven on the live system in full; one proven in part or on one device of two goes under `not covered`. Where the orchestrate progress bar is installed, it reads this line and marks each covered identifier verified.

Post it whether the result is `VERIFIED` or `NOT_VERIFIED`; a `NOT_VERIFIED` comment names the missing gate so the next session knows what to check. Read the comment back (`gh issue view <issue-number> --comments`) and record `ISSUE_COMMENT = POSTED / FAILED / NO_ISSUE` (no closing issue was referenced). Do not comment on, close, or otherwise change any Linear record: that reconciliation no longer exists. If the issue still links a Linear identifier from before the product contract moved to GitHub, say so in the comment so the user can close it by hand.

**Later live checks use the same format.** Sometimes a session, this one or a later one, finishes checks that an earlier `NOT_VERIFIED` or partly covered comment left open. It records them as a new `PRODUCTION VERIFICATION #<issue>` comment in the template above. Its `Covers` line lists every identifier now proven live, counting the earlier comments too. Do not record them in free prose, and do not edit an earlier comment. The progress bar and the next session read only the template's lines, so a result written any other way stays invisible and the issue looks unverified.

Record `PRODUCTION_STATUS`, `PRODUCTION_ACCESS_STATUS`, and `ISSUE_COMMENT` for the final report.

### Step 14: Epic Context Check

**Before reporting success, re-detect epic context** (in case it was lost during the session).

Use the issue number captured in Step 2. Step 12 has already returned the checkout to the default branch, so the current branch no longer carries it, and `git branch --show-current` would return the wrong answer here.

**Write the number into the command as a literal** — do not reference a shell variable. Each command you run is a separate shell, so a variable set back in Step 2 is empty by now, and an empty number turns the search into `in:body "#"`, which silently matches nothing and reports an epic child as a finished standalone issue:

```bash
# Literal issue number, e.g. 125 — never "$issue_number"
gh issue list --search 'in:body "#125"' --state open --json number,title,body --limit 20
```

Parse results to find a parent issue containing task list items (`- [ ] #N` or `- [x] #N`). If found, list all child issue references from the parent's body and check their open/closed state.

**Set:**
```
EPIC_DETECTED  = true/false
EPIC_PARENT    = #[parent-number] (if detected)
EPIC_REMAINING = [list of still-open sibling issues] (if detected)
```

### Step 15: Report Success

Use `SHIP COMPLETED` only when the PR is merged, production is `VERIFIED` for the whole acceptance scope, campsite cleanup is complete, and the production-verification comment is posted on the closing issue (or there is no closing issue). Otherwise, including a partly covered verification, use `SHIP FOLLOW-UP REQUIRED` and name the unfinished gate without implying that the release is fully complete.

**If EPIC_DETECTED = false (single issue, no epic):**

```
============================================
[SHIP COMPLETED or SHIP FOLLOW-UP REQUIRED, using the gates above]
============================================

PR:       #[pr-number]
URL:      [pr-url]
Branch:   [branch-name] → [default-branch]
Merge:    [MERGED / AUTO_MERGE_ENABLED / BLOCKED]

Status:
  Build:     [PASS/SKIPPED, or "not run (cleanup-only re-entry)"]
  Tests:     [X passing / SKIPPED, or "not run (cleanup-only re-entry)"]
  Commit:    [commit-hash, or "not run (cleanup-only re-entry)"]
  Changelog: [Updated/Skipped, or "not run (cleanup-only re-entry)"]
  Security:  [PASS / N-A / WAIVED, or "not run (cleanup-only re-entry)"]
  Review:    [CLEAN / FIXED (n fixed, n noted) / WAITING / BLOCKED, or "not run (cleanup-only re-entry)"]
  Production:[VERIFIED / NOT VERIFIED]
  Access:    [CLEAN / INCIDENT / NOT_RUN / N-A]
  Issue:     [verification comment POSTED on #N / FAILED / NO_ISSUE]

============================================
CAMPSITE
============================================
[Paste campsite.sh's output verbatim — it already lists what was done,
 what was left alone and why, and the leftovers. Do not summarize or
 re-word it, and do not add a fix-it recipe of your own: a PARTIAL means
 the script found a reason not to delete something.]

[Then add ONE line matching CAMPSITE_STATUS:]

CLEANED:  Nothing further to do.
PARTIAL:  Left behind on purpose — see above. Re-run /ship-it from this
          branch once the reason is resolved.
DEFERRED: The merge is still pending on required checks. Re-run /ship-it
          from this branch once it lands and cleanup will finish, or, if
          the /cleanup-branches skill is installed, run it later.
============================================

IMPORTANT: Do NOT continue work on this branch after merge.
           If more work is needed, create a NEW branch.
============================================
[Step 16 archive verdict — always the last line]
```

**If EPIC_DETECTED = true (issue is part of an epic):**

```
============================================
[SHIP COMPLETED or SHIP FOLLOW-UP REQUIRED, using the same gates as above]
EPIC IN PROGRESS
============================================

PR:       #[pr-number]
URL:      [pr-url]
Branch:   [branch-name] → [default-branch]
Merge:    [MERGED / AUTO_MERGE_ENABLED / BLOCKED]

Status:
  Build:     [PASS/SKIPPED, or "not run (cleanup-only re-entry)"]
  Tests:     [X passing / SKIPPED, or "not run (cleanup-only re-entry)"]
  Commit:    [commit-hash, or "not run (cleanup-only re-entry)"]
  Changelog: [Updated/Skipped, or "not run (cleanup-only re-entry)"]
  Security:  [PASS / N-A / WAIVED, or "not run (cleanup-only re-entry)"]
  Review:    [CLEAN / FIXED (n fixed, n noted) / WAITING / BLOCKED, or "not run (cleanup-only re-entry)"]
  Production:[VERIFIED / NOT VERIFIED]
  Access:    [CLEAN / INCIDENT / NOT_RUN / N-A]
  Issue:     [verification comment POSTED on #N / FAILED / NO_ISSUE]

============================================
CAMPSITE
============================================
[Same as the non-epic template above: campsite.sh's output verbatim, then
 the one matching status line. The leftover report is required here too —
 do not collapse it into the NEXT STEPS line below.]

--------------------------------------------
EPIC PROGRESS: #[parent-number] - [parent-title]
--------------------------------------------
Completed: [X] of [total] issues
This release: #[issue-number] - [issue-title] — [verified status or unfinished gate]

Remaining issues:
  #[N] - [title]
  #[N] - [title]
  ...

⚠ THE EPIC IS NOT COMPLETE.
  Parent completion still requires the remaining epic work.
--------------------------------------------
NEXT STEPS
--------------------------------------------

1. Campsite: [one-line recap of CAMPSITE_STATUS — the detail is in the CAMPSITE
   block above, which is printed in full, leftovers included.]

2. Remaining epic work: [next issue or binding decision, with the reason it advances the epic].
   Continue only if the user's existing request includes that work.
============================================
[Step 16 archive verdict — always the last line]
```

**CRITICAL behavioral rules when EPIC_DETECTED = true:**
- Report the requested issue release as complete only when its release gates pass.
- State that the parent epic remains incomplete and name its remaining work.
- A request to ship one child issue ends when that release is handled; it does not authorize
  implementing siblings or require another question before ending the session.
- If the user already requested the whole epic, continue within that authorization and preserve
  the remaining gates. Do not confuse one completed child with the entire outcome.

### Step 16: Archive Verdict

The point of `/ship-it` is to reach the moment the user can archive this session and clear it
from the side panel without losing anything. Say whether that moment has arrived, every time.

**Every run ends with exactly one archive line, as the last line of the reply.** That includes
the full report, a stop on a failed gate, a merge conflict, a blocked security gate, and
"nothing to ship". There are two values and no third: no "probably", no "safe once X".

```
ARCHIVE THIS SESSION: YES — merged, live, verified, recorded on #<issue>, cleaned up. No further action is needed in this session.
ARCHIVE THIS SESSION: NOT YET — <the open item, in plain words>. <Who does what> to clear it, then re-run /ship-it.
```

**`YES` requires every condition below.** Read each one from a result recorded in this run,
including a cleanup-only re-entry. Never infer it or carry it from memory. Anything unknown
counts as unmet.

| # | Condition | Recorded as |
|---|-----------|-------------|
| 1 | The pull request is merged. | `MERGE_STATUS = MERGED` |
| 2 | The release works in production for the whole acceptance scope, and access checks are clean where the security gate applied. | `PRODUCTION_STATUS = VERIFIED` with nothing under "not covered"; `PRODUCTION_ACCESS_STATUS = CLEAN`, or the gate was `N/A` |
| 3 | The verification evidence is on GitHub. | `ISSUE_COMMENT = POSTED` or `NO_ISSUE` |
| 4 | Cleanup finished. | `CAMPSITE_STATUS = CLEANED` |
| 5 | Nothing exists only in this session. | The fresh check below |

Production not yet verified is `NOT YET`, even when the `NOT_VERIFIED` comment is posted and
everything else is clean. A fix is done when it is confirmed on the live system, and an archived
session is how that last check gets forgotten.

**Condition 5, checked fresh just before printing the line.** Run `git status --short` in the
folder this session worked in. If campsite removed that folder, nothing remains there. The
condition fails on any of these:

- A file this session created or changed that is not committed and pushed. Files Step 1 or Step 5
  already classified as unrelated and left alone belong to other work; name them in the report,
  but they do not block.
- A question, approval, or waiver still waiting on the user.
- A follow-up this run identified that is recorded only in this conversation, not on GitHub.

**`NOT YET` names the first unmet condition in table order**, in words the user can act on
("the merge is waiting on a required check", not `AUTO_MERGE_ENABLED`). It says who acts and what
clears it. When more than one condition is unmet, the report above carries the rest.

**On an epic,** open sibling issues do not block `YES`; they are already tracked on the parent
issue. The exception is a session the user asked to deliver the whole epic, where remaining
siblings are `NOT YET`.

**Nothing to ship** (Step 1) has no merge, release, or cleanup to judge, so only condition 5
applies. It is the one stop that can end in `YES`, worded for what actually happened:

```
ARCHIVE THIS SESSION: YES — nothing to ship, and nothing exists only in this session. No further action is needed in this session.
```

Do not archive the session yourself. The line tells the user it is safe; archiving is their call.

---

## Error Handling

| Error | Action |
|-------|--------|
| On main/default branch or detached HEAD | STOP - must use feature branch |
| Build fails | STOP - must fix before shipping |
| Clean working tree | Classify Step 1: resume unshipped commits, an open PR, or merged-PR cleanup; stop only when no shipping work remains |
| Unexpected files staged | Unstage, show corrected staged diff, continue with the intended set |
| Push rejected | Fetch, explain branch state, ask before rebase or force-with-lease |
| PR creation fails | Show error, provide manual steps |
| Review finds a choice the scope does not make | Ask the user one question with a recommended answer; do not merge until answered (`REVIEW_STATUS = WAITING`) |
| A defect or failing check survives two fix rounds | STOP before merging (`REVIEW_STATUS = BLOCKED`); report what fails and why |
| Merge conflicts | STOP, report the conflicting PR, and do not merge |
| Required checks block merge | Leave auto-merge enabled when possible; otherwise report the unmet check |
| CHANGELOG.md malformed | Show error, ask user to fix manually |
| `campsite.sh` exits 10 (PARTIAL) | Report its output verbatim. It left something alone on purpose — do not finish the job by hand |
| `campsite.sh` exits 1 | Report the error and change nothing manually; a precondition it needs could not be established |
| Security gate BLOCKED | STOP - report the failed check and what would resolve it; ship only on an explicit user waiver recorded in the PR |
| Access proof is positive-only or run with an admin key | Treat as BLOCKED - the check that matters was not run |
| No advisor baseline on the issue for a gate-tripping diff (Supabase projects) | Treat as BLOCKED (waivable) - a post-change advisor run is not a baseline |
| Lockdown-direction diff without a consumer enumeration | Treat as BLOCKED (waivable) - locking down unenumerated readers is how a fix becomes an outage |
| New security-advisor finding after deployment | Treat as a live exposure: report immediately, default to rolling back; post NOT_VERIFIED with the finding on the issue only after rollback or mitigation |
| Consumer surface returns zero rows after a lockdown ships | Treat as a live outage: report immediately, default to rolling back; post NOT_VERIFIED with the finding on the issue only after rollback or mitigation |
| Production verification is absent | Post NOT_VERIFIED naming the missing gate on the issue and report it |
| Merge/deployment pending or live release identity unknown | Production NOT_VERIFIED, access NOT_RUN; do not count checks on an old or unidentified deployment |
| Posting the verification comment fails | Report `ISSUE_COMMENT = FAILED` with the full comment text so it can be posted by hand; do not report SHIP COMPLETED |
| Any stop or error above | End with `ARCHIVE THIS SESSION: NOT YET`, naming the stop and what clears it (Step 16). The one exception is nothing to ship, which Step 16 judges on condition 5 alone |

---

## What This Command Does NOT Do

- Does not delete anything before the PR is actually merged — a pending auto-merge leaves the branch alone
- Does not delete a branch whose local commits aren't all contained in the merge
- Does not force-remove a worktree holding uncommitted work — reports it instead
- Does not remove stray sibling clones (a second full clone of the repo in another folder). Git cannot tell one from the real checkout, so the entropy audit reports those and removing one is a manual decision; this command only removes worktrees it can positively identify
- Does not switch a checkout that is dirty or parked on unrelated work
- Does not skip build verification
- Does not ship a change to data access without both halves of the access proof, or treat a working feature as evidence that nothing was exposed
- Does not soften security wording anywhere except the public changelog
- Does not pause for routine commit-scope approval when `/ship-it` was invoked — report the selected files and continue
- Does not stage secrets, `.env.local`, or clearly unrelated dirty files without an explicit user decision when ownership is ambiguous
- Does not bypass merge conflicts, required checks, reviews, or branch protection
- Does not decide behaviour the approved scope leaves open; review findings that need such a choice go to the user
- Does not force changelog entries for non-user-facing changes
- Does not treat a deployment, local run, preview, or historical tracker comment as current production verification
- Does not touch Linear: no comments, state changes, or links on Linear records. Release evidence goes to the GitHub issue
- Does not archive the session. It ends every run by saying whether archiving is safe; the user archives

---

## Quick Reference: The Full Workflow

```
/orchestrate 198       # Begin: /start-work workers create the branch and baseline,
                        #        and the orchestrator re-checks their proof
[... do your work ...]
[... verify it works ...]
/ship-it               # End: commits, pushes, creates PR, reviews it and fixes what
                        #      it finds until checks are green, merges if conflict-free,
                        #      and — once merged — deletes the branch (local + origin),
                        #      removes the worktree if the work was done in one, and
                        #      returns to a fresh default branch (the campsite phase),
                        #      then posts the live-production verification as a comment
                        #      on the closing GitHub issue, and ends with
                        #      ARCHIVE THIS SESSION: YES or NOT YET
[... if the merge was still pending on required checks, rerun /ship-it from the
     branch once it lands — it detects the merged PR and finishes the cleanup ...]
```

---

## Related Skills

- **changelog-writer** (if installed): Provides patterns for writing changelog entries; the project's existing changelog style takes precedence
