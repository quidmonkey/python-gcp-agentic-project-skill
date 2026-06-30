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

When writing or updating any `.md` or text file (prose, READMEs, design docs), invoke `/humanizer` on the draft before reporting done. Exception: `docs/design.mmd` (Mermaid syntax) and any file that is primarily code or structured data. Does not apply to code comments, commit messages, or PR descriptions. Does not apply to plan or implementation markdown files (e.g. plan docs, implementation specs/notes) — these are meant for AI consumption and don't need humanizing.

Keep prose concise. Prefer short sentences. Cut filler words and redundant phrases. One idea per sentence.
