# Delivery Contract Template

The delivery contract is the second section of the outcome's GitHub issue, directly below the
product contract `/scope` wrote; an epic child carries only a delivery contract that names the
parent. `scripts/contract.py` in the scope skill writes the section and stamps the product
version, fingerprint, and default-branch commit it was planned against; supply only the text
below the heading. Use the smallest set of sections that completely transfers the delivery
decision and proof plan. Cite `SR-*`, `AC-*`, and `D-*`; never restate the product contract.

Keep the top-level subsections at `## `, including `## Requirement-to-proof matrix`, and never
add another `## ` heading between that heading and its table: the orchestrate progress bar
(where installed) collects identifiers from the matrix heading to the next `## ` heading.

```markdown
## Scope authority

- **Scope basis:** [product contract | technical | legacy Linear (read-only)]
- **Product contract:** [#N v<version> `<fingerprint>`, scoped at `<commit>`; N/A with a reason
  for technical scope; or, for a legacy issue (only where the `linear` CLI is available), the Linear identifier, URL, and `updatedAt` read
  through the CLI]
- **Delivery tier:** [light | full | epic]
- **Named milestone:** [approved product milestone, or N/A for technical scope]
- **Completes original outcome:** [Yes, No with the remaining milestone, or N/A for technical scope]

## Drift report

- **Scoped at:** `<commit>` · **Default branch at planning:** `<commit>`
- **Paths watched:** [`dir/`, `dir/file` for the code behind each entry of the product
  contract's `Relies on`; `/start-work` and `/orchestrate` rerun the comparison over exactly these]
- **What changed:** [One short paragraph: the commits and files under the watched paths since
  scoping, and whether any requirement, decision, or the experience artifact is affected.
  `Nothing: scoping and planning used the same default-branch commit` is valid when true.]

## Outcome summary

[One short paragraph explaining the intended result. The product contract above holds the detail.]

## Scope concordance

- **Original requested outcome:** [Bounded restatement from the approved scope, or N/A for
  technical scope.]
- **Approved experience artifact:** [Exact low- or high-fidelity link/file and version, or `No
  material experience change` with the reason and source of any settled correction.]
- **Existing primary job preserved:** [The adjacent journey that must remain usable, or `No
  user-facing change` with a reason.]
- **Product decisions implemented:** [Applicable `D-*` identifiers governing capability, entry
  point, hierarchy, placement, labels, defaults, and responsive behavior, or N/A for technical
  scope.]
- **Deviations from approved scope or experience:** [Must be `None`; otherwise return to `/scope`.]

## Current behavior and evidence

[What the system currently does, how it was established, and relevant source links.]

## Delivery boundaries

### In scope

- [Technical result required by this issue]

### Deferred or out of scope

- [Explicit boundary and destination, including pre-existing risks or optional hardening found
  during planning]

## Proposed approach

- **Simplest complete delivery:** [Smallest change to the existing approved journey that achieves
  the milestone.]
- **Existing behavior and controls reused:** [Journey, authority, data, recovery, and operating
  paths retained.]
- **Necessary new layers:** [Each new screen, mode, service, authority, durable record, migration,
  recovery mechanism, coordination layer, or security control, with the approved outcome or
  credible incremental risk that requires it. Use `None` when possible.]
- **Simpler alternative rejected:** [Only when a simpler option cannot meet the milestone or its
  minimum safe controls; otherwise use the simpler option.]
- **Optional hardening deferred:** [Items from the approved risk posture that are not required now.]

## User integration

- **Entry point:** [where the user or external system meets the change]
- **Journey:** [trigger through observable outcome]
- **Feedback:** [how success and failure appear]
- **Experience artifact mapping:** [frames or states this journey implements]
- **Existing primary job preservation:** [what remains unchanged and how the user still completes it]

Use `No user-facing change` with a reason for internal work.

## Data and access

- **Schema or stored-data changes:** [details or none]
- **Migration and backfill:** [details or none]
- **Authorization and tenant boundaries:** [which roles reach which data, and how the ones that must not are stopped — or N/A with a reason]
- **Access rules that must exist before this ships:** [the rules the intended readers depend on. Turning protection on without them does not fail loudly; the affected screens quietly show nothing.]
- **Consumers of this database:** [every app, job, edge function, and script that reads the objects this change touches, and how each authenticates. Required for any change to protection, grants, storage rules, or which role a view or function runs as — and for any schema change that alters an object other consumers may read: renames, drops, type or constraint changes. A search of this repository alone does not answer it.]
- **Documentation consulted:** [the Supabase or platform documentation used for the access rules, or N/A]
- **Compatibility and cleanup:** [details or N/A]

When the project uses Supabase, follow [`supabase-database-security.md`](supabase-database-security.md) — it names the specific failure modes to check and what counts as proof.

## Requirement-to-proof matrix

### Outcome experiment (when applicable)

- **Linked experiment:** [ID/revision and where the record lives; with Volta's systems (the `outwork` command is available), retrieve it with `outwork experiment get <id>`]
- **Measurement work:** [Minimum collection/instrumentation and proof that it produces usable evidence]
- **Before exposure:** [Required baseline capture or agreed alternative, plus activation evidence]
- **Review handoff:** [Date, human owner, and manual reviewer or existing scheduler; no implied automation]

Omit this subsection when no experiment is warranted. Its result does not substitute for delivery
proof, and a successful delivery does not establish the experiment's hypothesis.

| Scope ID | Required behavior | Surface | Automated proof | Runtime proof | Readback or evidence |
|---|---|---|---|---|---|
| SR-01 / AC-01 | [behavior] | [frontend/backend/data/integration/operations] | [existing or new test that can fail, or justified direct check] | [path to exercise] | [capture or query] |

Reuse meaningful existing tests. A new test is needed only for a coverage gap, not for each
identifier. For a small reversible, settled copy correction, state the exact direct check and why
additional automated testing adds no meaningful protection. Required repository checks and
applicable access and runtime proof remain required.

Include a proof row for the approved new job and a separate regression row for the adjacent
primary job named in Scope concordance. A component snapshot or source-text assertion does not
prove placement, discoverability, responsive behavior, or the complete user journey.

For a technical-scope issue without product-contract identifiers, use `TR-01`, `TR-02`, ...
and keep those identifiers stable through implementation.

## Surface test plan

| Surface | Applies? | Automated test | Runtime and edge-case check |
|---|---|---|---|
| Frontend | [yes/N/A reason] | [component or journey test] | [browser path matching the experience artifact at desktop and narrow viewports, plus preservation of the adjacent primary job] |
| Backend | [yes/N/A reason] | [business rule or integration test] | [API/service trigger and applicable changed failure behavior] |
| Data and access | [yes/N/A reason] | [migration/access test] | [query as the declared audience **and** as the roles it excludes, reconciliation, uniqueness, readback] |
| Full-stack or external | [yes/N/A reason] | [end-to-end or contract test] | [complete journey and external result] |
| Operational | [yes/N/A reason] | [build/config/deploy check] | [health, logging, monitoring, rollback signal] |

## Test-first sequence

1. [Named existing or new failing behavior test and expected failure]
2. [Smallest complete implementation outcome]
3. [Passing test and regression suite]
4. [Refactor or cleanup while green]

Omit this section for behavior-preserving prose, formatting, or an exact settled copy correction
when direct verification suffices; record the check and reason. Once the required checks pass,
repeat or broaden them only for changed content, a failure, or a specific unresolved concern.

## Security, privacy, and failure handling

- [Threat, sensitive data, validation, or failure behavior introduced or materially affected by
  this change, or N/A reason. Broader pre-existing weaknesses belong under Deferred or out of
  scope unless explicitly approved.]
- **Risk-posture fit:** [actual users, reach, sensitivity, reversibility, credible harm,
  likelihood, existing controls, consequence of omission, and why these are the minimum safe
  controls rather than optional hardening.]
- **Who must not reach this data:** [the roles excluded by the declared audience, and what stops each. Anonymous users belong here only when the approved audience excludes them. Carry the access decision from the product contract; an explicitly public surface must remain accessible to its intended public readers. For technical scope without a product contract, record the existing access contract or the explicit audience decision for approval with the issue. Never invent an audience from a generic security checklist.]
- **Credential handling:** [which key each path uses, and confirmation that no admin or service-role key is reachable by the browser or published to the client, or N/A]

## Rollout, observability, and rollback

- [Deployment order, flags, monitoring, rollback, or N/A reason]

## Dependencies and issue relationships

- **Blocked by:** [issue or none]
- **Blocks:** [issue or none]
- **Parent epic:** [issue or none]
- **Overall completion gate:** [When this issue is a partial increment, name the remaining issue
  or milestone and state that closing this issue does not complete the original outcome.]

## Decisions and dismissed objections

- [Technical decision or material grill objection, with rationale]

## Completion contract

- [ ] Every scope or technical requirement has a proof row.
- [ ] The delivery has no deviation from the approved product scope or experience artifact.
- [ ] The approved new job and the adjacent primary job both pass through their real user journeys.
- [ ] Every added layer is required by the approved outcome or a credible incremental risk.
- [ ] A partial increment is not reported as completing the original outcome.
- [ ] Repository-native checks pass with nonzero test collection where tests apply.
- [ ] Runtime behavior is observed at the affected surface.
- [ ] Unmet proof is reported honestly rather than replaced with code inspection.
- [ ] Where access changed, both halves are proven: the declared audience reaches the data, and the roles it excludes cannot. Intentionally public access has an explicit audience declaration and a positive public-read check; negative checks target excluded operations, objects, or roles.
```

## Epic guidance

An epic summarizes the shared outcome, cross-cutting constraints, dependency graph, and
overall proof. The product contract lives on the parent; each child carries only a delivery
contract, created with `contract.py create --section delivery --parent <epic> --product-issue
<epic>`, so the drift check on a child follows its stamp to the parent. Each child remains
independently implementable and proves a bounded subset of scope identifiers. Do not repeat the
parent's product contract in any child. Also list the children on the parent as a task list
(`- [ ] #N`), so an epic is recognised even where sub-issue fields are unavailable.
