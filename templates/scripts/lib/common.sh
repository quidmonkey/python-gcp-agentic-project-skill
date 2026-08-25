# Shared helpers for scripts/code-review.sh and scripts/ship.sh. Sourced, not
# executed — no shebang, no set -u here (each caller sets its own options).

# rc_get <key> [rc-file] — reads key=value from an rc file (default
# .codereviewrc), one per line. Strips inline comments (whitespace then #) and
# surrounding whitespace, so a line copied with its trailing comment parses.
# Prints the last matching line if a key repeats.
rc_get() {
    local key=$1 file=${2:-.codereviewrc}
    sed -n "s/^$key=//p" "$file" 2>/dev/null | tail -n 1 \
        | sed -e 's/[[:space:]][[:space:]]*#.*$//' \
              -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# default_branch — the repo's default branch per origin/HEAD, falling back to
# main if the remote HEAD ref isn't set locally (git remote set-head origin -a).
default_branch() {
    local b
    b=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    echo "${b:-main}"
}
