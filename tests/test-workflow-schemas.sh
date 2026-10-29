#!/usr/bin/env bash
# tests/test-workflow-schemas.sh — Validates JSON schemas, sdd_cycle.py AST,
# verify-crit.sh --json output, open-decision blocking, and sdd.sh orchestrate payload.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDD="$REPO_ROOT/scripts/sdd.sh"
VERIFY="$REPO_ROOT/scripts/verify-crit.sh"

fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

# 1. Validate JSON Schemas & workflow.json
python3 - "$REPO_ROOT" <<'PYEOF' || fail "Schema or workflow AST validation failed"
import ast
import json
import os
import sys

root = sys.argv[1]
schemas = [
    "assets/schemas/spec_verification.json",
    "assets/schemas/task_breakdown.json",
    "assets/schemas/audit_verdict.json",
    "assets/schemas/session_state.json",
    "workflows/workflow.json",
]

for rel in schemas:
    p = os.path.join(root, rel)
    assert os.path.isfile(p), f"Missing file: {rel}"
    with open(p, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert isinstance(data, dict), f"Invalid JSON root in {rel}"

wf_path = os.path.join(root, "workflows", "sdd_cycle.py")
assert os.path.isfile(wf_path), "Missing workflows/sdd_cycle.py"
with open(wf_path, "r", encoding="utf-8") as f:
    src = f.read()

compile(src, wf_path, "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)

for required_token in [
    'phase("Audit Spec")',
    'phase("Atomic Implementation")',
    'phase("Mechanical Gate")',
    'phase("Doubt-Driven Audit")',
    'workspace="branch"',
    '"run_command"',
]:
    assert required_token in src, f"Missing token {required_token} in sdd_cycle.py"
PYEOF

# 2. Test verify-crit.sh --json and sdd.sh orchestrate in a hermetic git repo
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
cd "$D" || exit 1
git init -q
git config user.email "test@test.local"
git config user.name "test"

mkdir -p plans src
cat > plans/PLAN-1.md <<'EOF'
# PLAN-1 — JSON & Orchestrate Test

## F1 — Phase 1

### Acceptance criteria
- [ ] CRIT-01: automated check
- [ ] CRIT-02: (manual) human check
EOF

printf '# CRIT-01: verified in test\n' > src/app.py
git add -A
git commit -qm "init"

bash "$SDD" start F1 tester >/dev/null

# 2a. Passing verify-crit.sh --json
JSON_PASS=$(TEST_COMMAND=true bash "$VERIFY" --json plans/PLAN-1.md F1)
python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["passed"] is True, d
assert d["exit_code"] == 0, d
assert d["stage"] == "complete", d
assert d["automated_count"] == 1, d
assert d["manual_count"] == 1, d
assert d["failures"] == 0, d
assert d["test_suite_passed"] is True, d
' "$JSON_PASS" || fail "verify-crit.sh --json pass payload invalid: $JSON_PASS"

# 2b. sdd.sh orchestrate F1 emits valid JSON for run_workflow
ORCH_JSON=$(TEST_COMMAND="pytest -q" bash "$SDD" orchestrate F1 --lint-cmd "flake8")
python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["tool"] == "run_workflow", d
assert d["ScriptPath"].endswith("workflows/sdd_cycle.py"), d
assert d["Args"]["phase_id"] == "F1", d
assert d["Args"]["plan_file"] == "plans/PLAN-1.md", d
assert d["Args"]["test_cmd"] == "pytest -q", d
assert d["Args"]["lint_cmd"] == "flake8", d
' "$ORCH_JSON" || fail "sdd.sh orchestrate payload invalid: $ORCH_JSON"

# 2c. Failing verify-crit.sh --json on missing CRIT-03 (exit 2)
echo "- [ ] CRIT-03: missing test" >> plans/PLAN-1.md
set +e
JSON_FAIL=$(TEST_COMMAND=true bash "$VERIFY" --json plans/PLAN-1.md F1)
FAIL_RC=$?
set -e
[ "$FAIL_RC" -eq 2 ] || fail "Expected exit code 2 for missing CRIT-03, got $FAIL_RC"
python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["passed"] is False, d
assert d["exit_code"] == 2, d
assert d["stage"] == "traceability", d
assert "CRIT-03" in d["missing_crits"], d
' "$JSON_FAIL" || fail "verify-crit.sh --json failure payload invalid: $JSON_FAIL"

# 2d. Failing verify-crit.sh --json on unresolved '## DECISIÓN ABIERTA' (exit 2)
printf '\n## DECISIÓN ABIERTA\nPending architectural choice.\n' >> plans/PLAN-1.md
set +e
JSON_OPEN=$(TEST_COMMAND=true bash "$VERIFY" --json plans/PLAN-1.md F1)
OPEN_RC=$?
set -e
[ "$OPEN_RC" -eq 2 ] || fail "Expected exit code 2 for DECISIÓN ABIERTA, got $OPEN_RC"
python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["passed"] is False, d
assert d["exit_code"] == 2, d
assert d["stage"] == "open_decision", d
' "$JSON_OPEN" || fail "verify-crit.sh --json open_decision payload invalid: $JSON_OPEN"

echo "test-workflow-schemas: all assertions passed"
