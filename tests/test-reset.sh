#!/usr/bin/env bash
# tests/test-reset.sh — reset.sh removes skill traces, preserves foreign content.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESET="$REPO_ROOT/scripts/reset.sh"
fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }
[ -x "$RESET" ] || fail "reset.sh missing/executable"

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

build_fixture() {
    local p="$1"
    mkdir -p "$p/scripts" "$p/plans/archive" "$p/src"
    printf -- '---\nsdd_state: execute\nactive_task: F1\nplan_hash: none\n---\n' > "$p/SESSION.md"
    printf '# plan\n' > "$p/PLAN-1.md"
    printf '# plan\n' > "$p/plans/PLAN-2.md"
    printf '# plan\n' > "$p/plans/archive/PLAN-1.md"
    printf 'code\n' > "$p/src/code.py"
    git -C "$p" init -q
    git -C "$p" config user.email "test@test.local"
    git -C "$p" config user.name "test"
    git -C "$p" add -A
    git -C "$p" commit -qm "init"
}

# --- 1. dry run changes nothing ---
build_fixture "$D/dry"
bash "$RESET" -d "$D/dry" --dry-run > /tmp/opencode-reset1.log 2>&1
[ -f "$D/dry/SESSION.md" ] || fail "dry run must not remove SESSION.md"
[ -f "$D/dry/plans/PLAN-2.md" ] || fail "dry run must not remove plans"
grep -q "dry run" /tmp/opencode-reset1.log || fail "dry run should say so"

# --- 2. full reset removes everything ours, keeps code ---
build_fixture "$D/full"
printf '<!-- BEGIN DISCIPLINE-FLOW -->\ncontract\n<!-- END DISCIPLINE-FLOW -->\n' > "$D/full/AGENTS.md"
printf '@AGENTS.md\n' > "$D/full/CLAUDE.md"
cp "$REPO_ROOT/scripts/pre-commit-hook.sh" "$D/full/.git/hooks/pre-commit"
cp "$REPO_ROOT/scripts/commit-msg-hook.sh" "$D/full/.git/hooks/commit-msg"
cp "$REPO_ROOT/scripts/sdd.sh" "$D/full/scripts/sdd.sh"
bash "$RESET" -d "$D/full" --force > /tmp/opencode-reset2.log 2>&1
for f in SESSION.md PLAN-1.md plans/PLAN-2.md plans/archive/PLAN-1.md AGENTS.md CLAUDE.md .git/hooks/pre-commit .git/hooks/commit-msg scripts/sdd.sh; do
    [ ! -e "$D/full/$f" ] || fail "should be removed: $f"
done
[ ! -d "$D/full/plans" ] || fail "empty plans/ should be rmdir'd"
[ -f "$D/full/src/code.py" ] || fail "project code must survive"
# hooks gone: commits flow without gates
printf 'more\n' >> "$D/full/src/code.py"
git -C "$D/full" add -A
git -C "$D/full" commit -qm "whatever: no gates left"

# --- 2b. piped stdin without --force aborts (no accidental confirm) ---
build_fixture "$D/piped"
printf 'y\n' | bash "$RESET" -d "$D/piped" >/tmp/opencode-reset2b.log 2>&1 && fail "piped y without --force must abort"
[ -f "$D/piped/SESSION.md" ] || fail "aborted reset must change nothing"

# --- 3. foreign content preserved with warnings ---
build_fixture "$D/foreign"
printf '# my rules\n<!-- BEGIN DISCIPLINE-FLOW -->\ncontract\n<!-- END DISCIPLINE-FLOW -->\n' > "$D/foreign/AGENTS.md"
printf '#!/bin/sh\necho custom hook\n' > "$D/foreign/.git/hooks/pre-commit"
printf '# custom docs\n' > "$D/foreign/CLAUDE.md"
printf 'customized\n' > "$D/foreign/scripts/sdd.sh"
bash "$RESET" -d "$D/foreign" --force > /tmp/opencode-reset3.log 2>&1
grep -q "# my rules" "$D/foreign/AGENTS.md" || fail "custom AGENTS.md rules must survive"
grep -q "DISCIPLINE-FLOW" "$D/foreign/AGENTS.md" && fail "managed block must be stripped"
[ -f "$D/foreign/.git/hooks/pre-commit" ] || fail "foreign hook must survive"
grep -q "custom hook" "$D/foreign/.git/hooks/pre-commit" || fail "foreign hook content intact"
[ -f "$D/foreign/CLAUDE.md" ] || fail "custom CLAUDE.md must survive"
[ -f "$D/foreign/scripts/sdd.sh" ] || fail "customized script must survive"
grep -q "left untouched" /tmp/opencode-reset3.log || fail "skips should be reported"

# --- 4. non-tty without --force aborts ---
build_fixture "$D/noint"
if bash "$RESET" -d "$D/noint" < /dev/null >/tmp/opencode-reset4.log 2>&1; then
    fail "non-interactive without --force must abort"
fi
[ -f "$D/noint/SESSION.md" ] || fail "aborted reset must change nothing"

# --- 5. refuse skill repo itself without --self ---
if bash "$RESET" -d "$REPO_ROOT" --dry-run >/dev/null 2>&1; then
    fail "resetting the skill repo without --self must fail"
fi

rm -f /tmp/opencode-reset1.log /tmp/opencode-reset2.log /tmp/opencode-reset2b.log /tmp/opencode-reset3.log /tmp/opencode-reset4.log
echo "test-reset: all assertions passed"
