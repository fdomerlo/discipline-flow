#!/usr/bin/env bash
# tests/test-crit-search.sh — verify-crit.sh CRIT search: expanded dirs,
# *.md exclusion (no self-match on PLAN), CRIT_SEARCH_PATHS override.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D" || exit 1
git init -q
git config user.email "test@test.local"
git config user.name "test"

# Layout with new P1-8 dirs: e2e/, __tests__/, pkg/ must be searched.
mkdir -p e2e __tests__ pkg src plans
cat > plans/PLAN-1.md <<'EOF'
# PLAN-1 — Demo

## F1 — Demo phase

### Acceptance criteria
- [ ] CRIT-01: e2e covered
- [ ] CRIT-02: pkg covered
- [ ] CRIT-03: (manual) human check
- [ ] CRIT-04: missing evidence
EOF
printf -- '---\nsdd_state: execute\nactive_task: F1\nplan_hash: none\n---\n- **Plan:** plans/PLAN-1.md\n' > SESSION.md
printf '// CRIT-01: e2e proof\n' > e2e/checkout.test.js
printf '# CRIT-02: pkg proof\n' > pkg/worker.py
git add -A
git commit -qm "test: fixture (F1)"

VERIFY="$REPO_ROOT/scripts/verify-crit.sh"

# --- CRIT-01 in e2e/ and CRIT-02 in pkg/ must be found (new dirs) ---
OUT=$(CRIT_SEARCH_PATHS="tests test __tests__ spec e2e src lib pkg internal app" TEST_COMMAND=true bash "$VERIFY" plans/PLAN-1.md F1 2>&1 || true)
echo "$OUT" | grep -q 'CRIT-01.*Localizado' || fail "CRIT-01 in e2e/ not found: $OUT"
echo "$OUT" | grep -q 'CRIT-02.*Localizado' || fail "CRIT-02 in pkg/ not found: $OUT"
echo "$OUT" | grep -q 'CRIT-03.*Manual' || fail "CRIT-03 manual not classified: $OUT"

# --- CRIT-04 with no evidence must fail (exit 2), not silently pass ---
if CRIT_SEARCH_PATHS="tests test __tests__ spec e2e src lib pkg internal app" TEST_COMMAND=true bash "$VERIFY" plans/PLAN-1.md F1 >/dev/null 2>&1; then
    fail "verify should fail with CRIT-04 missing"
fi

# --- *.md exclusion: evidence only in a .md file must NOT count ---
printf 'CRIT-04 mentioned only in prose\n' > notes.md
git add -A
git commit -qm "docs: prose mention (F1)"
if CRIT_SEARCH_PATHS="tests test __tests__ spec e2e src lib pkg internal app" TEST_COMMAND=true bash "$VERIFY" plans/PLAN-1.md F1 >/dev/null 2>&1; then
    fail "md-only mention must not satisfy CRIT-04"
fi
# real code evidence fixes it
printf '# CRIT-04: real test\n' > src/fix.py
git add -A
git commit -qm "test: real evidence (F1)"
CRIT_SEARCH_PATHS="tests test __tests__ spec e2e src lib pkg internal app" TEST_COMMAND=true bash "$VERIFY" plans/PLAN-1.md F1 >/dev/null 2>&1 || fail "verify should pass once code evidence exists"

echo "test-crit-search: all assertions passed"
