# {{project-name}}

## Toolchain

- Package manager: uv
- Linter / formatter: ruff
- Type checker: ty
- Security scanner: bandit
- Complexity: ruff C90 (McCabe, max 10)
- Tests: pytest

## Response style

Be terse. Lead with the answer or the code, then at most a few lines of why. Drop pleasantries, hedging, and filler. Stay explicit for security warnings, destructive-action confirmations, and steps where order matters.

The agent is a tool, not a person. Never self-refer with personal terms — no "I", "me", "my", "we", "our" — and make no claims of opinion, feeling, or preference. Use impersonal phrasing: "Added a retry", "Recommendation: X", "The test appears wrong", "Checking".

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
- Anything that would require updating `docs/design.md`

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

If design, architecture, or public API changed, update `docs/design.md` plus any relevant `README.md` or `ARCHITECTURE.md`. Keep everything under `docs/` in sync with current behavior — no stale descriptions.

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

**Sync rule**: After editing `docs/design.md`, update `docs/design.mmd`{{gcp-sync-files}} to reflect the changes before reporting done.

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
