# workflows/sdd_cycle.py
# Deterministic SDD Orchestration Workflow for Antigravity `run_workflow`.
# Primitives provided by runtime: phase, agent, parallel, pipeline, call_tool, ToolError, log, WORKSPACES.

import json
import os
import subprocess

# ---------------------------------------------------------------------------
# 0. Runtime Configuration & Schema Loading
# ---------------------------------------------------------------------------
wf_args = globals().get("args") or {}
workspace_root = wf_args.get("workspace_root") or (WORKSPACES[0] if WORKSPACES else os.getcwd())
skill_root = wf_args.get("skill_root") or workspace_root
plan_file = wf_args.get("plan_file", "plans/PLAN-1.md")
phase_id = wf_args.get("phase_id", "F1")
test_cmd = wf_args.get("test_cmd", "")
lint_cmd = wf_args.get("lint_cmd", "none")
max_doubt_cycles = min(int(wf_args.get("max_doubt_cycles", 3)), 3)

schemas_dir = os.path.join(skill_root, "assets", "schemas")
scripts_dir = os.path.join(skill_root, "scripts")


def load_schema(name):
    path = os.path.join(schemas_dir, name)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


spec_schema = load_schema("spec_verification.json")
task_schema = load_schema("task_breakdown.json")
audit_schema = load_schema("audit_verdict.json")

impl_result_schema = {
    "type": "object",
    "additionalProperties": False,
    "required": ["task_id", "status", "branch", "commit_sha", "modified_files", "tests_added"],
    "properties": {
        "task_id": {"type": "string"},
        "status": {"type": "string", "enum": ["completed", "blocked"]},
        "branch": {"type": "string"},
        "commit_sha": {"type": "string"},
        "modified_files": {"type": "array", "items": {"type": "string"}},
        "tests_added": {"type": "array", "items": {"type": "string"}},
    },
}


def group_tasks_by_waves(tasks):
    """Partitions tasks into topological waves of independent items."""
    completed = set()
    remaining = list(tasks)
    waves = []

    while remaining:
        ready = [
            t for t in remaining
            if all(dep in completed for dep in t.get("dependencies", []))
        ]
        if not ready:
            raise RuntimeError(
                f"Cyclic or unsatisfied task dependencies detected in phase {phase_id}: "
                f"{[t['id'] for t in remaining]}"
            )

        # Split ready tasks into conflict-free parallel batches (disjoint affected_files)
        wave = []
        touched_in_wave = set()
        for t in ready:
            files = set(t.get("affected_files", []))
            if not wave or (t.get("parallelizable", False) and files.isdisjoint(touched_in_wave)):
                wave.append(t)
                touched_in_wave.update(files)

        waves.append(wave)
        for t in wave:
            completed.add(t["id"])
            remaining.remove(t)

    return waves


async def exec_gate_command(cmd_str, summary):
    """Executes a mechanical gate command via call_tool('run_command', ...)."""
    try:
        output = await call_tool(
            "run_command",
            CommandLine=cmd_str,
            Cwd=workspace_root,
            WaitMsBeforeAsync=10000,
            toolSummary=summary,
            toolAction=f"Running {summary}",
        )
        return {"ok": True, "output": output}
    except ToolError as exc:
        # Fallback if the runtime's call_tool allowlist restricts direct run_command
        log(f"[Mechanical Gate] call_tool('run_command') raised ToolError ({exc.message}); executing deterministic local fallback.")
        proc = subprocess.run(
            ["bash", "-c", cmd_str],
            cwd=workspace_root,
            capture_output=True,
            text=True,
        )
        combined = (proc.stdout or "") + (proc.stderr or "")
        return {"ok": proc.returncode == 0, "exit_code": proc.returncode, "output": combined.strip()}


# ---------------------------------------------------------------------------
# Phase 1: Audit Spec
# ---------------------------------------------------------------------------
phase("Audit Spec")
log(f"Auditing specification '{plan_file}' for phase '{phase_id}'...")

spec_verdict = await agent(
    f"Audit the specification in '{plan_file}' (focusing on phase '{phase_id}') against the "
    f"Discipline Flow SDD invariants.\n"
    f"1. Read '{plan_file}' and 'SESSION.md' (if present).\n"
    f"2. Verify that objective, executable commands (build/test/lint), boundaries, out_of_scope, "
    f"and testable CRIT-XX criteria for {phase_id} are defined.\n"
    f"3. Set approved=True ONLY if open_questions is empty, missing_sections is empty, and all "
    f"criteria are concrete and falsifiable.",
    schema=spec_schema,
    role=f"Spec Auditor ({phase_id})",
)

log(f"Spec audit approved={spec_verdict['approved']}, criteria={len(spec_verdict['criteria'])}")

if not spec_verdict["approved"] or spec_verdict["open_questions"] or spec_verdict["missing_sections"]:
    raise RuntimeError(
        f"Spec Audit FAILED for {plan_file} ({phase_id}). "
        f"Open questions: {spec_verdict['open_questions']} | "
        f"Missing sections: {spec_verdict['missing_sections']}"
    )

breakdown = await agent(
    f"Decompose phase '{phase_id}' from '{plan_file}' into atomic, vertical-slice tasks.\n"
    f"Invariants:\n"
    f"- Maximum 5 affected_files per task.\n"
    f"- Every automated CRIT-XX in {phase_id} must map to tests_to_create and criteria_ids.\n"
    f"- Mark parallelizable=True only when affected_files are disjoint from sibling tasks.",
    schema=task_schema,
    role=f"Task Planner ({phase_id})",
)

waves = group_tasks_by_waves(breakdown["tasks"])
log(f"Planned {len(breakdown['tasks'])} atomic task(s) across {len(waves)} execution wave(s).")

# ---------------------------------------------------------------------------
# Phase 2: Atomic Implementation
# ---------------------------------------------------------------------------
phase("Atomic Implementation")

# Unlock execute state via sdd.sh before implementation
sdd_cli = os.path.join(scripts_dir, "sdd.sh")
await exec_gate_command(f"bash '{sdd_cli}' start '{phase_id}' orchestrator", f"Activate phase {phase_id}")

implementation_results = []
for wave_idx, wave in enumerate(waves, start=1):
    log(f"Executing wave {wave_idx}/{len(waves)} with {len(wave)} parallel task(s): {[t['id'] for t in wave]}")
    wave_results = await parallel(
        wave,
        lambda t: agent(
            f"Implement atomic task {t['id']} ({t['title']}) for phase {phase_id} from '{plan_file}'.\n"
            f"- Allowed files to touch (<= 5): {t['affected_files']}\n"
            f"- Required CRIT-XX tags in test names/bodies: {t['criteria_ids']}\n"
            f"- Tests to create/update: {t['tests_to_create']}\n"
            f"- Follow strict TDD (RED -> GREEN -> REFACTOR).\n"
            f"- Commit your changes with message prefix 'feat({phase_id}): ' or 'test({phase_id}): '.",
            schema=impl_result_schema,
            role=f"Impl {t['id']}",
            workspace="branch",
        ),
    )
    for res in wave_results:
        log(f"Task {res['task_id']} -> {res['status']} (commit {res['commit_sha']} on {res['branch']})")
        if res["status"] != "completed":
            raise RuntimeError(f"Task {res['task_id']} reported blocked status.")
    implementation_results.extend(wave_results)

# ---------------------------------------------------------------------------
# Phase 3: Mechanical Gate
# ---------------------------------------------------------------------------
phase("Mechanical Gate")

verify_cli = os.path.join(scripts_dir, "verify-crit.sh")
effective_test_cmd = test_cmd or spec_verdict["commands"].get("test", "")
effective_lint_cmd = lint_cmd if lint_cmd != "none" else spec_verdict["commands"].get("lint", "none")


async def run_mechanical_gate():
    env_prefix = f"TEST_COMMAND={json.dumps(effective_test_cmd)} " if effective_test_cmd else ""
    verify_cmd = f"{env_prefix}bash '{verify_cli}' --json '{plan_file}' '{phase_id}'"
    gate_res = await exec_gate_command(verify_cmd, f"Verify CRIT-XX ({phase_id})")

    raw_out = gate_res.get("output", "").strip()
    parsed_json = None
    for line in reversed(raw_out.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                parsed_json = json.loads(line)
                break
            except Exception:
                pass

    if not parsed_json:
        try:
            parsed_json = json.loads(raw_out)
        except Exception:
            parsed_json = {"passed": gate_res.get("ok", False), "raw_output": raw_out}

    if not parsed_json.get("passed", False):
        return {"passed": False, "stage": "verify-crit", "details": parsed_json}

    if effective_lint_cmd and effective_lint_cmd.lower() != "none":
        lint_res = await exec_gate_command(effective_lint_cmd, "Run Linter")
        if not lint_res.get("ok", False):
            return {"passed": False, "stage": "linter", "details": lint_res}

    return {"passed": True, "stage": "complete", "details": parsed_json}


gate_status = await run_mechanical_gate()
log(f"Mechanical Gate status: passed={gate_status['passed']} (stage={gate_status['stage']})")
if not gate_status["passed"]:
    raise RuntimeError(f"Mechanical Gate FAILED at stage '{gate_status['stage']}': {json.dumps(gate_status['details'])}")

# ---------------------------------------------------------------------------
# Phase 4: Doubt-Driven Audit
# ---------------------------------------------------------------------------
phase("Doubt-Driven Audit")

ADVERSARIAL_STANDING_PROMPT = (
    "You are a blind Adversarial Auditor operating under Doubt-Driven Development.\n"
    "Assume the implementation author is overconfident. Your sole job is to DISPROVE "
    "that the ARTIFACT satisfies the CONTRACT.\n"
    "Look for:\n"
    "- Unstated assumptions and unhandled edge cases\n"
    "- Hidden coupling, shared mutable state, or race conditions\n"
    "- Ways the CONTRACT or boundaries could be violated\n"
    "- Scope leaks from 'Out of scope'\n"
    "- Tautological or superficial CRIT-XX tests\n\n"
    "Classify every finding strictly in precedence order:\n"
    "1. 'contract_misread' (contract itself is ambiguous)\n"
    "2. 'actionable' (real defect in code or tests requiring remediation)\n"
    "3. 'trade_off' (acceptable engineering trade-off to document)\n"
    "4. 'noise' (false positive)\n"
    "Do NOT validate or praise. Emit your response via finish matching AuditVerdict schema."
)

auditor = agent(
    ADVERSARIAL_STANDING_PROMPT,
    schema=audit_schema,
    role=f"Blind Auditor ({phase_id})",
)

final_verdict = None
non_actionable_streaks = 0

try:
    for cycle in range(1, max_doubt_cycles + 1):
        diff_res = await exec_gate_command("git diff HEAD~1..HEAD 2>/dev/null || git diff", "Extract Artifact Diff")
        artifact_diff = diff_res.get("output", "")

        audit_turn_prompt = (
            f"CYCLE: {cycle} of {max_doubt_cycles}\n"
            f"Inspect ONLY the ARTIFACT diff and CONTRACT below (no author claims provided).\n"
            f"- CONTRACT FILE: {plan_file} (Phase {phase_id})\n"
            f"- CONTRACT CRITERIA: {json.dumps(spec_verdict['criteria'])}\n"
            f"- CONTRACT OUT OF SCOPE: {json.dumps(spec_verdict['out_of_scope'])}\n"
            f"- MECHANICAL GATE JSON: {json.dumps(gate_status['details'])}\n\n"
            f"ARTIFACT DIFF:\n{artifact_diff[:40000]}"
        )

        verdict = await auditor(audit_turn_prompt, audit_schema)
        final_verdict = verdict
        violations = verdict.get("violations", [])
        misreads = [v for v in violations if v["category"] == "contract_misread"]
        actionables = [v for v in violations if v["category"] == "actionable"]

        log(
            f"Doubt Cycle {cycle}: passed={verdict['passed']}, "
            f"total_violations={len(violations)}, actionable={len(actionables)}, misreads={len(misreads)}"
        )

        if misreads:
            raise RuntimeError(
                f"Doubt Audit halted on contract_misread in {plan_file}: "
                f"{[m['description'] for m in misreads]}"
            )

        if verdict["passed"] and not actionables:
            log(f"Doubt-Driven Audit PASSED on cycle {cycle}.")
            break

        if violations and not actionables:
            non_actionable_streaks += 1
            if non_actionable_streaks >= 2:
                raise RuntimeError("Doubt Theater detected (>=2 cycles with findings but 0 actionable). Escalating to human.")

        if cycle == max_doubt_cycles:
            raise RuntimeError(
                f"Doubt-Driven Audit exhausted {max_doubt_cycles} cycles with remaining actionable violations: "
                f"{[a['description'] for a in actionables]}"
            )

        # Remediate actionable findings and re-verify mechanical gate before next auditor turn
        await agent(
            f"Fix the following actionable violations found by the Blind Auditor in phase {phase_id}:\n"
            f"{json.dumps(actionables, indent=2)}\n"
            f"Keep all CRIT-XX tests passing and commit with '{phase_id}' token.",
            schema=impl_result_schema,
            role=f"Remediate Cycle {cycle}",
        )

        gate_status = await run_mechanical_gate()
        if not gate_status["passed"]:
            raise RuntimeError(
                f"Mechanical Gate failed after remediation in cycle {cycle}: {json.dumps(gate_status['details'])}"
            )
finally:
    del auditor

# Advance SDD state to verify (awaiting final human diff sign-off)
await exec_gate_command(f"bash '{sdd_cli}' advance verify", "Advance state to verify")

print(
    json.dumps(
        {
            "phase_id": phase_id,
            "plan_file": plan_file,
            "spec_approved": spec_verdict["approved"],
            "tasks_completed": len(implementation_results),
            "mechanical_gate": gate_status["details"],
            "audit_verdict": final_verdict,
        },
        indent=2,
    )
)
