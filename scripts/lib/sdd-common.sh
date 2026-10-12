#!/bin/sh
# discipline-flow/scripts/lib/sdd-common.sh
# Shared SDD frontmatter + plan helpers (POSIX sh compatible, zero deps).
# Canonical source for SESSION.md parsing and PLAN resolution.
# Sourced by sdd.sh, verify-crit.sh, and (best-effort) git hooks.
# Hooks installed under .git/hooks are single-file copies and keep an
# inline fallback when this lib is unavailable (already-bootstrapped projects).

# Session file (env override respected, default SESSION.md in cwd).
sdd_session_file() {
    printf '%s\n' "${SESSION_FILE:-SESSION.md}"
}

# Read a key from the first YAML frontmatter block (--- ... ---).
# Usage: sdd_get_val <key> [session_file]  -> prints value or 'none'.
sdd_get_val() {
    _sk="$1"
    _sf="${2:-${SESSION_FILE:-SESSION.md}}"
    if [ ! -f "$_sf" ]; then
        printf 'none\n'
        return 0
    fi
    awk -v k="$_sk" '/^---$/ { if (c++ == 1) exit } c==1 && $0 ~ ("^" k ":") { sub("^" k ":[[:space:]]*", ""); gsub(/\r/, ""); print $0 }' "$_sf"
}

# Convenience wrappers used by hooks.
sdd_state() {
    sdd_get_val "sdd_state" "${1:-${SESSION_FILE:-SESSION.md}}"
}

sdd_active_task() {
    sdd_get_val "active_task" "${1:-${SESSION_FILE:-SESSION.md}}"
}

sdd_active_agent() {
    sdd_get_val "active_agent" "${1:-${SESSION_FILE:-SESSION.md}}"
}

# sha256 of plan file via coreutils, or 'none'.
sdd_calc_hash() {
    _hp="$1"
    if [ -n "$_hp" ] && [ -f "$_hp" ]; then
        sha256sum "$_hp" | awk '{print $1}'
    else
        printf 'none\n'
    fi
}

# Resolve the active PLAN file.
# Priority: 1) SESSION.md reference, 2) plans/ (canonical), 3) repo root (legacy).
sdd_resolve_plan() {
    _sess="${1:-${SESSION_FILE:-SESSION.md}}"
    _plan=""
    if [ -f "$_sess" ]; then
        _plan=$(grep -oE '([a-zA-Z0-9_.-]+/)?PLAN-[0-9]+(\.[0-9]+)?\.md' "$_sess" 2>/dev/null | head -n 1 || true)
    fi
    if [ -n "$_plan" ] && [ -f "$_plan" ]; then
        printf '%s\n' "$_plan"
        return 0
    fi
    _plan=$(ls plans/PLAN-*.md 2>/dev/null | sort -V | tail -n 1 || true)
    if [ -n "$_plan" ] && [ -f "$_plan" ]; then
        printf '%s\n' "$_plan"
        return 0
    fi
    _plan=$(ls PLAN-*.md 2>/dev/null | sort -V | tail -n 1 || true)
    printf '%s\n' "$_plan"
}
