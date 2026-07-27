#!/usr/bin/env bash
# Two-pass agentic code review, run by the pre-push hook.
#   Pass 1: general review — DRY, YAGNI, library leverage, missing tests,
#           best practices, security, fit with the codebase.
#   Pass 2: spec conformance against the documents in docs/.
# The passes are independent and run in parallel.
#
# Commits are reviewed once: the last passing commit per branch is recorded in
# .git/code-review-ledger, and later pushes review only new commits since.
# The full report is written to working/code-review-report.md (gitignored).
#
# When fix_enabled=true, a failed review hands its REQUIRED findings (both
# passes combined) to a single fix agent that edits the working tree to resolve
# them. Fixes are left uncommitted for review; the push stays blocked.
#
# Config: .codereviewrc (key=value) — review_agent, review_model, enabled,
#         command, fix_enabled, fix_agent, fix_model, fix_command.
# Skip:   SKIP_CODE_REVIEW=true git push, or enabled=false in .codereviewrc.
set -u

rc_file=".codereviewrc"
report="working/code-review-report.md"

# --- skip checks -------------------------------------------------------------

case "${SKIP_CODE_REVIEW:-}" in
    1 | true | TRUE | yes | YES)
        echo "SKIP_CODE_REVIEW set — skipping code review."
        exit 0
        ;;
esac

# key=value, one per line. Strips inline comments (whitespace then #) and
# surrounding whitespace, so a line copied with its trailing comment parses.
rc_get() {
    sed -n "s/^$1=//p" "$rc_file" 2>/dev/null | tail -n 1 \
        | sed -e 's/[[:space:]][[:space:]]*#.*$//' \
              -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

review_agent=$(rc_get review_agent)
review_agent=${review_agent:-claude}
# Pinned so the gate's cost doesn't move when the CLI's default model changes:
# a blocked push with auto-fix on can run up to 6 review passes.
review_model=$(rc_get review_model)
review_model=${review_model:-sonnet}
enabled=$(rc_get enabled)
enabled=${enabled:-true}
custom_cmd=$(rc_get command)

# Auto-fix: after a failed review, hand the REQUIRED findings to a fix agent
# that edits the working tree. Off by default; fixes are left uncommitted.
fix_enabled=$(rc_get fix_enabled)
fix_enabled=${fix_enabled:-false}
fix_agent=$(rc_get fix_agent)
fix_agent=${fix_agent:-claude}
# The fixer writes code, so it gets the stronger default of the two.
fix_model=$(rc_get fix_model)
fix_model=${fix_model:-opus}
fix_cmd=$(rc_get fix_command)
fix_max_iterations=$(rc_get fix_max_iterations)
fix_max_iterations=${fix_max_iterations:-2}

if [ "$enabled" = "false" ]; then
    echo "Code review disabled in $rc_file — skipping."
    exit 0
fi

# --- agent validation ---------------------------------------------------------
# Misconfiguration fails closed: a bad rc file must block the push and surface,
# not silently disable the gate. Only a missing CLI for a valid agent fails
# open, so one machine without the tool doesn't block everyone's pushes.

case "$review_agent" in
    claude) ;;
    custom)
        if [ -z "$custom_cmd" ]; then
            echo "ERROR: review_agent=custom requires command= in $rc_file — blocking push." >&2
            exit 1
        fi
        ;;
    *)
        echo "ERROR: unknown review_agent '$review_agent' in $rc_file (claude | custom) — blocking push." >&2
        exit 1
        ;;
esac

# Validate the fix agent up front on the same fail-closed terms, but only when
# auto-fix is on. A missing claude CLI is handled at fix time (fail-open).
if [ "$fix_enabled" = "true" ]; then
    case "$fix_agent" in
        claude) ;;
        custom)
            if [ -z "$fix_cmd" ]; then
                echo "ERROR: fix_agent=custom requires fix_command= in $rc_file — blocking push." >&2
                exit 1
            fi
            ;;
        *)
            echo "ERROR: unknown fix_agent '$fix_agent' in $rc_file (claude | custom) — blocking push." >&2
            exit 1
            ;;
    esac
    case "$fix_max_iterations" in
        '' | *[!0-9]*)
            echo "ERROR: fix_max_iterations must be a positive integer in $rc_file — blocking push." >&2
            exit 1
            ;;
    esac
    if [ "$fix_max_iterations" -lt 1 ]; then
        echo "ERROR: fix_max_iterations must be >= 1 in $rc_file — blocking push." >&2
        exit 1
    fi
fi

if [ "$review_agent" = "claude" ] && ! command -v claude >/dev/null 2>&1; then
    echo "WARNING: 'claude' not found — skipping code review (fail-open)." >&2
    echo "Install it, or set review_agent=custom with command= in $rc_file." >&2
    exit 0
fi

# run_review_agent reads the prompt as $1 and prints the review to stdout; the
# review must end with "VERDICT: PASS" or "VERDICT: FAIL" as its final line. A
# custom command receives the prompt on stdin instead.
# git status is allowed: the re-review prompt needs it to see untracked files
# the fixer added, and a headless -p run has no prompt to approve it with.
run_review_agent() {
    case "$review_agent" in
        claude)
            claude -p "$1" --model "$review_model" \
                --allowed-tools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git status:*)"
            ;;
        custom)
            printf '%s\n' "$1" | sh -c "$custom_cmd"
            ;;
    esac
}

# run_fix_agent reads the fix prompt as $1 and edits the working tree in place.
# Unlike the review agent it gets write tools, plus the checks it must not break;
# a custom command receives the prompt on stdin instead.
run_fix_agent() {
    case "$fix_agent" in
        claude)
            claude -p "$1" --model "$fix_model" \
                --allowed-tools "Read,Edit,Write,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*),Bash(git status:*),Bash(uv run pytest:*),Bash(uv run pre-commit:*),Bash(make run-check:*)"
            ;;
        custom)
            printf '%s\n' "$1" | sh -c "$fix_cmd"
            ;;
    esac
}

# --- diff range --------------------------------------------------------------

zero_sha=0000000000000000000000000000000000000000
# Empty-tree hash: diff base for a brand-new repository's first push.
empty_tree=4b825dc642cb6eb9a060e54bf8d69288fbee4904

# Under pre-push, pre-commit exports the refs being pushed; prefer them so the
# review covers what actually goes to the remote, not the checked-out branch.
# Pin HEAD once up front: the passes run minutes apart, and a commit made
# mid-review must never be recorded as reviewed.
to_ref="${PRE_COMMIT_TO_REF:-}"
if [ "$to_ref" = "$zero_sha" ]; then
    echo "Ref deletion — nothing to review."
    exit 0
fi
head_sha=${to_ref:-$(git rev-parse HEAD)}
branch="${PRE_COMMIT_LOCAL_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
branch=${branch#refs/heads/}
ledger="$(git rev-parse --git-dir)/code-review-ledger"

default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
default_branch=${default_branch:-main}

last_reviewed=""
[ -f "$ledger" ] && last_reviewed=$(awk -v b="$branch" '$1 == b { print $2 }' "$ledger")

from_ref="${PRE_COMMIT_FROM_REF:-}"
[ "$from_ref" = "$zero_sha" ] && from_ref=""
# A remote sha we don't have locally (diverged force-push) can't be a base.
if [ -n "$from_ref" ] && ! git cat-file -e "$from_ref" 2>/dev/null; then
    from_ref=""
fi

if [ -n "$last_reviewed" ] && git merge-base --is-ancestor "$last_reviewed" "$head_sha" 2>/dev/null; then
    # Reviewed before: only new commits since the last passing review.
    base=$last_reviewed
elif [ -n "$from_ref" ]; then
    # pre-push: exactly the commits the remote doesn't have yet.
    base=$from_ref
elif [ -z "$to_ref" ] && base=$(git rev-parse -q --verify '@{upstream}' 2>/dev/null); then
    # Manual run (make review): everything not yet pushed upstream.
    :
elif base=$(git merge-base "origin/$default_branch" "$head_sha" 2>/dev/null) \
    || base=$(git merge-base "$default_branch" "$head_sha" 2>/dev/null); then
    # First review of a branch: the whole branch vs the default branch.
    :
elif [ -z "$(git for-each-ref refs/remotes)" ]; then
    # Brand-new repository with no remote branches: everything is new.
    base=$empty_tree
else
    echo "ERROR: cannot determine a review base — branch '$default_branch' not found." >&2
    echo "Set the remote default branch (git remote set-head origin -a) and retry." >&2
    exit 1
fi
range="$base..$head_sha"

# An error here must block, not skip: an unresolvable range looks identical to
# an empty diff on stdout, and silence would wave unreviewed commits through.
if ! changed=$(git diff --name-only "$range" 2>&1); then
    echo "ERROR: git diff $range failed — blocking push (cannot tell what is unreviewed):" >&2
    echo "$changed" >&2
    exit 1
fi
if [ -z "$changed" ]; then
    echo "No unreviewed changes in $range — skipping code review."
    exit 0
fi

# --- review passes -----------------------------------------------------------

mkdir -p working
{
    echo "# Code review report"
    echo
    echo "- Branch: \`$branch\`"
    echo "- Range: \`$range\`"
    echo "- Review agent: \`$review_agent\`"
    [ "$fix_enabled" = "true" ] && echo "- Fix agent: \`$fix_agent\`"
    echo "- Date: $(date '+%Y-%m-%d %H:%M:%S')"
} > "$report"

# finish_pass <title> <output-file> <agent-exit-status> — appends the pass
# output to the report. Returns 0 only if the agent exited 0 and the FINAL
# line of the output is "VERDICT: PASS" — a verdict quoted or drafted
# mid-output must not count.
finish_pass() {
    local title=$1 file=$2 status=$3 output
    output=$(cat "$file")
    {
        echo
        echo "## $title"
        echo
        echo "$output"
    } >> "$report"
    if [ "$status" -ne 0 ]; then
        echo "Agent failed (exit $status) during $title — see $report" >&2
        return 1
    fi
    printf '%s\n' "$output" | tail -n 1 | grep -q '^VERDICT: PASS[[:space:]]*$'
}

# show_pass <title> <output-file> <ok> — prints a pass's review so the results
# are readable in the terminal, pass or fail, not just in the report. Capped:
# a finding-heavy review can overflow stdout, and agent harnesses truncate
# long hook output — losing the verdict and "push blocked" lines printed
# after the passes. The full text is always in the report.
show_limit=100
show_pass() {
    local verdict=FAILED
    [ "$3" = 1 ] && verdict=PASSED
    echo ""
    echo "==== $1 — $verdict ===="
    head -n "$show_limit" "$2"
    if [ "$(wc -l < "$2")" -gt "$show_limit" ]; then
        echo "[... truncated at $show_limit lines — full pass output in $report]"
    fi
}

# The most recent review's combined findings, refreshed by every run_review call
# and consumed by apply_fixes. Kept in one stable file so the fixer always sees
# the latest findings, not the whole accumulated report.
findings_file=$(mktemp)
trap 'rm -f "$findings_file"' EXIT

# run_review runs both passes over a given scope, prints and reports the outcome,
# and refreshes $findings_file. Called once for the initial review and again per
# fix iteration.
#   $1 — the argument to `git diff` naming the scope (e.g. "A..B" or "A")
#   $2 — a one-line human description of that scope
#   $3 — a label suffix for section titles and console lines (may be empty)
#   $4 — extra prompt line(s) after the diff command (may be empty)
# The passes are independent (each only reads the diff and repo files), so run
# them concurrently and append their report sections in order. Returns 0 only if
# both passes pass.
run_review() {
    local diff_arg=$1 scope_desc=$2 label=$3 extra=$4
    local p1 p2 o1 o2 s1 s2 ok1 ok2 pid1 pid2

    # read -d '' (not $(cat <<EOF)): bash 3.2 mis-parses quotes inside heredocs
    # nested in command substitutions.
    read -r -d '' p1 <<EOF || true
You are performing pass 1 of 2 of a pre-push code review for this repository.

Scope: $scope_desc. Start with:
    git diff $diff_arg
$extra
Read surrounding source files as needed for context, and read CLAUDE.md for
this project's coding and testing guidelines.

Review the changes for:
- DRY: duplicated logic that should be extracted or should reuse an existing function
- YAGNI: speculative abstractions, unused flexibility, code with no current need
- Library leverage: hand-rolled code where the stdlib or an already-installed dependency does the job
- Missing tests: gaps per the testing guidance in CLAUDE.md (critical flows and core logic need tests; handlers and unexpected paths do not)
- General Python best practices
- Security best practices (injection, secrets in code, unsafe deserialization, path traversal, etc.)
- Whether the change makes sense in the context of the codebase

Report every finding as a markdown bullet:
- **REQUIRED** or **SUGGESTED** — \`file:line\` — what is wrong and what change is needed

Use REQUIRED only for findings that must be fixed before this code merges.
Use SUGGESTED for improvements the code could reasonably ship without.
If there are no findings, say so.

End with your verdict on its own line, as plain text with no backticks or
other formatting. The final line must be exactly VERDICT: PASS if there are
no REQUIRED findings, otherwise exactly VERDICT: FAIL.
EOF

    read -r -d '' p2 <<EOF || true
You are performing pass 2 of 2 of a pre-push code review for this repository:
spec conformance.

Scope: $scope_desc. Start with:
    git diff $diff_arg
$extra
Then read docs/design.md. If docs/specs/ holds per-flow specs, read the ones
covering the flows this change touches (design.md's Flows index maps them);
each is the source of truth for its own flow. Read any other document in docs/
that bears on the change.

Check that the changed code conforms to the intent laid out in the specs:
- Architecture and component boundaries match docs/design.md
- Per-flow behavior matches the flow's spec under docs/specs/
- Data flow and integration points match the documented design
- Nothing contradicts documented decisions or constraints
- If the change alters design, architecture, or public API, the docs were updated in the same change

Where the specs are silent on an area, that is not a finding. Only deviations
from documented intent count.

Report every finding as a markdown bullet:
- **REQUIRED** or **SUGGESTED** — \`file:line\` (or doc section) — the spec statement, the deviation, and what change is needed

If there are no findings, say so.

End with your verdict on its own line, as plain text with no backticks or
other formatting. The final line must be exactly VERDICT: PASS if there are
no REQUIRED findings, otherwise exactly VERDICT: FAIL.
EOF

    o1=$(mktemp)
    o2=$(mktemp)
    echo ""
    echo "Running pass 1 (general review) and pass 2 (spec conformance) in parallel$label"
    echo "(this can take a few minutes)..."
    run_review_agent "$p1" > "$o1" 2>&1 &
    pid1=$!
    run_review_agent "$p2" > "$o2" 2>&1 &
    pid2=$!

    s1=0
    wait "$pid1" || s1=$?
    s2=0
    wait "$pid2" || s2=$?

    ok1=0
    ok2=0
    finish_pass "Pass 1: general review$label" "$o1" "$s1" && ok1=1
    finish_pass "Pass 2: spec conformance$label" "$o2" "$s2" && ok2=1
    show_pass "Pass 1: general review$label" "$o1" "$ok1"
    show_pass "Pass 2: spec conformance$label" "$o2" "$ok2"

    { cat "$o1"; echo; cat "$o2"; } > "$findings_file"
    rm -f "$o1" "$o2"
    [ "$ok1" = 1 ] && [ "$ok2" = 1 ]
}

# apply_fixes hands the most recent review's REQUIRED findings to a single fix
# agent (both passes combined — coupled fixes and shared root causes need one
# coherent pass, not one agent per finding). The agent edits the working tree
# and leaves the changes uncommitted. The fixer's summary is appended to the
# report and printed to the terminal, capped like the review passes so it can't
# overflow and get truncated. $1 is a label suffix for the section/console line.
# Returns non-zero if the fixer could not run, so the loop can stop.
apply_fixes() {
    local label=$1 fix_prompt fix_out
    if [ "$fix_agent" = "claude" ] && ! command -v claude >/dev/null 2>&1; then
        echo "WARNING: 'claude' not found — cannot auto-fix. Fix REQUIRED findings manually." >&2
        return 1
    fi

    read -r -d '' fix_prompt <<EOF || true
You are the fix pass of a pre-push code review for this repository.

A code review of your changes failed. Read the findings in:
    $findings_file
and read CLAUDE.md for this project's coding and testing guidelines.

Apply code fixes for every finding marked REQUIRED. Ignore SUGGESTED findings.

Rules:
- Fix at the root cause. If several findings share one root cause, fix it once.
- Make the minimal, localized change that resolves each REQUIRED finding.
- Edit files in the working tree. Do NOT stage, commit, amend, or push — leave
  all changes uncommitted for human review.
- Verify before finishing: run \`uv run pre-commit run --files <changed files>\`
  and \`uv run pytest\`. A fix that breaks lint or tests is not a fix.
- If a REQUIRED finding cannot be fixed safely and automatically, leave it and
  say why.

End with a report titled "Fix summary" with one entry per REQUIRED finding:
the finding (file:line and what was wrong) and exactly what you changed to fix
it — or, if unfixed, why. Keep it concise.
EOF

    echo ""
    echo "fix_enabled=true — applying fixes for REQUIRED findings with '$fix_agent'$label"
    echo "(this can take a few minutes)..."
    fix_out=$(mktemp)
    run_fix_agent "$fix_prompt" > "$fix_out" 2>&1

    {
        echo
        echo "## Auto-fix$label"
        echo
        cat "$fix_out"
    } >> "$report"

    echo ""
    echo "==== Auto-fix$label — REQUIRED findings ===="
    head -n "$show_limit" "$fix_out"
    if [ "$(wc -l < "$fix_out")" -gt "$show_limit" ]; then
        echo "[... truncated at $show_limit lines — full fix summary in $report]"
    fi
    rm -f "$fix_out"
}

# --- initial review ----------------------------------------------------------
# Reviews the committed range that is actually being pushed. A pass here is the
# only outcome that records the ledger and lets the push through.

if run_review "$range" "the changes in git range $range" "" ""; then
    tmp=$(mktemp)
    [ -f "$ledger" ] && awk -v b="$branch" '$1 != b' "$ledger" > "$tmp"
    echo "$branch $head_sha" >> "$tmp"
    mv "$tmp" "$ledger"
    echo ""
    echo "Code review PASSED. Recorded for '$branch' — only new commits will be reviewed next push."
    echo "Report: $report"
    exit 0
fi

echo ""
echo "Code review FAILED — push blocked."
echo "Full report: $report"

if [ "$fix_enabled" != "true" ]; then
    echo "Fix the REQUIRED findings, commit, and push again."
    exit 1
fi

# --- fix / re-review loop ----------------------------------------------------
# Fixes are uncommitted, so re-reviews look at the working tree (base -> tree),
# not the committed range. A working-tree pass is never recorded in the ledger
# (the passing state isn't a commit) and never lets this push through: the fixes
# must be committed and pushed, where they get one honest re-review.

extra_note="Also run \`git status --porcelain\` and read any new untracked files the fixes added — they are part of the scope but will not appear in the diff above."
iteration=1
while :; do
    if ! apply_fixes " (iteration $iteration)"; then
        echo "Auto-fix could not run — push blocked. Fix the REQUIRED findings manually."
        exit 1
    fi

    if run_review "$base" \
        "the working tree relative to $base (your changes plus the just-applied fixes)" \
        " (re-review $iteration)" "$extra_note"; then
        echo ""
        echo "Auto-fix resolved all REQUIRED findings after $iteration iteration(s)."
        echo "The fixes are in the working tree, uncommitted — this push is still blocked."
        echo "Review the diff, commit the fixes, and push again."
        echo "Report: $report"
        exit 1
    fi

    if [ "$iteration" -ge "$fix_max_iterations" ]; then
        echo ""
        echo "Auto-fix stopped after $iteration iteration(s) (fix_max_iterations=$fix_max_iterations) with REQUIRED findings remaining."
        echo "Review the working tree and $report, finish the fixes, commit, and push again."
        exit 1
    fi

    iteration=$((iteration + 1))
done
