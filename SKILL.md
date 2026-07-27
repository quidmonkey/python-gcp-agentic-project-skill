---
name: python-gcp-agentic-project-skill
version: 2.8.0
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
Placeholders: `{{project-name}}`, `{{package_name}}`, `{{code-dir}}`, `{{test-dir}}`, `{{layout-line}}`, `{{gcp-doc-lines}}`, `{{gcp-sync-files}}`

## Step 1: Gather inputs

Use project name from args if provided, else ask.

Ask layout via `AskUserQuestion`:
- **Single package**: `uv init --package`. Code in `src/<name>/`, tests in `tests/`.
- **Monorepo**: `uv init`. Code under `packages/<name>/`, tests colocated under `packages/<name>/tests/`.

Derive `{{package_name}}`: lowercase, hyphens → underscores.

Ask "GCP project?" via `AskUserQuestion` (yes/no). This controls whether GCP cost/infra docs and the GCP doc-sync rules are included.

Set variables:
- `{{code-dir}}`: `src` (single) or `packages` (monorepo)
- `{{test-dir}}`: `tests` (single) or `packages` (monorepo)
- `{{layout-line}}`: `src/{{package_name}}/` with `tests/` (single) or `packages/{{package_name}}/` with `packages/{{package_name}}/tests/` (monorepo)
- `{{gcp-doc-lines}}`: if GCP, the two-line block below; if non-GCP, empty string (and drop the blank line that follows it).
  ```
  - `finops.md` — GCP cost analysis for the design
  - `infra.md` — CI pipeline, IAM accounts and roles
  ```
- `{{gcp-sync-files}}`: if GCP, `` and `docs/finops.md` ``; if non-GCP, empty string.

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
uv add --dev ruff ty "bandit[toml]" pytest pre-commit
```

## Step 4: Write config files

Read each template from `~/.claude/skills/python-gcp-agentic-project-skill/templates/`, substitute all placeholders, write to destination.

Notes:
- `uv init` pre-creates `.gitignore` and `README.md`. To overwrite, Read the existing file first (the harness blocks overwrite-without-read), then Write.
- `pyproject-additions.toml` is appended, so it must start with a `[table]` header. Never add a bare top-level key (e.g. `requires-python`) at its top — it would leak into the last existing table (`[dependency-groups]`) and break the parse. `uv init` already sets `requires-python` in `[project]`.

| Template | Destination | Mode |
|----------|------------|------|
| `templates/pre-commit-config.yaml` | `.pre-commit-config.yaml` | write |
| `templates/pyproject-additions.toml` | `pyproject.toml` | append |
| `templates/CLAUDE.md` | `CLAUDE.md` | write |
| `templates/README.md` | `README.md` | write |
| `templates/.codereviewrc` | `.codereviewrc` | write |
| `templates/scripts/code-review.sh` | `scripts/code-review.sh` | write |
| `templates/settings.json` | `.claude/settings.json` | write |
| `templates/Makefile` | `Makefile` | write |
| `templates/docs/design.md` | `docs/design.md` | write |
| `templates/docs/design.mmd` | `docs/design.mmd` | write |
| `templates/docs/finops.md` | `docs/finops.md` | write — **GCP only** |
| `templates/docs/infra.md` | `docs/infra.md` | write — **GCP only** |
| `templates/.gitignore` | `.gitignore` | write |

Skip the `finops.md` and `infra.md` rows entirely for non-GCP projects.

```bash
mkdir -p .claude docs working scripts
chmod +x scripts/code-review.sh
```

`working/` holds dirty files needed during development but never committed. The `.gitignore` template excludes it.

## Step 5: Install project skills

```bash
claude plugin install google-agents-cli --scope project 2>/dev/null || true
```

Humanizing is baked into `CLAUDE.md` directly (no `humanizer` skill needed).
`google-agents-cli` is best-effort: the install no-ops unless its marketplace is
already registered. Report it as installed only if the command above succeeded;
otherwise tell the user to add the marketplace first.

## Step 6: Init git and install pre-commit hooks

```bash
git init
git add .
uv run pre-commit install
```

`default_install_hook_types` in `.pre-commit-config.yaml` makes this install both the pre-commit and pre-push stages — pre-push carries the pytest and code-review hooks.

## Step 7: Report

- Project: `./{{project-name}}/`
- Tools: ruff, ty, bandit, pytest, pre-commit
- Agent files: `CLAUDE.md`, `.claude/settings.json` (Stop hook runs pre-commit; detects `docs/design.md` changes)
- Docs: `docs/design.md`, `docs/design.mmd` (+ `docs/finops.md`, `docs/infra.md` for GCP projects)
- Code review: pre-push hook runs a two-pass agentic review (`scripts/code-review.sh`, configured via `.codereviewrc`; `review_agent` defaults to claude, `review_model` to sonnet); blocks the push on REQUIRED findings, always prints each pass's findings to the terminal (capped at 100 lines per pass), full report in `working/code-review-report.md`, incremental per branch
- Auto-fix (optional): `fix_enabled=true` in `.codereviewrc` (default false) hands a failed review's REQUIRED findings to a single `fix_agent` (default claude, `fix_model` opus) that edits the working tree and verifies with pre-commit and pytest, then loops fix -> re-review (up to `fix_max_iterations`, default 2) until the tree passes; prints a capped fix summary and leaves changes uncommitted with the push still blocked
- App run check: `make run-check` — the agent runs it after every code change per `CLAUDE.md`, and a pre-push hook runs it as a backstop; ships as an import check, to be upgraded once the app has a real entry point
- Scratch: `working/` (gitignored — dirty/dev files, never committed)
- Skills: `google-agents-cli` (project plugin — only if install above succeeded). Humanizing is baked into `CLAUDE.md`, no skill needed.
- Commands: `make setup` (post-clone), `make test`, `make lint`, `make check`, `make run-check`, `uv run pre-commit autoupdate`
- Team onboarding: clone repo, run `make setup` — installs deps and pre-commit hooks
