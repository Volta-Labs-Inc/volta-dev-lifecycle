# Prototype Brief

Create only the prototype needed to lock a material change to the user experience. Use the
result to confirm or reopen the contract before milestone approval. The approved product
contract remains authoritative for behavior the prototype cannot show.

Apply [the settled-correction boundary](../SKILL.md#settled-corrections) before creating an
artifact. An exact correction that introduces no material experience decision needs only its
source and verification; it does not require a new prototype or another design approval.

Use low fidelity when placement, hierarchy, flow, terminology, or a familiar control is the
material decision. Use high fidelity when realistic content, visual density, responsive
behavior, or a novel interaction could change the decision. Show both the affected future state
and enough of the current or adjacent journey to prove the primary job has not been displaced.

```markdown
# [Outcome] - Prototype Brief

## Risk being tested

[The usability or interaction assumption that could change the product commitment.]

## Fidelity and approval boundary

- **Fidelity:** [Low or high, with the reason.]
- **Existing journey shown:** [The current primary job or screen being preserved.]
- **Binding decisions:** [Capability, entry point, hierarchy, placement, labels, defaults, and
  responsive behavior this artifact settles.]
- **Not settled by this artifact:** [Rules or edge cases that remain in the product contract.]

## Job stories

- **J-01** - When [situation], I want to [motivation], so I can [outcome].

## Prototype coverage

| Flow or screen | Job story | Existing behavior preserved | What the reviewer should test | Artifact |
|---|---|---|---|---|
| [name] | J-01 | [primary job or adjacent behavior] | [observable question] | [link or file] |

## Rules the prototype does not show

- Access and visibility: [link to contract section]
- Failure or edge behavior: [link to SR/AC identifiers]
- Other product constraints: [link to contract section]

## Evidence

| Assumption | How tested | Result | Status |
|---|---|---|---|
| [assumption] | [review, test, interview, or not yet tested] | [finding] | [retired/open] |

## Approval

- **Approved artifact:** [Exact link/file and version or digest.]
- **Approved decisions:** [The binding experience decisions represented.]
- **Approval evidence:** [User approval captured after the context reset and milestone recap.]

## Open questions

- [Question that could still change the contract]
```

Delete unused rows. Do not prototype settled behavior merely to make the artifact look complete.
Do not hand off to `/document` while a binding experience question or the artifact approval is
still open.
