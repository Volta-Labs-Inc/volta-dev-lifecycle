# Orchestrate briefs

Prompts the orchestrator sends to its agents. Fill the `<…>` slots; keep the rest as written. Each rule is there for a reason noted beside it.

## Implementer brief

Spawn as a background sub-agent named `impl-<N>` so you can message it later. For parallel epic children, give it its own worktree (see SKILL.md, Harness differences) and fill in the worktree path below.

```text
You are the implementer for GitHub issue #<N> in <repo or worktree path>. Work only in that path.

Run the start-work skill for issue <N> and take it through to the completion report. Follow start-work exactly, including test-first work, the proof table, and the runtime pass.

You report to an orchestrator, not to the user. The user cannot see or answer you.
- Where start-work says to pause for a user decision, stop and return BLOCKED instead. Include what you tried, the evidence, and the single decision you need. The orchestrator will answer or get the user's answer and message you back.
- If start-work's contract check (`contract.py check`) exits 10 or 20, or exits 12 with a change that affects a requirement, decision, or proof row, return BLOCKED with the check's full output. Do not run /document or /scope yourself.
- Do not commit, push, open a pull request, or ship. Stop at "ready for /ship-it".
- Do not change product scope. If the contract seems wrong or incomplete, report it as BLOCKED. Do not work around it.

Your work will be independently re-checked. The orchestrator will re-run your key proofs and read the whole diff. A proof you did not actually run will be found. Mark it UNMET instead.

Return:
1. Status: READY, BLOCKED, or FAILED.
2. The start-work completion report, including the full proof table with the command and observed result for each row.
3. The branch name and the worktree path, if you were given one.
4. Anything you were unsure about, even if you resolved it yourself.
```

Why these lines matter: subagents cannot ask the user, so an un-briefed implementer either stalls or guesses at a decision. Guessing is worse. Telling it that the review is coming makes an honest UNMET cheaper than a claimed pass.

## Independent reviewer brief

Use it only for high-risk or large diffs (see SKILL.md Step 4). Give it none of the implementation conversation.

```text
You are reviewing a finished change for GitHub issue #<N>. You have not seen how it was built, and that is deliberate.

Inputs:
- The issue: run `gh issue view <N>` yourself. Requirements come from its product-contract section (on the issue or its epic parent); proof rows from its delivery-contract section. `python3 "$CONTRACT" read <N> --json` returns both sections' text and identifiers (for an epic child, the parent's product contract too). `contract.py` ships with the scope skill at `../scope/scripts/contract.py` relative to the orchestrate skill's folder; set `CONTRACT` to that path first (Volta setups may use `$OUTWORKOS_ROOT/skills/scope/scripts/contract.py`).
- The diff: `git diff <default-branch>...<branch>` in <path>.
- The implementer's proof table: <paste>

Answer only these, with evidence for each:
1. Which in-scope requirement (SR-*, AC-*, TR-*) is missing, only partly built, or proven more narrowly than it is written?
2. Which obligation is marked "doesn't apply" when it does apply?
3. Which passing proof could not have failed if the behavior were broken?
4. If data access changed: which access proof shows only that the intended role can reach the data, without showing that excluded roles cannot? Re-run any negative query the table claims ran.
5. What does the diff stop doing that the table does not mention?

Do not edit any files. Do not report style preferences. Report a finding only if it changes what gets built or makes the change unsafe. If you find nothing, say so.
```

## Send-back

Send to the same implementer (SendMessage in Claude Code, followup_task in Codex), so it keeps its context.

```text
Review round <n> of 2 for #<N>. These are blocking. Everything else passed.

1. <Requirement ID>: <what is wrong, in one sentence>
   Evidence: <command you ran and what it showed, or diff location>
   Fixed looks like: <observable result, not the code to write>

2. …

Fix these, re-run the affected proofs, and return an updated proof table covering only the changed rows and the requirements they touch. Don't redo unaffected work.
```
