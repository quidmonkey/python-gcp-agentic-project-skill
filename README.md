# python-gcp-agentic-project-skill

A Claude Code skill that scaffolds Python projects with `uv`. One command wires linting, type checking, security scanning, and tests into pre-commit. It also drops agent instruction files that stop Claude from skipping those checks when writing code. GCP projects get extra cost and infra docs; the skill asks at setup.

## What it creates

```
my-project/
├── .claude/
│   └── settings.json        # Stop hooks (pre-commit + docs drift); gcloud/terraform/docker read-only allowlist
├── docs/                    # design.md, design.mmd (+ finops.md, infra.md for GCP)
├── scripts/
│   ├── code-review.sh       # two-pass agentic code review, runs on git push
│   └── docs-sync-check.sh   # Stop-hook gate: blocks finishing on stale docs/
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

`CLAUDE.md` tells Claude Code to run pre-commit after every change and fix failures at root cause rather than suppress them. It also sets a terse, impersonal response style, coding guidelines that favor reuse and the stdlib over new code, an explicit source-of-truth hierarchy (`docs/` > tests > code, so a failing test sends the agent to the specs rather than to the test file), and prose-humanizing directives (strip AI-writing tells from `.md` files) — all condensed in-line so no extra skills are needed. It's deliberately kept short: enforcement lives in hooks, and the file states each rule once rather than restating what a hook already checks. `.claude/settings.json` adds a `Stop` hook that runs pre-commit when Claude finishes responding, scoped to changed files for speed, falling back to `--all-files` on a clean working tree. The output feeds back as context, so Claude sees any failures and corrects them before you're involved. A second `Stop` hook (`scripts/docs-sync-check.sh`) does the same job for documentation drift.

The same file pre-approves read-only `gcloud`, `terraform`, and `docker` commands: `describe`, `list`, `get-iam-policy`, `logging read`, `plan`, `validate`, `state list`, `docker ps`, `docker logs`, `docker inspect`, `docker compose config`, and so on. Inspecting a GCP project or a running container no longer costs one permission prompt per command. Writes are a different matter. Anything not on the allowlist still prompts, and the destructive operations (`terraform apply`/`destroy`, `gcloud secrets versions access`, `projects delete`, service-account key creation, auth changes) sit in `ask`, so they prompt even if someone later adds a broader allow rule. `docker *` and `docker-compose *` sit in `ask` too, which keeps `run`, `exec`, `build`, `rm`, and `prune` prompting while the read verbs above go through. One limit worth knowing: permission rules only wildcard at the end, so a read verb on a service group the list doesn't name still prompts. Add it to `allow` when that happens.

Precedence matters if you edit any of this. `deny` beats `ask` beats `allow`, across every settings file. A blanket `Bash(gcloud *)` in an `ask` array silently kills every specific `gcloud` allow rule, these included. The specific rules stay in the file; they just stop doing anything.

The `Stop` hooks are the important part. They're enforcement, not reminders, and that distinction has teeth: a Stop hook that exits 0 prints to the transcript, where the model never sees it. Both hooks exit 2 and write to stderr, the one channel that feeds back into the turn.

## Docs sync gate

`scripts/docs-sync-check.sh` runs when Claude tries to finish. It blocks the stop and lists what's stale if:

- `docs/design.md` changed but `docs/design.mmd` didn't, so the diagram no longer matches the design.
- A spec under `docs/specs/` changed but its `<flow>-diagram.mmd` didn't, or a spec exists that the Flows index in `docs/design.md` doesn't link. An unlinked spec is invisible to both readers and the review's spec pass.
- `docs/design.md` has grown past 400 lines and no per-flow specs exist yet (see below).
- The project has a deployable footprint and `docs/finops.md` is still the scaffold template, `_TBD_` rows and all.
- That footprint changed (`docs/design.md`, `docs/infra.md`, `Dockerfile`, `scripts/deploy.sh`, or any `*.tf`) but `docs/finops.md` didn't. Adding a Cloud Run service changes the bill whether or not anyone edited the design doc, so the trigger is the infrastructure, not the prose.

Both finops checks wait for something deployable to exist: a `Dockerfile`, a `scripts/deploy.sh`, terraform, or an `infra.md` with the placeholders filled in. A project with nothing built yet has no costs to record, so the gate stays quiet. On non-GCP projects the file doesn't exist at all and the check skips.

The template check is there because "did the file change?" isn't enough on its own. Before the first commit every file reads as new, so an untouched `finops.md` looks freshly written, which is exactly the state a scaffold test is in. Checking for `_TBD_` catches the file nobody ever filled in.

The gate fires at most once per turn (it honors `stop_hook_active`), so an agent that genuinely can't satisfy it stops instead of looping.

## One design doc, then many specs

A new project gets a single `docs/design.md`, which is right until it isn't. Past a few hundred lines the file stops being readable in one sitting, and every code review has to load all of it to check one flow.

So the scaffold names the threshold instead of leaving it to taste: once `design.md` passes 400 lines or covers three or more flows, each flow moves into `docs/specs/<flow>.md` with a `docs/specs/<flow>-diagram.mmd` beside it. `design.md` keeps the overview, a Flows index linking each spec, the architecture, the data flow between components, deployment, and the cross-cutting concerns. A spec takes its flow's step-by-step behavior, the tools and endpoints only it calls, its configuration, its edge cases, and its limits. Nothing is stated in both places — the index line plus the link is the whole handoff, and each spec links back up to `design.md` and down to its own diagram.

A new project has no `docs/specs/` directory. It gets created at the split, by whoever writes the first spec. The shape a spec starts from — what it does, components, configuration, auth, limits and out of scope, open questions — lives as a skeleton inside `CLAUDE.md`, so a fresh repo carries no empty directory and no template file waiting on a flow that may never come. Copying a filled-in structure beats inventing one per flow, and `CLAUDE.md` ships with the repo, so teammates without the skill still have it.

What holds the set together is enforced by the sync gate rather than left to discipline: a spec's diagram tracks the spec, a spec is reachable from the index, and a `design.md` that has outgrown itself gets split. `CLAUDE.md` carries the same rule for the agent, and the review's spec pass reads the flow's spec as the source of truth for that flow.

## App run check

Beyond lint and tests, the scaffold bakes in one operational rule: after writing code, the agent runs the app to confirm it still starts. The command lives in one place, `make run-check`. It ships as an import check (a new project has nothing to run yet), and `CLAUDE.md` requires the agent to upgrade it the moment a real entry point exists — `--help` or a dry run for a CLI, start + health probe + teardown for a server — and to keep it under 30 seconds with no external services. A pre-push hook runs the same target next to pytest, so a push that breaks startup is blocked even if the agent skipped the procedure.

## Code review on push

Every scaffolded project gets a pre-push code review gate (`scripts/code-review.sh`, wired into pre-commit's pre-push stage). Pushing a branch runs an AI agent over the branch diff in two passes, executed in parallel:

1. **General review** — DRY, YAGNI, preferring existing libraries over hand-rolled code, missing tests per the project's CLAUDE.md testing rules, general best practices, and security.
2. **Spec conformance** — reads the design docs in `docs/` and flags code that deviates from the documented intent.

Findings come back as REQUIRED or SUGGESTED. Both passes' findings are printed to the terminal whether the review passes or fails, capped at 100 lines per pass so a finding-heavy review can't flood stdout; the full report is written to `working/code-review-report.md`. Any REQUIRED finding fails the hook and blocks the push. The project's CLAUDE.md tells the agent to read that report, fix REQUIRED findings at root cause, and push again.

Reviews are incremental: the last passing commit for each branch is recorded in `.git/code-review-ledger`, so the next push reviews only new commits. An unchanged branch is never re-reviewed.

Optionally, a failed review can fix itself: set `fix_enabled=true` and the REQUIRED findings from both passes go to a single fix agent that edits the working tree, then the review runs again over the tree. Fix → re-review loops until it passes or `fix_max_iterations` is hit. The fixes are always left uncommitted and the push always stays blocked, even on success — what passed is a working tree, not a commit, so it can't be recorded or shipped. Review the diff, commit, push again.

Both agents are configurable via `.codereviewrc`:

| Key | Values | Default |
|-----|--------|---------|
| `review_agent` | `claude`, `custom` | `claude` |
| `review_model` | model alias or full name | `sonnet` |
| `enabled` | `true` / `false` | `true` |
| `command` | shell command for `review_agent=custom`; receives the prompt on stdin | — |
| `fix_enabled` | `true` / `false` | `false` |
| `fix_agent` | `claude`, `custom` | `claude` |
| `fix_model` | model alias or full name | `opus` |
| `fix_max_iterations` | positive integer | `2` |
| `fix_command` | shell command for `fix_agent=custom`; receives the fix prompt on stdin | — |

The contract is agent-agnostic: whatever runs must print its review to stdout and end with `VERDICT: PASS` or `VERDICT: FAIL`. Models are pinned rather than inherited from the `claude` CLI default so the gate's cost doesn't drift when that default changes — one blocked push with auto-fix on runs up to 6 review passes and 2 fix passes. A misconfigured file (unknown agent, `custom` with no command) blocks the push rather than silently disabling the gate.

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
