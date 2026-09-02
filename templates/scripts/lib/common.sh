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

# rc_set <key> <value> [rc-file] — writes key=value into an rc file, replacing
# the existing line for that key if present or appending a new one otherwise.
# Creates the file (with a header comment) if it doesn't exist yet. Used to
# record a personal choice (e.g. pr_automation) without touching other keys.
rc_set() {
    local key=$1 value=$2 file=${3:-.codereviewrc}
    if [ ! -f "$file" ]; then
        printf '# Personal review/ship automation settings (gitignored) -- see scripts/code-review.sh and scripts/ship.sh.\n' > "$file"
    fi
    if grep -q "^$key=" "$file" 2>/dev/null; then
        sed -i.bak "s/^$key=.*/$key=$value/" "$file" && rm -f "$file.bak"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}
