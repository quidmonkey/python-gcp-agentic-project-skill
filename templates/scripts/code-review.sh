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
# Config: .codereviewrc (key=value) — agent, enabled, command.
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

agent=$(rc_get agent)
agent=${agent:-claude}
enabled=$(rc_get enabled)
enabled=${enabled:-true}
custom_cmd=$(rc_get command)

if [ "$enabled" = "false" ]; then
    echo "Code review disabled in $rc_file — skipping."
    exit 0
fi

# --- agent validation ---------------------------------------------------------
# Misconfiguration fails closed: a bad rc file must block the push and surface,
# not silently disable the gate. Only a missing CLI for a valid agent fails
# open, so one machine without the tool doesn't block everyone's pushes.

case "$agent" in
    claude) ;;
    custom)
        if [ -z "$custom_cmd" ]; then
            echo "ERROR: agent=custom requires command= in $rc_file — blocking push." >&2
            exit 1
        fi
        ;;
    *)
        echo "ERROR: unknown agent '$agent' in $rc_file (claude | custom) — blocking push." >&2
        exit 1
        ;;
esac

if [ "$agent" = "claude" ] && ! command -v claude >/dev/null 2>&1; then
    echo "WARNING: 'claude' not found — skipping code review (fail-open)." >&2
    echo "Install it, or set agent=custom with command= in $rc_file." >&2
    exit 0
fi

# run_agent reads the prompt as $1 and prints the review to stdout; the review
# must end with "VERDICT: PASS" or "VERDICT: FAIL" as its final line. A custom
# command receives the prompt on stdin instead.
run_agent() {
    case "$agent" in
        claude)
            claude -p "$1" \
                --allowed-tools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)"
            ;;
        custom)
            printf '%s\n' "$1" | sh -c "$custom_cmd"
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
    echo "- Agent: \`$agent\`"
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

# read -d '' (not $(cat <<EOF)): bash 3.2 mis-parses quotes inside heredocs
# nested in command substitutions.
read -r -d '' pass1_prompt <<EOF || true
You are performing pass 1 of 2 of a pre-push code review for this repository.

Scope: the changes in git range $range. Start with:
    git diff $range
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

read -r -d '' pass2_prompt <<EOF || true
You are performing pass 2 of 2 of a pre-push code review for this repository:
spec conformance.

Scope: the changes in git range $range. Start with:
    git diff $range
Then read every spec document in docs/ (design.md and any others present).

Check that the changed code conforms to the intent laid out in the specs:
- Architecture and component boundaries match docs/design.md
- Data flow and integration points match the documented design
- Nothing contradicts documented decisions or constraints
- If the change alters design, architecture, or public API, the docs were updated in the same range

Where the specs are silent on an area, that is not a finding. Only deviations
from documented intent count.

Report every finding as a markdown bullet:
- **REQUIRED** or **SUGGESTED** — \`file:line\` (or doc section) — the spec statement, the deviation, and what change is needed

If there are no findings, say so.

End with your verdict on its own line, as plain text with no backticks or
other formatting. The final line must be exactly VERDICT: PASS if there are
no REQUIRED findings, otherwise exactly VERDICT: FAIL.
EOF

# The passes are independent (each only reads the diff and repo files), so run
# them concurrently and append their report sections in order afterwards.
pass1_out=$(mktemp)
pass2_out=$(mktemp)
trap 'rm -f "$pass1_out" "$pass2_out"' EXIT

echo ""
echo "Running pass 1 (general review) and pass 2 (spec conformance) in parallel"
echo "(this can take a few minutes)..."
run_agent "$pass1_prompt" > "$pass1_out" 2>&1 &
pass1_pid=$!
run_agent "$pass2_prompt" > "$pass2_out" 2>&1 &
pass2_pid=$!

pass1_status=0
wait "$pass1_pid" || pass1_status=$?
pass2_status=0
wait "$pass2_pid" || pass2_status=$?

pass1_ok=0
pass2_ok=0
finish_pass "Pass 1: general review" "$pass1_out" "$pass1_status" && pass1_ok=1
finish_pass "Pass 2: spec conformance" "$pass2_out" "$pass2_status" && pass2_ok=1

echo ""
if [ "$pass1_ok" = 1 ] && [ "$pass2_ok" = 1 ]; then
    tmp=$(mktemp)
    [ -f "$ledger" ] && awk -v b="$branch" '$1 != b' "$ledger" > "$tmp"
    echo "$branch $head_sha" >> "$tmp"
    mv "$tmp" "$ledger"
    echo "Code review PASSED. Recorded for '$branch' — only new commits will be reviewed next push."
    echo "Report: $report"
    exit 0
fi

echo "Code review FAILED — push blocked."
[ "$pass1_ok" = 1 ] || echo "  - Pass 1 (general review) found REQUIRED changes"
[ "$pass2_ok" = 1 ] || echo "  - Pass 2 (spec conformance) found REQUIRED changes"
echo "Full report: $report"
echo "Fix the REQUIRED findings, commit, and push again."
exit 1
