#!/usr/bin/env bash
# prepare-commit-msg hook (wired through .pre-commit-config.yaml): lists the
# recorded decisions for the staged files as comment lines in the commit
# message editor, so whoever writes the message sees them. Git strips comment
# lines, so nothing extra lands in the commit.
#
#   $1  the commit message file (pre-commit passes it)
# pre-commit exports git's message source as PRE_COMMIT_COMMIT_MSG_SOURCE.
#
# Never blocks a commit: every early exit is 0.
set -uo pipefail

msg_file=${1:-}
[ -f "$msg_file" ] || exit 0

# Only when an editor opens on a fresh message. With -m or -F (message), a
# merge, a squash, or --amend (commit), the message may not be edited, and git
# then keeps comment lines instead of stripping them.
case "${PRE_COMMIT_COMMIT_MSG_SOURCE:-}" in
    '' | template) ;;
    *) exit 0 ;;
esac

# The same holds for a cleanup mode that doesn't strip comments.
case "$(git config commit.cleanup || echo default)" in
    default | strip) ;;
    *) exit 0 ;;
esac

staged=()
while IFS= read -r f; do
    [ -n "$f" ] && staged+=("$f")
done <<< "$(git diff --cached --name-only --diff-filter=d)"
[ ${#staged[@]} -gt 0 ] || exit 0

script_dir=$(cd "$(dirname "$0")" && pwd)
decisions=$(bash "$script_dir/decisions.sh" --limit 15 -- "${staged[@]}")
[ -n "$decisions" ] || exit 0

comment_char=$(git config core.commentChar || echo '#')
case "$comment_char" in auto | '') comment_char='#' ;; esac

block=$(
    printf '%s\n' "Prior decisions on the staged files (README.md, \"Decision history\")." \
        "If this commit reverses one, record why with a new Decision: trailer." "" "$decisions" |
        sed "s/^/$comment_char /; s/ $//"
)

# git commit -v appends the diff below a scissors line and drops everything
# after it, so the block goes above that line when there is one.
tmp=$(mktemp)
# The block goes through the environment: awk -v mangles backslashes and
# newlines.
BLOCK=$block CC=$comment_char awk '
    BEGIN { block = ENVIRON["BLOCK"]; cc = ENVIRON["CC"] }
    !done && index($0, cc " ------------------------ >8 ------------------------") == 1 {
        print block; print cc; done = 1
    }
    { print }
    END { if (!done) { print cc; print block } }
' "$msg_file" > "$tmp" && mv "$tmp" "$msg_file"
exit 0
