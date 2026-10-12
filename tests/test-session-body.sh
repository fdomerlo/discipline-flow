#!/usr/bin/env bash
# tests/test-session-body.sh — sdd.sh refreshes machine-owned SESSION body
# fields on every transition; agent-owned prose is never touched.
# Regression: body frozen since F1 while frontmatter reached F5.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
mkdir -p "$D/scripts/lib"
cp "$REPO_ROOT/scripts/sdd.sh" "$D/scripts/sdd.sh"
cp "$D/scripts/sdd.sh" "$D/sdd.sh"
cp "$REPO_ROOT/scripts/lib/sdd-common.sh" "$D/scripts/lib/sdd-common.sh"
cp "$REPO_ROOT/scripts/verify-crit.sh" "$D/scripts/verify-crit.sh" 2>/dev/null || true
cp "$REPO_ROOT/scripts/new-plan.sh" "$D/scripts/new-plan.sh" 2>/dev/null || true
cd "$D" || exit 1
git init -q
git config user.email "test@test.local"
git config user.name "test"
git commit -q --allow-empty -m "init"

# Stale body as reported: frontmatter will move to F5, body frozen at F1.
cat > SESSION.md <<'EOF'
---
sdd_state: execute
active_task: F1
active_agent: none
plan_hash: none
---
# Session Checkpoint

- **Plan:** plans/PLAN-1.md
- **Phase:** F1
- **Status:** Initialized
- **Updated:** 2020-01-01T00:00:00Z
- **Base commit:** deadbee

## Completed in this session
- Finished F1 login work

## Current working state
- F1 done, F2-F5 sketched

## Next action
- Create plan with ./scripts/sdd.sh plan "<title>"

## Open decisions
- Token TTL under debate

## Verification
- Human review: pending
EOF
mkdir -p plans
printf '# plan\n' > plans/PLAN-1.md
git add -A
git commit -qm "fixture"

# --- start F5 refreshes machine fields, preserves prose ---
BEFORE_TS="2020-01-01T00:00:00Z"
bash ./sdd.sh start F5 >/dev/null
grep -q '^- \*\*Status:\*\* Phase F5 in progress$' SESSION.md || fail "Status must track F5"
grep -q '^- \*\*Phase:\*\* F5$' SESSION.md || fail "Phase bullet must track F5"
grep -q '^- \*\*Next action' SESSION.md && fail "Next action must stay a section header"
grep -q 'F5' SESSION.md || fail "Next action must mention F5"
grep -qv "^- \*\*Updated:\*\* $BEFORE_TS$" SESSION.md || fail "Updated must be refreshed"
grep -qE '^- \*\*Updated:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}T' SESSION.md || fail "Updated must be ISO UTC"
grep -q '^- \*\*Phase-start commit:\*\* [0-9a-f]\{4,\}$' SESSION.md || fail "phase-start marker must exist"
grep -q '^- Finished F1 login work$' SESSION.md || fail "Completed prose must survive"
grep -q '^- F1 done, F2-F5 sketched$' SESSION.md || fail "Working-state prose must survive"
grep -q '^- Token TTL under debate$' SESSION.md || fail "Open-decisions prose must survive"
grep -q 'Create plan with' SESSION.md && fail "stale Next action must be replaced"
AFTER_TS=$(sed -n 's/^- \*\*Updated:\*\* //p' SESSION.md)
[ "$AFTER_TS" != "$BEFORE_TS" ] || fail "Updated timestamp must change"

# --- Updated actually moves forward between transitions ---
sleep 1.2
bash ./sdd.sh advance plan >/dev/null
grep -q '^- \*\*Status:\*\* Plan review, awaiting approval$' SESSION.md || fail "advance plan must reset Status"
TS2=$(sed -n 's/^- \*\*Updated:\*\* //p' SESSION.md)
[ "$TS2" != "$AFTER_TS" ] || fail "Updated must move on advance plan"

# --- verify refreshes to audit state ---
printf -- '---\nsdd_state: execute\nactive_task: F1\nactive_agent: none\nplan_hash: none\n---\n# Session Checkpoint\n\n- **Plan:** plans/PLAN-1.md\n- **Phase:** F1\n- **Status:** Phase F1 in progress\n- **Updated:** 2020-01-01T00:00:00Z\n- **Base commit:** none\n\n## Next action\n\nWork F1\n' > SESSION.md
cat > plans/PLAN-1.md <<'EOF'
# PLAN-1 — Demo

## F1 — Demo

### Acceptance criteria
- [ ] CRIT-01: covered
EOF
mkdir -p src
printf '# CRIT-01: proof\n' > src/code.py
git add -A
git commit -qm "feat(F1): evidence"
bash ./sdd.sh verify F1 >/dev/null 2>&1 || fail "verify should pass"
grep -q '^- \*\*Status:\*\* phase-closed, awaiting human audit$' SESSION.md || fail "verify must set audit Status"
grep -q 'auditar el diff\|Auditar el diff' SESSION.md || fail "verify must set audit Next action"
grep -q '^sdd_state: verify$' SESSION.md || fail "frontmatter must reach verify"

echo "test-session-body: all assertions passed"
