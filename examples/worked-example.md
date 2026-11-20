# Worked example: a finished issue

This is what a GitHub issue looks like once `/scope` and `/document` have both run on it. The example is fictional: a small bakery wants customers to be able to ask for an email when their online order is ready to collect. `/scope` wrote the first section, the product contract, which says what the customer gets and how we will know it works. `/document` wrote the second section, the delivery contract, which says how it will be built and what proof each requirement needs. Both sections carry a short fingerprint of the product contract, so if anyone changes the product contract later, the builders' tools notice the mismatch and stop before building against an out-of-date plan.

The body below was produced by `skills/scope/scripts/contract.py` itself (`create`, then `write --section delivery`), so the hidden markers, stamp lines and fingerprint are exactly what the tool writes and `contract.py check` reports the two sections as in sync.

## The issue body

````markdown
<!-- contract:product v=1 fp=5f8d38b7 at=3ef57f66 date=2026-11-20 -->
# Product contract

_Product contract v1 · fingerprint `5f8d38b7` · scoped at default-branch commit `3ef57f66` · 2026-11-20 · written by /scope_

<!-- contract:product:body -->
## Outcome

Fewer customers wait at the counter for orders that are not ready: customers who ask for an email are told the moment their order can be collected.

## Outcome integrity

- **Original request:** "Let customers ask to be emailed when their order is ready."
- **Committed outcome:** An optional "Email me when it's ready" choice on the order form, and one email when staff mark the order ready.
- **Complete or partial:** Complete.
- **Explicitly deferred:** None.

## Problem and evidence

Customers who order ahead arrive early and wait, or phone the shop to ask. Staff report six to ten "is it ready?" calls on a Saturday morning, which pull them away from the oven.

## Learning check

No experiment: the bakery will add the option either way, and the call count is watched informally by the owner.

## Experience contract

- **Existing primary job:** A customer fills in the order form and gets an order number; staff mark the order ready on the orders screen.
- **Approved change:** One unticked checkbox, "Email me when it's ready", under the email field on the order form. Nothing changes on the staff screen.
- **Must remain unchanged:** Placing an order without ticking the box, and the staff "Mark ready" button.
- **Experience artifact:** `wireframes/order-form-ready-email.png` (low fidelity, approved).

## Relies on

- Placing an order through the online order form.
- Staff marking an order ready on the orders screen.
- The shop's existing order-confirmation email.

## Scope

### In scope

- The opt-in checkbox and one "ready to collect" email per order.

### Out of scope

- Text messages, delivery tracking, and emails for any other status change.

## Milestone and completion

- **Milestone:** Ready-to-collect email.
- **Definition of done:** A customer who ticked the box receives one email within a minute of staff marking the order ready.
- **Does this complete the original request?** Yes.
- **Must not be called complete when:** The email is sent to customers who did not tick the box.

## Product requirements

- **SR-01** - When a customer places an order, the form must offer an unticked "Email me when it's ready" checkbox.
- **SR-02** - When staff mark an order ready and the customer ticked the box, the product must send one email naming the order number.
- **SR-03** - When the customer did not tick the box, the product must send no ready email.

## Acceptance examples

### AC-01 - Customer asked to be told

- **Given** an order placed with the box ticked
- **When** staff press "Mark ready"
- **Then** the customer receives one email that names the order number

### AC-02 - Customer did not ask

- **Given** an order placed with the box unticked
- **When** staff press "Mark ready"
- **Then** no ready email is sent

## Risk posture

- **Users and reach:** One shop's online customers; tens of orders a day.
- **Data and sensitivity:** The email address the customer already gives for the confirmation email; nothing new is collected.
- **Credible incremental harm:** An unwanted email if the choice is ignored; low likelihood.
- **Reversibility and existing controls:** The option can be hidden again; emails already go through the shop's mail service.
- **Minimum safe controls for this milestone:** Send only when the box was ticked (SR-03).
- **Consequence of deferring those controls:** Customers receive mail they did not ask for.
- **Optional hardening deferred:** None.

## Decisions

No material decisions beyond the requirements.
<!-- /contract:product -->

<!-- contract:delivery v=1 fp=5f8d38b7 at=3ef57f66 date=2026-11-20 -->
# Delivery contract

_Delivery contract · planned against product contract v1 `5f8d38b7` at default-branch commit `3ef57f66` · 2026-11-20 · written by /document_

<!-- contract:delivery:body -->
## Scope authority

- **Scope basis:** product contract
- **Product contract:** #1 v1 `5f8d38b7`, scoped at `3ef57f66`
- **Delivery tier:** light
- **Named milestone:** Ready-to-collect email
- **Completes original outcome:** Yes

## Drift report

- **Scoped at:** `3ef57f66` · **Default branch at planning:** `3ef57f66`
- **Paths watched:** `app/checkout/`, `app/orders/`, `app/email/`
- **What changed:** Nothing: scoping and planning used the same default-branch commit.

## Outcome summary

Customers who tick the new box get one email when staff mark their order ready; everyone else sees no change.

## Scope concordance

- **Original requested outcome:** Email customers who ask when their order is ready.
- **Approved experience artifact:** `wireframes/order-form-ready-email.png` (low fidelity).
- **Existing primary job preserved:** Ordering without the box, and the staff "Mark ready" button.
- **Product decisions implemented:** N/A: the product contract has no `D-*` entries.
- **Deviations from approved scope or experience:** None.

## Current behavior and evidence

The order form saves the order and sends a confirmation email through the shop's mail service. "Mark ready" changes the order's status and sends nothing. Established by placing a test order and marking it ready on a local copy.

## Proposed approach

- **Simplest complete delivery:** Store the customer's choice with the order; when status changes to ready and the choice is set, send one email through the existing mail service.
- **Existing behavior and controls reused:** Order form, status change, confirmation-email sender.
- **Necessary new layers:** One yes/no field on the order (defaults to no).
- **Optional hardening deferred:** None.

## Requirement-to-proof matrix

| Scope ID | Required behavior | Surface | Automated proof | Runtime proof | Readback or evidence |
|---|---|---|---|---|---|
| SR-01 | Unticked checkbox under the email field | frontend | order-form test: box present and unticked | load the form at desktop and phone width | screenshot against the wireframe |
| SR-02 / AC-01 | One ready email naming the order number | backend | status-change test: one send when opted in | place an opted-in order, press "Mark ready" | test inbox shows one email with the order number |
| SR-03 / AC-02 | No email when not opted in | backend | status-change test: zero sends when not opted in | place an order without the box, press "Mark ready" | test inbox shows nothing |
| Regression | Ordering and "Mark ready" work as before | full-stack | existing checkout and orders tests | order without the box, mark ready | order status reads ready |

## Completion contract

- [ ] Every scope requirement has a proof row.
- [ ] The delivery has no deviation from the approved product scope or experience artifact.
- [ ] The new email and the existing order journey both pass through their real user journeys.
- [ ] Repository-native checks pass with nonzero test collection.
- [ ] Runtime behavior is observed at the affected surface.
<!-- /contract:delivery -->
````

## What happens next

- **`/orchestrate`** picks up the issue and runs `/start-work` workers against it, after confirming the product contract still has fingerprint `5f8d38b7`.
- **`/start-work`** builds the change test-first and reports proof for each row of the requirement-to-proof matrix (SR-01, SR-02 / AC-01, SR-03 / AC-02, and the regression row); `/orchestrate` re-checks that proof independently.
- **`/ship-it`** merges the work, then confirms in production that an opted-in order gets its email and records that on the issue.
