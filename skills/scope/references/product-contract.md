# Product Contract Template

Use the smallest contract that preserves the product commitment. Keep it product-facing and
link to evidence instead of copying research.

Start a light contract with three to five requirements, two to four acceptance examples, and no
decision entry unless a material choice actually exists. Seven requirements, five acceptance
examples, and three decisions are ceilings that trigger reduction, not targets to fill. Remove
duplication and split pre-existing risk or optional hardening into follow-up work before
promoting depth.

## Light contract

```markdown
## Outcome

[The measurable customer or business result this work should improve.]

## Outcome integrity

- **Original request:** [The user's literal requested outcome before decomposition.]
- **Committed outcome:** [What this contract commits to deliver.]
- **Complete or partial:** [State whether this milestone fully satisfies the original request.]
- **Explicitly deferred:** [Core capability deferred with approval, or `None`. A partial milestone
  must not be represented as completing the original outcome.]

## Problem and evidence

[Who experiences the problem, what happens today, why it matters, and the strongest evidence.]

## Learning check

[Consequential assumption and experiment ID/revision (Outwork, where `/experiment` is used),
owner, review date, and launch dependency; or one sentence explaining why an experiment would
not change a decision. The full experiment definition and findings remain wherever the team
records experiments.]

## Experience contract

- **Existing primary job:** [What the user does today and where.]
- **Approved change:** [Capability, flow, entry point, hierarchy, placement, labels, and defaults
  that will change.]
- **Must remain unchanged:** [Adjacent job or interface behavior this work must preserve.]
- **Experience artifact:** [Approved low- or high-fidelity link/file, or `No material experience
  change` with a reason, including an exact settled correction when applicable.]

## Relies on

[The existing journeys, access boundaries, and behaviours this contract depends on, named in
product terms, one per line. `/document` maps them to code paths and watches those paths for
drift between scoping and planning; `/start-work` watches them again before building.]

- [Journey, access boundary, or behaviour that must keep working as it does today]

## Scope

### In scope

- [Committed product behavior or result]

### Out of scope

- [Explicit boundary or deferred behavior]

## Milestone and completion

- **Milestone:** [One named product milestone.]
- **Definition of done:** [Observable outcome required before this milestone is complete.]
- **Does this complete the original request?** [Yes, or No with the remaining named milestone.]
- **Must not be called complete when:** [Unmet core capability or acceptance boundary.]

## Product requirements

- **SR-01** - When [condition], the product must [one observable behavior].

## Access and visibility

[Include when the increment creates stored data, changes who may see or act on it, or depends on
an unsettled access boundary. When an existing authorized path and audience are unchanged, state
that briefly in Scope instead and delete this section.]

- **Who may see this:** [roles, accounts, or relationships; `Public by design` is valid when reasoned]
- **Who must not:** [roles excluded by the declared audience; anonymous users only when this is
  private, other customers or tenants where isolated, and excluded internal roles]
- **Without permission:** [denied, empty, or not shown]

## Acceptance examples

### AC-01 - [Observable scenario]

- **Given** [relevant state]
- **When** [one user or external-system event]
- **Then** [observable outcome]

## Risk posture

- **Users and reach:** [Who uses this, likely audience size, and whether exposure is bounded or public.]
- **Data and sensitivity:** [What is affected and why it is or is not sensitive.]
- **Credible incremental harm:** [Concrete harm introduced or worsened by this change, with
  likelihood; `None beyond the existing path` is valid when supported.]
- **Reversibility and existing controls:** [How mistakes are contained or recovered today.]
- **Minimum safe controls for this milestone:** [Only controls needed for the approved outcome to
  be responsibly usable.]
- **Consequence of deferring those controls:** [What happens if the minimum is omitted.]
- **Optional hardening deferred:** [Stronger protection not required for this milestone, or `None`.]

## Decisions

- **D-01** - [Material choice and rationale]

[Use `No material decisions beyond the requirements` when true.]
```

## Full additions

For full or grill work, include these sections:

```markdown
## User and job

[One job story or user story when it clarifies situation, motivation, and value.]

## Product constraints

- [Accessibility, privacy, policy, timing, performance, legal, or operational constraint]

## Product risks

| Risk | Evidence | Current assessment | Next action |
|---|---|---|---|
| [Value, viability, usability, feasibility, or safety] | [source] | [retired/open] | [action] |

## Open questions and blockers

- [Question, owner, and whether it blocks technical planning]

## Source links

- Context map: [link]
- Evidence: [link]
- Prototype: [link, when applicable]
```

Delete optional rows that do not apply. If a full section has no finding, say that directly and
briefly; do not add filler to make the contract look complete.

The four light-contract gates—Outcome integrity, Experience contract, Milestone and completion,
and Risk posture—are not optional, and neither is Relies on: an empty list leaves the drift
check nothing specific to watch, so it compares the whole repository and drowns the signal. Keep them short when the answer is simple. Their purpose is
to prevent a technically coherent plan from narrowing the requested outcome, relocating the
experience, completing only part of the job, or importing disproportionate hardening.

Include only risks introduced or materially worsened by the requested increment in the current
contract. Link pre-existing risks as follow-up work and keep optional hardening out of scope
unless the user explicitly approves expansion.

## Access rule

When the requested increment creates stored data, changes who may see or act on it, or depends
on an unsettled access boundary, the contract must say who may see it, who must not, and what
happens without permission. State the user-visible rule, not the mechanism. “A coach sees only
the companies they support” is a product decision. A database policy belongs in `/document`.
When the increment reuses an existing authorized path and leaves its audience unchanged, say so
briefly and do not reopen permission design merely because stored data is involved.

## Experience and milestone rules

Treat these as product decisions whenever they could change what the user experiences:
capability, job-to-be-done, entry point, navigation, information hierarchy, placement, labels,
defaults, responsive behavior, and preservation of an existing adjacent journey. A linked
wireframe is required for a material change. Low fidelity is enough to settle familiar flow or
hierarchy; high fidelity is required when realistic content, visual density, responsive behavior,
or a novel interaction could change approval.

Apply the settled-correction boundary in [the scope skill](../SKILL.md#settled-corrections).
Record an exact correction and its source without reopening a choice the user already made;
a changed label or interface file alone does not require a new prototype.

If delivery is decomposed, keep the original outcome visible. A child milestone may be complete
without completing the original request, but the contract must say so and name what remains.

## Content boundary

Do not put these in the product contract:

- file or line references;
- component, function, API, table, or migration designs;
- implementation sequencing;
- test filenames or commands;
- copied raw research or long historical narratives.

Those belong in linked evidence or the delivery contract `/document` writes below it. The
section's version, fingerprint, and scoped-at commit are stamped by `scripts/contract.py`; do
not write them by hand.
