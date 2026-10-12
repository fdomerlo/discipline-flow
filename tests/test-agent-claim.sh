#!/usr/bin/env bash
# tests/test-agent-claim.sh — sdd.sh start [agente]: claim, release, warning.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/scripts/lib"
cp "$REPO_ROOT/scripts/sdd.sh" "$D/scripts/sdd.sh"
cp "$D/scripts/sdd.sh" "$D/sdd.sh"
cp "$REPO_ROOT/scripts/lib/sdd-common.sh" "$D/scripts/lib/sdd-common.sh"
cd "$D" || exit 1
git init -q
git config user.email "test@test.local"
git config user.name "test"
git commit -q --allow-empty -m "init"

# --- claim records agent + phase-start marker ---
bash ./sdd.sh start F1 alice >/dev/null
[ "$(bash -c '. ./scripts/lib/sdd-common.sh; SESSION_FILE=SESSION.md sdd_get_val active_agent')" = "alice" ] || fail "agent should be alice"
grep -q '^- \*\*Phase-start commit:' SESSION.md || fail "missing phase-start marker"

# --- status shows agent ---
bash ./sdd.sh status | grep -q 'Agente activo  : alice' || fail "status should show alice"

# --- conflicting claim warns but proceeds (audit trail, not a lock) ---
OUT=$(bash ./sdd.sh start F1 bob 2>&1)
echo "$OUT" | grep -q "reclamada por el agente 'alice'" || fail "conflicting claim should warn, got: $OUT"
[ "$(bash -c '. ./scripts/lib/sdd-common.sh; SESSION_FILE=SESSION.md sdd_get_val active_agent')" = "bob" ] || fail "agent should now be bob"

# --- same agent re-claim: no warning ---
OUT=$(bash ./sdd.sh start F1 bob 2>&1)
echo "$OUT" | grep -q "reclamada" && fail "same-agent re-claim must not warn"

# --- start without agent releases claim ---
bash ./sdd.sh start F2 >/dev/null
[ "$(bash -c '. ./scripts/lib/sdd-common.sh; SESSION_FILE=SESSION.md sdd_get_val active_agent')" = "none" ] || fail "agent should reset to none"

# --- advance plan releases claim ---
bash ./sdd.sh start F2 carol >/dev/null
bash ./sdd.sh advance plan >/dev/null
[ "$(bash -c '. ./scripts/lib/sdd-common.sh; SESSION_FILE=SESSION.md sdd_get_val active_agent')" = "none" ] || fail "advance plan should reset agent"

echo "test-agent-claim: all assertions passed"
