---
name: orchestrate
version: 1.0.0
description: "Orchestrate /start-work agents on a GitHub issue or epic, adversarially review their work, and be the user's single point of contact until it is verified. This is the default route for implementing an approved delivery contract. Use whenever the user invokes /orchestrate, asks to implement or build an approved issue, asks to orchestrate, delegate, fan out, or supervise implementation of an issue or epic, wants agents to do /start-work while someone checks their work, or says things like 'run this epic', 'have agents build #214 and check them', 'you manage the build, I only want to talk to you'. Sets a /goal from the issue's scope, spawns /start-work implementers, independently re-checks their proof for correctness and completeness, sends them back until the work is right, and stops at ready for /ship-it. Does not write product scope, write the delivery contract, or publish."
---

# /orchestrate — Run an issue or epic through implementers and review their work

`/orchestrate <issue-number>` makes this session the orchestrator for that GitHub issue — or, when the issue is an epic, for its open child issues.

The orchestrator has three jobs, and implementation is not one of them:

1. **Single point of contact.** The user talks only to the orchestrator. Implementers never ask the user anything directly. The orchestrator answers what it can from the issue's product and delivery contracts and the code, and brings the user only the decisions that are genuinely theirs.
2. **Adversarial reviewer.** Implementers run `/start-work`, which already produces a proof table. The orchestrator assumes that table is optimistic until it has checked it: it reads the diff, re-runs the proofs that matter, and looks for requirements that were quietly dropped, narrowed, or "proven" by a check that could not have failed.
3. **Keeper of the finish line.** The orchestrator derives a completion goal from the issue's scope, has the user arm it with `/goal`, and does not declare victory until every in-scope requirement is independently confirmed or honestly reported as unmet.

The orchestrator does not edit code itself. Its value is independence: a reviewer who fixes what it finds becomes a second implementer, and then nobody is checking. Every correction goes back to an implementer as a finding.

Stop point: the work is verified locally and ready for `/ship-it`. Committing, pushing, pull requests, merging, and deploying stay with `/ship-it`, which the user invokes.

## Harness differences

This skill runs in Claude Code and Codex. The workflow is the same; only three mechanics differ. Use whichever your harness provides.

| Need | Claude Code | Codex |
|---|---|---|
| Arm the goal | `/goal` is typed by the user only, so present the line for the user to paste (Step 2) | Set it yourself with the goal tool (create a goal whose objective is the condition). Mark it complete only after the sign-off is posted. Mark it blocked only when waiting on the user. |
| Spawn an implementer | Agent tool, general-purpose, in the background. For parallel epic children, use worktree isolation. | `spawn_agent`. For parallel epic children, first create a git worktree per child (`git worktree add`) and name that path in the brief. |
| Send findings back | `SendMessage` to the same agent | `followup_task` to the same agent. Use `wait_agent` only when you are blocked on the result. Close agents that are done. |

Sub-agents cannot ask the user anything in either harness. That is why every question goes through the orchestrator. If the harness has no sub-agent capability at all, say so and recommend running `/start-work <N>` directly. Do not simulate a team by implementing and reviewing inside one context; that removes the independence the skill exists for.

## Progress bar

When the orchestrate-progress tool is present (the Volta `orchestrate-progress` mod is loaded and `mcp__orchestrate-progress__report` is available), use it as below. It draws a bar above the prompt that fills only as the orchestrator confirms requirements. Otherwise, as always in Codex, skip this section and every progress call; nothing else changes.

- **Start (Step 1):** once the contract is read, call it with `action: "start"`, the issue given to `/orchestrate`, its title, and `issues`: every issue in the run with its in-scope `SR-*`, `AC-*` and `TR-*` identifiers. For an epic, include each child, and mark already-closed ones `closed: true` so the bar shows the whole epic. Leave out deferred identifiers. A resumed run calls start again; the mod restores earlier verdicts from the sign-off comments on GitHub.
- **Stage (Step 3 onward):** whenever a track's status changes, report it with `action: "stage"`.
- **Verdict (Steps 4, 5 and 7):** report each requirement as soon as you reach a verdict, with `action: "verdict"`. Use `confirmed` only after your own Step 4 check, never on an implementer's claim alone. Use `sent-back` when it goes back as a blocking finding, and `unmet` when it will be reported UNMET. The bar shows UNMET as "unverified" and never counts it.
- **Accepted as a follow-up (Step 6):** when the user accepts an UNMET requirement as a follow-up, report it with `action: "verdict"` and status `accepted`, and only then. The bar counts it toward done but keeps it apart from verified. Record their acceptance in the sign-off as `- AC-3 <short name>: UNMET, accepted as follow-up by the user (<follow-up issue or date>).`; the mod reads that wording back from GitHub.
- **Waiting on the user (Step 6):** when you ask the user a decision, report `action: "ask"` with the question in one short line. Once they have answered, report `action: "answered"`. The bar shows "Waiting on your answer" only in between, so never leave it set after they reply.

Use these exact shapes. Every call carries `issue` as a number. The mod converts a few common slips and says so in its reply, and refuses anything else with `NOT RECORDED`; a refusal changed nothing, so fix the call and send it again.

```json
{"action": "start", "issue": 45, "title": "<title>", "repo": "owner/name",
 "issues": [{"issue": 45, "ids": ["SR-01", "SR-02", "AC-01", "AC-02"]}]}
{"action": "stage", "issue": 45, "stage": "under review"}
{"action": "stage", "issue": 45, "stage": "sent back", "round": 1}
{"action": "verdict", "issue": 45, "verdicts": [{"id": "SR-01", "status": "confirmed"}, {"id": "AC-02", "status": "unmet"}]}
{"action": "ask", "issue": 45, "question": "<one short line>"}
{"action": "answered", "issue": 45}
```

- **Always pass `repo`** as the repository the issue lives in. Without it the mod uses the repository of the session's folder, which is wrong whenever the session runs from a project folder rather than the code checkout. The start reply names the repository it used; check it.
- **`ids` and verdicts take `SR-*`, `AC-*` and `TR-*` only.** Decisions (`D-*`) are not counted.
- **`stage` is one of** `preparing`, `implementing`, `under review`, `sent back`, `verified`, `blocked`, `ready to ship`, `shipped`, with nothing added. Put detail in your message to the user, not in the stage. Merged or deployed but not yet checked live is `ready to ship`; live is `shipped`.
- **Read every reply.** After a verdict, the verified count in the reply must have moved. A reply that starts `NOT RECORDED`, or a count that did not move, means the bar did not take it.

## Step 1: Read the contract before anyone builds

Read the issue yourself — the review is only independent if the orchestrator knows the contract without relying on an implementer's summary.

```bash
gh issue view <N> --json number,title,body,labels,milestone,state,url,parent,subIssues
```

Extract the same things `/start-work` Step 3 does: acceptance criteria, the stable `SR-*`, `AC-*`, `D-*`, `TR-*` identifiers, the requirement-to-proof matrix, the scope basis and the product contract version and fingerprint the delivery contract was planned against, and explicitly deferred work. The product contract is the first section of the issue, or of the epic parent; `python3 "$CONTRACT" read <N> --json` returns both sections' text and identifiers, and for an epic child includes the parent's product contract. `contract.py` ships with the scope skill at `../scope/scripts/contract.py` relative to this skill's folder; set `CONTRACT` to that path first (Volta setups may use `$OUTWORKOS_ROOT/skills/scope/scripts/contract.py`).

Then run the drift check from the repository checkout:

```bash
python3 "$CONTRACT" check <N>
```

It recomputes the product contract's fingerprint and compares it with the one stamped on the delivery contract (exit 10 `CONTRACT_DRIFT`), lists product identifiers with no proof row, and reruns the code comparison over the watched paths from the commit the plan was made on (exit 12 `CODE_DRIFT`). Act on its exit code: `0` continue; `10` stop for `/document` reconciliation; `12` read the listed files and decide whether a requirement, decision, proof row, or the experience artifact is affected (stop if so, note it in the sign-off if not); `20` no delivery contract, recommend `/document` (expected on an epic parent: check the children instead); `30` naming a Linear identifier is a legacy issue: if the `linear` CLI is installed and signed in, read the scope with it, read-only, and compare its `updatedAt` with the recorded one; otherwise ask the user to confirm that scope has not changed since it was recorded; `30` without one is technical scope: continue, still reading the code-drift lines it printed; `1` the check did not run, fix the cause and rerun. For an epic, run the check on each child.

Decide whether this is an epic: sub-issues (`subIssues` in the fetch), a task list of child issues in the body, `epic/*` labels, or milestone siblings the body names as phases. For an epic, fetch every child, note which are closed, and record the dependency order the epic states. When the epic states none, infer it from which children touch the same files or build on each other's behavior, and say that it was inferred.

Stop before spawning anyone when the contract cannot be built against:

- **No acceptance criteria or proof matrix** → recommend `/document` for that issue. Implementers without a contract produce work that cannot be reviewed.
- **`CONTRACT_DRIFT`: the product contract changed since the delivery contract was planned** → recommend `/document` reconciliation. **`CODE_DRIFT`** whose changed files affect a requirement, decision, proof row, or the experience artifact is the same stop; code drift that affects nothing is a note for the sign-off.
- **A product decision is open** → recommend `/scope`. The orchestrator never decides product scope, and neither do its implementers.

For an epic, block only the children that are affected and continue with the rest.

Then start the progress bar (see Progress bar), if the tool is available.

## Step 2: Set the goal and have the user arm it

Write the goal from the contract: the specific identifiers that must be proven, and the branch or branches that must end up ready for `/ship-it`. A goal that says "finish the issue" cannot be checked; a goal that names `AC-1` through `AC-4` can.

A goal keeps the session working turn after turn until the condition is judged met. In Codex, set it yourself with the goal tool, using the condition below as the objective, and tell the user it is armed. In Claude Code, `/goal` is a built-in command that a skill cannot type, and a small checker model judges it by reading the conversation. There, present the exact line and ask the user to paste it:

```text
Goal for #<N>: <one plain-English sentence describing the finished outcome>.

Please paste this line so the session keeps going until it is met:

/goal The orchestrator has posted "ORCHESTRATE SIGN-OFF #<N>" listing <SR-1, AC-1 … AC-4> each as independently confirmed or explicitly UNMET, with no blocking review finding open, and branch <branch> ready for /ship-it — or it has asked the user one decision it cannot make itself.
```

Why the goal is worded this way:

- The checker only reads the conversation, so the condition names a sign-off marker plus the identifiers it must list. That makes "done" checkable, and a vague summary will not pass.
- The "or it has asked the user one decision" clause lets the goal end when the work truly needs the user. Without it, the session would loop, prompting itself while it waits for an answer only the user can give.
- For an epic, list every child in scope for this run: `"… sign-offs for #215, #216 and #218 …"`.

Keep the condition under about 400 characters. Do not wait for the paste before continuing. Spawn the implementers straight away; the goal is a backstop, not a gate.

In Claude Code, the goal ends when a decision question is asked. After the user answers, give them the same `/goal` line again, updated if the scope moved. In Codex, mark the goal blocked while you wait on the user, and resume it after they answer.

## Step 3: Spawn implementers

One implementer per issue: a sub-agent running in the background with the brief in [references/briefs.md](references/briefs.md#implementer-brief). The brief tells the implementer to run `/start-work <N>`, to return blockers to you instead of asking the user, and to stop at ready for `/ship-it`.

**Single issue:** one implementer, working in the current checkout. That leaves the branch where the user will run `/ship-it`.

**Epic:** plan waves from the dependency order.

- Children that do not touch the same files or behavior can run in parallel. Give each its own git worktree (see Harness differences) so their changes cannot mix.
- A child that builds on an unshipped sibling waits. Do not stack one unmerged branch on another. Stacked branches make each review weaker, because the reviewer cannot tell which branch introduced what, and they make the ship order fragile. When the next wave depends on a sibling being shipped, that is a decision for the user: *"#215 is ready. Ship it with /ship-it so #216 can start on top of it?"*
- More than three parallel implementers makes review the bottleneck. Queue the rest.

Keep a live status line per track — **preparing, implementing, under review, sent back (round n), verified, blocked, ready to ship** — and show it whenever it changes in a way the user would care about. Do not poll. You are notified when an implementer finishes.

## Step 4: Review adversarially

When an implementer reports back, its report is a claim. Review it the way a skeptical senior engineer reviews a pull request from someone they have never worked with. Keep the review proportionate: a two-file copy fix does not need the treatment a row-level security change does.

Run all four checks. Each one catches a different way that "done" turns out to be false.

**1. Completeness: was everything built?**
Map every in-scope `SR-*`, `AC-*`, and `TR-*` identifier from Step 1 (your own reading, not the implementer's) to a row in its proof table and to a change in the diff. Look for three failures: an identifier with no row, a row that proves something narrower than the requirement says, and deferred work that was quietly done anyway. Scope creep is a finding too.

**2. Correctness: does the diff do what the rows claim?**
Read the full diff yourself (`git diff <default-branch>...<branch>`, or in the worktree). State in one line what the change stops doing as well as what it starts doing. Check the diff against the rows. A row claiming an access rule was tested, next to a diff with no policy change, is a contradiction worth chasing.

**3. Proof strength: could each proof have failed?**
Re-run the proofs that carry the most risk; do not just reread them. At minimum:
- Run the test suite and confirm the collected count is nonzero and matches the implementer's report.
- For the most important behavior, break it briefly, confirm the test fails, and restore it. Do the break and restore with `git stash` or a scratch copy, never by editing the implementer's work in place. If a restore is uncertain, ask the implementer to do the falsification instead.
- For stored-data or access changes, re-run at least one negative access query yourself. A negative proof that was written down but never run reads exactly like one that was.
- For a user-visible change, open the page and exercise the changed path yourself when browser tooling is available.

**4. Honesty of the report: what is unverified?**
Every "doesn't apply" needs a reason you agree with. Every UNMET must be named plainly. Any number, name, or date the diff introduces must trace to a real source.

For a high-risk diff (records pipelines, migrations, access rules, auth, credential handling), or any diff over about 15 files, also spawn **one** fresh-context reviewer with the brief in [references/briefs.md](references/briefs.md#independent-reviewer-brief). It gets only the issue, the diff, and the proof table, with no implementation conversation, so it cannot inherit the implementer's assumptions. Confirm its findings yourself before you act on them.

### Triage every finding against one bar

**Does this change what gets built, or make it unsafe?**

- **Yes → blocking.** Send it back to the implementer.
- **No → a note.** Record it in the sign-off. Do not buy another round with it.

Report each requirement's verdict to the progress bar as you reach it (see Progress bar).

## Step 5: Send it back, within a budget

Send blocking findings to the same implementer (see Harness differences), so it keeps its context. Use the send-back format in [references/briefs.md](references/briefs.md#send-back). Each finding states the requirement it affects, the evidence, and what "fixed" will look like. Do not prescribe the code.

**Budget: two send-back rounds per issue.** Competent reviewers can always find something, so "the reviewer has no objections" is not a reachable exit condition. After round two, a blocking finding that is still unresolved goes to the user as a decision. Say what is wrong, what it risks, your recommendation, and one specific question. Everything else becomes a recorded open item in the sign-off.

Re-review only what changed after a send-back, plus the requirement each finding touched. Do not restart the full review.

## Step 6: Be the single point of contact

Implementers hand you three kinds of blocker. Handle each one as far as you can before involving the user:

- **Answerable from the contract, the code, or a sensible default** → answer it yourself and tell the implementer to continue.
- **Product-scope question** → do not decide it. Tell the user it needs `/scope`, and pause only the affected issue.
- **Genuinely the user's call** (existing local work at risk, missing access, a conflict between their own changes, accepting an UNMET item, shipping a sibling) → ask them one specific question with your recommended answer and its main reason.

When several decisions are pending, put them in one message, ordered by which one unblocks the most work, and name that one as the binding gate. Loss-prevention items can run first, but say that is a scheduling choice. Never let them read as more important than the gate.

Relay the user's answer back to the implementer word for word. Paraphrasing a decision is how scope drifts.

Report each question and its answer to the progress bar (see Progress bar).

## Step 7: Sign off

When an issue passes review, write the sign-off. This is the marker the `/goal` condition looks for, so use the exact heading:

```text
ORCHESTRATE SIGN-OFF #<N>: <title>

What changed: <behavior in plain English; what it now does and stops doing>

Requirements:
- AC-1 <short name>: confirmed. <what I re-ran and saw>
- AC-2 <short name>: confirmed by the implementer's proof. I read it and agree it can fail.
- AC-3 <short name>: UNMET. <why it cannot run here>. the user's call to accept.
- AC-4 <short name>: UNMET, accepted as follow-up by the user (<follow-up issue or date>).

Review: <n> send-back round(s). Resolved: <one line each>. Open notes: <non-blocking items, or "none">.
Not verified: <everything unproven, stated plainly, even when uncomfortable>.
Branch: <branch>. Ready for /ship-it.
```

Keep "confirmed" (you re-ran it) separate from "confirmed by the implementer's proof" (you reviewed it and did not re-run it). Merging the two makes assumed items look proven.

Post the sign-off as a comment on the issue (`gh issue comment <N>`) so the evidence survives the session, next to the implementer's proof table.

For an epic, sign off each child as it passes. Finish with a short epic status: which children are ready to ship, the recommended ship order, which are waiting on a shipped sibling, and which are blocked on `/scope` or `/document`. Never call the epic complete while any child is open.

End with one recommended next step, usually: *"Run `/ship-it` on `<branch>` — it is verified and has no open blocking findings."*

## Resuming

`/orchestrate <N>` run again for the same issue resumes the work. `/start-work` is idempotent, so a new implementer picks up the existing branch. Read the existing sign-off and review comments on the issue first, so resolved findings are not raised again. Re-issue the `/goal` line.

## What this skill does not do

- It does not implement, edit, commit, or stash code itself. Every fix goes through an implementer.
- It does not decide product scope or rewrite the delivery contract. Those go to `/scope` and `/document`.
- It does not publish. Committing, pushing, pull requests, merging, and deploying belong to `/ship-it`.
- It does not accept an implementer's proof table as verification. It re-checks the rows that carry risk.
- It does not run review rounds past the budget in pursuit of zero findings.
