#!/usr/bin/env bash
# Stop-hook gate: runs pre-commit over the files changed in the working tree and
# blocks the agent from finishing while any hook fails.
#
# Exit 2 with a message on stderr is the only Stop-hook channel the model reads
# (see docs-sync-check.sh), so a failure reported any other way goes unseen.
set -uo pipefail

# Claude Code re-runs Stop hooks after a block. stop_hook_active means a gate
# already fired once this turn -- let the agent stop rather than loop forever.
payload=$(cat 2>/dev/null || true)
if printf '%s' "$payload" | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# Tracked changes plus untracked files, minus deletions.
files=$({ git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } |
  sort -u | while IFS= read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done)

# Nothing changed (e.g. the turn only answered a question): nothing to check.
[ -n "$files" ] || exit 0

if output=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 uv run pre-commit run --files 2>&1); then
  exit 0
fi

# Capped: agent harnesses truncate long hook output.
cat >&2 <<EOF
PRE-COMMIT FAILED on the changed files. Some hooks (ruff --fix, ruff-format,
end-of-file-fixer) may already have rewritten files; re-run
'uv run pre-commit run --files <changed files>' and fix what remains at root cause.

$(printf '%s\n' "$output" | tail -n 80)
EOF
exit 2
