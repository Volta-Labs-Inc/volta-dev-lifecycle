---
name: document
version: 1.0.0
description: "Turn approved product scope or a settled technical change into an implementation-ready GitHub delivery contract. Use whenever the user says /document, asks to file or design a GitHub issue, wants an approved product contract translated for developers, needs light-versus-full delivery sizing, or wants implementation and test criteria. Locks delivery to the approved outcome, milestone, experience artifact, and risk posture; refuses to plan around unresolved product decisions; maps scope requirements to runtime proof; and creates or updates GitHub only after approval. Does not redefine product scope or implement the change."
---

# /document - Design the GitHub Delivery Contract

Translate an approved product contract or settled technical change into the GitHub issue
that a developer will implement and prove.

The skill owns **how the work should be delivered and how completion will be demonstrated**.
It does not own the product outcome or silently make missing product decisions.

## Authority and boundaries

- The product-contract section of the GitHub issue, written only by `/scope`, owns product
  outcomes, users, scope boundaries, product requirements, and decisions. For an epic it sits
  on the parent issue.
- GitHub owns technical investigation, delivery design, dependencies, and the proof contract,
  in the delivery-contract section this skill writes directly below the product contract (or
  on each epic child).
- The repository and running system determine what currently exists.
- Implementation runs through `/orchestrate`, whose workers run `/start-work` and record the
  implementation evidence; publication belongs to `/ship-it`.

Cite the product contract's identifiers instead of copying it. A short outcome summary is
useful; a second independent product specification is not. The mechanics of reading and
writing the sections live in `scripts/contract.py` of the scope skill; see
[`../scope/references/github-handoff.md`](../scope/references/github-handoff.md).

Treat the approved product delta as a containment boundary. Technical planning may choose the
smallest approach and proof needed to deliver it, but it may not add a new journey, authority,
data contract, recovery system, migration, coordination mechanism, or operational subsystem to
solve a broader pre-existing weakness. Preview that expansion and return it to `/scope` for
explicit approval.

Treat a new trusted entry point for the same user, same connected account, and same approved
action as delivery routing, not new product authority. It becomes an authority change only when
it expands who can act, which account or tenant can be affected, what provider permission is
granted, or which action is authorized.

For a clear technical chore, maintenance change, or bug whose intended behavior is already
settled, a product contract is optional. State `Scope basis: technical` and explain why no
product decision or operating-record update is required.

If material product behavior is missing or disputed, invoke `/scope` and return only after the
decision is approved. Do not invent the decision inside GitHub.

No GitHub issue, pull request, comment, implementation session, reviewer finding, or production
constraint may supersede an approved decision in the product contract. This skill never edits
the product-contract section. Return any proposed product change to `/scope` as a comment on
the issue, let `/scope` update the product contract and experience artifact, and obtain a new
milestone approval before revising the delivery contract.

## Scope readiness and experience lock

For work based on a product contract, before technical investigation confirm that the
approved contract contains:

- the original requested outcome and whether the named milestone fully satisfies it;
- one named milestone with falsifiable completion semantics;
- the current primary journey and behavior that must remain unchanged;
- an approved low- or high-fidelity artifact for every material experience change, or an
  explicit statement that there is no material experience change, with a reason;
- a risk posture that distinguishes minimum safe controls from optional hardening; and
- the version and fingerprint stamp `/scope` writes (an unstamped product section was not
  written through the approved path; return it to `/scope`); and
- a `Relies on` list naming the journeys, access boundaries, and behaviours the contract
  depends on, which the drift check below watches.

Apply [scope's settled-correction boundary](../scope/SKILL.md#settled-corrections) to exact copy
corrections or restoration of already-approved behavior. Carry the correction and its source
into the delivery without inventing a prototype or reopening a settled product choice.

Stop and return to `/scope` if any applicable item is missing, disputed, stale, or contradicted
by the proposed delivery. `/document` may not invent or change approved capability,
job-to-be-done, entry point, navigation, hierarchy, placement, labels, defaults, responsive
behavior, or completion semantics. It must implement the approved experience.

For a technical scope basis, use this gate only to confirm that the change has no unresolved
user-facing product decision. Record product-only fields as `N/A` with a reason. If the work
would change capability or experience beyond already settled behavior, return it to `/scope`;
otherwise proceed without requiring a product contract or experience artifact.

## Modes and tiers

### `trivial`

Use only when there is no runtime or agent-behavior change and no GitHub issue is useful.
Draft a repository-appropriate commit message and stop. A substantial skill or instruction
change is behavioral and is not trivial merely because it is Markdown.

### `light`

Use for a single bounded delivery concern and one likely pull request. Reusing an existing
approved external action, permission boundary, data contract, or recovery path remains light
when the change does not alter those controls. A light issue remains responsible for every
applicable test and runtime proof. A new trusted entry point for the same actor, account, and
approved operation remains light even when that surface was previously read-only.

### `full`

Use only when the requested delivery itself introduces or materially changes multiple journeys,
business rules, which people, roles, tenants, or connected accounts may act, provider credential
or consent scope, access boundaries, a durable data contract, irreversible behavior without
existing recovery, significant operational coordination, or independently deliverable phases.
An external provider, stored-data read or write, new same-authority entry point, or existing
system weakness does not make the delivery full by itself.

### Epic

Use when independently deliverable phases have real dependencies or can be owned and proven
separately. An epic is always full.

### `grill`

`grill` controls review depth, not issue size. Use three fresh-context reviewers even when
the initial candidate looks light. Otherwise, a light candidate receives one reviewer and a
full or epic candidate receives three.

An explicit tier is a proposal, not an instruction to suppress evidence. Review may recommend
promotion or reduction before creation.

## Workflow

### 1. Establish the scope basis

If the input names a GitHub issue, or an epic parent, that carries a product contract:

1. Read it with the contract script from a checkout of the issue's repository.
   `contract.py` ships with the scope skill at `../scope/scripts/contract.py` relative to this
   skill's folder; set `CONTRACT` to that path first (Volta setups may use
   `$OUTWORKOS_ROOT/skills/scope/scripts/contract.py`).

   ```bash
   python3 "$CONTRACT" read <issue> --json
   ```

   For an epic child, `read` includes the parent's product contract (found through the delivery
   stamp or the sub-issue link) and names the issue it came from.
2. Capture the product contract version, fingerprint, and scoped-at commit, the `SR-*`, `AC-*`,
   `D-*`, named milestone, completion semantics, risk posture, experience-artifact link,
   boundaries, blockers, and the `Relies on` list.
3. Read linked evidence needed to understand current behavior.
4. Compare the original outcome, committed milestone, approved experience, and proposed delivery.
5. Stop and return to `/scope` when a blocking product decision remains unresolved, a core
   capability was deferred without explicit approval, the experience artifact is missing, or the
   milestone could be mistaken for completing more than it does.

If the issue has no product contract but links a Linear issue (`read` lists it under
`linear`) and the `linear` CLI is installed and signed in, use the read-only compatibility path
so in-flight work keeps moving: run
`linear issue --help`, read the scope with the `linear` CLI, capture its identifier, URL, and
`updatedAt`, and record them in Scope authority as `legacy Linear (read-only)`. Do not write to
Linear. When that product scope needs to change, `/scope` writes the product contract on the
GitHub issue; Linear is not updated. Without the `linear` CLI, stop and ask the user for the
scope (or return it to `/scope`) rather than planning without one.

If the issue already carries a delivery contract and `/start-work` or `/orchestrate` stopped on
`CONTRACT_DRIFT` or on code drift that affects a requirement, decision, or proof row, this run
is a reconciliation: read the current product contract, repeat Step 2 against it, and update
the delivery section in place in Step 8. When the drift means the product contract itself must
change, return it to `/scope` first.

If the input is a settled technical change, record:

- the current unwanted behavior;
- the intended technical outcome;
- why no product-scope decision is needed;
- the repository and evidence that establish the behavior.

### 2. Inspect the current system

Start with what moved since scoping. Map each entry under the product contract's `Relies on`
to the code paths that implement it (directories or files), then run, from the repository
checkout:

```bash
python3 "$CONTRACT" drift --since <scoped-at commit> -- <path> [<path> ...]
```

It fetches the default branch and lists the commits and files under those paths since `/scope`
wrote the contract (exit 12 when something changed, 0 when nothing did; exit 1 with
`commit ... is not known` means the checkout has not fetched it: fetch and rerun, never plan
on a comparison that did not run). Note the `until` commit it prints: Step 8 stamps that
commit as the one the plan was made on, so anything landing after it is caught by the next
check. Read the changed files, then write the **Drift report** of the delivery contract: the scoped-at and current
default-branch commits, the paths watched, and one short paragraph saying what changed and
whether any requirement, decision, or the experience artifact is affected. `/start-work` and
`/orchestrate` rerun the same comparison over exactly those paths from the commit this plan
is stamped with, so choose paths that cover every journey the contract relies on. A change
that affects the product contract goes back to `/scope` before planning continues; do not
plan around it. For technical scope there is no scoped-at commit; record the default-branch
commit you investigated and the paths the change touches, so `/start-work` can still watch them.

Then read the project's context map, if it keeps one, otherwise its own agent instructions
(AGENTS.md, CLAUDE.md) and README; then its repository status, existing issues,
code, tests, data contracts, and deployment guidance. Search for prior art before proposing
new work.

Determine:

- the user or external-system entry point;
- current behavior and failure modes;
- affected frontend, backend, data, access, integration, and operational surfaces;
- existing tests and runtime verification paths;
- security, privacy, migration, compatibility, and rollback implications;
- dependencies and safe decomposition boundaries.

Begin with the simplest complete delivery: the smallest change to the existing approved journey
that achieves the milestone and passes its acceptance examples. For every proposed new screen,
mode, service, authority, durable record, migration, recovery mechanism, coordination layer, or
security control, name either the approved outcome it enables or the credible incremental risk
that makes it necessary. Remove or defer anything that satisfies neither test.

Do not mistake a more hardened design for a safer product decision. Calibrate protection to the
scope's actual users, reach, data sensitivity, reversibility, credible harm, likelihood, existing
controls, consequence of omission, and impact on the approved experience. If investigation shows
the approved minimum is unsafe, return the evidence to `/scope`; do not silently replace it with
a deeper system.

Classify every discovered concern as an **increment blocker**, **pre-existing risk**, or
**optional hardening**. Only an increment blocker may expand the current delivery contract: the
requested change must introduce or materially worsen it, and resolving it must be necessary for
the approved outcome or safe use. Record the others as deferred work without designing them into
this issue unless the user explicitly expands scope.

When the change touches stored data, access rules, storage, authentication, or credentials and
the project uses Supabase, read
[`references/supabase-database-security.md`](references/supabase-database-security.md) and
answer its named failure modes rather than the generic question. Two determinations belong in
this step and are hard to recover later: which roles must be stopped from reaching the data, and
which other applications, jobs, and scripts read the objects being changed. Searching this
repository does not answer the second — deployments usually inject the database URL through their
environment, so a text search undercounts the consumers.

Use independent reconnaissance workers when the lenses can run separately. Return conclusions
and evidence rather than raw file listings.

### 3. Draft the delivery contract

Read [references/delivery-contract.md](references/delivery-contract.md) and use its template.

Carry every applicable `SR-*` and `AC-*` identifier into the requirement-to-proof matrix.
Do not renumber product identifiers in GitHub.

Carry the named milestone, completion semantics, risk posture, and exact experience artifact
into the delivery contract. Include a scope-concordance statement confirming that the proposed
entry point, hierarchy, placement, labels, defaults, and unchanged primary journey match the
approved artifact. Any deviation is a product change and blocks the draft.

The issue must make each delivery surface explicit:

- frontend;
- backend and business rules;
- data and access;
- full-stack or external integration;
- operational and deployment behavior.

For each surface, state `Applicable` with exact proof or `N/A` with a reason. Do not invent a
frontend test for backend-only work or excuse a backend behavior change because the issue is light.

### 4. Design the proof before the tasks

When scope links an experiment, read its current record through
[`../experiment/SKILL.md`](../experiment/SKILL.md) if the experiment skill is installed alongside,
otherwise wherever the team keeps it. Carry its ID/revision into the delivery contract.
Plan the minimum collection, instrumentation, source access, and exposure evidence needed to run
the recorded analysis. Identify any baseline that must be captured before launch and the person
or existing mechanism responsible for the dated review. Do not invent a scheduler or change the
hypothesis, targets, or cohort here. If measurement needs a new product decision, return it to
`/scope`. For settled technical work without product scope, recommend an outcome experiment (`/experiment`, if installed) only when a
consequential outcome assumption could change the decision. Acceptance proof verifies delivery;
the later experiment evaluates whether it produced the expected outcome.

For every acceptance identifier, define:

1. the existing or planned automated test that can fail when the behavior breaks, or a justified
   direct check for a small, reversible correction where a new test adds no meaningful protection;
2. the runtime path that makes the changed behavior observable;
3. any independent readback needed to verify data-derived claims;
4. the failure or edge-case probe relevant to behavior introduced or affected by this change;
5. the evidence that will be captured.

For every material user-facing change, add two runtime proofs:

- the approved new job succeeds through the exact experience artifact at the relevant desktop
  and narrow viewport; and
- the named adjacent primary job remains usable and has not been displaced, buried, renamed, or
  given a conflicting control.

When multiple sessions, links, identities, or state transitions are possible, include the
successive-use journey that could expose stale state; isolated happy paths are insufficient.

Use existing meaningful tests when they already cover the acceptance condition. Add or change a
test only for a coverage gap; do not require a new test per acceptance identifier or tests that
merely repeat source text. For changed product or runtime behavior, plan test-first work using
the relevant existing or new test: observe the failure, make the smallest complete change, and
observe it pass. For behavior-preserving prose, formatting, or an exact settled copy correction,
record the concrete direct check and why additional automated testing adds no meaningful proof.
Settled product intent alone is not a test exemption: restoring broken runtime behavior still
needs relevant behavior tests and probes. Repository-required checks and applicable access and
runtime evidence still apply.

Name the required checks and the reason to broaden them before implementation. Once they pass,
repeat or broaden testing only for changed content, a failure, or a specific unresolved concern.

The proof plan must distinguish tests, runtime observation, and production evidence. One does
not substitute for another.

### 5. Recommend a tier

Recommend the tier from product and delivery risk, not file count alone.

Choose **light** when the product decision is settled, one delivery concern is affected, the
change reuses existing authority and recovery behavior, the proof is compact, and one pull
request is likely.

Choose **full** when the requested change itself introduces or materially changes business
rules, authority, access, durable data, integrations, operations, or independently useful staged
delivery. Do not promote solely because the existing path has broader weaknesses.

Choose an **epic** only when multiple independently valuable or dependent phases genuinely
benefit from separate issues. Do not create issue hierarchies as ceremony.

### 6. Run the fresh-context grill review

Reviewers receive the product contract, draft delivery contract, and relevant repository
evidence.
They do not receive the drafting conversation.

Budget one review round by default. Use a second only when the first identifies a supported
increment blocker and the draft changes materially; focus it on the correction and affected
proof. After two rounds, record findings that do not change what gets built or make it unsafe
as open questions. An unresolved increment blocker still prevents an implementation-ready
handoff; report the specific decision or missing evidence instead of starting another round.

For a **light candidate**, use one reviewer:

> First identify delivery work that can be removed while preserving the approved outcome and
> safe use. Then try to disprove the light classification. Find hidden delivery surfaces,
> unhandled failures, missing proof, security or data implications, or a reason this needs more
> than one issue. Classify every finding as an increment blocker, pre-existing risk, or optional
> hardening. Only increment blockers may widen the current issue.
> If the draft marks the Data and access surface N/A on a project backed by a shared
> database, start by trying to disprove that N/A from the schema and the intended change.
> Cite concrete evidence. If light is appropriate, say so directly.
> Also compare the delivery with the approved experience artifact and identify any unnecessary
> new layer, relocated entry point, changed default, or adjacent journey regression.

For **full, epic, or explicit grill mode**, use three lenses:

1. **Feasibility** - does the approach fit the system and its real constraints?
2. **Coverage** - does every scope and acceptance identifier map to falsifiable automated and runtime proof?
3. **Risk and sizing** - are security, data, rollback, operations, dependencies, or issue boundaries missing or excessive? Where data access changes, answer three specifically: who is *not* stopped from reaching the data, which consumer of this database would break, and which proof shows only that the intended role succeeds. Treat a Data-and-access N/A as a claim to disprove from the schema and the intended change, not a fact to accept.

All review depths also apply two product-preservation checks: the delivery matches the approved
experience without inventing UI or capability decisions, and every added protection is the
minimum justified by the approved risk posture. A stronger but unnecessary system is an
optional-hardening finding, not an automatic requirement.

Every reviewer classifies additions as increment blockers, pre-existing risks, or optional
hardening. Pre-existing risks and optional hardening do not become issue requirements without
explicit scope expansion.

Reconcile contradictions between reviewers and reconnaissance against the evidence. A product
objection returns to `/scope`. A delivery objection updates the draft. Record material dismissed
objections with the reason they did not survive review.

Confirm the tier only after reconciliation.

### 7. Preview the complete action

Present:

- a scope-concordance card showing the original outcome, named milestone, whether it completes
  the outcome, approved experience artifact, unchanged primary journey, and any deviations
  (`None` is the required value for an implementation-ready draft);
- proposed repository, title, tier, labels, and issue body;
- any epic and child issues in dependency order;
- the product contract version and fingerprint the delivery contract will be stamped against,
  and the default-branch commit it was planned on;
- any GitHub records and relationships that will be created or changed: a new issue, epic
  children, parent links.

Wait for explicit approval. Approval must cover the section text and every record it creates.

### 8. Create or update GitHub

After approval:

1. Write the delivery section with the contract script. It detects the repository from the
   checked-out remote, stamps the product version, fingerprint, and default-branch commit the
   plan was made against, keeps the product section and any other text untouched, reads the
   issue back, and verifies it. Supply only the text below the `Delivery contract` heading.

   Pass `--commit <until commit from the Step 2 drift run>` so the stamp records the commit
   the plan was actually made against, not the tip at the moment of writing.

   ```bash
   # The outcome's issue already carries the product contract
   python3 "$CONTRACT" write <issue> --section delivery --file <draft> --product-fingerprint <fingerprint from Step 1> --commit <until commit>

   # An epic child: a new issue under the parent that holds the product contract
   python3 "$CONTRACT" create --section delivery --title "<title>" --file <draft> --parent <epic> --product-issue <epic> --product-fingerprint <fingerprint from Step 1> --commit <until commit> [--label <label>]

   # Technical scope, or a legacy Linear basis: no product fingerprint; the stamp records fp=none
   python3 "$CONTRACT" write <issue> --section delivery --file <draft> --commit <until commit>
   python3 "$CONTRACT" create --section delivery --title "<title>" --file <draft> --commit <until commit> [--label <label>]
   ```

   When the product contract lives in another repository, name it as
   `--product-issue <owner/repo>#<number>`; a child whose GitHub parent is in another repository
   finds that parent on its own, and the stamp records `product=<owner/repo>#<number>`.
   `create --parent` takes a number in the child's own repository, so for an epic in another
   repository create the child without `--parent`, then add it as a sub-issue of the epic in
   GitHub.

   A `stale` refusal (exit 10) means the product contract moved since Step 1: read it again,
   reconcile, and re-approve. Exit 30 means the issue named by `--product-issue` has no product
   contract: an epic whose parent was never scoped goes back to `/scope`. A read-back mismatch
   (exit 11) is reported as it is; inspect the issue before any retry. Exit 1 means nothing was
   written; fix the cause. Never edit the section by hand. If creating an epic's children stops
   partway, list what exists (`gh issue list --search "<title>"`) before creating the rest.
2. Use labels for organization, not as a switch that suppresses testing (`--label` on create,
   `gh issue edit --add-label` on an existing issue).
3. Report the URL, identifiers, confirmed tier, and the stamped product version and fingerprint.

Do not begin implementation unless the user explicitly asks. The next implementation step is
`/orchestrate <issue>`: it runs `/start-work` workers and independently re-checks their proof.
Recommend `/start-work <issue>` directly only when the user asks for it.

## Completion conditions

The delivery contract is ready when:

- product authority is clear: the delivery contract is stamped with the product contract's
  current fingerprint, or the technical or legacy basis is stated;
- the drift report is written and no product-affecting change was planned around;
- the original outcome, named milestone, and completion semantics are preserved without silent
  deferral;
- every material experience change matches an approved artifact and the adjacent primary journey
  has explicit preservation proof;
- the proposed approach is the simplest complete delivery and every new layer is required by the
  approved outcome or a credible incremental risk;
- minimum controls match the approved risk posture and optional hardening remains deferred unless
  explicitly added through `/scope`;
- the technical approach follows existing project patterns;
- every scope and acceptance identifier maps to proof;
- each delivery surface is applicable with exact proof or N/A with a reason;
- user integration, data, access, security, failure, rollout, and rollback implications are addressed;
- every included concern is introduced or materially worsened by the requested change, or was
  explicitly approved as wider scope;
- the grill review is reconciled and tiering is explained;
- the user approved the write and the created records were read back.
