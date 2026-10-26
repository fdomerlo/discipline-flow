#!/usr/bin/env bash
# tests/test-workflows.sh — End-to-end deterministic tests for workflows/sdd_*.py
# and the pre-commit secret/key security gate.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "ASSERT FAIL: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 required for workflow tests"

# --- 1. Syntax & top-level await compilation check for all workflows/*.py ---
python3 - "$REPO_ROOT/workflows" <<'PY'
import ast, glob, os, sys

wf_dir = sys.argv[1]
files = sorted(glob.glob(os.path.join(wf_dir, "*.py")))
assert len(files) == 4, f"Expected 4 workflows, found {files}"
for path in files:
    with open(path, "r", encoding="utf-8") as f:
        src = f.read()
    compile(src, path, "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)
    assert "from ." not in src, f"Local imports forbidden in {path}"
PY

# --- 2. Test sdd_doubt.py: Claim isolation & Doubt Theater detection ---
python3 - "$REPO_ROOT/workflows/sdd_doubt.py" <<'PY'
import ast, asyncio, io, json, sys
from contextlib import redirect_stdout

wf_path = sys.argv[1]
with open(wf_path, "r", encoding="utf-8") as f:
    src = f.read()

code_obj = compile(src, wf_path, "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)

async def run_doubt(args_dict, agent_fn):
    logs, phases = [], []
    env = {
        "__builtins__": __builtins__,
        "args": args_dict,
        "log": lambda *a: logs.append(" ".join(str(x) for x in a)),
        "phase": lambda name: phases.append(name),
        "agent": agent_fn,
    }
    buf = io.StringIO()
    with redirect_stdout(buf):
        coro = eval(code_obj, env)
        if asyncio.iscoroutine(coro):
            await coro
    return json.loads(buf.getvalue()), logs

# 2a. Verify claim is NEVER leaked to the Reviewer, and Doubt Theater stops at cycle 2
SECRET_CLAIM = "SUPER_SECRET_HYPOTHESIS_12345"

async def mock_agent_theater(prompt, schema=None, role=None, **kw):
    if "Adversarial Reviewer" in (role or ""):
        assert SECRET_CLAIM not in prompt, "CLAIM leaked into Reviewer prompt!"
        return {
            "substantive_issues": [
                {
                    "id": "ISS-1",
                    "severity": "high",
                    "description": "Race condition in cache",
                    "failure_mode": "Data corruption",
                }
            ]
        }
    # Reconciler classifies everything as noise -> triggers Doubt Theater after 2 cycles
    return {
        "classifications": [
            {"issue_id": "ISS-1", "category": "noise", "rationale": "Ignored"}
        ],
        "updated_artifact": "def cache(): pass",
        "updated_contract": "Thread-safe",
        "trade_offs": [],
    }

res, _ = asyncio.run(
    run_doubt(
        {
            "claim": SECRET_CLAIM,
            "artifact": "def cache(): pass",
            "contract": "Thread-safe",
        },
        mock_agent_theater,
    )
)
assert res["status"] == "doubt_theater_detected", f"Expected doubt_theater_detected, got {res}"
assert res["cycles_run"] == 2, f"Expected 2 cycles, got {res['cycles_run']}"
PY

# --- 3. Test sdd_plan.py, sdd_execute.py, sdd_close.py, and pre-commit secret guard ---
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

bash "$REPO_ROOT/scripts/init.sh" -d "$D" -t "true" -p "wf-demo" >/dev/null 2>&1
cd "$D" || exit 1
git config user.email "test@test.local"
git config user.name "test"
git add -A
git commit -qm "chore: bootstrap"

# 3a. Run sdd_plan.py in hermetic mock runtime
python3 - "$REPO_ROOT/workflows/sdd_plan.py" "$REPO_ROOT" <<'PY'
import ast, asyncio, io, json, sys
from contextlib import redirect_stdout

wf_path, skill_dir = sys.argv[1], sys.argv[2]
with open(wf_path, "r", encoding="utf-8") as f:
    code_obj = compile(f.read(), wf_path, "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)

async def mock_agent(prompt, schema=None, role=None, **kw):
    if role == "Capability Mapper":
        return {
            "initiative": "Auth & Billing",
            "modules": [
                {"id": "identity", "responsibility": "Auth", "depends_on": []},
                {"id": "billing", "responsibility": "Payments", "depends_on": ["identity"]},
            ],
        }
    if "Auditor:" in (role or ""):
        return {"passed": True, "defects": []}
    return {
        "objective": "Implementar servicio de autenticación determinista.",
        "diagnosis": "Falta validación de sesión.",
        "phases": [
            {
                "name": "Token Validation",
                "what_changes": "Agrega validador.",
                "spec": "Validar firma.",
                "tests_proof": "Test unitario CRIT-01.",
                "files_touched": ["src/auth.py", "tests/test_auth.py"],
                "criteria": [
                    {"manual": False, "description": "Rechaza tokens expirados."},
                    {"manual": True, "description": "Revisar pantalla de login."},
                ],
            }
        ],
        "out_of_scope": ["OAuth de terceros"],
        "open_decisions": [],
    }

async def mock_parallel(items, fn):
    return [await fn(item) for item in items]

async def main():
    env = {
        "__builtins__": __builtins__,
        "args": {
            "title": "Auth Cycle",
            "spec": "Build auth",
            "decompose": True,
            "skill_dir": skill_dir,
        },
        "log": lambda *a: None,
        "phase": lambda name: None,
        "agent": mock_agent,
        "parallel": mock_parallel,
    }
    buf = io.StringIO()
    with redirect_stdout(buf):
        coro = eval(code_obj, env)
        if asyncio.iscoroutine(coro):
            await coro
    return json.loads(buf.getvalue())

out = asyncio.run(main())
assert out["plan_file"] == "plans/PLAN-1.md", f"Unexpected plan_file: {out}"
PY

[ -f "CAPABILITY_MAP.md" ] || fail "CAPABILITY_MAP.md should be created when decompose=True"
[ -f "plans/PLAN-1.md" ] || fail "plans/PLAN-1.md should be created"
grep -q "^- \[ \] CRIT-01: Rechaza tokens expirados\." plans/PLAN-1.md || fail "CRIT-01 missing in PLAN-1.md"
grep -q "^- \[ \] CRIT-02: (manual) Revisar pantalla de login\." plans/PLAN-1.md || fail "CRIT-02 manual missing in PLAN-1.md"

# Verify plan_hash in SESSION.md matches actual SHA-256 of plans/PLAN-1.md
ACTUAL_HASH=$(sha256sum plans/PLAN-1.md | awk '{print $1}')
RECORDED_HASH=$(awk '/^plan_hash:/ {print $2}' SESSION.md)
[ "$ACTUAL_HASH" = "$RECORDED_HASH" ] || fail "plan_hash mismatch: $ACTUAL_HASH vs $RECORDED_HASH"

# 3b. Overwrite protection: re-running sdd_plan.py with unticked CRIT-01 must fail
if python3 - "$REPO_ROOT/workflows/sdd_plan.py" "$REPO_ROOT" <<'PY' 2>/dev/null
import ast, asyncio, sys
wf_path, skill_dir = sys.argv[1], sys.argv[2]
with open(wf_path, "r", encoding="utf-8") as f:
    code_obj = compile(f.read(), wf_path, "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)
async def main():
    env = {"__builtins__": __builtins__, "args": {"title": "New", "spec": "x", "skill_dir": skill_dir}}
    coro = eval(code_obj, env)
    if asyncio.iscoroutine(coro):
        await coro
asyncio.run(main())
PY
then
    fail "sdd_plan.py must refuse to overwrite an incomplete plan without allow_overwrite=True"
fi

# Commit the plan in plan mode
git add plans/PLAN-1.md CAPABILITY_MAP.md SESSION.md
git commit -qm "docs: add PLAN-1"

# 3c. Run sdd_execute.py for F1
python3 - "$REPO_ROOT/workflows/sdd_execute.py" "$REPO_ROOT" <<'PY'
import ast, asyncio, io, os, subprocess, sys
from contextlib import redirect_stdout

wf_path, skill_dir = sys.argv[1], sys.argv[2]
with open(wf_path, "r", encoding="utf-8") as f:
    code_obj = compile(f.read(), wf_path, "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)

async def mock_agent(prompt, schema=None, role=None, **kw):
    if "TDD Red" in (role or ""):
        os.makedirs("tests", exist_ok=True)
        with open("tests/test_auth.py", "w", encoding="utf-8") as tf:
            tf.write("# CRIT-01: test expired token rejection\ndef test_crit_01_expired(): assert True\n")
        return {
            "test_files": ["tests/test_auth.py"],
            "tests_added": [
                {
                    "crit_id": "CRIT-01",
                    "test_name": "test_crit_01_expired",
                    "guards_against": "Expired token acceptance",
                }
            ],
        }
    if "TDD Green" in (role or ""):
        os.makedirs("src", exist_ok=True)
        with open("src/auth.py", "w", encoding="utf-8") as sf:
            sf.write("def validate(): return True\n")
        subprocess.run(["git", "add", "src/auth.py", "tests/test_auth.py"], check=True)
        subprocess.run(["git", "commit", "-qm", "feat(F1): implement token validation"], check=True)
        return {
            "files_changed": [
                {"file": "src/auth.py", "summary": "Token validation logic"},
                {"file": "tests/test_auth.py", "summary": "CRIT-01 unit test"},
            ],
            "deviations": [],
            "open_questions": [],
        }
    if "Security & DoD Auditor" in (role or ""):
        return {"passed": True, "blocking_issues": []}
    return "OK"

async def main():
    env = {
        "__builtins__": __builtins__,
        "args": {"phase": "F1", "skill_dir": skill_dir},
        "log": lambda *a: None,
        "phase": lambda name: None,
        "agent": mock_agent,
        "parallel": lambda items, fn: asyncio.gather(*(fn(x) for x in items)),
    }
    buf = io.StringIO()
    with redirect_stdout(buf):
        coro = eval(code_obj, env)
        if asyncio.iscoroutine(coro):
            await coro
    return buf.getvalue()

report = asyncio.run(main())
assert "Reporte de Cierre de Fase F1" in report, f"Missing closure report header: {report}"
assert "CRIT-01" in report, "Missing CRIT-01 in report"
PY

# Verify Python automatically ticked CRIT-01 ([x]) and left manual CRIT-02 unticked ([ ])
grep -q "^- \[x\] CRIT-01:" plans/PLAN-1.md || fail "sdd_execute.py must tick automated CRIT-01 after verify"
grep -q "^- \[ \] CRIT-02: (manual)" plans/PLAN-1.md || fail "sdd_execute.py must leave manual CRIT-02 unticked"
grep -q "^sdd_state: verify$" SESSION.md || fail "sdd_state must be verify after sdd_execute.py"
grep -q "Human review: pending" SESSION.md || fail "SESSION.md must record Human review: pending"

# 3d. Run sdd_close.py (C2 Cycle Close Audit)
python3 - "$REPO_ROOT/workflows/sdd_close.py" <<'PY'
import ast, asyncio, io, sys
from contextlib import redirect_stdout

wf_path = sys.argv[1]
with open(wf_path, "r", encoding="utf-8") as f:
    code_obj = compile(f.read(), wf_path, "exec", flags=ast.PyCF_ALLOW_TOP_LEVEL_AWAIT)

async def mock_agent(prompt, schema=None, role=None, **kw):
    if "Reality vs Plan" in (role or ""):
        return {
            "unrequested_changes": [],
            "missing_deliverables": [],
            "unticked_analysis": [
                {
                    "criterion": "CRIT-02",
                    "status": "done_unverifiable_by_agent",
                    "explanation": "Revisión visual pendiente del humano.",
                }
            ],
        }
    return {
        "scope_leaks": [],
        "leftovers_for_backlog": ["Agregar soporte OAuth en próximo ciclo"],
        "honest_verdict": "El ciclo cumplió el 100% de los criterios automatizados sin desvíos de alcance.",
    }

async def mock_parallel(items, fn):
    return [await fn(item) for item in items]

async def main():
    env = {
        "__builtins__": __builtins__,
        "args": {},
        "log": lambda *a: None,
        "phase": lambda name: None,
        "agent": mock_agent,
        "parallel": mock_parallel,
    }
    buf = io.StringIO()
    with redirect_stdout(buf):
        coro = eval(code_obj, env)
        if asyncio.iscoroutine(coro):
            await coro
    return buf.getvalue()

c2_out = asyncio.run(main())
assert "Reporte de Cierre de Ciclo (C2)" in c2_out, f"Missing C2 header: {c2_out}"
assert "1 pendientes / 1 completadas" in c2_out, f"Wrong criteria count in C2: {c2_out}"
PY

# 3e. Verify pre-commit hook blocks .env and private keys even in execute state
bash "$REPO_ROOT/scripts/sdd.sh" start F1 >/dev/null
printf "SECRET=123\n" > .env
git add .env
if git commit -qm "feat(F1): add env" 2>/dev/null; then
    fail "pre-commit hook must block .env files"
fi
git reset -q HEAD .env && rm -f .env

printf -- "-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n" > src/key.txt
git add src/key.txt
if git commit -qm "feat(F1): add private key" 2>/dev/null; then
    fail "pre-commit hook must block private key headers"
fi
git reset -q HEAD src/key.txt && rm -f src/key.txt

echo "test-workflows: all assertions passed"
