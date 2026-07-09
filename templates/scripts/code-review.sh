#!/usr/bin/env bash
# Two-pass agentic code review, run by the pre-push hook.
#   Pass 1: general review — DRY, YAGNI, library leverage, missing tests,
#           best practices, security, fit with the codebase.
#   Pass 2: spec conformance against the documents in docs/.
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

rc_get() { sed -n "s/^$1=//p" "$rc_file" 2>/dev/null | tail -n 1; }

agent=$(rc_get agent)
agent=${agent:-claude}
enabled=$(rc_get enabled)
enabled=${enabled:-true}
custom_cmd=$(rc_get command)

if [ "$enabled" = "false" ]; then
    echo "Code review disabled in $rc_file — skipping."
    exit 0
fi

# --- agent presets -----------------------------------------------------------
# Each preset reads the prompt as $1, prints the review to stdout, and the
# review must end with "VERDICT: PASS" or "VERDICT: FAIL". Adjust flags here
# if your agent CLI's syntax changes, or use agent=custom with command= in
# .codereviewrc (the custom command receives the prompt on stdin).

run_agent() {
    local prompt=$1
    case "$agent" in
        claude)
            claude -p "$prompt" \
                --allowed-tools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)"
            ;;
        codex)
            codex exec --sandbox read-only "$prompt"
            ;;
        gemini)
            gemini -p "$prompt"
            ;;
        copilot)
            copilot -p "$prompt" \
                --allow-tool 'shell(git diff*)' --allow-tool 'shell(git log*)' --allow-tool 'shell(git show*)'
            ;;
        pi)
            pi -p "$prompt"
            ;;
        custom)
            if [ -z "$custom_cmd" ]; then
                echo "agent=custom requires command= in $rc_file" >&2
                return 1
            fi
            printf '%s\n' "$prompt" | sh -c "$custom_cmd"
            ;;
        *)
            echo "Unknown agent '$agent' in $rc_file (claude|codex|gemini|copilot|pi|custom)" >&2
            return 1
            ;;
    esac
}

agent_bin=$agent
[ "$agent" = "custom" ] && agent_bin=${custom_cmd%% *}
if ! command -v "$agent_bin" >/dev/null 2>&1; then
    echo "WARNING: '$agent_bin' not found — skipping code review (fail-open)." >&2
    echo "Install it, or set agent/command in $rc_file." >&2
    exit 0
fi

# --- diff range --------------------------------------------------------------

branch=$(git rev-parse --abbrev-ref HEAD)
ledger="$(git rev-parse --git-dir)/code-review-ledger"

# Empty-tree hash: diff base for a repo's very first push.
empty_tree=4b825dc642cb6eb9a060e54bf8d69288fbee4904

default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
default_branch=${default_branch:-main}

last_reviewed=""
[ -f "$ledger" ] && last_reviewed=$(awk -v b="$branch" '$1 == b { print $2 }' "$ledger")

if [ -n "$last_reviewed" ] && git merge-base --is-ancestor "$last_reviewed" HEAD 2>/dev/null; then
    # Branch reviewed before: only new commits since the last passing review.
    range="$last_reviewed..HEAD"
elif [ "$branch" = "$default_branch" ]; then
    # Pushing the default branch: review the commits being pushed.
    from_ref="${PRE_COMMIT_FROM_REF:-}"
    case "$from_ref" in
        "" | 0000000000000000000000000000000000000000)
            from_ref=$(git rev-parse -q --verify HEAD~1 || echo "$empty_tree")
            ;;
    esac
    range="$from_ref..HEAD"
else
    # First review of a feature branch: the whole branch vs the default branch.
    base=$(git merge-base "origin/$default_branch" HEAD 2>/dev/null \
        || git merge-base "$default_branch" HEAD 2>/dev/null \
        || echo "$empty_tree")
    range="$base..HEAD"
fi

if [ -z "$(git diff --name-only "$range" 2>/dev/null)" ]; then
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

# run_pass <title> <prompt> — appends the agent's output to the report.
# Returns 0 only if the output contains "VERDICT: PASS".
run_pass() {
    local title=$1 prompt=$2 output status
    echo ""
    echo "Running $title (this can take a few minutes)..."
    output=$(run_agent "$prompt" 2>&1)
    status=$?
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
    printf '%s\n' "$output" | grep -q '^VERDICT: PASS[[:space:]]*$'
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

Your final line must be exactly \`VERDICT: PASS\` if there are no REQUIRED
findings, otherwise exactly \`VERDICT: FAIL\`.
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

Your final line must be exactly \`VERDICT: PASS\` if there are no REQUIRED
findings, otherwise exactly \`VERDICT: FAIL\`.
EOF

pass1_ok=0
pass2_ok=0
run_pass "Pass 1: general review" "$pass1_prompt" && pass1_ok=1
run_pass "Pass 2: spec conformance" "$pass2_prompt" && pass2_ok=1

echo ""
if [ "$pass1_ok" = 1 ] && [ "$pass2_ok" = 1 ]; then
    tmp=$(mktemp)
    [ -f "$ledger" ] && awk -v b="$branch" '$1 != b' "$ledger" > "$tmp"
    echo "$branch $(git rev-parse HEAD)" >> "$tmp"
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
