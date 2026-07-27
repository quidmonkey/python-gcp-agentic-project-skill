#!/usr/bin/env bash
# Stop-hook gate: blocks the agent from finishing while docs/ is stale relative
# to the working tree.
#
# Exit 2 with a message on stderr is the only Stop-hook channel the model reads.
# Exit 0 output goes to the transcript and is ignored, so a reminder printed
# that way does nothing.
set -uo pipefail

# Claude Code re-runs Stop hooks after a block. stop_hook_active means this gate
# already fired once this turn -- let the agent stop rather than loop forever.
payload=$(cat 2>/dev/null || true)
if printf '%s' "$payload" | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# Porcelain paths start at column 4; renames read "old -> new".
changed=$(git status --porcelain 2>/dev/null | cut -c4- | sed 's/.* -> //')
[ -n "$changed" ] || exit 0

has() { printf '%s\n' "$changed" | grep -qxF "$1"; }
has_re() { printf '%s\n' "$changed" | grep -qE "$1"; }

stale=""

if has docs/design.md && ! has docs/design.mmd; then
  stale="$stale
- docs/design.mmd -- redraw the diagram to match docs/design.md"
fi

# Anything that moves the deployed GCP footprint moves the bill.
# A bare scaffold has nothing deployed and nothing to cost out. A container, a
# deploy script, terraform, or a filled-in infra doc means the footprint is real.
deployable=false
if [ -f Dockerfile ] || [ -f scripts/deploy.sh ] ||
  [ -n "$(find . -name '*.tf' -not -path './.venv/*' -print -quit 2>/dev/null)" ] ||
  { [ -f docs/infra.md ] && ! grep -q '_TBD_' docs/infra.md; }; then
  deployable=true
fi

if [ -f docs/finops.md ] && $deployable; then
  if grep -q '_TBD_' docs/finops.md; then
    # Catches the case a "did it change?" test misses: the scaffold template was
    # never filled in, so the file looks touched but says nothing.
    stale="$stale
- docs/finops.md -- still the scaffold template (_TBD_) while a deployable footprint exists; fill in the service table and cost estimates"
  elif has_re '^(docs/design\.md|docs/infra\.md|Dockerfile|scripts/deploy\.sh)$|\.tf$' &&
    ! has docs/finops.md; then
    stale="$stale
- docs/finops.md -- update the service table and cost estimates for the changed GCP footprint"
  fi
fi

[ -n "$stale" ] || exit 0

cat >&2 <<EOF
DOCS SYNC REQUIRED. These docs are stale relative to the working tree:
$stale

Update them now, then stop. Do not report the task done first.
EOF
exit 2
