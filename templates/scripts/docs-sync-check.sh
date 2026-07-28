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

# Per-flow specs carry the same diagram and index obligations as design.md.
while IFS= read -r spec; do
  [ -n "$spec" ] || continue
  # A deleted spec is also "changed". It needs neither a diagram nor an index
  # entry -- retiring a flow is a removal on both sides, not a sync failure.
  [ -f "$spec" ] || continue
  flow=$(basename "$spec" .md)
  if ! has "docs/specs/$flow-diagram.mmd"; then
    stale="$stale
- docs/specs/$flow-diagram.mmd -- redraw the flow diagram to match $spec"
  fi
  # The index in design.md is the only path into a spec. An unlinked one is
  # invisible to both readers and the code-review spec pass.
  if [ -f docs/design.md ] && ! grep -qF "specs/$flow.md" docs/design.md; then
    stale="$stale
- docs/design.md -- link $spec from the Flows index"
  fi
done <<EOF
$(printf '%s\n' "$changed" | grep -E '^docs/specs/[^/]+\.md$' || true)
EOF

# A design doc past this size stops being readable in one sitting, and the
# code-review spec pass has to load all of it to check one flow.
# docs/specs/ is absent until the first split, so find on a missing dir is the
# normal "no specs yet" case, not an error.
if has docs/design.md && [ -f docs/design.md ] &&
  [ "$(wc -l <docs/design.md)" -gt 400 ] &&
  [ -z "$(find docs/specs -name '*.md' -print -quit 2>/dev/null)" ]; then
  stale="$stale
- docs/specs/ -- docs/design.md is over 400 lines with no per-flow specs; create docs/specs/ and split each flow into docs/specs/<flow>.md (skeleton in CLAUDE.md) plus docs/specs/<flow>-diagram.mmd, leave the architecture and cross-cutting sections in design.md, and link each spec from its Flows index"
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
