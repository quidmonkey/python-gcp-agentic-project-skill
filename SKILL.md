---
name: python-gcp-agentic-project-skill
version: 2.1.0
description: |
  Create a new Python project using uv with pre-commit, ruff, ty, bandit, and pytest
  configured and ready to use. Prompts for project name and layout (single package or monorepo).
  Generates CLAUDE.md and .claude/settings.json to enforce pre-commit checks
  during agentic development.
  Use when user says "create python project", "new python project", "init python project",
  "scaffold python project", or invokes /python-gcp-project.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - AskUserQuestion
---

# Python GCP Agentic Project Skill

Scaffold a Python project with ruff, ty, bandit, pytest, pre-commit, and agent instruction files.

Templates: `~/.claude/skills/python-gcp-agentic-project-skill/templates/`
Placeholders: `{{project-name}}`, `{{package_name}}`, `{{code-dir}}`, `{{test-dir}}`, `{{layout-line}}`

## Step 1: Gather inputs

Use project name from args if provided, else ask.

Ask layout via `AskUserQuestion`:
- **Single package**: `uv init --package`. Code in `src/<name>/`, tests in `tests/`.
- **Monorepo**: `uv init`. Code under `packages/<name>/`, tests colocated under `packages/<name>/tests/`.

Derive `{{package_name}}`: lowercase, hyphens → underscores.

Set variables:
- `{{code-dir}}`: `src` (single) or `packages` (monorepo)
- `{{test-dir}}`: `tests` (single) or `packages` (monorepo)
- `{{layout-line}}`: `src/{{package_name}}/` with `tests/` (single) or `packages/{{package_name}}/` with `packages/{{package_name}}/tests/` (monorepo)

## Step 2: Create project

**Single:**
```bash
uv init --package {{project-name}}
cd {{project-name}}
mkdir -p tests && touch tests/__init__.py
```

**Monorepo:**
```bash
uv init {{project-name}}
cd {{project-name}}
rm -f hello.py
mkdir -p packages/{{package_name}}/tests
touch packages/{{package_name}}/__init__.py packages/{{package_name}}/tests/__init__.py
```

## Step 3: Add dev dependencies

```bash
uv add --dev ruff ty bandit pytest pre-commit
```

## Step 4: Write config files

Read each template from `~/.claude/skills/python-gcp-agentic-project-skill/templates/`, substitute all placeholders, write to destination.

| Template | Destination | Mode |
|----------|------------|------|
| `templates/pre-commit-config.yaml` | `.pre-commit-config.yaml` | write |
| `templates/pyproject-additions.toml` | `pyproject.toml` | append |
| `templates/CLAUDE.md` | `CLAUDE.md` | write |
| `templates/settings.json` | `.claude/settings.json` | write |
| `templates/docs/design.md` | `docs/design.md` | write |
| `templates/docs/design.mmd` | `docs/design.mmd` | write |
| `templates/docs/finops.md` | `docs/finops.md` | write |
| `templates/docs/infra.md` | `docs/infra.md` | write |
| `templates/.gitignore` | `.gitignore` | write |

```bash
mkdir -p .claude docs
```

## Step 5: Install project skills

```bash
git clone --depth 1 https://github.com/blader/humanizer .claude/skills/humanizer
claude plugin install google-agents-cli --scope project 2>/dev/null || true
```

## Step 6: Init git and install pre-commit hooks

```bash
git init
git add .
uv run pre-commit install
```

## Step 7: Report

- Project: `./{{project-name}}/`
- Tools: ruff, ty, bandit, pytest, pre-commit
- Agent files: `CLAUDE.md`, `.claude/settings.json` (Stop hook runs pre-commit; detects `docs/design.md` changes)
- Docs: `docs/design.md`, `docs/design.mmd`, `docs/finops.md`, `docs/infra.md`
- Skills: `humanizer` (`.claude/skills/humanizer`), `google-agents-cli` (project plugin)
- Commands: `uv run pytest`, `uv run pre-commit run --all-files`, `uv run pre-commit autoupdate`
