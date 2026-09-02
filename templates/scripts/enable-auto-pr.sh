#!/usr/bin/env bash
# Prompt for, or unconditionally turn on, scripts/ship.sh's PR automation
# (open a PR after a successful push, self-approve it, enable auto-merge).
# Off by default: a fresh clone has no .codereviewrc, and `make ship` just
# pushes and leaves the PR to you.
#
# Usage:
#   scripts/enable-auto-pr.sh --prompt   # ask; no-op if stdin isn't a TTY (make setup)
#   scripts/enable-auto-pr.sh --enable   # turn it on unconditionally (make auto-pr)
set -u

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

mode=${1:---prompt}

enable() {
    rc_set pr_automation true
    echo "Auto-PR enabled — 'make ship' will open a PR after a successful push, self-approve it, and enable auto-merge."
    echo "Requires the gh (or az) CLI, logged in with permission to open and merge PRs. Adjust pr_host / pr_merge_method / etc. in .codereviewrc."
}

case "$mode" in
--enable)
    enable
    ;;
--prompt)
    if [ ! -t 0 ]; then
        echo "Skipping the auto-PR prompt (no TTY) — 'make ship' will just push. Run 'make auto-pr' to enable it later."
        exit 0
    fi
    read -r -p "Enable auto-PR? 'make ship' will push, then open, self-approve, and auto-merge a PR (requires the gh or az CLI) [y/N] " answer
    case "$answer" in
        y | Y | yes | YES) enable ;;
        *) echo "Skipped — 'make ship' will just push. Run 'make auto-pr' anytime to enable it." ;;
    esac
    ;;
*)
    echo "ERROR: unknown mode '$mode' (expected --prompt or --enable)." >&2
    exit 1
    ;;
esac
