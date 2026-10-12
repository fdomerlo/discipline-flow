#!/usr/bin/env bash
# tests/test-init-nocopy.sh — init.sh references the skill in place.
# Regression: scripts/assets must never be copied into the target project.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

# Fake installed skill (as it would sit under .agents/skills/).
mkdir -p "$D/.agents/skills/discipline-flow"
cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/assets" "$D/.agents/skills/discipline-flow/"
SKILL="$D/.agents/skills/discipline-flow"

# --- 1. fresh bootstrap copies nothing, points at the skill ---
bash "$SKILL/scripts/init.sh" -d "$D/proj" -t "./tests/run.sh" -p "demo" >/tmp/opencode-init.log 2>&1
[ ! -e "$D/proj/scripts" ] || fail "scripts/ must not be copied into the project"
[ ! -e "$D/proj/assets" ] || fail "assets/ must not be copied into the project"
grep -q ".agents/skills/discipline-flow/scripts/sdd.sh" "$D/proj/AGENTS.md" || fail "AGENTS.md must reference the skill path"
grep -q "{{SKILL_PATH}}" "$D/proj/AGENTS.md" && fail "unsubstituted placeholder in AGENTS.md"
[ -x "$D/proj/.git/hooks/pre-commit" ] || fail "pre-commit hook missing"
[ -x "$D/proj/.git/hooks/commit-msg" ] || fail "commit-msg hook missing"
grep -q ".agents/skills/discipline-flow/scripts/lib/sdd-common.sh" "$D/proj/.git/hooks/pre-commit" || fail "hook must bake the skill lib path"
grep -q "{{SKILL_PATH}}" "$D/proj/.git/hooks/pre-commit" && fail "unbaked placeholder in pre-commit"
grep -q "{{SKILL_PATH}}" "$D/proj/.git/hooks/commit-msg" && fail "unbaked placeholder in commit-msg"

# --- 2. installed hooks enforce using the in-place skill CLI ---
cd "$D/proj" || exit 1
git config user.email "test@test.local"
git config user.name "test"
bash "$SKILL/scripts/sdd.sh" start F1 >/dev/null
mkdir -p src
printf 'x\n' > src/code.py
git add -A
git commit -qm "feat(F1): in-place skill works"
git commit -q --allow-empty -m "fix: missing token" 2>/dev/null && fail "hook must block token-less commit"
echo "hook enforcement via installed paths: ok"
cd "$D" || exit 1

# --- 3. legacy vendored copies are flagged, not recopied ---
mkdir -p "$D/proj2/scripts"
printf 'stale\n' > "$D/proj2/scripts/sdd.sh"
bash "$SKILL/scripts/init.sh" -d "$D/proj2" -t "true" -p "demo2" > /tmp/opencode-init2.log 2>&1
grep -q "legacy vendored copy" /tmp/opencode-init2.log || fail "legacy copy should be flagged"
[ "$(cat "$D/proj2/scripts/sdd.sh")" = "stale" ] || fail "legacy copy must be left untouched"
[ ! -e "$D/proj2/assets" ] || fail "assets/ must not be copied (legacy project)"

# --- 4. --self resolves to ./scripts/... ---
mkdir -p "$D/selfskill"
cp -r "$REPO_ROOT/scripts" "$REPO_ROOT/assets" "$D/selfskill/"
bash "$D/selfskill/scripts/init.sh" --self -t "true" >/dev/null 2>&1
grep -q "./scripts/sdd.sh" "$D/selfskill/AGENTS.md" || fail "--self must resolve to ./scripts/..."
grep -q "{{SKILL_PATH}}" "$D/selfskill/AGENTS.md" && fail "unsubstituted placeholder in --self AGENTS.md"

rm -f /tmp/opencode-init.log /tmp/opencode-init2.log
echo "test-init-nocopy: all assertions passed"
