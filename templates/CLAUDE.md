# {{project-name}}

## Toolchain

- Package manager: uv
- Linter / formatter: ruff
- Type checker: ty
- Security scanner: bandit
- Complexity: ruff C90 (McCabe, max 10)
- Tests: pytest

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
- `finops.md` — GCP cost analysis for the design
- `infra.md` — CI pipeline, IAM accounts and roles

**Sync rule**: After editing `docs/design.md`, update `docs/design.mmd` and `docs/finops.md` to reflect the changes before reporting done.

## Writing prose and markdown

When writing or updating any `.md` or text file (prose, READMEs, design docs), invoke `/humanizer` on the draft before reporting done. Exception: `docs/design.mmd` (Mermaid syntax) and any file that is primarily code or structured data. Does not apply to code comments, commit messages, or PR descriptions.

Keep prose concise. Prefer short sentences. Cut filler words and redundant phrases. One idea per sentence.
