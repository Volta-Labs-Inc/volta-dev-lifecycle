# Volta AI Development Lifecycle

Eight agent skills that take a piece of customer work from an agreed problem to a verified change in production. This repository is the one place they are edited. Volta's own sessions use them straight from here, and builders download them from the [releases](https://github.com/Volta-Labs-Inc/volta-dev-lifecycle/releases).

The guide, with a plain-English description, version and download link for each skill, is at https://docs.voltaeffect.com/builders/ai-development-lifecycle (built from `docs/index.html`).

## Quick start for builders

If Volta has asked you to build part of a customer project:

1. **Install the skills** (see Install below) and open your agent tool in the project's repository.
2. **Fill in the solution brief.** Volta sends you a brief to complete. Run `/solution-brief` and choose Guide mode; it walks you through it and saves a file you send back to Volta.
3. **Wait for the 1.0 brief.** Volta reviews it and sends you the approved 1.0 copy. Each of its increments becomes one piece of work.
4. **Write the product contract.** Run `/scope` on one increment. It reads the 1.0 brief and writes what must be true when you're done onto a GitHub issue.
5. **Write the delivery contract.** Run `/document` on that issue. It adds how you'll build it and how each requirement will be proved.
6. **Build it.** Run `/orchestrate` on the issue. It runs builder agents, checks their proof itself and comes back to you only for decisions.
7. **Ship it.** Run `/ship-it`. It commits, opens and merges the pull request, and confirms the change works in production.

Use `/grill-me` at any point to pressure-test a plan. To see what a finished issue looks like after steps 4 and 5, read [`examples/worked-example.md`](examples/worked-example.md).

**Good to know:** `/ship-it` merges the pull request itself once its checks pass. If the repository has no required reviews and you don't administer it, it tells you so and asks before merging. Agree with the customer how changes get reviewed before you use it on their repository.

## The lifecycle

Use them in this order. Each one hands its result to the next.

| Step | Skill | What it does |
|---|---|---|
| 1 | `/problem-brief` | Writes the one-page Problem Brief a customer confirms: the problem, how we will measure it and what done means. Volta-run. |
| 2 | `/solution-brief` | Records the chosen approach and why it beat the alternatives, what success means for the builder, the riskiest assumption and the increments to build. Its Guide mode works for any builder; set-up and review are Volta-run. |
| 3 | `/scope` | Writes the **product contract** on the work's GitHub issue: outcome, who it is for, boundaries and numbered requirements. It says what, never how. One run per increment. |
| 4 | `/document` | Writes the **delivery contract** under it: how the change will be built, and the tests and checks that prove each requirement. |
| 5 | `/orchestrate` | Runs one or more `/start-work` builder agents, re-checks their proof independently, and is your single point of contact until the work is verified. |
| – | `/start-work` | What each builder agent runs: builds against the contracts, test-first, and reports proof for every requirement. You rarely call it yourself. |
| 6 | `/ship-it` | Security checks, commit, pull request, merge, branch cleanup, then confirms the change works in production. |
| Optional | `/grill-me` | Interviews you one question at a time about a plan you already have and pushes back on weak answers. Try it before `/scope` to test the solution brief's approach, before `/document` to challenge a risky technical approach, or whenever a decision feels shaky. Works in the Claude app too. |

Both contracts live on the work's GitHub issue, as its first two sections. A small script that ships with the scope skill, `skills/scope/scripts/contract.py`, writes and reads them and fingerprints the product contract, so builders stop if it changed after the plan was made.

## One edition, with skips

There is one version of each skill. Steps that need Volta's own systems (its operating database and `outwork` command, project context maps, Linear, the task hub, the orchestrate progress bar) say so at the start and are skipped, with an alternative where one exists, when those systems are not there. Supabase-specific database checks run only when the project uses Supabase.

## What you need

- **Claude Code or Codex**, or another agent tool that loads skills from a folder and can run sub-agents. `/grill-me` works anywhere, including the Claude app. The others need a terminal, git and GitHub.
- **git**, and the project in a **GitHub** repository.
- The **GitHub CLI (`gh`)**, signed in to an account that can read and write issues and pull requests on that repository.
- **Python 3** (standard library only) for the contract script.
- The project's own **test runner** and build commands, documented in the repository so agents can find them.
- Credentials the project needs, provided the way the project documents (a `.env` setup or a secret manager). The skills never ask you to paste a secret into the chat.

Optional, used only when your project has them: Supabase (extra database security checks; the standard is in `skills/document/references/`), a hosting platform that deploys on merge, and browser automation in your agent tool for checking pages.

## Install

Download the full set from the [latest release](https://github.com/Volta-Labs-Inc/volta-dev-lifecycle/releases/latest) and unzip it into your agent tool's skills folder, keeping the skill folders side by side:

| Tool | Every project | One repository |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `.claude/skills/` |
| Codex | `~/.agents/skills/` (older versions: `~/.codex/skills/`) | `.agents/skills/` |
| Cursor | `~/.cursor/skills/` | `.cursor/skills/` |

Keep them together. `/document`, `/orchestrate` and `/start-work` find the contract script at `../scope/scripts/contract.py`, and `/start-work` and `/ship-it` read the database security standard inside `document/`. Scope drafts not yet on GitHub are kept in `~/.local/state/scope-drafts/` unless `SCOPE_DRAFTS_DIR` says otherwise.

## Staying up to date

Click **Watch → Custom → Releases** on this repository to be told when a new version comes out. Each skill's `CHANGELOG.md` says what changed.

The easiest way to stay current is to clone the repository once and link the skills into your tool's folder, then update with `git pull`:

```bash
git clone https://github.com/Volta-Labs-Inc/volta-dev-lifecycle.git ~/volta-dev-lifecycle
for s in ~/volta-dev-lifecycle/skills/*/; do ln -s "$s" ~/.claude/skills/; done
```

Change `~/.claude/skills/` to your tool's folder from the table above. If you downloaded a zip instead, download the new one and replace the folders.

## Check it works

```bash
bash skills/scope/scripts/contract.test.sh
bash skills/ship-it/campsite.test.sh
```

Both run offline, against a stand-in for GitHub and throwaway local repositories, and should report 0 failed.

## Changing a skill

1. Edit the skill under `skills/<name>/`.
2. Raise its `version` in the SKILL.md frontmatter and add an entry to `skills/<name>/CHANGELOG.md`. Use 1.0.1 for wording fixes, 1.1.0 for a new step or behaviour, 2.0.0 when it changes what it hands to the next skill.
3. Raise `VERSION` (the release number) and add an entry to the top-level `CHANGELOG.md`.
4. Run the tests above and `python3 scripts/build.py`, which rebuilds `dist/*.zip` and `docs/index.html`.
5. Commit, push, then publish the release: `gh release create v<VERSION> dist/*.zip`.
6. Republish the guide with Volta's `/doc` skill: `~/.claude/skills/doc/scripts/publish.sh docs/index.html builders/ai-development-lifecycle`.

## Licence

MIT. Use, change and share these skills on any work, keeping the copyright notice. See `LICENSE`.
