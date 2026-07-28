---
name: python-gcp-agentic-project-skill
version: 2.13.0
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
Placeholders: `{{project-name}}`, `{{package_name}}`, `{{code-dir}}`, `{{test-dir}}`, `{{layout-line}}`, `{{gcp-doc-lines}}`, `{{gcp-sync-rule}}`

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
- `{{gcp-sync-rule}}`: if GCP, the line below; if non-GCP, empty string (and drop the blank line that follows it).
  ```
  After any change to the deployed GCP footprint — `docs/design.md`, `docs/infra.md`, `Dockerfile`, `scripts/deploy.sh`, or any `*.tf` — update `docs/finops.md` so the service table and cost estimates match what is actually deployed.
  ```

## Step 2: Create project

**Single:**
```bash
uv init --package --python 3.12 {{project-name}}
cd {{project-name}}
mkdir -p tests && touch tests/__init__.py
```

**Monorepo:**
```bash
uv init --python 3.12 {{project-name}}
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
- `pyproject-additions.toml` is appended, so it must start with a `[table]` header. Never add a bare top-level key (e.g. `requires-python`) at its top — it would leak into the last existing table (`[dependency-groups]`) and break the parse. `uv init` already sets `requires-python` in `[project]`. Keep the `--python 3.12` flag on `uv init` — without it uv picks whatever interpreter its `python-preference = "managed"` default resolves to, which can be older than 3.12 and silently lowers both `requires-python` and the ruff `target-version` inferred from it.

| Template | Destination | Mode |
|----------|------------|------|
| `templates/pre-commit-config.yaml` | `.pre-commit-config.yaml` | write |
| `templates/pyproject-additions.toml` | `pyproject.toml` | append |
| `templates/CLAUDE.md` | `CLAUDE.md` | write |
| `templates/README.md` | `README.md` | write |
| `templates/.codereviewrc` | `.codereviewrc` | write |
| `templates/scripts/code-review.sh` | `scripts/code-review.sh` | write |
| `templates/scripts/docs-sync-check.sh` | `scripts/docs-sync-check.sh` | write |
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
chmod +x scripts/code-review.sh scripts/docs-sync-check.sh
```

Do not create `docs/specs/`. It comes into existence when the design outgrows one file; `CLAUDE.md` carries the spec skeleton and the rule for creating it then.

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

## Step 7: Trust the workspace

Claude Code drops every project-scoped `permissions.allow` entry until the workspace is trusted, so a freshly scaffolded project starts with all 182 pre-approvals inert and all 24 `ask` rules live — maximally prompt-y. Record trust for the new directory so `.claude/settings.json` takes effect on first use.

Run from the project root. Both path spellings are recorded because Claude Code keys projects by the cwd it was started with, which may be a symlinked path. `uv run python` is used rather than a bare `python3` — uv is already a hard requirement and the project env exists by now, whereas `python3` goes through whatever version manager the user has and can fail inside a directory holding a `.python-version` file.

```bash
uv run python - "$(pwd)" "$(pwd -P)" <<'PY'
import json, os, sys, tempfile

config = os.path.expanduser("~/.claude.json")
keys = list(dict.fromkeys(sys.argv[1:]))

try:
    with open(config) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except json.JSONDecodeError:
    sys.exit(f"~/.claude.json is not valid JSON — leaving it alone. Accept the trust dialog manually in {keys[0]}.")

projects = data.setdefault("projects", {})
for key in keys:
    projects.setdefault(key, {})["hasTrustDialogAccepted"] = True

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config), suffix=".tmp")
with os.fdopen(fd, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, config)
print("Trusted workspace:", *keys)
PY
```

The write is read-modify-replace on the whole file, so it preserves every other key. It is not concurrency-safe: another Claude Code session running at the same time holds `~/.claude.json` state in memory and will overwrite this on its next flush. If that happens, re-run the block.

If the script exits with the JSON error, report it — do not hand-edit `~/.claude.json`, and tell the user to run `claude` in the project once and accept the dialog instead.

## Step 8: Report

- Project: `./{{project-name}}/`
- Tools: ruff, ty, bandit, pytest, pre-commit
- Agent files: `CLAUDE.md`, `.claude/settings.json` (Stop hooks run pre-commit and the docs-sync gate; pre-approves read-only `gcloud`/`terraform`/`docker` commands, prompts on writes)
- Workspace trust: recorded in `~/.claude.json` (`hasTrustDialogAccepted`), so the allowlist is live on first run with no trust dialog. Say so explicitly — the user is entitled to know a scaffold granted its own pre-approvals
- Docs sync gate: `scripts/docs-sync-check.sh` (Stop hook, exits 2 so the agent actually sees it) blocks finishing while `docs/design.mmd` is stale against `docs/design.md`; a changed spec's `docs/specs/<flow>-diagram.mmd` is stale or the spec isn't linked from the Flows index in `docs/design.md`; `docs/design.md` is over 400 lines with no per-flow specs yet; or — GCP only, once something deployable exists — `docs/finops.md` is still `_TBD_` or wasn't updated alongside a changed footprint (`docs/design.md`, `docs/infra.md`, `Dockerfile`, `scripts/deploy.sh`, `*.tf`). Fires at most once per turn
- Docs: `docs/design.md`, `docs/design.mmd` (+ `docs/finops.md`, `docs/infra.md` for GCP projects)
- Design doc split: while the project is small `design.md` holds everything, and `docs/specs/` doesn't exist. Past ~400 lines or three flows, each flow moves to `docs/specs/<flow>.md` + `docs/specs/<flow>-diagram.mmd` (skeleton in `CLAUDE.md`), linked from the Flows index in `design.md`, which keeps the architecture and cross-cutting sections. `CLAUDE.md` states the rule; the Stop hook enforces it
- Code review: pre-push hook runs a two-pass agentic review (`scripts/code-review.sh`, configured via `.codereviewrc`; `review_agent` defaults to claude, `review_model` to sonnet); blocks the push on REQUIRED findings, always prints each pass's findings to the terminal (capped at 100 lines per pass), full report in `working/code-review-report.md`, incremental per branch
- Auto-fix (optional): `fix_enabled=true` in `.codereviewrc` (default false) hands a failed review's REQUIRED findings to a single `fix_agent` (default claude, `fix_model` opus) that edits the working tree and verifies with pre-commit and pytest, then loops fix -> re-review (up to `fix_max_iterations`, default 2) until the tree passes; prints a capped fix summary and leaves changes uncommitted with the push still blocked
- App run check: `make run-check` — the agent runs it after every code change per `CLAUDE.md`, and a pre-push hook runs it as a backstop; ships as an import check, to be upgraded once the app has a real entry point
- Scratch: `working/` (gitignored — dirty/dev files, never committed)
- Skills: `google-agents-cli` (project plugin — only if install above succeeded). Humanizing is baked into `CLAUDE.md`, no skill needed.
- Commands: `make setup` (post-clone), `make test`, `make lint`, `make check`, `make run-check`, `uv run pre-commit autoupdate`
- Team onboarding: clone repo, run `make setup` — installs deps and pre-commit hooks
