#!/usr/bin/env bash
# tests/test-sdd-state.sh — sdd.sh set_val/advance regression (P0-4).
# Verifies: update existing key, insert new key, no duplication, advance works.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDD="$REPO_ROOT/scripts/sdd.sh"

fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }
[ -x "$SDD" ] || fail "sdd.sh missing/executable"

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cp "$SDD" "$D/sdd.sh"
mkdir -p "$D/scripts"
cp "$SDD" "$D/scripts/sdd.sh"
if [ -f "$REPO_ROOT/scripts/lib/sdd-common.sh" ]; then
    mkdir -p "$D/scripts/lib"
    cp "$REPO_ROOT/scripts/lib/sdd-common.sh" "$D/scripts/lib/sdd-common.sh"
fi
cd "$D" || exit 1

# --- advance execute updates existing key, preserves body ---
printf -- '---\nsdd_state: plan\nactive_task: none\nplan_hash: none\n---\n# Session body\n' > SESSION.md
bash ./sdd.sh advance execute >/dev/null
grep -q '^sdd_state: execute$' SESSION.md || fail "advance execute did not set state"
grep -q '^active_task: none$' SESSION.md || fail "advance must preserve active_task"
grep -q '^plan_hash: none$' SESSION.md || fail "advance must preserve plan_hash"
grep -q '# Session body' SESSION.md || fail "advance must preserve body"
[ "$(grep -c '^sdd_state:' SESSION.md)" = "1" ] || fail "sdd_state duplicated"

# --- advance plan resets active_task ---
bash ./sdd.sh start F1 >/dev/null
grep -q '^active_task: F1$' SESSION.md || fail "start F1 did not set active_task"
bash ./sdd.sh advance plan >/dev/null
grep -q '^active_task: none$' SESSION.md || fail "advance plan must reset active_task"

# --- set_val inserts a brand-new key before closing --- (P0-4 regression) ---
# Extract functions without executing sdd.sh's CLI dispatcher.
if [ -f "$D/scripts/lib/sdd-common.sh" ]; then
    # shellcheck disable=SC1091
    . "$D/scripts/lib/sdd-common.sh"
fi
eval "$(sed -n '/^ensure_session_file/,/^}/p; /^set_val/,/^}/p; /^get_val/,/^}/p; /^resolve_plan_file/,/^}/p; /^calc_plan_hash/,/^}/p' ./sdd.sh)"
SESSION_FILE=SESSION.md
set_val "nueva_clave" "123"
grep -q '^nueva_clave: 123$' SESSION.md || fail "set_val did not insert new key"
[ "$(grep -c '^nueva_clave:' SESSION.md)" = "1" ] || fail "new key duplicated"
# key must be inside frontmatter (before 2nd ---), not in body
awk '/^---$/{c++; next} c==1 && /^nueva_clave:/{found=1} END{exit !found}' SESSION.md || fail "new key outside frontmatter"
# updating it again must not duplicate
set_val "nueva_clave" "456"
[ "$(grep -c '^nueva_clave:' SESSION.md)" = "1" ] || fail "update duplicated key"
grep -q '^nueva_clave: 456$' SESSION.md || fail "update did not replace value"

echo "test-sdd-state: all assertions passed"
