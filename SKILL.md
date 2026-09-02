---
name: python-gcp-agentic-project-skill
version: 2.16.0
description: |
  Create a new Python project using uv with pre-commit, ruff, ty, bandit, and pytest
  configured and ready to use. Prompts for project name and layout (single package or monorepo).
  For GCP projects, optionally scaffolds with Google's agent-starter-pack (ADK/LangGraph
  agent templates, Cloud Run/Agent Engine/GKE deployment, Terraform, CI/CD) and layers this
  skill's tooling on top. Generates CLAUDE.md and .claude/settings.json to enforce pre-commit
  checks during agentic development.
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

Scaffold a Python project with ruff, ty, bandit, pytest, pre-commit, and agent instruction files. For GCP projects, optionally hands base scaffolding to Google's [agent-starter-pack](https://github.com/GoogleCloudPlatform/agent-starter-pack) and layers this skill's lint/pre-commit/code-review/docs tooling on top rather than replacing it.

Templates: `~/.claude/skills/python-gcp-agentic-project-skill/templates/` (plain scaffold), `~/.claude/skills/python-gcp-agentic-project-skill/templates/asp/` (agent-starter-pack addenda)
Placeholders: `{{project-name}}`, `{{package_name}}`, `{{code-dir}}`, `{{test-dir}}`, `{{layout-line}}`, `{{gcp-doc-lines}}`, `{{gcp-sync-rule}}`, `{{lint-target}}`, `{{bandit-exclude-arg}}`, and (ASP mode) `{{asp-agent}}`, `{{asp-deployment-target}}`, `{{asp-depth-flag}}`

## Step 1: Gather inputs

Use project name from args if provided, else ask.

Ask "GCP scope?" via `AskUserQuestion` (single question, one call):
- **Not a GCP project**: no GCP docs, no agent-starter-pack.
- **GCP project**: plain `uv`-scaffolded project, GCP cost/infra docs included.
- **GCP project via agent-starter-pack**: scaffold with Google's [agent-starter-pack](https://github.com/GoogleCloudPlatform/agent-starter-pack) (ADK/LangGraph agent templates, Cloud Run/Agent Engine/GKE deployment, Terraform, CI/CD), then layer this skill's lint/pre-commit/code-review/docs tooling on top.

Set `{{gcp}}` = true for either GCP option, `{{asp}}` = true only for the agent-starter-pack option.

### If `{{asp}}`

Ask via `AskUserQuestion` (up to 3 questions, one call):
- **Agent template** (`-a`): offer `adk` (ReAct agent via ADK — recommended default), `langgraph` (ReAct agent via LangGraph), `agentic_rag` (RAG agent, Vertex AI Search/Vector Search), `adk_a2a` (Agent-to-Agent protocol). User can pick "Other" and give any template id agent-starter-pack accepts (a local name, an `adk@`/`adk-py@` shortcut, or a remote Git URL).
- **Deployment target** (`-d`): `agent_engine` (recommended default), `cloud_run`, `gke`, `none`.
- **Scaffold depth**: `Prototype` (recommended for exploration — `--prototype`, no CI/CD or Terraform, fastest to iterate) or `Full` (CI/CD + Terraform via GitHub Actions — production-ready pipeline, more setup).

Skip the layout question entirely — agent-starter-pack owns the directory layout.

Set:
- `{{code-dir}}`: `app` (agent-starter-pack's default agent directory)
- `{{test-dir}}`: `tests/unit` — **not** `tests/integration` or `tests/eval`. Confirmed by dry run: agent-starter-pack's own `tests/integration/` makes live Vertex AI calls and fails with a 403 the moment there's no GCP project/credentials configured, which a fresh scaffold never has. Gating every `git push` on that would block the pre-push hook out of the box. `make test` (agent-starter-pack's own target, unchanged) still runs `tests/unit` + `tests/integration` for whoever has real credentials; only this skill's pre-push pytest hook is scoped down. `tests/eval` holds ADK evalsets, run via `make eval`, and was never in scope for either.
- `{{lint-target}}`: `{{code-dir}}`
- `{{bandit-exclude-arg}}`: empty string

### Otherwise (plain `uv` scaffold, GCP or not)

Ask layout via `AskUserQuestion`:
- **Single package**: `uv init --package`. Code in `src/<name>/`, tests in `tests/`.
- **Monorepo**: `uv init`. Code under `packages/<name>/`, tests colocated under `packages/<name>/tests/`.

Derive `{{package_name}}`: lowercase, hyphens → underscores.

Set:
- `{{code-dir}}`: `src` (single) or `packages` (monorepo)
- `{{test-dir}}`: `tests` (single) or `packages` (monorepo)
- `{{layout-line}}`: `src/{{package_name}}/` with `tests/` (single) or `packages/{{package_name}}/` with `packages/{{package_name}}/tests/` (monorepo)
- `{{lint-target}}`: `{{code-dir}}/{{package_name}}`
- `{{bandit-exclude-arg}}`: ` -x {{code-dir}}/{{package_name}}/tests`

### Shared, for any GCP project (`{{gcp}}`)

- `{{gcp-doc-lines}}`: the two-line block below.
  ```
  - `finops.md` — GCP cost analysis for the design
  - `infra.md` — CI pipeline, IAM accounts and roles
  ```
- `{{gcp-sync-rule}}`: the line below.
  ```
  After any change to the deployed GCP footprint — `docs/design.md`, `docs/infra.md`, `Dockerfile`, `scripts/deploy.sh`, or any `*.tf` — update `docs/finops.md` so the service table and cost estimates match what is actually deployed.
  ```

For a non-GCP project, both are the empty string (drop the blank line that follows each).

## Step 2: Create project

**agent-starter-pack (`{{asp}}`):**
```bash
uvx agent-starter-pack create {{project-name}} \
  -a {{asp-agent}} \
  -d {{asp-deployment-target}} \
  --agent-guidance-filename CLAUDE.md \
  -y -s \
  {{asp-depth-flag}}
cd {{project-name}}
```
`{{asp-depth-flag}}` is `--prototype` for Prototype depth, or `--cicd-runner github_actions` for Full (this skill's own `ship.sh` assumes a `gh`/`az repos pr`-reachable host, so GitHub Actions is the consistent default; Cloud Build isn't offered as a choice here). `-s` skips agent-starter-pack's live GCP/Vertex AI auth checks — this is a scaffolding step, not a deploy step. `-y` accepts its own defaults for anything not covered by the flags above.

agent-starter-pack prints its own next steps (`make install`, `make playground`, etc.) — that output is expected and is not this skill's own report.

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

**agent-starter-pack:** its own `pyproject.toml` already carries `pytest` (in `dependency-groups.dev`) and `ruff`/`ty` (in `project.optional-dependencies.lint`, not the dev group — our pre-commit hooks call them with `--no-sync`, so they need to be in the dev group too):
```bash
uv add --dev ruff ty "bandit[toml]" pre-commit
```

**Plain scaffold:**
```bash
uv add --dev ruff ty "bandit[toml]" pytest pre-commit
```

## Step 4: Write config files

Read each template from `~/.claude/skills/python-gcp-agentic-project-skill/templates/`, substitute all placeholders, write to destination.

Notes:
- `uv init` (plain scaffold) and `agent-starter-pack create` (ASP scaffold) both pre-create `.gitignore`, `README.md`, and `pyproject.toml`. To overwrite a file, Read it first (the harness blocks overwrite-without-read), then Write. Where the table below says **append**, use Edit/Read + append instead — never overwrite a file agent-starter-pack owns.
- `pyproject-additions.toml` / `templates/asp/pyproject-bandit.toml` are appended, so each must start with a `[table]` header. Never add a bare top-level key (e.g. `requires-python`) at its top — it would leak into the last existing table and break the parse. Keep the `--python 3.12` flag on `uv init` (plain scaffold only) — without it uv picks whatever interpreter its `python-preference = "managed"` default resolves to, which can be older than 3.12 and silently lowers both `requires-python` and the ruff `target-version` inferred from it.

**Plain scaffold (GCP or not):**

| Template | Destination | Mode |
|----------|------------|------|
| `templates/pre-commit-config.yaml` | `.pre-commit-config.yaml` | write |
| `templates/pyproject-additions.toml` | `pyproject.toml` | append |
| `templates/CLAUDE.md` | `CLAUDE.md` | write |
| `templates/README.md` | `README.md` | write |
| `templates/.codereviewrc` | `.codereviewrc` | write — gitignored, not `git add`ed |
| `templates/scripts/lib/common.sh` | `scripts/lib/common.sh` | write |
| `templates/scripts/code-review.sh` | `scripts/code-review.sh` | write |
| `templates/scripts/ship.sh` | `scripts/ship.sh` | write |
| `templates/scripts/enable-auto-pr.sh` | `scripts/enable-auto-pr.sh` | write |
| `templates/scripts/docs-sync-check.sh` | `scripts/docs-sync-check.sh` | write |
| `templates/settings.json` | `.claude/settings.json` | write |
| `templates/Makefile` | `Makefile` | write |
| `templates/docs/design.md` | `docs/design.md` | write |
| `templates/docs/design.mmd` | `docs/design.mmd` | write |
| `templates/docs/finops.md` | `docs/finops.md` | write — **GCP only** |
| `templates/docs/infra.md` | `docs/infra.md` | write — **GCP only** |
| `templates/.gitignore` | `.gitignore` | write |

Skip the `finops.md` and `infra.md` rows entirely for non-GCP projects.

**agent-starter-pack scaffold (`{{asp}}`):** agent-starter-pack already owns `pyproject.toml`, `Makefile`, `README.md`, `CLAUDE.md`, and `.gitignore` — none of those are overwritten. This skill's tooling layers on top of them:

| Template | Destination | Mode |
|----------|------------|------|
| `templates/pre-commit-config.yaml` | `.pre-commit-config.yaml` | write — agent-starter-pack has no pre-commit config |
| `templates/asp/pyproject-bandit.toml` | `pyproject.toml` | append — only `[tool.bandit]`; agent-starter-pack already configures `[tool.ruff]`/`[tool.ty]`/`[tool.pytest.ini_options]`, and a duplicate TOML table header breaks the parse |
| `templates/asp/CLAUDE-addendum.md` | `CLAUDE.md` | append to the file agent-starter-pack generated (`--agent-guidance-filename CLAUDE.md` in Step 2 made this the guaranteed target) |
| `templates/asp/README-addendum.md` | `README.md` | append |
| `templates/asp/Makefile-addendum` | `Makefile` | append |
| `templates/asp/gitignore-addendum` | `.gitignore` | append — only the four lines not already covered by agent-starter-pack's own `.gitignore` |
| `templates/.codereviewrc` | `.codereviewrc` | write — gitignored, not `git add`ed |
| `templates/scripts/lib/common.sh` | `scripts/lib/common.sh` | write |
| `templates/scripts/code-review.sh` | `scripts/code-review.sh` | write |
| `templates/scripts/ship.sh` | `scripts/ship.sh` | write |
| `templates/scripts/enable-auto-pr.sh` | `scripts/enable-auto-pr.sh` | write |
| `templates/scripts/docs-sync-check.sh` | `scripts/docs-sync-check.sh` | write |
| `templates/settings.json` | `.claude/settings.json` | write |
| `templates/docs/design.md` | `docs/design.md` | write |
| `templates/docs/design.mmd` | `docs/design.mmd` | write |
| `templates/docs/finops.md` | `docs/finops.md` | write — GCP is always true in ASP mode |
| `templates/docs/infra.md` | `docs/infra.md` | write |

`templates/asp/Makefile-addendum`'s `run-check` target assumes `{{code-dir}}/agent.py` (e.g. `app/agent.py`) is the agent's entry point, matching agent-starter-pack's default layout for the built-in templates. If the chosen template or `--agent-directory` places it elsewhere, fix the target before reporting done.

```bash
mkdir -p .claude docs working scripts/lib
chmod +x scripts/code-review.sh scripts/ship.sh scripts/enable-auto-pr.sh scripts/docs-sync-check.sh
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
otherwise tell the user to add the marketplace first. In ASP mode, agent-starter-pack's
own CLI output names `google-agents-cli` as its successor — installing it here is
doubly relevant, not redundant with anything ASP already did.

## Step 6: Init git and install pre-commit hooks

```bash
git init
git add .
uv run pre-commit install
```

`git init` on a directory `agent-starter-pack create` already initialized as a repo is a safe no-op.

In ASP mode, run `uv run pre-commit run --all-files` once here and fix what it finds before reporting done — confirmed by dry run (agent-starter-pack v0.41.3, `adk` template): the `end-of-file-fixer` hook fixes `deployment_metadata.json` (expected, first-run only), and `ruff-check` fails on a pre-existing `RUF005` violation in agent-starter-pack's own generated `{{code-dir}}/agent_engine_app.py` (`register_operations`) — that file is agent-starter-pack's, not this skill's template, and `--unsafe-fixes` or a one-line manual edit clears it. Different agent-starter-pack templates or versions may generate different code; run the hooks and fix whatever they actually report rather than assuming this exact finding.

`default_install_hook_types` in `.pre-commit-config.yaml` makes this install both the pre-commit and pre-push stages — pre-push carries the pytest and code-review hooks.

## Step 7: Trust the workspace

Claude Code drops every project-scoped `permissions.allow` entry until the workspace is trusted, so a freshly scaffolded project starts with all 275 pre-approvals inert and all 35 `ask` rules live — maximally prompt-y. Record trust for the new directory so `.claude/settings.json` takes effect on first use.

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
- Tools: ruff, ty, bandit, pytest, pre-commit (in ASP mode, layered on the agent-starter-pack stack: ADK/LangGraph, `uv`, ADK eval — say so explicitly, and name the agent template and deployment target chosen)
- Agent files: `CLAUDE.md`, `.claude/settings.json` (Stop hooks run pre-commit and the docs-sync gate; pre-approves read-only `gcloud`/`terraform`/`docker` commands, prompts on writes, denies reads of `.env` variants that hold secrets and of `secrets/`). Every `ask` rule names a mutating subcommand rather than a bare binary — a wildcard like `Bash(gcloud *)` or `Bash(docker *)` would silently cancel the read-only allowlist below it, because permission rules merge across all settings files and `ask` outranks `allow`. In ASP mode, `CLAUDE.md` is agent-starter-pack's own file with this skill's governance section appended — say both parts are present, not that `CLAUDE.md` was generated fresh
- Workspace trust: recorded in `~/.claude.json` (`hasTrustDialogAccepted`), so the allowlist is live on first run with no trust dialog. Say so explicitly — the user is entitled to know a scaffold granted its own pre-approvals
- Docs sync gate: `scripts/docs-sync-check.sh` (Stop hook, exits 2 so the agent actually sees it) blocks finishing while `docs/design.mmd` is stale against `docs/design.md`; a changed spec's `docs/specs/<flow>-diagram.mmd` is stale or the spec isn't linked from the Flows index in `docs/design.md`; `docs/design.md` is over 400 lines with no per-flow specs yet; or — GCP only, once something deployable exists — `docs/finops.md` is still `_TBD_` or wasn't updated alongside a changed footprint (`docs/design.md`, `docs/infra.md`, `Dockerfile`, `scripts/deploy.sh`, `*.tf`). Fires at most once per turn
- Docs: `docs/design.md`, `docs/design.mmd` (+ `docs/finops.md`, `docs/infra.md` for GCP projects)
- Design doc split: while the project is small `design.md` holds everything, and `docs/specs/` doesn't exist. Past ~400 lines or three flows, each flow moves to `docs/specs/<flow>.md` + `docs/specs/<flow>-diagram.mmd` (skeleton in `CLAUDE.md`), linked from the Flows index in `design.md`, which keeps the architecture and cross-cutting sections. `CLAUDE.md` states the rule; the Stop hook enforces it
- Code review: pre-push hook runs a two-pass agentic review (`scripts/code-review.sh`, configured via `.codereviewrc`; `review_agent` defaults to claude, `review_model` to sonnet); blocks the push on REQUIRED findings, always prints each pass's findings to the terminal (capped at 100 lines per pass), full report in `working/code-review-report.md`, incremental per branch
- Auto-fix: `fix_enabled=true` in `.codereviewrc` (default true) hands a failed review's REQUIRED findings to a single `fix_agent` (default claude, `fix_model` opus) that edits the working tree and verifies with pre-commit and pytest, then loops fix -> re-review (up to `fix_max_iterations`, default 2) until the tree passes; prints a capped fix summary and leaves changes uncommitted with the push still blocked
- Shipping: `make ship` (`scripts/ship.sh`) pushes the branch (same review gate as `git push`), then — only when `pr_automation=true` in `.codereviewrc` (off by default) — opens a PR via `gh` or `az repos pr` (auto-detected from `origin`), self-approves it (best-effort), enables auto-merge/auto-complete, polls until it lands, then checks out the default branch, pulls, and deletes the branch. Not a git hook: it runs after `git push` succeeds, since a PR can't be opened against commits the host doesn't have yet
- Auto-PR is opt-in: `scripts/enable-auto-pr.sh` sets `pr_automation=true` in `.codereviewrc`, run either via `make auto-pr` (anytime) or `--prompt` mode, which `make setup` runs once post-clone (a y/N prompt; a no-op if stdin isn't a TTY, e.g. CI). ASP mode has no `make setup` of its own to hook — `agent-starter-pack` owns `install` — so there `make auto-pr` is the only path; say so if asked
- `.codereviewrc` is gitignored, not committed: review-gate settings are personal defaults baked into the scripts (an absent file behaves identically), and `pr_automation` is a per-developer call that shouldn't auto-merge a teammate's pushes just because they pulled a commit — it stays off until that developer opts in themselves
- App run check: `make run-check` — the agent runs it after every code change per `CLAUDE.md`, and a pre-push hook runs it as a backstop; ships as an import check, to be upgraded once the app has a real entry point (in ASP mode, once the actual agent entry point differs from `{{code-dir}}/agent.py`)
- Scratch: `working/` (gitignored — dirty/dev files, never committed)
- Skills: `google-agents-cli` (project plugin — only if install above succeeded). Humanizing is baked into `CLAUDE.md`, no skill needed.
- Commands, plain scaffold: `make setup` (post-clone; also prompts for auto-PR), `make test`, `make lint`, `make check`, `make run-check`, `make auto-pr`, `uv run pre-commit autoupdate`
- Commands, ASP mode: agent-starter-pack's own `make install` (post-clone), `make playground`, `make eval`, `make deploy`, plus this skill's `make run-check`, `make review`, `make ship`, `make auto-pr`, `uv run pre-commit autoupdate`
- Team onboarding, plain scaffold: clone repo, run `make setup` — installs deps and pre-commit hooks, and prompts to enable auto-PR, in one step
- Team onboarding, ASP mode: clone repo, run `make install && uv run pre-commit install` — agent-starter-pack's `install` target only syncs deps, so the pre-commit step doesn't fold into it; run `make auto-pr` separately to opt in to auto-PR
