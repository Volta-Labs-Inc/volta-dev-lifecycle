# Changelog

## v1.1.0 (19 Nov 2026)

Changes from a review of the repository through an outside builder's eyes.

- **solution-brief 1.1.0, scope 1.1.0:** builders now receive the approved 1.0 Solution Brief, and `/scope` reads it from there. For Volta customer work, `/scope` stops and asks for the brief rather than scoping without it.
- **ship-it 1.1.0:** says up front that it merges the pull request itself, and asks before merging into a branch with no required reviews unless you administer the repository. Uses whichever merge method the repository allows, and finds the default branch instead of assuming `main`.
- **start-work 1.0.1:** new branches start from the repository's default branch.
- **orchestrate 1.0.1:** the Volta progress-bar instructions moved to their own file, so the skill is shorter for builders.
- New quick start for builders, a worked example of a finished issue, install folders for Codex and Cursor, how to stay up to date, and an MIT licence.

## v1.0.0 (19 Nov 2026)

First release. This repository becomes the single place Volta's AI development lifecycle skills are edited, replacing the hand-made builders' copy that had drifted from the skills Volta was using.

All eight skills at 1.0.0: problem-brief, solution-brief, grill-me, scope, document, orchestrate, start-work, ship-it.

- One edition for everyone: steps that need Volta's own systems say so and are skipped cleanly without them.
- The Supabase database security standard now ships inside the document skill, so start-work and ship-it can find it in any install.
- A download zip for each skill and one for the whole set, plus a guide page listing each skill in lifecycle order.
