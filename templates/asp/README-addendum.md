
## Repo governance: code review and shipping

On top of the agent-starter-pack commands above (`make install`, `make test`, `make lint`, `make playground`, `make eval`, `make deploy`), this repo adds:

```bash
make run-check  # confirm the agent still imports cleanly (also runs on git push)
make review     # run the code review manually (also runs on git push)
make ship       # push, then (if auto-PR is enabled) open/approve/auto-merge a PR
make auto-pr    # enable make ship's PR automation (off by default)
```

Auto-PR has no post-clone prompt in ASP mode — `make install` is agent-starter-pack's own target, not this skill's `make setup`. Run `make auto-pr` once after `make install` to turn it on; see [Shipping a branch](#shipping-a-branch).

### Code review on push

`git push` triggers an agentic code review (`scripts/code-review.sh`, wired in as a pre-push hook). It makes two passes over your branch's diff:

1. General review: DRY, YAGNI, use of existing libraries over hand-rolled code, missing tests, best practices, security.
2. Spec conformance: checks the change against the design documents in `docs/`.

Each pass reports findings as REQUIRED or SUGGESTED. Any REQUIRED finding blocks the push, and the full report lands in `working/code-review-report.md`. Fix the REQUIRED findings, commit, and push again — or see [Auto-fix](#auto-fix) below.

Reviews are incremental. After a passing review, the reviewed commit is recorded in `.git/code-review-ledger`, and the next push only reviews commits added since. A branch that hasn't changed is never re-reviewed.

### Auto-fix

Set `fix_enabled=true` to have a failed review hand its REQUIRED findings to a fix agent. Both passes' findings go to a single fix agent — coupled fixes and shared root causes need one coherent pass, not one agent per finding. The agent edits the working tree to resolve the findings and prints a fix summary (also appended to the report). SUGGESTED findings are left alone.

After the fix pass the review runs again over the working tree, and fix -> re-review repeats until the tree passes or `fix_max_iterations` is hit. The fixes are always left uncommitted and the push always stays blocked, even once the working tree passes — the state that passed is uncommitted, not a commit, so it can't be recorded or shipped; the hook itself never commits or pushes on its own. A plain `git push` leaves it there: review the diff, commit the fixes, and push again — the committed fixes get one honest re-review and the pass is recorded then. `make ship` goes one step further; see [Shipping a branch](#shipping-a-branch).

### Configuration

`.codereviewrc` in the repo root:

```
review_agent=claude    # claude | custom
review_model=sonnet    # model for the review passes (alias or full name)
enabled=true           # false disables the review
# command=...          # for review_agent=custom: reads the prompt on stdin, prints the review

fix_enabled=true       # false skips auto-fix and stops at the first failed review
fix_agent=claude       # claude | custom
fix_model=opus         # model for the fix pass
fix_max_iterations=2   # max fix -> re-review rounds before giving up
# fix_command=...      # for fix_agent=custom: reads the fix prompt on stdin, edits the tree

pr_automation=false    # true: `make ship` also opens/approves/auto-merges a PR (set via `make auto-pr`)
# pr_host=gh           # gh | az, auto-detected from origin's remote URL
pr_merge_method=squash # squash | merge | rebase, used once auto-merge completes
pr_self_approve=true   # best-effort; a no-op if the host rejects self-review
pr_poll_interval=15    # seconds between polls while waiting for auto-merge
pr_poll_timeout=1800   # give up waiting after this many seconds (auto-merge stays armed)

ship_fix_retries=1     # max times `make ship` commits an auto-fix and pushes again, on your confirmation
```

The models are pinned rather than inherited from the `claude` CLI default, so the gate's cost doesn't move when that default changes. One blocked push with `fix_enabled=true` runs up to 6 review passes and 2 fix passes.

A custom review command must end its output with `VERDICT: PASS` or `VERDICT: FAIL` as the last non-empty line. Anything after the verdict is read as a failure, so nothing may follow it; surrounding `**` or backticks are tolerated. If the `claude` CLI isn't installed, the hook warns and lets the push through rather than blocking everyone without it; a misconfigured `.codereviewrc` (unknown agent, `custom` without its command) blocks the push instead.

### Skipping a review

```bash
SKIP_CODE_REVIEW=true git push
```

Or set `enabled=false` in `.codereviewrc` to turn it off for the repo. Skipping is for humans; agents working in this repo are instructed not to.

## Shipping a branch

`make ship` (`scripts/ship.sh`) always pushes the current branch (running the same review gate as `git push`). What happens next depends on `pr_automation` in `.codereviewrc`, off by default: with it enabled, `ship.sh` also opens a PR against the default branch, self-approves it, enables auto-merge, and once it lands, checks out the default branch, pulls, and deletes the branch (local and remote). With it disabled, `ship.sh` stops after the push and leaves the PR to you.

Enable it with `make auto-pr` (see above).

It's a separate script from the pre-push hook: `code-review.sh` runs before the commits reach the remote, so it can't open a PR against them. `ship.sh` pushes first, and only opens the PR once that push succeeds. The PR title and description come from the branch's own commit log, not a generated summary.

A REQUIRED finding blocks `ship.sh` exactly like it blocks `git push` — with one difference: if `fix_enabled`'s loop (see [Auto-fix](#auto-fix)) resolved every REQUIRED finding, the fix is still uncommitted, and `ship.sh` shows you that diff and asks `Commit these fixes and push again? [y/N]`. Only on `y` does it commit and retry the push, up to `ship_fix_retries` times; declining, or running non-interactively, leaves the fix uncommitted exactly like a plain `git push` would.

`ship.sh` picks `gh` or `az repos pr` from `origin`'s remote URL unless `pr_host` is set. Self-approval is best-effort: on a branch that requires review from someone else, the host rejects it and auto-merge (not an immediate merge) waits for a real reviewer instead of failing.

Before pushing anything, `ship.sh` checks that CLI is installed and logged in. Either one missing prints a friendly message (install it, or run `gh auth login` / `az login`) and exits without pushing.

`.codereviewrc` is gitignored and personal to your machine — `pr_automation` decides whether *your* pushes get auto-merged, which shouldn't flip on for a teammate just because they pulled a commit, and stays off until you deliberately turn it on. Every other default above is baked into the scripts, so a fresh clone with no `.codereviewrc` at all behaves exactly like the file shown here; edit your local copy only to actually change something.

## Documentation

Design docs live in `docs/`, alongside the agent-starter-pack dev and deployment guides linked from `CLAUDE.md`. `design.md` is the source of truth for architecture decisions; the code review's second pass enforces it, so keep it current.

One file holds the whole design at first. Once `design.md` passes ~400 lines or covers three or more flows, create `docs/specs/` and move each flow into its own `docs/specs/<flow>.md` with a `docs/specs/<flow>-diagram.mmd` beside it, leaving `design.md` the overview, the Flows index, the architecture, and the cross-cutting concerns. `CLAUDE.md` holds the skeleton a new spec starts from. The docs sync gate blocks a turn that adds a spec without its diagram or without linking it from the index.
