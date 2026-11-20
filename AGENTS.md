# Volta AI Development Lifecycle: instructions for agents

This repository holds eight agent skills, in `skills/`, that take a piece of customer work from an agreed problem to a verified change in production. The README explains what each skill does, and the guide at https://docs.voltaeffect.com/builders/ai-development-lifecycle is built from it.

## This repository is public

Anyone can read everything committed here. Never commit customer names, customer data, internal links (claude.ai artifacts, private documents), credentials, or anything about a real engagement. Examples use fictional customers, such as the bakery in `examples/worked-example.md`.

## Changing a skill

1. Edit the skill under `skills/<name>/`. Keep the skills side by side: `/document`, `/orchestrate` and `/start-work` find the contract script at `../scope/scripts/contract.py`.
2. Steps that need Volta's own systems start with a plain condition (for example, "If you have Volta's systems…") so the skill still works without them. Keep every new Volta-only step that way.
3. Run the tests. Both must report 0 failed:

   ```bash
   bash skills/scope/scripts/contract.test.sh
   bash skills/ship-it/campsite.test.sh
   ```

4. Run `python3 scripts/build.py`, which rebuilds `dist/*.zip` and `docs/index.html`, then `python3 scripts/build.py --check`.
5. Follow the README's "Changing a skill" section for versions, the changelog and the release.

## Files that stay off this repository

Maintainers who register this folder in their own tooling keep their working notes (context maps, logs, next steps, harness configs) local and out of Git.
