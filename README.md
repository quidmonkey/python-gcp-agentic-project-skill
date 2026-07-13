# python-gcp-agentic-project-skill

A Claude Code skill that scaffolds Python projects with `uv`. One command wires linting, type checking, security scanning, and tests into pre-commit. It also drops agent instruction files that stop Claude from skipping those checks when writing code. GCP projects get extra cost and infra docs; the skill asks at setup.

## What it creates

```
my-project/
├── .claude/
│   └── settings.json        # Stop hook: runs pre-commit + detects docs/design.md changes
├── docs/                    # design.md, design.mmd (+ finops.md, infra.md for GCP)
├── scripts/
│   └── code-review.sh       # two-pass agentic code review, runs on git push
├── .codereviewrc            # code review config: agent, enabled, custom command
├── pyproject.toml           # ruff, ty, bandit, pytest config
├── .pre-commit-config.yaml  # all hooks configured (pre-commit + pre-push stages)
├── .gitignore
├── uv.lock                  # committed; pins transitive deps for deterministic installs
├── CLAUDE.md                # Claude Code agent instructions
├── README.md                # project readme, documents the code review flow
└── src/my_package/          # single package layout
    └── __init__.py
    tests/
    └── __init__.py
```

For monorepo layout, code lives under `packages/<name>/` instead of `src/`.

## Toolchain

| Tool | Purpose |
|------|---------|
| [ruff](https://github.com/astral-sh/ruff) | Linting + formatting (replaces flake8, isort, pyupgrade, and more) |
| [ty](https://github.com/astral-sh/ty) | Type checking, 10-100x faster than mypy |
| [bandit](https://github.com/PyCQA/bandit) | Security scanning |
| [pytest](https://pytest.org) | Tests |
| [pre-commit](https://pre-commit.com) | Runs all of the above as git hooks |

Complexity is enforced via ruff's built-in C90 (McCabe) rules rather than a separate tool.

## Skills installed

| Skill | Source |
|-------|--------|
| [google-agents-cli](https://docs.anthropic.com/en/docs/claude-code/plugins) | Google Cloud agent tooling (project plugin; installs only if its marketplace is registered) |

Humanizing prose is baked into `CLAUDE.md` as inline directives (condensed from [humanizer](https://github.com/blader/humanizer)), so no separate skill is installed.

## Agentic development

Two files keep AI agents honest after they write code.

`CLAUDE.md` tells Claude Code to run pre-commit after every change and fix failures at root cause rather than suppress them. It also sets a terse response style, a "laziest solution that works" rule (reuse and stdlib before new code, no speculative abstractions), and prose-humanizing directives (strip AI-writing tells from `.md` files) — all condensed in-line so no extra skills are needed. `.claude/settings.json` adds a `Stop` hook that runs pre-commit when Claude finishes responding, scoped to changed files for speed, falling back to `--all-files` on a clean working tree. The output feeds back as context, so Claude sees any failures and corrects them before you're involved. A second hook warns when `docs/design.md` was modified without updating `docs/design.mmd` (and `docs/finops.md` on GCP projects).

The `Stop` hook is the important one. It's enforcement, not a reminder.

## App run check

Beyond lint and tests, the scaffold bakes in one operational rule: after writing code, the agent runs the app to confirm it still starts. The command lives in one place, `make run-check`. It ships as an import check (a new project has nothing to run yet), and `CLAUDE.md` requires the agent to upgrade it the moment a real entry point exists — `--help` or a dry run for a CLI, start + health probe + teardown for a server — and to keep it under 30 seconds with no external services. A pre-push hook runs the same target next to pytest, so a push that breaks startup is blocked even if the agent skipped the procedure.

## Code review on push

Every scaffolded project gets a pre-push code review gate (`scripts/code-review.sh`, wired into pre-commit's pre-push stage). Pushing a branch runs an AI agent over the branch diff in two passes, executed in parallel:

1. **General review** — DRY, YAGNI, preferring existing libraries over hand-rolled code, missing tests per the project's CLAUDE.md testing rules, general best practices, and security.
2. **Spec conformance** — reads the design docs in `docs/` and flags code that deviates from the documented intent.

Findings come back as REQUIRED or SUGGESTED. Any REQUIRED finding fails the hook, blocks the push, and writes the full report to `working/code-review-report.md`. The project's CLAUDE.md tells the agent to read that report, fix REQUIRED findings at root cause, and push again.

Reviews are incremental: the last passing commit for each branch is recorded in `.git/code-review-ledger`, so the next push reviews only new commits. An unchanged branch is never re-reviewed.

The reviewing agent is configurable via `.codereviewrc`:

| Key | Values | Default |
|-----|--------|---------|
| `agent` | `claude`, `codex`, `gemini`, `copilot`, `pi`, `custom` | `claude` |
| `enabled` | `true` / `false` | `true` |
| `command` | shell command for `agent=custom`; receives the prompt on stdin | — |

The contract is agent-agnostic: whatever runs must print its review to stdout and end with `VERDICT: PASS` or `VERDICT: FAIL`. Preset CLI flags live at the top of `code-review.sh` and are easy to adjust if a CLI's syntax changes.

Escape hatches: `SKIP_CODE_REVIEW=true git push` skips one push, `enabled=false` turns it off for the repo. If the agent CLI isn't installed at all, the hook warns and fails open so teammates without it aren't blocked.

## Installation

Clone directly into the skills directory:

```bash
git clone git@github.com:quidmonkey/python-gcp-agentic-project-skill.git \
  ~/.claude/skills/python-gcp-agentic-project-skill
```

## Usage

In any Claude Code session:

```
create a new python project called my-api
```

Or invoke directly:

```
/python-gcp-agentic-project-skill my-api
```

Claude will ask whether you want a single package or monorepo layout, then scaffold the entire project.

## Requirements

- [Claude Code](https://claude.ai/code)
- [uv](https://github.com/astral-sh/uv)
- Git
- Python ≥ 3.12

## Notes

The [templates/](./templates/) directory holds the actual opinions: what tools to use, how to configure them, what to tell the AI agent. They come from two decades across startups and enterprise, meant as a baseline, not a straitjacket.

A few deliberate choices:
- Everything installs locally via `uv`, no global deps, no version conflicts
- `uv.lock` is committed so installs are reproducible
- Documentation lives in the repo (`docs/`) so the AI agent can read and update it
- Setup is intentionally minimal; context overload makes agents worse, not better
