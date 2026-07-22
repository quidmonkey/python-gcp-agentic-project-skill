# {{project-name}}

## Toolchain

- Package manager: uv
- Linter / formatter: ruff
- Type checker: ty
- Security scanner: bandit
- Complexity: ruff C90 (McCabe, max 10)
- Tests: pytest

## Response style

Be terse. Lead with the answer or the code, then at most a few lines of why. Drop pleasantries, hedging, and filler. Fragments are fine. One idea per sentence.

The agent is a tool, not a person. Never self-refer with personal terms: no "I", "me", "my", "mine", "we", "our", "myself", and no claims of opinion, feeling, or preference. Use impersonal phrasing instead:

- "I added a retry" → "Added a retry"
- "My recommendation is X" → "Recommendation: X"
- "I think the test is wrong" → "The test appears wrong"
- "Let me check" → "Checking"

Stay fully explicit — never terse — for security warnings, confirmations of destructive or irreversible actions, and multi-step instructions where order matters.

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

- Write the simplest code that remains clear and maintainable
- Code should be optimized for readability and ease of iteration
- Reuse existing functions and modules before creating new ones
- Identify duplicate logic; extract shared functionality
- Prefer composition over duplication
- Prefer modular and functional style over OOP
- Avoid over-abstraction unless reuse >= 2

**Reach for the laziest solution that works.** Before writing code, climb this ladder and stop at the first rung that holds:
1. Does it need to exist? Speculative need → skip it, say so.
2. Already in this codebase? Reuse the existing helper / util / type / pattern.
3. Stdlib does it? Use it.
4. Native platform or framework feature covers it? Use it over a new dependency.
5. Already-installed dependency solves it? Use it — don't add one for a few lines.
6. Can it be one line? One line.
7. Only then: the minimum code that works.

- No speculative abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes.
- Deletion over addition. Boring over clever.
- Bug fix = root cause: grep every caller and fix the shared function once, not just the path the report names.
- Mark a deliberate shortcut with a comment naming the ceiling and the upgrade path.

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

- Check for lint violations and fix root causes
- Check failing tests and determine if behavior or test is incorrect
- Treat tests as the source of truth for intended behavior
- Never:
  - disable lint rules unless absolutely necessary
  - modify tests solely to make them pass without justification

## After every code change

Run pre-commit on changed files before reporting done:

```bash
# Fast — scope to changed files only
uv run pre-commit run --files <changed files>

# Full — run all hooks across entire project (use before committing)
uv run pre-commit run --all-files
```

Use `--files` during iteration. Use `--all-files` before reporting a task complete.

### Verify the app runs

After writing or changing code, run the app to confirm it still starts:

```bash
make run-check
```

This is standard operating procedure, not a test. Run it before reporting a task complete, alongside pre-commit. It also runs on `git push`.

Keep the target honest:
- The scaffolded command is an import check — a placeholder, acceptable only while the project has no entry point.
- When you add or change the app's entry point (CLI command, server boot, job main), update `make run-check` in the same change so it exercises the real startup path: a CLI gets `--help` or a dry-run invocation; a server gets start + health probe + teardown.
- The command must exit non-zero on failure, finish in under 30 seconds, and need no external services or credentials.
- If `make run-check` fails, fix the startup breakage before anything else — the app not running invalidates all other work.

Fix all failures at root cause. Rules:
- Never use `--no-verify` or `--skip`
- Never disable lint rules to silence failures
- Never modify tests solely to make them pass — tests are the source of truth
- Re-run until clean

If design, architecture, or public API changed: update any of `README.md`, `ARCHITECTURE.md`, `docs/design.md` that exist and are relevant. Keep all files under `docs/` in sync with current behavior — do not leave stale descriptions.

Also verify:
- No duplicate logic was introduced
- Changes are minimal and localized
- Code follows the guidelines above

## Code review gate

`git push` triggers a two-pass agentic code review (pre-push hook, `scripts/code-review.sh`):

1. General review — DRY, YAGNI, library leverage, missing tests, best practices, security
2. Spec conformance — the change vs the intent in `docs/`

Commits are reviewed once per branch: after a passing review, only new commits are reviewed on the next push. Config lives in `.codereviewrc`.

Optional auto-fix: set `fix_enabled=true` in `.codereviewrc` to have a failed review hand its REQUIRED findings to a single fix agent that edits the working tree, then re-review and fix again in a loop (up to `fix_max_iterations`, default 2) until the tree passes. The changes are left uncommitted and the push stays blocked even on success — review the diff, commit, and push again.

If the push is blocked by a failed review:
1. Read `working/code-review-report.md`
2. Fix every REQUIRED finding at root cause (or review the auto-fix diff if `fix_enabled=true`)
3. Commit and push again (only the new commits get re-reviewed)

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
