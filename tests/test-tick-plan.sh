#!/usr/bin/env bash
# tests/test-tick-plan.sh — verify must tick the plan (phase + cycle criteria)
# only after traceability and the suite are green; manual criteria stay human.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDD="$REPO_ROOT/scripts/sdd.sh"
TICK="$REPO_ROOT/scripts/tick-plan.sh"
fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D" || exit 1
git init -q
git config user.email "test@test.local"
git config user.name "test"
mkdir -p plans tests
cat > plans/PLAN-1.md <<'EOF'
# PLAN-1 — Demo

## F1 — First
### Acceptance criteria
- [ ] CRIT-01: auto one
- [ ] CRIT-02: (manual) eyeball one
- [ ] CRIT-03: (manual) eyeball two

## F2 — Second
### Acceptance criteria
- [ ] CRIT-04: auto two

## F10 — Tenth (must not be touched by F1)
### Acceptance criteria
- [ ] CRIT-05: auto ten

## Out of scope

- nothing

## Criteria for the whole cycle

- [ ] Full suite green.
- [ ] Every phase's acceptance criteria met and demonstrated.
- [ ] Nothing from "Out of scope" leaked into a phase diff.
EOF
printf '#!/bin/sh\n# CRIT-01 CRIT-04 CRIT-05\nexit 0\n' > tests/run.sh
chmod +x tests/run.sh
git add -A
git commit -qm "chore: init" --no-verify

bash "$SDD" plan >/dev/null
bash "$SDD" start F1 >/dev/null
# CRIT-ids must be searchable in tests/ for verify to pass.
OUT=$(bash "$SDD" verify F1 2>&1) || fail "verify F1 should pass (2 manual crits must not crash): $OUT"

grep -q '^- \[x\] CRIT-01' plans/PLAN-1.md || fail "CRIT-01 not ticked"
grep -q '^- \[ \] CRIT-02' plans/PLAN-1.md || fail "manual CRIT-02 must stay unticked"
grep -q '^- \[ \] CRIT-03' plans/PLAN-1.md || fail "manual CRIT-03 must stay unticked"
grep -q '^- \[ \] CRIT-04' plans/PLAN-1.md || fail "F2 criterion ticked by F1 verify"
grep -q '^- \[ \] CRIT-05' plans/PLAN-1.md || fail "F10 criterion ticked by F1 verify"
echo "$OUT" | grep -q '2 manuales pendientes' || fail "manual count wrong: $OUT"
grep -q '^- \[ \] Full suite green' plans/PLAN-1.md || fail "cycle criterion ticked too early"

# Plan hash re-frozen: tick must not look like spec drift.
STATUS=$(bash "$SDD" status 2>&1)
echo "$STATUS" | grep -q 'ÍNTEGRO' || fail "plan hash drift after tick: $STATUS"

# Failing suite => nothing ticked.
bash "$SDD" start F2 >/dev/null
printf '#!/bin/sh\n# CRIT-01 CRIT-04 CRIT-05\nexit 1\n' > tests/run.sh
if bash "$SDD" verify F2 >/dev/null 2>&1; then fail "verify must fail with red suite"; fi
grep -q '^- \[ \] CRIT-04' plans/PLAN-1.md || fail "ticked despite red suite"

# Green again: F2 and F10 done -> automated cycle criteria derive, manual blocks 'Every phase'.
printf '#!/bin/sh\n# CRIT-01 CRIT-04 CRIT-05\nexit 0\n' > tests/run.sh
bash "$SDD" verify F2 >/dev/null 2>&1 || fail "verify F2 should pass"
bash "$SDD" start F10 >/dev/null
bash "$SDD" verify F10 >/dev/null 2>&1 || fail "verify F10 should pass"
grep -q '^- \[x\] CRIT-05' plans/PLAN-1.md || fail "CRIT-05 not ticked"
grep -q '^- \[x\] Full suite green' plans/PLAN-1.md || fail "Full suite green not ticked"
grep -q '^- \[ \] Every phase' plans/PLAN-1.md || fail "'Every phase' ticked while manual criteria pending"

# Human ticks the manual ones; cycle recomputes; scope-clean is explicit.
sed -i 's/^- \[ \] CRIT-02/- [x] CRIT-02/; s/^- \[ \] CRIT-03/- [x] CRIT-03/' plans/PLAN-1.md
N=$(bash "$TICK" cycle plans/PLAN-1.md)
[[ "$N" == "1" ]] || fail "expected 1 cycle tick, got $N"
grep -q '^- \[x\] Every phase' plans/PLAN-1.md || fail "'Every phase' not ticked"
grep -q '^- \[ \] Nothing from' plans/PLAN-1.md || fail "scope line must wait for the C2 audit"
bash "$TICK" scope-clean plans/PLAN-1.md >/dev/null
grep -q '^- \[x\] Nothing from' plans/PLAN-1.md || fail "scope-clean did not tick"

# Idempotent.
N=$(bash "$TICK" all plans/PLAN-1.md)
[[ "$N" == "0" ]] || fail "tick must be idempotent, got $N"

echo "test-tick-plan: all assertions passed"
