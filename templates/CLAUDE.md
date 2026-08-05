# {{project-name}}

## Toolchain

- Package manager: uv
- Linter / formatter: ruff
- Type checker: ty
- Security scanner: bandit
- Complexity: ruff C90 (McCabe, max 10)
- Tests: pytest

## Response style

Lead with the answer or the code. Keep explanation to a few lines and cut anything not load-bearing: no preamble, no restating the question, no summary of what was just shown.

Write complete sentences. Terse means fewer words, not fewer grammatical parts — keep the connectives that carry the reasoning.

The agent is a tool, not a person: no first person, no performed emotion, no claims of opinion or preference. Achieve that by moving the subject, never by deleting it. Subjectless telegraph ("Added a retry", "Checking") and colon-nominalization ("Recommendation: X") are unreadable, and they aren't required to stay impersonal.

The subject should be the code, the file, the evidence, or the reader:

- "Added a retry" → "`client.py:40` now retries on 429"
- "My recommendation is X" → "X is the better option because Y"
- "I think the test is wrong" → "The test contradicts `docs/design.md:12`"
- "I'm not sure that's the cause" → "That may not be the cause; the logs don't cover the failing window"
- "Let me check" → say nothing and run the tool

Ground judgments in something nameable: a file, a line, test output. "The evidence suggests" and "it seems likely" trade a person for a vague authority, which is worse than either.

Say when something is uncertain; that's information, not hedging. Don't hedge on what was verified.

Stay fully explicit for security warnings, destructive-action confirmations, and steps where order matters.

Code, commit messages, and PR descriptions are written normally.

## Running tools

Always prefix with `uv run`:

```bash
uv run pytest
uv run ruff check .
uv run ty check
uv run pre-commit run --all-files
```

## Dependencies

`uv.lock` is committed to version control. Never delete or gitignore it — it pins transitive dependencies for deterministic installs. When adding or updating dependencies, commit the updated `uv.lock` alongside the `pyproject.toml` change.

## Coding Guidelines

- Write the simplest code that stays clear and maintainable; optimize for readability and ease of iteration
- Reuse before writing, in this order: an existing helper in this repo, the stdlib, an already-installed dependency. Add a new dependency only when none of those cover it
- Prefer modular and functional style over OOP
- No speculative abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes. Avoid abstraction until reuse >= 2
- Deletion over addition. Boring over clever
- Bug fix = root cause: grep every caller and fix the shared function once, not just the path the report names
- Mark a deliberate shortcut with a comment naming the ceiling and the upgrade path

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

Before reporting done, run pre-commit over the changed files and confirm the app still starts:

```bash
uv run pre-commit run --files <changed files>   # during iteration
uv run pre-commit run --all-files               # before reporting a task complete
make run-check                                  # confirms the app starts; also runs on git push
```

`make run-check` is standard operating procedure, not a test. If it fails, fix the startup breakage before anything else — the app not running invalidates all other work. It ships as a placeholder import check; when you add or change the app's entry point, update the target in the same change so it exercises real startup (the `Makefile` documents the constraints and patterns).

Fix every failure at root cause:
- Never use `--no-verify` or `--skip`, and never disable a lint rule to silence a failure
- Never modify a test solely to make it pass. Change a test only when the docs show it's wrong
- Re-run until clean

If design, architecture, or public API changed, update `docs/design.md` — or the spec under `docs/specs/` that owns the flow — plus any relevant `README.md` or `ARCHITECTURE.md`. Keep everything under `docs/` in sync with current behavior — no stale descriptions.

## Code review gate

`git push` triggers a two-pass agentic review (pre-push hook, `scripts/code-review.sh`): pass 1 is a general review (DRY, YAGNI, library leverage, missing tests, security), pass 2 checks the change against the intent in `docs/`. Any REQUIRED finding blocks the push. The hook prints both passes' findings and writes the full report to `working/code-review-report.md`; fix every REQUIRED finding at root cause, commit, and push again — only new commits get re-reviewed. Config lives in `.codereviewrc`.

Never set `SKIP_CODE_REVIEW`, set `enabled=false` in `.codereviewrc`, or use `SKIP=code-review` to get past a failing review. Skipping is a human decision.

## Testing

- Add tests for critical user flows or core business logic (e.g. `utils.py` files)
- Test expected code paths; avoid testing unexpected code paths
- One good integration test covering the happy path is worth more than many unit tests
- Avoid tests for handlers
- Avoid mocks and fixtures
- Don't use test coverage or number of tests as a metric
- Keep tests performant

## Project layout

{{layout-line}}

## Documentation

Project docs live in `docs/`:
- `design.md` — RFC; defines architecture and design decisions
- `design.mmd` — Mermaid diagram of the design
{{gcp-doc-lines}}

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

**Sync rules**: After editing `docs/design.md`, update `docs/design.mmd` to match before reporting done. After editing a spec, update its `-diagram.mmd`. A new spec must be linked from the Flows index in `docs/design.md`.
{{gcp-sync-rule}}
A Stop hook (`scripts/docs-sync-check.sh`) blocks the turn from ending while any of these are stale, so sync them as part of the change rather than waiting to be told.

## Writing prose and markdown

When writing or updating any `.md` or prose file (READMEs, design docs), strip the AI-writing tells below before reporting done. Skip: `docs/design.mmd` (Mermaid), files that are primarily code or structured data, code comments, commit messages, PR descriptions, and plan/implementation docs (written for AI consumption — leave as-is).

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
