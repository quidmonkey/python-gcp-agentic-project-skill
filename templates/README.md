# {{project-name}}

## Setup

Clone the repo, then:

```bash
make setup
```

This installs dependencies with `uv` and the git hooks with `pre-commit` (both the pre-commit and pre-push stages).

## Everyday commands

```bash
make test       # run pytest
make lint       # run all pre-commit hooks
make check      # ruff + ty
make run-check  # confirm the app still starts (also runs on git push)
make review     # run the code review manually (also runs on git push)
```

Tools run through `uv run`, so nothing needs to be installed globally.

`make run-check` starts as an import check. Once the project has a real entry point (CLI, server, job), update the target so it exercises actual startup — the pre-push hook runs it, and agents working in this repo run it after every code change.

## Code review on push

`git push` triggers an agentic code review (`scripts/code-review.sh`, wired in as a pre-push hook). It makes two passes over your branch's diff:

1. General review: DRY, YAGNI, use of existing libraries over hand-rolled code, missing tests, best practices, security.
2. Spec conformance: checks the change against the design documents in `docs/`.

Each pass reports findings as REQUIRED or SUGGESTED. Any REQUIRED finding blocks the push, and the full report lands in `working/code-review-report.md`. Fix the REQUIRED findings, commit, and push again.

Reviews are incremental. After a passing review, the reviewed commit is recorded in `.git/code-review-ledger`, and the next push only reviews commits added since. A branch that hasn't changed is never re-reviewed.

### Auto-fix

Set `fix_enabled=true` to have a failed review hand its REQUIRED findings to a fix agent. Both passes' findings go to a single fix agent — coupled fixes and shared root causes need one coherent pass, not one agent per finding. The agent edits the working tree to resolve the findings and prints a fix summary (also appended to the report). SUGGESTED findings are left alone.

After the fix pass the review runs again over the working tree, and fix -> re-review repeats until the tree passes or `fix_max_iterations` is hit. The fixes are always left uncommitted and the push always stays blocked, even once the working tree passes — the state that passed is uncommitted, not a commit, so it can't be recorded or shipped. Review the diff, commit the fixes, and push again; the committed fixes get one honest re-review and the pass is recorded then.

### Configuration

`.codereviewrc` in the repo root:

```
review_agent=claude    # claude | custom
review_model=sonnet    # model for the review passes (alias or full name)
enabled=true           # false disables the review
# command=...          # for review_agent=custom: reads the prompt on stdin, prints the review

fix_enabled=false      # true auto-fixes REQUIRED findings after a failed review
fix_agent=claude       # claude | custom
fix_model=opus         # model for the fix pass
fix_max_iterations=2   # max fix -> re-review rounds before giving up
# fix_command=...      # for fix_agent=custom: reads the fix prompt on stdin, edits the tree
```

The models are pinned rather than inherited from the `claude` CLI default, so the gate's cost doesn't move when that default changes. One blocked push with `fix_enabled=true` runs up to 6 review passes and 2 fix passes.

A custom review command must end its output with `VERDICT: PASS` or `VERDICT: FAIL` as the last non-empty line. Anything after the verdict is read as a failure, so nothing may follow it; surrounding `**` or backticks are tolerated. If the `claude` CLI isn't installed, the hook warns and lets the push through rather than blocking everyone without it; a misconfigured `.codereviewrc` (unknown agent, `custom` without its command) blocks the push instead.

### Skipping a review

```bash
SKIP_CODE_REVIEW=true git push
```

Or set `enabled=false` in `.codereviewrc` to turn it off for the repo. Skipping is for humans; agents working in this repo are instructed not to.

## Documentation

Design docs live in `docs/`. `design.md` is the source of truth for architecture decisions; the code review's second pass enforces it, so keep it current.

One file holds the whole design at first. Once `design.md` passes ~400 lines or covers three or more flows, create `docs/specs/` and move each flow into its own `docs/specs/<flow>.md` with a `docs/specs/<flow>-diagram.mmd` beside it, leaving `design.md` the overview, the Flows index, the architecture, and the cross-cutting concerns. `CLAUDE.md` holds the skeleton a new spec starts from. The docs sync gate blocks a turn that adds a spec without its diagram or without linking it from the index.
