# python-gcp-agentic-project-skill

A Claude Code skill that scaffolds GCP-based Python projects using `uv`. Run one command and get linting, type checking, security scanning, and tests wired into pre-commit, along with agent instruction files that stop AI agents from skipping the checks when writing code.

## What it creates

```
my-project/
├── .claude/
│   └── settings.json        # Stop hook: runs pre-commit + detects docs/design.md changes
├── docs/                    # design.md, design.mmd, finops.md, infra.md
├── pyproject.toml           # ruff, ty, bandit, pytest config
├── .pre-commit-config.yaml  # all hooks configured
├── .gitignore
├── CLAUDE.md                # Claude Code agent instructions
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
| [humanizer](https://github.com/blader/humanizer) | Removes AI writing patterns from prose; auto-invoked on `.md` files |
| [google-agents-cli](https://docs.anthropic.com/en/docs/claude-code/plugins) | Google Cloud agent tooling (project plugin) |

## Agentic development

Two files keep AI agents honest after they write code.

`CLAUDE.md` tells Claude Code to run pre-commit after every change and fix failures at root cause rather than suppress them. `.claude/settings.json` adds a `Stop` hook that runs `pre-commit run --all-files` when Claude finishes responding; the output feeds back as context, so Claude sees any failures and corrects them before you're involved. A second hook warns when `docs/design.md` was modified without updating `docs/design.mmd` and `docs/finops.md`.

The `Stop` hook is the important one. It's enforcement, not a reminder.

## Installation

Clone directly into the skills directory:

```bash
git clone https://github.com/quidmonkey/python-project-skill \
  ~/.claude/skills/python-gcp-agentic-project-skill
```

## Usage

In any Claude Code session:

```
create a new python project called my-api
```

Or invoke directly:

```
/python-gcp-project my-api
```

Claude will ask whether you want a single package or monorepo layout, then scaffold the entire project.

## Requirements

- [Claude Code](https://claude.ai/code)
- [uv](https://github.com/astral-sh/uv)
- Git

## Notes

This skill has the following goals:
- Scaffold agentic projects using Claude, GCP, and Python
- Add guardrails & directives to keep the project healthy
- Depend on local project installs (no global dependencies)
- Prioritize documentation (which should live in the repo) and DX
- Keep setup minimal and avoid context overload
- Most of the ideas can be found in the [templates/](./templates/) directory. These ideas come through 2 decades worth of experience in both startups and enterprise companies. The goal is to establish baseline conventions, while allowing the project to take whatever form it needs. YMMV.
