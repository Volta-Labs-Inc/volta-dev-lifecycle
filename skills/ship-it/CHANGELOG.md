# Changelog: ship-it

## 1.1.0 (19 Nov 2026)

- The skill now says up front that it merges the pull request itself once checks pass.
- Before merging, it checks whether the target branch requires a review or passing checks. If nothing is required, it tells you that unreviewed changes would go straight in and asks whether to merge now or leave the pull request open, unless you already said to merge or you administer the repository.
- It now uses whichever merge method your repository allows (merge, squash or rebase) instead of failing when plain merges are turned off.
- It no longer assumes your main branch is called `main`; it asks GitHub for the repository's default branch.

## 1.0.0 (19 Nov 2026)

- First release in the Volta AI Development Lifecycle repository, taken from the version Volta was using on 19 Nov 2026.
- Steps that need Volta's own systems now say so and are skipped cleanly when those systems aren't there.
