#!/usr/bin/env bash
# tests/test-bypass-audit.sh — verify fails on code commits without phase
# token after the phase-start marker; passes when clean; skips without marker.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$REPO_ROOT/scripts/verify-crit.sh"
fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

setup_repo() {
    D=$(mktemp -d)
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
    git add -A
    git commit -qm "init"
}

# --- 1. evasor commit fails the gate ---
setup_repo
_EVASOR_D="$D"
printf -- '---\nsdd_state: execute\nactive_task: F1\nactive_agent: none\nplan_hash: none\n---\n- **Plan:** plans/PLAN-1.md\n- **Phase:** F1\n- **Phase-start commit:** '"$(git rev-parse HEAD)"'\n' > SESSION.md
printf 'sneaky\n' >> src/code.py
git add -A
git commit -qm "fix: sneaky change without token"
if TEST_COMMAND=true bash "$VERIFY" plans/PLAN-1.md F1 >/tmp/opencode-bypass1.log 2>&1; then
    fail "verify must fail on token-less code commit"
fi
grep -q 'bypass' /tmp/opencode-bypass1.log || fail "failure should mention bypass audit"
cd / && rm -rf "$_EVASOR_D"

# --- 2. clean history passes ---
setup_repo
_CLEAN_D="$D"
printf -- '---\nsdd_state: execute\nactive_task: F1\nactive_agent: none\nplan_hash: none\n---\n- **Plan:** plans/PLAN-1.md\n- **Phase:** F1\n- **Phase-start commit:** '"$(git rev-parse HEAD)"'\n' > SESSION.md
printf 'more\n' >> src/code.py
git add -A
git commit -qm "feat(F1): legit change"
TEST_COMMAND=true bash "$VERIFY" plans/PLAN-1.md F1 >/tmp/opencode-bypass2.log 2>&1 || fail "clean history should pass"
grep -q 'Bypass audit: limpia' /tmp/opencode-bypass2.log || fail "should report clean audit"
cd / && rm -rf "$_CLEAN_D"

# --- 3. docs-only commit without token does NOT fail ---
setup_repo
_DOCS_D="$D"
printf -- '---\nsdd_state: execute\nactive_task: F1\nactive_agent: none\nplan_hash: none\n---\n- **Plan:** plans/PLAN-1.md\n- **Phase:** F1\n- **Phase-start commit:** '"$(git rev-parse HEAD)"'\n' > SESSION.md
printf 'prose\n' > notes.md
git add -A
git commit -qm "docs: prose without token"
TEST_COMMAND=true bash "$VERIFY" plans/PLAN-1.md F1 >/dev/null 2>&1 || fail "docs-only commit must not fail bypass audit"
cd / && rm -rf "$_DOCS_D"

# --- 4. no marker: skipped, still passes (backward compat) ---
setup_repo
_NOMARK_D="$D"
printf -- '---\nsdd_state: execute\nactive_task: F1\nplan_hash: none\n---\n- **Plan:** plans/PLAN-1.md\n' > SESSION.md
TEST_COMMAND=true bash "$VERIFY" plans/PLAN-1.md F1 >/tmp/opencode-bypass4.log 2>&1 || fail "no-marker session should pass"
grep -q 'omitida' /tmp/opencode-bypass4.log || fail "should report skipped audit"
cd / && rm -rf "$_NOMARK_D"

rm -f /tmp/opencode-bypass1.log /tmp/opencode-bypass2.log /tmp/opencode-bypass4.log
echo "test-bypass-audit: all assertions passed"
