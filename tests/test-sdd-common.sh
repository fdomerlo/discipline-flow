#!/usr/bin/env bash
# tests/test-sdd-common.sh — sdd-common.sh: get_val + resolve_plan + calc_hash.
# Hermetic: uses mktemp sandbox, never touches repo SESSION.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/sdd-common.sh"

fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

[ -f "$LIB" ] || fail "lib missing: $LIB"
# shellcheck source=../scripts/lib/sdd-common.sh
. "$LIB"

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D" || exit 1

# --- sdd_get_val: missing file -> none ---
[ "$(SESSION_FILE="$D/nonexistent.md" sdd_get_val sdd_state)" = "none" ] || fail "missing file should be none"

# --- sdd_get_val: reads frontmatter, ignores body ---
cat > SESSION.md <<'EOF'
---
sdd_state: execute
active_task: F2
plan_hash: abc123
---
# Body mentions sdd_state: plan (must be ignored)
EOF
[ "$(sdd_get_val sdd_state)" = "execute" ] || fail "sdd_state should be execute"
[ "$(sdd_get_val active_task)" = "F2" ] || fail "active_task should be F2"
[ "$(sdd_get_val plan_hash)" = "abc123" ] || fail "plan_hash should be abc123"
[ "$(sdd_get_val missing_key)" = "" ] || fail "missing key should be empty"

# --- sdd_calc_hash: missing -> none, existing -> sha256 ---
[ "$(sdd_calc_hash "$D/nope.md")" = "none" ] || fail "hash missing should be none"
printf 'hello' > f.txt
EXPECTED=$(sha256sum f.txt | awk '{print $1}')
[ "$(sdd_calc_hash f.txt)" = "$EXPECTED" ] || fail "hash mismatch"

# --- sdd_resolve_plan priority: SESSION ref > plans/ (canonical) > root (legacy) ---
mkdir -p plans
printf '# root legacy\n' > PLAN-1.md
printf '# canonical\n' > plans/PLAN-2.md
# no SESSION ref yet: canonical plans/ wins over root
[ "$(SESSION_FILE=/dev/null sdd_resolve_plan /dev/null)" = "plans/PLAN-2.md" ] || fail "canonical plans/ should win, got: $(sdd_resolve_plan /dev/null)"
# SESSION ref to root legacy wins when explicitly referenced
printf -- '---\nsdd_state: plan\nactive_task: none\nplan_hash: none\n---\n- **Plan:** PLAN-1.md\n' > SESSION.md
[ "$(sdd_resolve_plan SESSION.md)" = "PLAN-1.md" ] || fail "SESSION ref should win"
# dangling SESSION ref falls back to canonical
printf -- '---\nsdd_state: plan\nactive_task: none\nplan_hash: none\n---\n- **Plan:** plans/PLAN-99.md\n' > SESSION.md
[ "$(sdd_resolve_plan SESSION.md)" = "plans/PLAN-2.md" ] || fail "dangling ref should fall back to plans/"

echo "test-sdd-common: all assertions passed"
