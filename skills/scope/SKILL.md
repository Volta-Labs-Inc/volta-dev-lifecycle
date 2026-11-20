---
name: scope
version: 1.0.0
description: "Define or refine product scope before technical planning. Use whenever the user wants to shape a feature, write a PRD or product brief, turn feedback into a product contract on a GitHub issue, decide whether work is light or full, pressure-test a product change, or invokes /scope. Separately locks the original outcome, named milestone, user experience, adjacent behavior, and proportionate risk posture; requires an approved low- or high-fidelity artifact for material experience changes; and blocks technical planning while those decisions remain open. Use the `grill` modifier when the user asks to be challenged, invokes /feature-forge (if installed), or the work has material ambiguity or risk. Does not choose implementation details or write the delivery contract."
---

# /scope - Define the Product Contract

Turn an idea, request, or existing issue into a product contract that a product manager can
own and a developer can later translate into a delivery plan. The contract lives as the
product-contract section of a GitHub issue; `/document` writes the delivery contract directly
below it.

The skill owns **what outcome is required and why**. It does not own code, architecture,
database design, test files, or implementation sequencing. Those belong to `/document`.

## Authority and handoff

- The project's context map, if it keeps one, otherwise its own agent instructions (AGENTS.md,
  CLAUDE.md) and README, routes systems of record and supporting evidence.
- The GitHub issue's product-contract section owns the current product outcome, scope,
  decisions, commitments, and open blockers. Only `/scope` writes it.
- The same issue's delivery-contract section, written by `/document`, owns the technical
  delivery contract.
- The repository and running system are evidence for what currently exists.

Keep research and implementation material out of the product contract. Link to evidence and
record the current product commitment.

```text
/scope -> approved product contract (GitHub issue) -> /document -> delivery contract (same issue)
  -> /orchestrate (its workers run /start-work) -> /ship-it
```

## Non-negotiable product gates

These gates protect the user's intended outcome from being narrowed, relocated, or hardened into
a different product during discovery:

1. **Preserve the literal outcome.** Restate the user's original requested outcome separately
   from the proposed milestone. If the milestone omits a core capability, label it partial,
   obtain explicit approval for the deferral, and never represent that milestone as completing
   the original outcome.
2. **Treat experience as product scope.** Material changes to capability, job-to-be-done, entry
   point, navigation, information hierarchy, placement, label, default, or an existing adjacent
   journey are product decisions. Record them as requirements or `D-*`; do not leave them for
   `/document` to invent.
3. **Approve the experience before technical planning.** When the increment materially changes
   an interface or journey, use prototype mode and obtain approval of a low- or high-fidelity
   experience artifact before handoff. No approved experience artifact means `/document` is
   blocked.
4. **Approve one named milestone.** The milestone must state its definition of done, what remains
   unchanged, what is deferred, and whether it completes the original outcome. Exploratory
   agreement, approval of an individual decision, and approval to write the issue are not
   substitutes for milestone approval.
5. **Choose the simplest complete solution at a proportionate risk level.** Start with the
   smallest change to the existing journey. Add a screen, mode, authority, durable record,
   subsystem, or security control only when it is required by the approved outcome or a credible
   incremental risk. Record optional hardening separately.

### Settled corrections

An exact copy correction or restoration of already-approved placement or behavior does not
reopen product discovery when it preserves meaning, available actions, permissions, defaults,
discoverability, and the adjacent journey. Record the requested correction and its source;
reuse the approved experience artifact when relevant, or state `No material experience change —
settled correction` with the reason. Do not manufacture a prototype or ask the user to choose
again solely because a label or interface file changes. A label that changes meaning or a move
that changes discoverability is still a material experience decision.

Use the user's explicit choices and established project conventions for routine details.
Ask only when the answer could change the outcome, experience, authority, or credible risk.
Continue independent investigation while a question is pending. Existing approval remains
valid for the unchanged approved action; a changed draft or write still follows the
re-fingerprinting and approval rules below.

## Proportionality gate

Size the remedy before opening a planning workflow or durable artifact:

1. Inspect only enough of the current system to identify the smallest safe user-visible change.
2. State the probable remedy in no more than three bullets, the likely implementation effort,
   and the planning budget.
3. Name the existing user journey, authority, access boundary, mutation path, and recovery
   behavior that the change reuses.
4. State the literal requested increment and the first explicit non-goals.

Keep planning effort below roughly one quarter of the likely implementation effort. If planning
starts to exceed that budget, stop and reduce the contract or split optional hardening into
follow-up work. Investigate a material unknown when it prevents responsible sizing; do not use
uncertainty as permission to inventory every possible risk.

## Depth and modifiers

Choose a candidate depth after the proportionality gate. Default to light. Review may recommend
full depth, but it cannot silently promote the work. Unless the user explicitly invoked full or
grill, preview the reason, added scope, and estimate impact and obtain approval before promotion.
Depth controls scope and review effort, not whether applicable behavior needs proof.

### Light

Default to light when the work has one clear outcome and journey, settled decisions, bounded
impact, and is likely to need one focused delivery issue or pull request. Reusing an existing
approved external action, permission boundary, data contract, or recovery path remains light
when the requested change does not alter those controls.

Adding a trusted entry point for the same user, same connected account, and same approved action
remains light even when that particular screen or command was previously read-only. A new entry
point is not new product authority unless it expands who can act, which account or tenant can be
affected, what provider permission is granted, or which action is authorized.

An external provider, stored-data read or write, or reversible mutation does not make work full
by itself.

Light uses one concise contract and one fresh-context challenge. Start with three to five `SR-*`
requirements, two to four `AC-*` acceptance examples, and no `D-*` decision unless a material
choice actually exists. Seven requirements, five acceptance examples, and three decisions are
ceilings that trigger reduction, not targets to fill. Keep light to one delivery increment. When
the draft reaches a ceiling, remove duplication and split follow-up work before considering
promotion. For exploratory work that is not going to GitHub, keep the draft in conversation
unless compaction or handoff is likely.

### Full

Use full only when the requested increment itself introduces or materially changes at least one
of these:

- multiple user journeys or independently shippable delivery increments;
- which people, roles, tenants, or connected accounts may act; provider credential or consent
  scope; who may see or change data; or a durable data contract;
- irreversible behavior without an existing recovery path;
- significant operational coordination; or
- a material unresolved product decision that changes what gets built.

Do not choose full solely because the existing system has broader reliability, privacy,
security, or operational weaknesses. Classify those separately under the scope-delta boundary.

Full uses the durable draft package and all three review lenses. One fresh reviewer may apply
all three lenses in one pass; use separate reviewers only when the stakes justify the extra cost.

### `grill` modifier

`grill` forces full depth. Use it when the user asks to be challenged, invokes
`/feature-forge` (if installed), or the product decisions are materially ambiguous or risky.

The grill method is:

1. Reconnaissance before questions.
2. One consequential question at a time.
3. A recommendation after each answer.
4. Pushback on contradictions or unsupported choices.
5. A durable decision and objection record.

### `prototype` modifier

Use automatically when the proposed increment materially changes a user-facing capability,
job, entry point, navigation, information hierarchy, placement, label, default, or adjacent
primary journey. Also use when the user asks for a PRD, wireframe, mockup, or prototype.
Complete an initial product framing, then read
[references/prototype-brief.md](references/prototype-brief.md) and make only the prototype
needed to lock the affected experience. Low fidelity is sufficient for familiar interactions
where placement, hierarchy, flow, or terminology is the material decision. Use high fidelity
when visual density, responsive behavior, a novel interaction, or realistic content could
change the decision. The contract remains authoritative for rules, permissions, and edge cases
the prototype cannot show. Prototype evidence may reopen the contract before approval.

Modifiers can combine: `/scope grill prototype ...`.

## Scope-delta and expansion boundary

Add a requirement, constraint, or blocker to the current contract only when both are true:

1. The requested increment introduces or materially worsens the condition.
2. Resolving it is necessary for the literal outcome or for that increment to be safe to use.

Ask: **Would this condition still exist if the requested change were not built?** If yes, default
it to a linked follow-up or explicit non-goal. It may enter the increment only when the change
materially increases exposure or cannot responsibly reuse the existing path without resolving
it.

Do not add a new user journey beyond the literal request, actor or account authority, permission
model, durable record, recovery system, migration, cross-process coordination mechanism, or
operational subsystem without previewing the expansion and obtaining explicit user approval.
Reviewer findings never grant that approval.

## Durable artifact boundary

Read [references/github-handoff.md](references/github-handoff.md) and create or resume its
draft package when any of these are true:

- the user wants the product contract created or updated on GitHub;
- the work is full or grill depth;
- compaction, replacement, or handoff could lose decisions.

Checkpoint after reconnaissance, every resolved or reopened `D-*` decision, the complete draft,
review reconciliation, and approval. Never leave the only copy of a decision in conversation
context. The GitHub issue becomes authoritative only after the controlled write and its
read-back both succeed.

The draft package holds only the text below the section heading; the script writes the
heading and the stamp. Name the journeys under `## Relies on` precisely: `/document` turns
them into the paths the drift check watches, and an empty list makes that check compare the
whole repository.

## Workflow

### 1. Size, orient, and investigate

1. Inspect the narrow current path needed to complete the proportionality gate.
2. State the probable remedy, implementation estimate, planning budget, reused controls, and
   explicit non-goals before drafting a contract.
3. If you have Volta's systems (the `outwork` command is available), read the project manifest
   when the project or system of record is not already established, and run `outwork context`
   when it was not injected and cross-project routing matters; otherwise skip this step.
4. Read the project's context map, if it keeps one, otherwise its own agent instructions
   (AGENTS.md, CLAUDE.md) and README, before proposing an operating-record change.
5. If the project keeps a context map and it is missing or materially stale, flag that before
   writing the contract.
6. Read referenced feedback, decisions, research, the existing GitHub issue when there is one
   (`contract.py read <issue>`, see [references/github-handoff.md](references/github-handoff.md)),
   and relevant evidence.
7. When the user points at a Linear issue and the `linear` CLI is installed and signed in, read
   it as evidence of the current product commitment and carry it into the product contract;
   otherwise skip this step. Do not write to Linear; it is no longer a system of record for
   product scope.
8. For Volta customer work, read the project's Solution Brief at 1.0: if you have Volta's
   systems, from its context map link with the Artifact tool; otherwise from the 1.0 file or link
   Volta sent. If it is not at 1.0 or can't be found, stop and ask for it, recommending
   `/solution-brief`; do not scope without it. Work that is not Volta customer work (internal or
   technical work, or a builder's own project) skips this step and proceeds from the user's own
   description of the outcome. Scope one of the brief's increments: carry its target metric into
   Outcome, its constraints into Risk posture and Relies on, and link it under Source links. Do
   not reopen the chosen approach here; if scoping shows the approach is wrong, return it to
   `/solution-brief`.
9. Create or resume the draft package when the durable artifact boundary applies.

Reading GitHub (and Linear, where available) is allowed. Creating or changing the product
contract requires an exact preview and explicit approval.

### 2. Frame the problem

State what the evidence establishes before asking questions:

- the outcome that should change;
- who experiences the problem and in what situation;
- what happens today and why it is inadequate;
- the literal requested behavior and the smallest safe increment;
- whether the proposed milestone fully satisfies the literal outcome or defers part of it;
- the current primary journey and anything about it that must remain unchanged;
- current alternatives and important constraints;
- which facts are confirmed, inferred, or unknown.

Do not turn the proposed feature into the problem statement. Ask what progress it is intended
to create.

### 3. Resolve product decisions

Investigate what the project can answer before asking the user. Then ask one consequential
question at a time. After each answer, recommend a choice, challenge conflicts with evidence or
earlier decisions, and record the resolved rationale as `D-*` when it materially affects what
must be delivered.

Stop when remaining uncertainty is honestly recorded and none of it prevents a responsible
product commitment.

Treat capability, job, entry point, hierarchy, placement, labels, defaults, and preservation of
the existing primary journey as decisions when they could change the delivered experience. If
the discussion moves into a tangent, security design, implementation detail, or a materially
different option, reset context before requesting approval by restating:

- the original requested outcome;
- the currently proposed milestone;
- what changed since the last checkpoint;
- what remains unchanged; and
- what is deferred.

A bare confirmation after a tangent does not approve a milestone unless this reset immediately
preceded it.

### 4. Draft and check the contract

Check whether the outcome depends on a consequential, untested assumption. If a result could
change a decision, recommend `/experiment` using [`../experiment/SKILL.md`](../experiment/SKILL.md)
if installed, otherwise an experiment or test however the team runs them. Record its ID/revision
(the Outwork ID where `/experiment` is used), learning question, owner, review date, and any
baseline-before-launch dependency in the contract; link to wherever the experiment is recorded
rather than copying the experiment plan.
If none is warranted, state the reason in one sentence. Do not require an experiment for a settled
fix or make lack of analytics a blanket blocker. The experiment skill owns the measurement design
and later outcome analysis; this contract still owns product scope.

Read [references/product-contract.md](references/product-contract.md) and use the light or full
template it defines.

Every contract includes concise **Outcome integrity**, **Experience contract**, **Milestone and
completion**, and **Risk posture** sections. When there is no material experience change, say
why in the Experience contract, including any settled correction, instead of manufacturing a
prototype. When the experience materially changes, link the approved artifact and ensure the
acceptance examples cover both the new job and the adjacent primary job that must remain usable.

Use stable identifiers:

- `SR-01`, `SR-02`, ... for product requirements;
- `AC-01`, `AC-02`, ... for acceptance examples;
- `D-01`, `D-02`, ... for material product decisions.

Do not renumber identifiers casually after `/document` or delivery work references them. Use a
user story or job story only when it adds value context.

Read [references/quality-and-grill.md](references/quality-and-grill.md). Make each requirement
necessary, product-level, unambiguous, complete, singular, feasible, verifiable, correct,
consistent, and free of unjustified implementation choices. Use Given/When/Then only when
conditions matter.

Apply the scope-delta boundary to every requirement, constraint, failure, and risk. Keep
pre-existing risks and optional hardening out of the committed increment unless the user
explicitly approves the expansion.

The Risk posture must be grounded in the actual users, reach, data sensitivity, reversibility,
credible harm, likelihood, existing controls, consequence of omitting a control, and experience
or delivery cost. A reviewer may require a minimum control for safe use, but may not promote
optional hardening into the milestone merely because a stronger system could be designed.

Record, under `## Relies on`, the existing journeys, access boundaries, and behaviours the
contract depends on, named in product terms. The proportionality gate already produced this
list; `/document` uses it to decide which code paths its drift check watches.

When a draft package exists, write the exact proposed section text to its
`product-contract.md`, note the proposed title (for a new issue) in `evidence.md`, and record
the draft's fingerprint with `contract.py fingerprint` before review.

### 5. Run one bounded review pass

Review the exact proposed contract with source access but without the drafting conversation or
an instructed verdict.

- **Light:** try to prove that hidden scope, an unhandled user or failure, or another delivery
  surface makes light unsafe.
- **Full/grill:** apply scope necessity, product completeness, and assumption quality.
- **Every depth:** apply the misreading lens to each `SR-*` and `AC-*`, so no requirement uses
  subjective wording that the builder and the customer could read differently.

For every user-facing contract, also try to disprove four claims: the milestone preserves the
literal outcome, the approved experience matches the requirements, the adjacent primary job
remains usable, and the proposed protections are proportionate to the actual risk posture.

Require evidence for objections. Reconcile conflicts against sources. Supported objections
reopen the relevant decision; preferences become notes. A material contract change invalidates
the prior final-fingerprint review.

Classify every finding as an **increment blocker**, **pre-existing risk**, or **optional
hardening**. Only an increment blocker may reopen the current contract. A pre-existing risk goes
to linked follow-up work; optional hardening remains an explicit non-goal unless the user expands
scope. Start by looking for requirements that can be removed without losing the requested
outcome.

Use one review round by default. Use a second only when the first finds a supported increment
blocker and the contract changes materially. After that, unresolved findings that do not change
what gets built or make the increment unsafe become explicit open questions rather than another
review round.

### 6. Preview, approve, and write

Before showing the write, present a compact approval card containing:

- original requested outcome;
- named milestone and whether it fully completes that outcome;
- user-visible changes, with the experience artifact;
- behavior that remains unchanged;
- deferred capabilities and optional hardening; and
- unresolved non-blocking questions.

Then show the complete section text, the action (create a new issue with this title, or
update issue `#N`), the repository, and any labels or parent issue. Wait for explicit approval
of the approval card, milestone, experience, and exact write. Record that response as the
approval evidence. Approval of an earlier draft, one decision, or an exploratory tangent does
not count.

The script detects the repository from the checkout it runs in. If the outcome belongs to a
different repository, name it and obtain separate approval before creating the issue there.

After approval:

1. Record approval against the final draft fingerprint.
2. Run `contract.py create --title "<title>" --file <draft> --approved-fingerprint <approved>`
   for a new issue, or `contract.py write <issue> --section product --file <draft>
   --approved-fingerprint <approved> --expect-fingerprint <current>` for an update. The
   script refuses text that no longer matches the approved fingerprint, stamps the version,
   fingerprint, and default-branch commit, writes only the product section, reads the issue
   back, and verifies the fingerprint.
3. Report the issue URL, version, and fingerprint from the script's output.

Do not edit the issue body by hand after approval. A `stale` refusal means the section moved
since it was read: read it again, reconcile, and re-approve. On a read-back mismatch or an
ambiguous create result, inspect the issue and report the blocker. Never retry a create
blindly.

### 7. Hand off to `/document`

Offer the next step; do not force it. When requested, pass:

- issue number and URL;
- product contract version, fingerprint, and scoped-at commit;
- light/full depth;
- `SR-*`, `AC-*`, and `D-*` identifiers;
- unresolved risks or open questions;
- named milestone and completion semantics;
- risk posture and deferred optional hardening; and
- evidence and required experience-artifact links.

Include the experiment ID/revision and measurement dependencies when applicable, or the reason
an experiment was unnecessary. An experiment review date does not itself schedule an agent.

If `/document` discovers a missing product decision, return it to `/scope`. The two skills may
hand work back once, but must not loop without new evidence or a user answer.

## Completion conditions

Scope is ready for technical planning when:

- the probable remedy, implementation estimate, and planning budget are proportionate;
- the original requested outcome and named milestone are distinct and reconciled;
- any deferral of a core capability was explicitly approved and cannot be mistaken for overall
  completion;
- material experience changes have an approved low- or high-fidelity artifact, while contracts
  with no material experience change explain why, including any settled correction;
- the contract states the existing primary journey that must remain usable;
- the risk posture justifies the minimum controls and separates optional hardening;
- the outcome, user, boundaries, and constraints are understandable;
- requirements and acceptance examples cover the important behavior and failures;
- work that creates stored data, changes access, or depends on an unsettled access boundary states
  who may see it, who must not, and what someone without permission gets;
- every included failure or risk passes the scope-delta boundary;
- no new journey beyond the literal request, actor or account authority, data contract, recovery
  system, or operational subsystem was added without explicit approval;
- open questions are resolved or explicitly non-blocking;
- the proportional review is reconciled and the depth is explained;
- when a GitHub write was requested, the user approved the final section text and the
  read-back matched the saved issue.
