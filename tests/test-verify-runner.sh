#!/usr/bin/env bash
# tests/test-verify-runner.sh — TEST_COMMAND preserves quoted args (P2-11).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$REPO_ROOT/scripts/verify-crit.sh"
fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D" || exit 1
git init -q
git config user.email "test@test.local"
git config user.name "test"
mkdir -p plans src
cat > plans/PLAN-1.md <<'EOF'
# PLAN-1 — Demo

## F1 — Demo phase

### Acceptance criteria
- [ ] CRIT-01: covered
EOF
printf '# CRIT-01: proof\n' > src/code.py
printf -- '---\nsdd_state: execute\nactive_task: F1\nplan_hash: none\n---\n- **Plan:** plans/PLAN-1.md\n' > SESSION.md
git add -A
git commit -qm "init"

# Quoted arg with a space must arrive intact (old `$TEST_COMMAND` split broke it).
OUT=$(TEST_COMMAND='printf "%s\n" "a b"' bash "$VERIFY" plans/PLAN-1.md F1 2>&1) || fail "verify should pass: $OUT"
echo "$OUT" | grep -q '^a b$' || fail "quoted arg not preserved, got: $OUT"

echo "test-verify-runner: all assertions passed"
