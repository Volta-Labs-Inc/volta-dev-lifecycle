---
name: start-work
version: 1.0.1
description: "Start and complete work on a GitHub delivery issue end to end. Use when the user invokes /start-work or when an /orchestrate worker runs it; route a general request to implement an approved issue to /orchestrate. It will: preserve existing work, load the issue's product contract (or the legacy Linear scope it links), confirm the delivery contract is current against it, prepare or resume the issue branch, implement each requirement test-first where behavior changes, run the defined frontend, backend, data, and runtime proof, and confirm the result locally."
---

# /start-work - Implement a GitHub Issue

`/start-work <issue-number>` means begin the actual work now. Prepare the environment, implement the issue, and verify the result locally. Do not stop after setup, planning, branch creation, or TDD activation.

Finish only when one of these conditions is true:

- The issue is implemented and verified locally, and is ready for `/ship-it`.
- A genuine blocker requires a user decision, missing access, or an external state change.

This skill does not publish the work. Committing, pushing, opening a pull request, merging, and deploying remain the responsibility of `/ship-it` unless the user explicitly asks otherwise.

## Usage

```text
/start-work <issue-number>
```

The issue number is required.

## Operating Rules

- Treat the issue's product-contract section (on the issue, or on its epic parent) as authority for product outcome, scope boundaries, and product decisions, and its delivery-contract section as authority for the technical delivery and proof contract. For an explicitly technical-scope issue, the delivery contract may be the only record. A legacy issue that links a Linear scope and has no product section keeps Linear as its read-only product authority.
- Do not build against a product contract that moved. If its fingerprint differs from the one the delivery contract was planned against, stop for `/document` reconciliation before implementation.
- Preserve local work. Never discard, reset, delete, or commit changes without the user's approval. You may automatically stash changes only under the clearly-safe conditions in Step 2.
- Surface and assess existing WIP before creating a branch or worktree. The inventory is evidence, not a blocker by itself; pause only when the analysis finds a real overlap, ambiguity, or risk to existing work.
- Make the workflow idempotent. Re-running `/start-work` for the same issue should resume the existing branch instead of creating a duplicate or returning a setup summary.
- Use progress updates to keep the user informed, not to hand the next implementation step back to them.
- Continue through recoverable problems. Pause only when proceeding would risk user work, require authority, or make verification unreliable.
- Explain behavior and decisions in plain English. Raw command output is evidence, not the explanation.
- Treat a claim as verified only when a command ran in this session and its result was observed. Reading code, a document, or an earlier report is research, not verification.

## Workflow

Execute the following workflow in order.

### Step 1: Surface Existing WIP

Run this guard before creating any branch or worktree. It must cover the current repository only and must run even when the worktree looks clean.

This guard warns; it does not block on inventory alone. Pause only when the evidence shows a
real overlap, ambiguity, or risk to existing work.

First identify the repository, its default branch, and its remote:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_PARENT="$(dirname "$REPO_ROOT")"
DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
```

Collect and retain the output for all five WIP categories:

```bash
# Dirty staged, unstaged, and untracked files
git status --short

# Stashes
git stash list

# Existing non-default local branches, including their ages
git for-each-ref \
  --format='%(refname:short)|%(committerdate:relative)|%(upstream:short)' \
  refs/heads/ | awk -F'|' -v default="$DEFAULT_BRANCH" '$1 != default'

# Open pull requests
gh pr list --state open --limit 100 \
  --json number,title,headRefName,createdAt,url,isDraft
```

Check both linked worktrees and sibling clones. A sibling clone counts as the same remote even when one checkout uses an SSH URL and the other uses HTTPS:

```bash
# Linked worktrees outside the current checkout
git worktree list --porcelain | while IFS= read -r line; do
  case "$line" in
    "worktree "*)
      worktree_path="${line#worktree }"
      [ "$worktree_path" = "$REPO_ROOT" ] || printf '%s\n' "$worktree_path"
      ;;
  esac
done

# Sibling checkouts of the same remote
remote_key() {
  printf '%s\n' "$1" | sed -E \
    -e 's#^git@([^:]+):#https://\1/#' \
    -e 's#^ssh://git@([^/]+)/#https://\1/#' \
    -e 's#\.git/?$##' \
    -e 's#/$##'
}

CURRENT_REMOTE_KEY="$(remote_key "$ORIGIN_URL")"
while IFS= read -r -d '' candidate; do
  [ "$candidate" = "$REPO_ROOT" ] && continue
  candidate_url="$(git -C "$candidate" remote get-url origin 2>/dev/null || true)"
  [ -n "$CURRENT_REMOTE_KEY" ] && \
    [ "$(remote_key "$candidate_url")" = "$CURRENT_REMOTE_KEY" ] && \
    printf '%s\n' "$candidate"
done < <(find "$REPO_PARENT" -mindepth 1 -maxdepth 1 -type d -print0)
```

Deduplicate checkout paths that appear in both scans. Do not silently treat a failed command as an empty result. Treat that part of the assessment as unavailable and explain the short reason.

#### Analyze the inventory before reporting it

Do not make the user interpret Git categories. Determine what each item means for the requested issue:

1. Correlate branches with linked worktrees, open pull requests, issue numbers, upstreams, and recent commits. A branch name by itself is not evidence of active work.
2. Inspect the status of active checkouts. When another active workstream exists, compare its changed file surfaces with the files or systems named by the requested issue.
3. Classify findings by effect:
   - **Resume:** Existing branch or worktree for the requested issue.
   - **Potential conflict:** Related active work could touch the same behavior or files.
   - **Isolated work:** Another active workstream is safely separated and does not overlap.
   - **Parked history:** Old, merged, recovery, or otherwise inactive branches that do not affect new work.
   - **Unknown:** Evidence is incomplete and a safe recommendation cannot yet be made.
4. Choose one recommendation: continue automatically, resume existing issue work, or pause for one specific decision.

Translate Git concepts into plain English when they matter:

- Dirty files mean the current checkout contains unsaved work that could be mixed with or disrupted by the new issue.
- A stash is saved work that is not currently active; it normally requires no action.
- A branch is only a pointer to work. It matters when it matches the requested issue, is checked out elsewhere, has an open pull request, or overlaps the requested change.
- A linked worktree or sibling clone is a separate checkout. It is normally safe when clean and isolated from the requested files.
- An open pull request is published work under review. It is not a blocker merely because it exists.

#### Report the conclusion, not the inventory

Lead with the outcome. Mention only findings that explain the recommendation. Summarize harmless history as a count instead of listing every branch. Do not output empty category labels such as `Dirty files: none` or `Stashes: none` unless an unavailable scan makes the proof boundary important.

Use one of these shapes.

When it is safe to proceed:

```text
WIP check: safe to continue.

- The current checkout is clean.
- [Other active work] is isolated in [worktree/PR] and does not overlap #[issue].
- [N] older branches are inactive history and do not affect this work.

Recommendation: [Start a fresh branch / resume the existing branch] for #[issue]. No cleanup is needed first.
```

Continue immediately. Do not ask the user to approve the recommendation when no existing work is at risk.

When existing work for the requested issue should be resumed:

```text
WIP check: resume existing work.

- #[issue] already has [branch/worktree/PR], last updated [time].
- The checkout is [clean / contains changes summarized in Step 2].

Recommendation: Resume [branch/worktree] instead of creating duplicate work.
```

Continue immediately when the checkout is clean. If it is dirty, apply Step 2 before switching or editing.

When a real decision is required:

```text
WIP check: decision needed.

- Risk: [plain-English description of the work that could be mixed, hidden, or overwritten].
- Relevance to #[issue]: [same behavior/files, unclear ownership, or incomplete scan].

Recommendation: [specific safest action and why].
Decision needed: [one concrete question].
```

Pause only in this last case. Never ask the generic question `Resolve any of these first, or continue?` because it makes the user interpret raw repository state.
Ask this single question once, then wait for the answer before changing existing work.

The guard never authorizes changing existing work. Do not stash changes, delete branches, close pull requests, remove checkouts, or otherwise clean up as part of Step 1. Step 2 decides how to preserve dirty local changes and may require a separate decision. If the user asks to resolve WIP first, stay within the action they authorize, rerun the full guard afterward, and continue the same `/start-work` invocation.

### Step 2: Review the Local State

Run:

```bash
git status --short --branch
```

#### Clean worktree

Continue immediately.

#### Worktree has local changes

Do not respond with only a list of filenames. Inspect enough context to explain what the changes do:

```bash
git diff --stat
git diff
git diff --cached --stat
git diff --cached
git ls-files --others --exclude-standard
```

Read untracked files when needed, while avoiding unnecessary exposure of secrets or generated binary content.

Group the changes by purpose and summarize each group in plain English:

- What behavior or configuration it changes.
- Whether it appears related to the requested issue.
- Whether it is staged, unstaged, or untracked.
- Whether it should be committed or stashed before work begins, with a short reason.
- What decision is required from the user.

After inspection, classify the whole worktree:

##### Clearly safe to preserve automatically

Automatically stash all tracked and untracked changes, report the descriptive stash name, and continue immediately when **all** of these are true:

- Every change is clearly unrelated to the requested issue.
- The changes are internally coherent and do not look partially applied, conflicted, or dependent on the current branch remaining checked out.
- Stashing them will not hide a running migration, active test fixture, required local configuration, or another state that would make issue verification unreliable.
- No nested repository, submodule state, ignored file, or external worktree would be left behind and mistaken for a clean environment.

Use a descriptive message that includes the issue number, for example:

```bash
git stash push --include-untracked -m "pre-start-work-$ISSUE_NUMBER unrelated local work"
```

Then rerun `git status --short --branch`, record the resulting stash reference, and proceed to Step 3. Do not ask the user to approve a routine, reversible stash when these conditions are satisfied; the purpose of the inspection is to protect their work without creating an unnecessary wait.

##### Decision required

Pause for the user only when any change appears related to the issue, its purpose is unclear, it may need to travel onto the issue branch, or stashing may disrupt or conceal active work. In that case, use this shape:

Use this shape:

```text
Local changes need a decision before I can start safely.

1. [Plain-English description]
   Related to issue: [yes / no / unclear]
   Recommendation: [commit / stash]
   Why: [short reason]

Decision needed: [specific question]
```

This is a deliberate pause because the choice affects existing user work. Do not commit or stash ambiguous or issue-related changes automatically. After the user resolves or approves the action, resume this workflow from Step 1 without requiring another `/start-work` invocation.

### Step 3: Load the Issue and Epic Context

Fetch the issue. `contract.py` ships with the scope skill at `../scope/scripts/contract.py` relative to this skill's folder; set `CONTRACT` to that path first (Volta setups may use `$OUTWORKOS_ROOT/skills/scope/scripts/contract.py`).

```bash
gh issue view "$ISSUE_NUMBER" --json number,title,body,labels,milestone,state,url,parent
python3 "$CONTRACT" read "$ISSUE_NUMBER" --json
```

The second command returns both contract sections with their text and identifiers; for an
epic child it includes the parent's product contract and names the issue it came from.
Confirm that the issue exists and is actionable. Extract:

- Title and description.
- Acceptance criteria.
- Scope basis, and the product contract version and fingerprint the delivery contract was planned against.
- Stable scope, acceptance, decision, or technical identifiers (`SR-*`, `AC-*`, `D-*`, `TR-*`).
- Labels and milestone.
- Files or systems named in the issue.
- Testing, TDD, UI, data, or deployment requirements.
- The requirement-to-proof matrix and surface test plan.
- Explicitly deferred work.

Then run the drift check from the repository checkout:

```bash
python3 "$CONTRACT" check "$ISSUE_NUMBER"
```

It recomputes the product contract's fingerprint (following an epic child's stamp to the parent), compares it with the one the delivery contract was planned against, lists product identifiers with no row in the proof matrix, and reruns the code-drift comparison from the commit `/document` planned on over the paths the delivery contract watches. Act on its exit code:

- `0` IN_SYNC: continue.
- `10` CONTRACT_DRIFT: the product contract changed after the delivery contract was planned. Stop and run `/document` reconciliation; do not judge the change harmless yourself.
- `12` CODE_DRIFT: the contract is current, but files under the watched paths changed since planning. Read the listed files and write one short paragraph: what changed, and whether any requirement, decision, proof row, or the experience artifact is affected. Carry it into the Step 10 report. If something is affected, stop for `/document` reconciliation; otherwise continue.
- `20` NO_DELIVERY: there is no delivery contract to build from; recommend `/document`.
- `30` NO_PRODUCT: a technical-scope issue (`Scope basis: technical`, `TR-*` identifiers) continues from its delivery contract; the check still prints the code-drift lines for the watched paths, and when they say `CHANGED` the paragraph above is owed just the same. An issue that links a Linear identifier instead is a legacy issue: if the `linear` CLI is installed and signed in, run `linear issue --help`, read the scope with the `linear` CLI, read-only, compare its current `updatedAt` with the one the delivery contract recorded (older issues call it `Scope version`), and stop for `/document` reconciliation when product behavior, boundaries, constraints, or identifiers changed; otherwise report the linked Linear scope as unreadable and stop for `/document`. Never write to Linear.
- `1`: the check could not run (a commit the checkout has not fetched, a gh failure, a malformed section). Fix the cause and rerun; never continue on a check that did not run.

Identifiers the check lists as missing from the matrix are unfinished planning unless the delivery contract explicitly defers them or, for an epic child, a sibling issue owns them (confirm against the epic's dependency list). If a product-facing issue has neither a product contract nor an explicit technical basis, pause only when the missing product decision would materially change delivery.

Report one short update:

> Starting work on #[number]: [title]

Check whether the issue belongs to an epic:

1. Read the `parent` field from the fetch above (a GitHub sub-issue).
2. Search open issue bodies for task-list references to `#$ISSUE_NUMBER`.
3. Check milestone siblings.
4. Check labels such as `epic/*`, `phase-*`, or `part-of-*`.

If a parent epic exists, record the parent, current phase, completed phases, and remaining phases. Completing the current issue must not be described as completing the whole epic.

### Step 4: Determine the Required Workflow

Read the issue's delivery tier and proof plan. A `lean` label or light tier controls issue
depth; it does not excuse an applicable test or runtime check.

#### Lean issue

- Use the compact delivery and proof plan in the issue.
- For new or changed behavior, still work test-first and observe the relevant test fail and pass.
- For behavior-preserving prose, formatting, or mechanical work, use the stated non-runtime proof and explain why behavior tests do not apply.
- Browser verification remains mandatory when the issue changes a user-visible surface.

#### Test-first behavior work

Test-first implementation is required when the issue changes product or runtime behavior. A
legacy issue also signals this requirement when it mentions any of the following:

- `TDD Required` or `Test-Driven Development Required`.
- `Write tests FIRST` or a failing test first.
- RED, GREEN, and REFACTOR in a testing workflow.
- A `TDD Workflow` section.
- A named failing behavior test.

When test-first work is required:

1. Investigate existing tests and test conventions before production code.
2. Select the next requirement or proof row.
3. Use an existing test that fails for that behavior; add or change a test only when coverage
   is missing. Do not duplicate an existing meaningful test to satisfy this sequence.
4. Run it and confirm it fails for the expected reason.
5. Write the minimum complete production change needed to pass.
6. Run the test and confirm it passes.
7. Refactor while keeping tests green.
8. Repeat until every applicable requirement and proof row is covered.

If the repository has no test runner, create the smallest repository-appropriate test harness as part of the RED phase. The absence of existing tests is not a reason to stop or skip TDD.

#### UI detection

Set `UI_AFFECTED = true` when the issue changes a page, card, table, component, layout, label, visual state, styling, responsive behavior, or any other browser-visible result.

UI changes require the browser runtime pass in Step 9.

#### Provisional proof obligations

Predict from the issue text which proof classes from Step 9 the work should trigger: an import or sync feature predicts a records obligation, a migration predicts a stored-data obligation, a visible change predicts browser verification. Record the prediction.

A predicted stored-data-and-access obligation has a deadline the others do not: its baseline must be captured in Step 7, before implementation changes anything. Carry that prediction forward explicitly.

The prediction is a cross-check, not the classification. Step 9 re-derives the obligations from the actual diff, and the diff decides. A class the issue predicted but the final diff never triggered is a scope question — ask whether part of the requested work went unimplemented — not an obligation to satisfy for form's sake.

### Step 5: Review Tools and Subagent Needs

Review available tools before implementation. Select only those relevant to the issue, such as database access for data-backed behavior, GitHub for issue context, documentation lookup for unfamiliar libraries, or browser tooling for UI verification.

Consider subagents when they materially improve the work:

- Deep codebase exploration.
- Security-sensitive changes — any change to who can read or write data, to authentication, or to how credentials are handled.
- Multiple independent implementation streams.

Do not use subagents for ceremony. A focused issue with one implementation path should proceed directly. Do not spawn subagents to verify or double-check your own implementation; the one sanctioned verification subagent is the grill proof review in Step 9, which has its own trigger conditions.

### Step 6: Prepare or Resume the Issue Branch

Determine the branch prefix from issue labels:

- `bug` -> `fix/`
- `documentation` -> `docs/`
- `enhancement` or `feature` -> `feature/`
- No matching label -> `feature/`

Use a lowercase branch name containing the issue number and a short kebab-case description, for example:

```text
feature/198-email-reminders
```

Make branch setup idempotent:

1. If the current clean branch already matches the issue number, reuse it.
2. Otherwise, if a local branch for the issue already exists, check it out and resume it.
3. Otherwise, check out the repository's default branch (`$DEFAULT_BRANCH`, which is not always `main`), pull it from `origin` using a fast-forward-safe update, and create the issue branch.
4. Never reset or recreate an existing issue branch just to make the workflow look fresh.
5. Preserve commits already made on the issue branch.

If syncing or switching creates a conflict, explain the conflict in plain English and pause before taking any destructive action.

### Step 7: Establish the Baseline

Detect and run the project's normal build and test commands before implementation when they exist.

Common signals include:

- `package.json` scripts.
- `Makefile` targets.
- `pyproject.toml`, `pytest.ini`, or other test-runner configuration.
- Repository instructions in `AGENTS.md`, `CLAUDE.md`, or equivalent files.

Record the baseline result. A pre-existing failure does not automatically stop the workflow:

- Continue when the failure is unrelated and the requested change can still be verified reliably.
- Pause when the failure prevents meaningful implementation or makes it impossible to distinguish a regression.

If no build or test command exists, record that and continue. Add focused test support during TDD when required.

When the build, tests, or database proof need credentials, provide them the way the project documents — its `.env` setup, its secret manager, or its CI secrets. Never paste a secret into the conversation or ask the user to; if the documented route does not work, treat it as missing access and report it as a blocker.

When Step 4 predicted a records obligation and the change will mutate state in place — a migration, a destructive import, a re-keying — capture the before counts now, from a source the change will not touch. A before count destroyed by the change cannot be reconstructed at verification time. Counts over immutable inputs can wait for Step 9.

When the work will touch database access — migrations, schema, row-level security, grants, storage rules, or database functions — capture the security baseline now, for the same reason: after the change there is nothing left to compare against.

- When the project uses Supabase, run the security advisors and **post the output to the GitHub issue as a comment immediately** — each finding's name and object, not just a count. The comparison happens at ship time, possibly in a different session; a baseline that lives only in this conversation does not survive to be compared against.
- Record which roles can currently reach the objects the change will touch, using read-only catalog queries (`pg_policies`, grants). Do not probe current access by calling mutating functions against production — if the current state is broken, the probe is the incident.
- Enumerate the project's consumers before touching anything; when the project uses Supabase, follow [`../document/references/supabase-database-security.md`](../document/references/supabase-database-security.md). Where the project already records its consumer inventory — the project's context map if it keeps one, otherwise its own agent instructions (AGENTS.md, CLAUDE.md) and README, a project memory, a security inventory — read it rather than deriving one from a text search. A search of the current repository undercounts consumers, because most deployments inject the database URL through their environment rather than a committed file.

### Step 8: Implement the Issue

Implementation begins in this step; do not return a "ready to start" response.

1. Inspect the relevant code, tests, data contracts, and documentation.
2. Translate each `SR-*`, `AC-*`, or `TR-*` identifier into an implementation and verification task without changing its product meaning.
3. Follow the required workflow from Step 4.
4. Implement the smallest complete change that satisfies the issue.
5. Keep unrelated refactors and metadata churn out of scope.
6. Update documentation and downstream explanations when the issue changes a business rule or user-visible meaning.
7. Continue until every in-scope acceptance criterion is addressed.

If implementation starts to touch a migration, policy, grant, storage rule, or schema object
that Step 4 did not predict, stop and capture the Step 7 security baseline before applying
the change. After the change is applied there is no pre-change state left to capture, and a
post-change advisor run is not a baseline.

Progress updates should explain what is being learned or changed. They are not completion points and must not end with instructions for the user to tell the agent to continue.

### Step 9: Verify the Result

Verification produces a proof table, not a narrative. Derive the obligations below from the final diff, then answer every one of them in one of three ways:

- **Proven** — the command that ran and the result observed.
- **Doesn't apply** — with a one-line reason.
- **UNMET** — the obligation applies but its proof cannot run here (no database access, no test runner for that surface). Never downgrade an unmet proof to "reviewed the code and it looks correct."

#### The universal floor

Every floor check runs on every change, whatever the classes say. Nothing exempts a change from the floor.

1. **Read the full final diff.** Confirm it contains only intended changes, and state what the change stops doing as well as what it starts doing — removed validations, deleted branches, and dropped fields are changes too.
2. **Run the repository's available checks** — test suite, build, lint, type-check. Report how many tests were collected and executed, not only that they passed. A green run that collected zero tests proves nothing.
3. **Check what the diff exposes.** No secret, admin key, service-role key, or privileged credential may reach code the browser can load or an environment variable published to the client. A credential that was already committed and merely moved by this diff still counts, and so does one that arrived in a config file, a fixture, or a comment. The same applies inside the database: no credential inlined in migration SQL, a trigger definition, a scheduled-job command, or a function body — webhook and job auth headers come from the database's secret store at call time (on Supabase, Vault).

#### Deriving the obligations

Classify from the final diff, not from the issue text or the branch name, and reconcile with Step 4's prediction. Every `SR-*`, `AC-*`, or `TR-*` identifier from Step 3 must map to at least one row of the table; an identifier with no proof row is unfinished work, not a reporting gap.

**1. Records** — the diff touches code that transforms collections of data items: files, rows, API results, messages. Importing, extracting, filtering, deduplicating, migrating, aggregating, syncing. Proof:

- Count in, count out, count rejected — and the three reconcile.
- The input count comes from a source the diff did not touch: a raw file count, a Step 7 baseline count, the upstream system's own total. A pipeline must not be the only witness to its own input, or it will reconcile cleanly around its own bug.
- Sample the rejected records and justify each one. A run that rejects 160 records and balances its books has proven conservation, not correctness.
- Any key used to look up, join, or deduplicate records is shown unique over the real data by a real query, not assumed unique from a schema or a name.

**2. Stored data and access** — migrations, schema changes, row-level security, grants, storage rules, database functions, or any new path that reads or writes a table. Proof has two halves, and the first half alone proves nothing:

- **Positive** — run the real query against a real database as the role the application actually uses — the RLS-scoped user, not the service key — and assert the rows that come back. Prefer a before/after count over one hand-picked row: a count that drops to zero is how a lockdown that broke the app announces itself.
- **Negative** — run it again as the roles the object's **declared audience** excludes: the anonymous/public key unless the object is public-read by recorded intent, a user from a different account or tenant, and any internal role the contract excludes. Assert they get nothing — or, for a declared public-read object, that anon gets only the declared projection and cannot write. A table with its protection turned off passes the positive half perfectly, which is exactly why the positive half cannot detect an exposed database.

Asserting text inside a migration file proves nothing about behavior; a migration written correctly and never applied reads the same as one that was.

When the project uses Supabase, this class also requires the shared standard in [`../document/references/supabase-database-security.md`](../document/references/supabase-database-security.md): declare each object's audience from the contract or consumer inventory (never at proof time), follow the standard's **How to run the proof** section — a bare `execute_sql` result is admin evidence, and mutating probes run on a branch, never production — consult the documentation before writing an access rule, compare the security advisors item-by-item against the Step 7 baseline posted on the issue, and enumerate every consumer of the project before changing who can reach an object. A finding the change introduced is a blocking defect, not a pre-existing condition. If no pre-change baseline exists, the advisor comparison is **UNMET** — a post-change capture is not a baseline.

**3. User-visible** — anything a person sees in the browser. Proof: the runtime pass below, driven in the browser, plus one read-path check — any data-derived figure the change displays is reconciled against an independent query of its source. A page can render perfectly and show numbers that are no longer true.

**4. Behaviour** — business rules, handlers, logic. Proof: a test observed failing for the right reason, then passing. For a behavior-preserving refactor the honest proof is the suite green at the Step 7 baseline and green after; do not write a ceremonial test for a change designed to change nothing.

**5. Everything else** — documentation, formatting, and developer tooling that cannot change program behavior. Proof: the universal floor only. A CLI flag, a test fixture, or a build script that changes what the program does or what the tests measure does not belong in this class.

**6. The open clause** — when the diff creates a risk none of the five proofs addresses, derive the missing obligation yourself and add it to the table. The classes are the floor of coverage, never its ceiling.

#### The provenance obligation

This obligation always applies. Every name, date, number, and attribution the diff adds must trace to a source this session actually opened or a command it actually ran. Name the source in the table, or delete the claim from the code. An invented specific — a confirmation that never happened, a figure no query produced — is a defect even when every test is green.

#### The falsifiability rule

A test is evidence only if it can fail when the behavior it protects breaks.

- A test observed failing during the TDD RED phase has already proven this; do not re-break it.
- For a test written after its production code, break the behavior the test claims to protect — not merely the file it reads — observe the failure, and restore. Anchor the break to the acceptance criterion the test covers.
- For a restored or re-enabled suite, run it, report a nonzero collected count, and falsify a sample per module rather than every test.
- A compile-time or type-level guarantee proves itself by refusing to build; count it as proof.
- A snapshot test fails on any change at all, so on its own it is near-zero evidence for any particular behavior.

#### The runtime pass

The proof table proves claims; this pass observes the running software. Run it whenever the diff reaches a runtime surface — a CLI command, a server route, a browser view, a library's public export, an agent's configured behavior. A docs-only, types-only, or tests-only change has no runtime surface: record SKIP with a one-line reason.

In a harness with a built-in `/verify` skill, invoke it to run this pass. Otherwise follow the protocol directly:

1. Identify the surface where a user meets the change, and drive the smallest path that makes the changed code execute: run the changed flag, hit the changed route, trigger the changed error.
2. Probe around changed behavior at the same surface — empty or malformed input, a typo'd flag,
   the wrong method, running it twice, interrupting it mid-operation. Run at least one relevant
   probe when interaction or runtime behavior changes. For behavior-preserving prose,
   formatting, or an exact settled copy correction, record why an additional edge-case probe
   adds no meaningful proof and directly verify the correction and existing primary path.
   Settled product intent does not exempt a runtime bug fix from behavior probes, and access
   changes still require both halves of their access proof.
3. Capture what the running software actually showed: command output, response bodies, screenshots. Captured output is evidence; memory is not.
4. Give a verdict: PASS, FAIL, BLOCKED (the change could not be made observable — a build or environment problem, which is not a verdict on the change), or SKIP. When in doubt, FAIL, with the raw capture attached. There is no partial pass.

Tests, type checks, and code reading do not count in this pass — the floor already ran them, and re-running them observes nothing new.

##### Browser surfaces

When `UI_AFFECTED = true`, the runtime pass runs in the browser and satisfies the browser-verification requirement — one pass, not two:

1. Start the local development server on an available port.
2. Open the affected route using available browser tooling.
3. Exercise the changed workflow, not only the page-load state.
4. Confirm the visible values, wording, layout, and relevant error or empty states against the issue.
5. Check additional viewport sizes when responsive behavior is in scope.
6. Capture and report browser evidence to the user.

Perform the pass yourself. Ask for user approval only when the expected appearance or behavior is genuinely ambiguous. If browser tooling is unavailable, provide the local URL, ask the user for manual confirmation, and record the pass as BLOCKED — do not claim it occurred.

#### The grill proof review

Run this pass when either raw trait holds, judged from the diff itself so a misclassified change still gets reviewed:

- The diff touches record-transforming code, migrations, schema, access rules, or UI that displays data-derived figures.
- The diff changes more than 5 files and any obligation in classes 1–4 was marked "doesn't apply."

Otherwise skip it. A small, fully proven change does not need a second opinion, and the pass must stay rare enough to mean something.

Give one subagent the final diff, the issue, and the proof table — none of the implementation conversation — and ask it three questions:

1. Which obligation is wrongly marked "doesn't apply"?
2. Which passing proof could not have failed?
3. Re-deriving the class list from the diff independently: which obligation is missing from the table entirely?

When the diff touched data access, ask a fourth: which access proof shows only that the intended role can reach the data, without showing that the roles the declared audience excludes cannot? Where the table claims a negative proof ran, the reviewer re-runs that query itself rather than accepting the row — a proof row that was written but never executed reads exactly like one that was.

A confirmed finding on question 1 or 3 — an applicable obligation that was skipped — is blocking: run the missing proof before Step 10 reports the work ready. Question 2 findings and unconfirmed observations are advisory; carry them into the completion report unedited.

### Step 10: Complete the Work

The work is complete when the proof table is complete — every obligation proven, reasoned out, or honestly UNMET — no blocking grill finding is unresolved, and the runtime pass ended in PASS or a reasoned SKIP. A runtime FAIL means the work is not done. A BLOCKED runtime pass is reported like an UNMET obligation: named plainly, the user's call.

Return a completion report covering:

- What changed, in user-visible or business-rule terms.
- The proof table: each obligation, whether it applies and why, the command run, and the result.
- The universal floor results, including test counts.
- The runtime pass verdict with its captured evidence and probe results — and the local URL when a user-visible surface changed.
- One explicit line naming everything not verified — UNMET obligations and untested areas — even when the line is uncomfortable.
- Grill findings, when the pass ran, unedited.
- Remaining risks or explicitly deferred work.
- The product contract version and fingerprint the work was built against (from the Step 3 check) and the code-drift paragraph when the check reported drift, or the stated technical-scope or legacy Linear basis.
- That the branch is ready for `/ship-it` — or ready except for named UNMET items, which are the user's call to accept or resolve, not the skill's.

Post the proof table as a comment on the issue (`gh issue comment "$ISSUE_NUMBER"`) so the evidence survives the session and is visible at merge time.

Do not change the product contract as part of implementation. If implementation reveals a
needed product-scope change, report it and return it to `/scope` for approval.

If the issue is part of an epic, also state the epic's remaining work. Do not claim the epic is complete unless all child issues are complete.

## Genuine Blockers

Pause only when continuing would be unsafe or impossible, including:

- Local changes are related to the issue, unclear, or unsafe to stash automatically and therefore require a commit-or-stash decision.
- The issue cannot be accessed or does not provide enough information to choose behavior safely.
- Authentication or required external access is unavailable.
- A merge conflict requires choosing between competing user changes.
- A required dependency or service is unavailable and no local substitute can verify the work.
- Product behavior is materially ambiguous and different choices would produce different outcomes.

When blocked, report what was attempted, what evidence was found, and the smallest decision or external change needed to resume. Once resolved, continue the same workflow automatically.

## What This Command Does Not Do

- It does not commit, stash, delete, reset, or overwrite existing local work without user approval.
- It does not commit, push, open a pull request, merge, or deploy completed issue work unless explicitly requested.
- It does not skip required tests or browser verification.
- It does not mark a proof obligation "doesn't apply" without a stated reason, and it does not report an unrunnable proof as anything but UNMET.
- It does not accept a positive-only access proof, change who can reach data without first enumerating the project's consumers, or absorb a newly introduced security-advisor finding into the baseline.
- It does not stop after setup and ask the user to initiate implementation.
