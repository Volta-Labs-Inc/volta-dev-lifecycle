# Requirements Quality and Grill Review

## Adapted requirements quality check

Use the practical characteristics from the INCOSE Guide to Writing Requirements as a
quality lint rather than as a heavyweight discovery process.

For each `SR-*`, verify:

1. **Necessary** - removing it would prevent the stated outcome or violate a real constraint.
2. **Appropriate** - it states product behavior at the product-contract level, not implementation.
3. **Unambiguous** - intended readers should reach one interpretation.
4. **Complete** - actor or entity, behavior, applicable conditions, and measurable constraint are present when needed.
5. **Singular** - it contains one obligation. Split independently verifiable behavior.
6. **Feasible** - evidence does not show it to be impossible within known constraints and acceptable risk.
7. **Verifiable** - an observer could tell whether it was satisfied.
8. **Correct** - it accurately represents its source, decision, or higher-level need.
9. **Conforming** - it follows the project terminology and identifier pattern.

For the full set, verify:

- the requirements cover the committed scope without relying on headings for meaning;
- no two requirements overlap or contradict each other;
- the same terms mean the same thing throughout;
- product constraints, failures, and important quality attributes are represented;
- each requirement appears once and only once;
- light-contract ceilings were not treated as targets and no requirement exists merely to fill
  a template or enumerate an unchanged system behavior;
- when the requested increment creates stored data, changes who may see or act on it, or depends
  on an unsettled access boundary, the contract says who may see it, who must not, and what
  someone without permission gets instead. `Public by design`, named and reasoned, is a valid
  answer. When the increment reuses an existing authorized path and leaves its audience
  unchanged, record that boundary as unchanged rather than reopening its permission design.

## Outcome, experience, milestone, and risk gates

Before approving the contract, verify all four:

1. **Outcome integrity** - the original request is preserved separately from the proposed
   milestone. A deferred core capability has explicit approval, and completing a partial
   milestone cannot be confused with completing the original outcome.
2. **Experience integrity** - every material capability, job, entry point, navigation,
   hierarchy, placement, label, default, responsive behavior, or adjacent journey change is
   explicit. A material experience change has an approved low- or high-fidelity artifact, and
   the existing primary job that must remain usable is named.
3. **Milestone integrity** - one named milestone has a falsifiable definition of done and clear
   completion semantics. Exploratory agreement or approval of an individual decision is not
   milestone approval.
4. **Risk proportionality** - minimum controls follow from actual users, reach, sensitivity,
   reversibility, credible harm, likelihood, existing controls, and consequence of omission.
   Optional hardening is separated along with its experience and delivery cost.

Apply [the settled-correction boundary](../SKILL.md#settled-corrections): an exact correction
with unchanged meaning, authority, and journey does not create a new product decision. Check
the evidence for that claim instead of requiring a prototype merely because an interface changes.

Fail the review when `/document` would still need to choose where a capability lives, what an
existing journey becomes, whether the milestone is complete, or how much protection is enough.

## Scope-delta check

Before adding any requirement, failure, constraint, or reviewer finding, ask:

1. Does the requested increment introduce or materially worsen this condition?
2. Is resolving it necessary for the literal outcome or for this increment to be safe?
3. Would the condition still exist if the increment were not built?

Classify the result:

- **Increment blocker** - introduced or materially worsened by the change and required now.
- **Pre-existing risk** - exists without the change; link or record it as follow-up work.
- **Optional hardening** - improves robustness but is not required for the committed outcome.

Only increment blockers enter the current contract automatically. A pre-existing risk may enter
only when the increment materially increases exposure or the user explicitly approves the wider
scope. Optional hardening requires explicit approval.

## Writing rules worth enforcing

- Use active voice with the responsible product, user, or external system named.
- State conditions explicitly instead of relying on surrounding prose.
- Replace vague terms such as "fast", "easy", "appropriate", or "regularly" with a measure or a decision.
- Avoid open-ended lists such as "etc." or "including but not limited to".
- Avoid absolutes such as "always" and "never" unless the absolute is intentional and feasible.
- Keep the requirement solution-free unless a real constraint justifies prescribing the design.
- Use one consistent glossary and units of measure.
- Use `must` for a committed product obligation. Use `may` only for genuinely optional behavior.

## Stories and acceptance examples

A user story or job story provides value context; it is not the full specification. Do not
derive one story per screen, component, or document heading.

Use Given/When/Then when a rule depends on meaningful conditions:

- **Given** establishes the relevant state.
- **When** names one user or external-system event.
- **Then** names an observable result rather than an implementation detail.

Use a simple bullet when the outcome has no meaningful scenario. Do not force every
criterion into the same syntax.

## Grill interview method

For each unresolved decision:

1. Ask the most consequential remaining question.
2. Let the user answer without front-loading the recommendation.
3. Give the recommended answer and reasoning.
4. Identify evidence that supports or contradicts the answer.
5. Resolve dependencies before moving to a downstream choice.
6. Record the choice and rationale as `D-*`.

Do not prolong the interview after the decisions converge.

If a tangent, implementation detail, or security discussion has displaced the original job,
perform a context reset before the next approval: original outcome, current milestone, changed
decisions, unchanged behavior, and deferrals. Do not treat a bare confirmation after a tangent
as approval of the full milestone.

## Fresh-context review prompts

Run one review pass against the exact proposed contract. A single fresh reviewer may apply all
three full-depth lenses. Use separate reviewers only when the product risk warrants the extra
cost. Budget at most two rounds; after that, non-safety findings that do not change what gets
built become recorded open questions.

### Light challenge

> First identify requirements that can be removed while preserving the literal requested
> outcome and safe use. Then try to disprove the proposed light classification. For every
> hidden scope, unhandled user or failure, missing constraint, or additional delivery surface,
> classify it as an increment blocker, pre-existing risk, or optional hardening using the
> scope-delta check. Cite the contract section and source evidence. Only increment blockers may
> justify wider current scope. If light is appropriate, say so directly.

### Scope necessity

> Refute unnecessary or duplicated scope and identify required behavior that is absent.
> Separate evidence-backed findings from preferences. Classify every addition as an increment
> blocker, pre-existing risk, or optional hardening. Prefer a follow-up over widening the
> current increment when the condition exists without it.

### Outcome and experience integrity

> Compare the original requested outcome with the committed milestone. Identify any core
> capability that was silently deferred, weakened, renamed, or treated as optional. Then compare
> the requirements with the approved experience artifact: entry point, job, hierarchy,
> placement, labels, defaults, responsive behavior, and the adjacent primary journey that must
> remain usable. Treat any decision `/document` would still have to invent as a blocker.

### Risk proportionality

> Test whether each required protection follows from the actual users, reach, sensitivity,
> reversibility, credible harm, likelihood, and existing controls. Identify security,
> reliability, audit, recovery, or operational layers that exceed the minimum safe controls for
> the approved milestone. Classify them as optional hardening unless omission makes this
> increment unsafe to use, and state the user-experience and delivery cost of keeping them.

### Product completeness

> Identify the user, condition, failure, constraint, acceptance example, or downstream
> consequence that the contract fails to address. Explain how the omission could change
> the delivered product.
>
> When the requested increment creates stored data, changes access, or depends on an unsettled
> access boundary, answer explicitly: who must not be able to see or act on it, and does the
> contract say so? When it reuses an existing authorized path without changing its audience,
> verify that claim without turning a broader access audit into feature scope.

### Assumption quality

> Identify unsupported claims, invented certainty, solution-first framing, or requirements
> that cannot be verified. Cite the source that supports or contradicts each finding.

## Sources

- INCOSE Guide to Writing Requirements V4 summary:
  https://www.incose.org/docs/default-source/working-groups/requirements-wg/guidetowritingrequirements/incose_rwg_gtwr_v4_summary_sheet.pdf
- Agile Alliance user stories:
  https://agilealliance.org/glossary/user-stories/
- Cucumber Gherkin reference:
  https://cucumber.io/docs/gherkin/reference/
