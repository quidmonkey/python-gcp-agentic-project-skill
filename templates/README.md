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

### Configuration

`.codereviewrc` in the repo root:

```
agent=claude      # claude | custom
enabled=true      # false disables the review
# command=...     # for agent=custom: reads the prompt on stdin, prints the review
```

A custom command must end its output with a final line reading `VERDICT: PASS` or `VERDICT: FAIL`. If the `claude` CLI isn't installed, the hook warns and lets the push through rather than blocking everyone without it; a misconfigured `.codereviewrc` (unknown agent, `custom` without `command=`) blocks the push instead.

### Skipping a review

```bash
SKIP_CODE_REVIEW=true git push
```

Or set `enabled=false` in `.codereviewrc` to turn it off for the repo. Skipping is for humans; agents working in this repo are instructed not to.

## Documentation

Design docs live in `docs/`. `design.md` is the source of truth for architecture decisions; the code review's second pass enforces it, so keep it current.
