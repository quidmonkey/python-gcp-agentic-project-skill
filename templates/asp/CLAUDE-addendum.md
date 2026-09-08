
---

# Repo Governance

The sections above come from `agent-starter-pack`; this section layers this repo's own review, docs, and shipping discipline on top. It applies alongside the ADK development phases above, not instead of them.

## Toolchain additions

Beyond the agent-starter-pack stack (uv, ruff, ty, ADK eval), this repo also runs:
- bandit — security scanner (pre-commit and pre-push)
- pre-commit — git hooks, installed once via `uv run pre-commit install` at scaffold time

The pre-push pytest hook runs `tests/unit` only, not `tests/integration` — the integration suite makes live Vertex AI calls and fails without real GCP credentials, which a push shouldn't require. `make test` is unaffected and still runs both.

## Design and architecture proposals

When the user proposes a design or architecture change, interview them before implementing. Walk down each branch of the decision tree, resolving dependencies one by one. For each question, provide your recommended answer. Ask one question at a time. Explore the codebase to answer questions where possible before asking the user.

Trigger this for proposals that involve:
- New services, components, or system boundaries
- Changes to data flow or integration points
- Dependency additions that affect architecture
- Refactors that shift module responsibilities
- Anything that would require updating `docs/design.md` or a spec under `docs/specs/`

Only proceed to implementation after all decision branches are resolved and the user confirms.

## Before making changes

Check for existing lint violations and failing tests first.

**Source of truth, highest authority first:** `docs/` (specs and `design.md`) > tests > code. Docs state intended behavior; tests encode it where the docs are silent; code only describes what happens now. Resolve any conflict by climbing to the highest level that speaks to it.

So a failing test means either the code is wrong or the test contradicts the docs. Check the docs before assuming the test is correct; where they're silent, the test wins over the code.

## After every code change

Before reporting done, run pre-commit over the changed files and confirm the agent still imports cleanly:

```bash
uv run pre-commit run --files <changed files>   # during iteration
uv run pre-commit run --all-files               # before reporting a task complete
make run-check                                  # confirms the agent imports cleanly; also runs on git push
```

`make run-check` here is an import check, not a substitute for `make playground` or `make eval` — run those too for behavioral changes, per the development phases above. When the agent's entry point changes, update the target in the same change so it keeps exercising real startup.

Fix every failure at root cause:
- Never use `--no-verify` or `--skip`, and never disable a lint rule to silence a failure
- Never modify a test solely to make it pass. Change a test only when the docs show it's wrong
- Re-run until clean

If design, architecture, or public API changed, update `docs/design.md` — or the spec under `docs/specs/` that owns the flow — plus any relevant `README.md`. Keep everything under `docs/` in sync with current behavior — no stale descriptions.

## Code review gate

`git push` triggers a two-pass agentic review (pre-push hook, `scripts/code-review.sh`): pass 1 is a general review (DRY, YAGNI, library leverage, missing tests, security), pass 2 checks the change against the intent in `docs/`. Any REQUIRED finding blocks the push. The hook prints both passes' findings and writes the full report to `working/code-review-report.md`. Config lives in `.codereviewrc` (gitignored, personal — not shared team policy).

`fix_enabled` defaults to `true`: a failed review hands its REQUIRED findings to a fix agent that edits the working tree and re-reviews in a loop (`fix_max_iterations`, default 2). The fix is always left uncommitted — the hook itself never commits or pushes, so nothing an agent wrote reaches the remote unseen. Run via a plain `git push`, that's the end of it: fix every REQUIRED finding at root cause yourself (or review the auto-fix's diff), commit, and push again — only new commits get re-reviewed. Run via `make ship` (`scripts/ship.sh`), and if the fix loop resolved every REQUIRED finding, `ship.sh` shows the diff and, only on your explicit `y` confirmation, commits it and pushes again — up to `ship_fix_retries` times (default 1). Declining, or a non-interactive shell, leaves it uncommitted exactly like the plain-`git push` case.

Never set `SKIP_CODE_REVIEW`, set `enabled=false` in `.codereviewrc`, or use `SKIP=code-review` to get past a failing review. Skipping is a human decision.

`make ship` (`scripts/ship.sh`) pushes the branch. It runs the same push (and the same review gate) as `git push`; it does not add a second way to bypass a failing review. When `pr_automation=true` in `.codereviewrc` (off by default — `make auto-pr` turns it on) it goes further: opens a PR, self-approves it, and enables auto-merge, landing it once checks and any required review clear, then checks out the default branch, pulls, and deletes the branch.

With `pr_automation=true`, `ship.sh` checks the relevant CLI (`gh` or `az`) is installed and logged in before pushing anything — missing either prints a friendly message and exits without touching the branch.

## Documentation

Project docs live in `docs/`, alongside the agent-starter-pack guides linked above:
- `design.md` — RFC; defines architecture and design decisions
- `design.mmd` — Mermaid diagram of the design
- `finops.md` — GCP cost analysis for the design
- `infra.md` — CI/CD pipeline, IAM accounts and roles

`docs/specs/` does not exist yet. Create it — and only then — when the design is large enough to split (see below); a new project has nothing to put in it.

### Splitting design.md into per-flow specs

While the project is small, `design.md` holds everything. Once it passes ~400 lines or covers three or more flows, split it: create `docs/specs/` and give each flow a `docs/specs/<flow>.md` (kebab-case, from the skeleton below) with a `docs/specs/<flow>-diagram.mmd` beside it.

`design.md` keeps the overview, the Flows index, the architecture, the data flow between components, deployment, and anything cross-cutting (auth, observability, security). Each spec takes its flow's step-by-step behavior, the tools and endpoints only it calls, its configuration, its edge cases, and its limits. Don't restate a spec's contents in `design.md` — the index line plus the link is the whole handoff.

A spec is the source of truth for its flow. When a change touches one flow, that spec is the doc to read first and the doc to update.

Start each new spec from this skeleton. Fill it in, drop the sections that don't apply, and keep both links — the up-link to `design.md` and the down-link to the diagram are how the set stays navigable.

````markdown
# Spec — <Flow Name>

Flow covered: **<Flow Name>** — one sentence on what the user asks for and what they get back.

Diagram: [<flow>-diagram.mmd](<flow>-diagram.mmd). High-level architecture: [design.md](../design.md).

## How it works

Numbered steps through the flow. Name the actual functions, endpoints, and tools, and link to the source files. State what happens on the unhappy paths — no match, ambiguous match, upstream error, missing permission.

## Components and integrations

What this flow touches. A table works well past two or three.

## Configuration

Settings this flow reads, where they come from, and what happens when one is unset.

## Auth and access

Whose identity each call runs as, and what that means for what the user can see.

## Limits and out of scope

What this flow deliberately does not do, and the data it does not have. Record the shortcuts here rather than leaving them implicit.

## Open questions

Decisions still outstanding, each with who owns it. Delete the section when it empties.
````

The matching `docs/specs/<flow>-diagram.mmd` starts from the same shape as `docs/design.mmd`: a `%%{init: {'theme':'forest'}}%%` line, `graph TD`, then the nodes and edges for that flow only.

**Sync rules**: After editing `docs/design.md`, update `docs/design.mmd` to match before reporting done. After editing a spec, update its `-diagram.mmd`. A new spec must be linked from the Flows index in `docs/design.md`. After any change to the deployed GCP footprint — `docs/design.md`, `docs/infra.md`, `Dockerfile`, `deployment/terraform/*.tf`, or `scripts/deploy.sh` — update `docs/finops.md` so the service table and cost estimates match what is actually deployed.

A Stop hook (`scripts/docs-sync-check.sh`) blocks the turn from ending while any of these are stale, so sync them as part of the change rather than waiting to be told.

## Writing prose and markdown

When writing or updating any `.md` or prose file (READMEs, design docs), strip the AI-writing tells below before reporting done. Skip: `docs/design.mmd` and any `*-diagram.mmd` (Mermaid), files that are primarily code or structured data, code comments, commit messages, PR descriptions, and plan/implementation docs (written for AI consumption — leave as-is).

Remove these tells:
- **Significance inflation** — "testament to", "pivotal/crucial/vital role", "marks a turning point", "evolving landscape", "underscores its importance".
- **Promotional tone** — "boasts", "vibrant", "rich", "nestled", "in the heart of", "breathtaking", "renowned", "stunning".
- **Superficial -ing tails** — "...highlighting/showcasing/reflecting/ensuring/fostering X" tacked on for fake depth.
- **Vague attribution** — "experts argue", "observers note", "industry reports" with no named source.
- **AI vocabulary** — additionally, delve, leverage, crucial, enhance, intricate, landscape, tapestry, testament, underscore, seamless.
- **Copula avoidance** — "serves as / stands as / functions as" → use "is / are / has".
- **Negative parallelism** — "not just X, but Y", "it's not merely… it's…".
- **Forced rule of three** — triplets for the sake of it ("innovation, inspiration, and insights").
- **Formulaic structure** — "Challenges and Future Prospects" sections, generic upbeat conclusions.
- **Style tics** — em-dash overuse, mechanical boldface, inline-header bullet lists, Title Case headings, emojis, curly quotes.
- **Chatbot artifacts** — "Great question!", "I hope this helps", "Let me know if…", knowledge-cutoff disclaimers.
- **Filler / hedging** — "in order to" → "to", "due to the fact that" → "because", "could potentially possibly".

Then: prefer specific facts over vague claims, vary sentence length, one idea per sentence. Read it aloud — if it sounds like a press release, rewrite.
