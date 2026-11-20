# Product Contract on the GitHub Issue

Use this protocol when `/scope` will create or update the product contract on a GitHub
issue, when the work is full or grill depth, or when compaction or handoff could otherwise
lose decisions. A bounded light draft that stays conversational needs none of it.

## Where the contract lives

One GitHub issue per outcome carries two fixed sections:

| Section | Written by | Holds |
|---|---|---|
| **Product contract** (first) | `/scope`, and only `/scope` | Outcome, user and problem, named milestone and its completion semantics, experience contract, `SR-*`/`AC-*`/`D-*`, non-goals and deferred work, risk posture, open questions, and what the contract relies on. No implementation approach, no file names. |
| **Delivery contract** (directly below) | `/document` | Current-system investigation, approach, delivery surfaces, requirement-to-proof matrix, tier, drift report. Cites the product identifiers; never restates the product contract. |

For an epic, the product contract sits on the parent issue and each child carries only a
delivery contract that names the parent. The product contract on GitHub is the product
source of truth once the controlled write and its read-back both succeed. Linear is no
longer written by any development skill.

`scripts/contract.py` owns the mechanics. It splices one section into the body without
touching the other section or any text it did not write, stamps the product section, reads
the issue back after every write, and verifies the fingerprint. Run it from a checkout of
the issue's repository:

`contract.py` ships with the scope skill at `../scope/scripts/contract.py` relative to this
skill's folder; set `CONTRACT` to that path first (Volta setups may use
`$OUTWORKOS_ROOT/skills/scope/scripts/contract.py`). Do not guess a path.

```bash
python3 "$CONTRACT" --help
```
 Set `GH_BIN` to
a stub only in tests. Run it from anywhere inside the issue's checkout: git questions are
asked at the checkout's root.

## What the stamp means

The script writes the section as an H1 (`# Product contract`), a visible stamp line, and the
section text between hidden markers. The text between the markers is what `/scope` supplied
(line endings, trailing whitespace, and blank edges normalized), so the stamp is derived from
it, never part of it:

- **Version** starts at 1 and increments only when the fingerprint changes. Writing identical
  text again is `ALREADY_CURRENT` and touches nothing, unless the stamp itself was edited by
  hand, in which case the script re-stamps the same version.
- **Fingerprint** is the first 8 hex characters of a SHA-256 over the normalized section
  text (LF line endings, no trailing whitespace, no blank edges). GitHub's own CRLF rewrite
  does not move it. `/document` records the fingerprint it planned against; `/start-work` and
  `/orchestrate` recompute it before anyone builds and stop on a difference.
- **Scoped at** is the default-branch commit of the repository when the section was written
  (after a fetch). `/document` compares that commit with the default branch at planning time,
  limited to the paths behind the journeys named under `## Relies on`.

`contract.py fingerprint <file>` gives the fingerprint a draft will carry (a pasted
`# Product contract` heading is ignored), so reviews and approval can bind to it before
anything is written, and the write refuses text that no longer matches
(`--approved-fingerprint`).

## Draft package

Until GitHub holds the approved text, the only durable copy of the contract is a local draft.
If you have Volta's systems (`$OUTWORKOS_ROOT` is set), `<drafts>` is
`$OUTWORKOS_ROOT/generated/scope-artifacts`; otherwise it is
`${SCOPE_DRAFTS_DIR:-$HOME/.local/state/scope-drafts}`:

```text
<drafts>/<project-slug>/<issue-number or outcome-slug>/
  product-contract.md   the text below the section heading, exactly as it will be written
  evidence.md           proposed title, bounded source references, decisions, review
                        receipts, approval response and approved fingerprint
```

The drafts folder is non-authoritative recovery state. Keep secrets, credentials, raw private
messages, and copied long-form evidence out of it. Checkpoint the package after:

1. Orientation and issue resolution.
2. Product reconnaissance.
3. Every resolved or reopened `D-*` decision.
4. The complete contract and quality check.
5. Review reconciliation.
6. Approval and the write result.

After compaction or handoff, reload both files and reconcile them with the GitHub issue
when one exists (`contract.py read <issue>`). Never reconstruct the contract from a
conversation summary when the package exists. Never leave the only copy of a decision in
conversation context.

## Fingerprint and review

Before review or preview, record the draft's fingerprint in `evidence.md`:

```bash
python3 "$CONTRACT" fingerprint <package>/product-contract.md
```

Required lenses are proportional: light uses `light-challenge`; full or grill use
`scope-necessity`, `product-completeness`, and `assumption-quality`. One fresh reviewer may
apply every required lens in a single pass. Each receipt records its lens, the fingerprint it
reviewed, verdict, findings, reconciliation, and timestamp. Reviewers identify defects but do
not edit the draft. Every required lens must review the final fingerprint: a change to the
section text invalidates prior review, approval, and any write that has not happened yet.

## Approval boundary

First present the final approval card from `/scope`: original requested outcome, named
milestone, whether it completes that outcome, approved experience artifact, user-visible
changes, adjacent primary job that remains unchanged, deferred capability, optional hardening,
and unresolved non-blocking questions. Then preview the exact section text, the action
(create a new issue with this title, or update issue `#N`), the repository, and any labels or
parent issue. Record approval only when the user explicitly approves that card, milestone,
experience, and complete write. A bare confirmation after a tangent or an approval of one
decision is not sufficient. Record the approval response and the approved fingerprint in
`evidence.md`. A later change to the text requires a new fingerprint, final-fingerprint
review, and new approval.

For an update, note the current version and fingerprint from `contract.py read <issue>`;
the write passes it as `--expect-fingerprint` so a section that moved since it was read is
refused rather than overwritten.

## Controlled write

After approval, use the script rather than editing the issue body by hand:

```bash
# New outcome
python3 "$CONTRACT" create \
  --title "<approved title>" --file <package>/product-contract.md \
  --approved-fingerprint <approved> [--label <label>]

# Existing issue
python3 "$CONTRACT" write <issue> \
  --section product --file <package>/product-contract.md \
  --approved-fingerprint <approved> --expect-fingerprint <current>
```

The script detects the repository from the checkout it runs in (pass `-R owner/repo` when the
issue lives elsewhere, together with `--commit <commit id>` for the scoped-at commit; a branch
name is refused), refuses text that no longer fingerprints to the approved value, refuses a
body that changed while the write was being prepared, writes only the product section, keeps
any delivery section and other text in place, reads the issue back, and verifies the saved
body, stamp, and (for a new issue) title, labels, and parent. Its exit codes:

| Exit | Meaning | What to do |
|---|---|---|
| 0 | `CREATED`, `WRITTEN`, or `ALREADY_CURRENT` | Record the issue URL, version, and fingerprint. |
| 10 | `stale`: the section or body on GitHub is not the one that was read, or the text is not the approved text | Read it again, reconcile, re-approve. |
| 11 | the write landed but the read-back differs | Inspect the issue (the message names it) before any retry; report what GitHub holds. |
| 1 | error (gh, git, malformed section) | Fix the cause; nothing was verified. |
| 2 | usage error | Fix the command line. |

A `WRITTEN` result that notes the delivery contract was planned against an earlier version is
expected after a product change: `/document` reconciliation is the next step, not a failure.
If `create` reports an ambiguous result, search the repository for the exact title before
deciding whether a new attempt is safe. Never retry a create blindly.

## Hand off to `/document`

Pass the issue number and URL, the product contract version and fingerprint, the scoped-at
commit, depth, and the identifiers. `/document` reads the section with
`contract.py read <issue>`, runs its drift checks, and writes the delivery contract below.

## Legacy records

- **An issue that links a Linear issue but has no product-contract section** stays
  buildable where the `linear` CLI is installed and signed in: `/document`, `/start-work`, and
  `/orchestrate` read the Linear scope through it, read-only, as they did before. When `/scope`
  next touches that outcome, it reads the Linear text as evidence and writes the product contract on the GitHub issue; it
  does not update Linear.
- **Older `generated/scope-artifacts/<project>/<uuid>/` packages** (Volta setups only) hold `contract.md`,
  `evidence.md`, and a `manifest.json` from the retired Linear persistence path. Treat
  `contract.md` as the draft and `evidence.md` as history; the manifest's receipts are no
  longer read. Carry an unfinished package forward by writing its contract as a product
  section with the commands above.
