# Changelog

## v1.1.0 (26 Nov 2026)

- `/ship-it` 1.1.0 reviews each pull request before merging, fixes the defects it finds and gets the checks green, and asks you about choices the scope leaves open.
- Also released here: changes made since v1.0.0 to `/problem-brief`, `/solution-brief` and `/scope` (branding step for Volta's own copies, a misreading review for requirements and targets), plus agent instructions for this repository.

## v1.0.0 (19 Nov 2026)

First release. This repository is the single place Volta's AI development lifecycle skills are edited and the place builders download them from.

All eight skills at 1.0.0: problem-brief, solution-brief, scope, document, orchestrate, start-work, ship-it, and grill-me (optional).

- One edition for everyone: steps that need Volta's own systems say so and are skipped cleanly without them.
- Builders receive the approved 1.0 Solution Brief, and `/scope` reads it; for Volta customer work it stops and asks for the brief rather than scoping without it.
- `/ship-it` says up front that it merges the pull request itself, asks before merging into a branch with no required reviews unless you administer the repository, uses whichever merge method the repository allows, and finds the default branch instead of assuming `main`.
- A builder quick start, a worked example of a finished issue, install folders for Claude Code, Codex and Cursor, how to stay up to date, and an MIT licence.
