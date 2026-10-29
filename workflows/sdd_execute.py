# workflows/sdd_execute.py
# Programmatic SDD Phase Execution (TDD Red -> Green -> Conditional Security/DoD Audit -> C1 Verify & Close).
# Replaces references/test-driven-development.md, references/multi-agent.md,
# references/phase-close.md (C1), references/definition-of-done.md, and
# references/security-checklist.md (~580 lines of prose) with deterministic Python gates.

import os
import re
import glob
import json
import subprocess
from datetime import datetime, timezone

phase_arg = args.get("phase") or args.get("phases")
agent_name = (args.get("agent_name") or "workflow").strip()

if not phase_arg:
    raise ValueError(
        "sdd_execute requires Args={'phase': 'F1'} (or {'phases': ['F1', 'F2']} for parallel work)."
    )


def resolve_skill_dir():
    explicit = args.get("skill_dir")
    if explicit and os.path.isfile(os.path.join(explicit, "scripts", "sdd.sh")):
        return explicit
    if os.path.isfile("AGENTS.md"):
        with open("AGENTS.md", "r", encoding="utf-8") as f:
            text = f.read()
        m = re.search(r"([A-Za-z0-9_./-]+?)/scripts/sdd\.sh", text)
        if m:
            cand = m.group(1)
            if os.path.isfile(os.path.join(cand, "scripts", "sdd.sh")):
                return cand
    for cand in [".", ".agents/skills/discipline-flow"]:
        if os.path.isfile(os.path.join(cand, "scripts", "sdd.sh")):
            return cand
    raise RuntimeError("Could not locate discipline-flow scripts/sdd.sh")


def resolve_plan_file():
    if os.path.isfile("SESSION.md"):
        with open("SESSION.md", "r", encoding="utf-8") as f:
            s_text = f.read()
        m = re.search(
            r"([a-zA-Z0-9_.-]+/)?PLAN-[0-9]+(\.[0-9]+)?\.md", s_text
        )
        if m and os.path.isfile(m.group(0)):
            return m.group(0)
    candidates = sorted(glob.glob("plans/PLAN-*.md") + glob.glob("PLAN-*.md"))
    for c in reversed(candidates):
        if os.path.isfile(c):
            return c
    raise RuntimeError("No active PLAN-*.md file found.")


def check_session_integrity():
    if not os.path.isfile("SESSION.md"):
        return
    with open("SESSION.md", "r", encoding="utf-8") as f:
        text = f.read()
    # Rule 5 from multi-agent.md: Conflict markers = full stop
    if re.search(r"^(<<<<<<<|=======|>>>>>>>)", text, flags=re.M):
        raise RuntimeError(
            "STOP: Marcadores de conflicto Git detectados en SESSION.md. "
            "No se resuelve adivinando; el humano debe arbitrar."
        )
    # Ancestor check from AGENTS.md contract
    m_base = re.search(r"^- \*\*Base commit:\*\*\s*(\S+)", text, flags=re.M)
    if m_base:
        base_sha = m_base.group(1).strip()
        if base_sha and base_sha not in ("uncommitted", "none", "None"):
            res = subprocess.run(
                ["git", "merge-base", "--is-ancestor", base_sha, "HEAD"],
                capture_output=True,
            )
            if res.returncode != 0:
                raise RuntimeError(
                    f"STOP: Base commit '{base_sha}' en SESSION.md no es ancestro de HEAD. "
                    "El repositorio se movió (rebase/reset). Informar al humano antes de continuar."
                )


def extract_phase_slice(plan_file, phase_id):
    with open(plan_file, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    in_phase = False
    slice_lines = []
    header_re = re.compile(rf"^## {re.escape(phase_id)}([^0-9]|$)")
    for line in lines:
        if header_re.match(line):
            in_phase = True
            slice_lines.append(line)
            continue
        if in_phase and line.startswith("## "):
            break
        if in_phase:
            slice_lines.append(line)

    if not slice_lines:
        raise RuntimeError(
            f"Phase '{phase_id}' not found in '{plan_file}'."
        )

    block = "\n".join(slice_lines)
    if "DECISIÓN ABIERTA" in block:
        raise RuntimeError(
            f"STOP: La fase {phase_id} contiene un bloque 'DECISIÓN ABIERTA' sin resolver en {plan_file}."
        )
    return block


def parse_phase_criteria(phase_block):
    automated = []
    manual = []
    for m in re.finditer(
        r"^- \[[ xX]\] (CRIT-[0-9]+):\s*(.*)$", phase_block, flags=re.M
    ):
        cid, desc = m.group(1), m.group(2)
        if "(manual)" in desc.lower():
            manual.append((cid, desc))
        else:
            automated.append((cid, desc))
    return automated, manual


def discover_test_command():
    if os.path.isfile("AGENTS.md"):
        with open("AGENTS.md", "r", encoding="utf-8") as f:
            text = f.read()
        m = re.search(r"Run `([^`]+)` before your first change", text)
        if m and m.group(1) != "{{TEST_COMMAND}}":
            return m.group(1)
    if os.path.isfile("pyproject.toml") or os.path.isfile("pytest.ini"):
        return "pytest -q"
    if os.path.isfile("package.json"):
        return "npm test"
    if os.path.isfile("Cargo.toml"):
        return "cargo test -q"
    if os.path.isfile("go.mod"):
        return "go test ./..."
    if os.access("tests/run.sh", os.X_OK):
        return "./tests/run.sh"
    return os.environ.get("TEST_COMMAND", "true")


def tick_verified_criteria_in_plan(plan_file, phase_id, skill_dir):
    """Delegate to scripts/tick-plan.sh (single writer of `- [x]`).

    sdd.sh verify already ticks on success; this call is an idempotent safety
    net so the workflow never closes a phase with the plan left unticked.
    """
    tick_cli = os.path.join(skill_dir, "scripts", "tick-plan.sh")
    if not os.path.isfile(tick_cli):
        raise RuntimeError(f"tick-plan.sh not found at '{tick_cli}'.")
    for mode_args in (["phase", plan_file, phase_id], ["cycle", plan_file]):
        subprocess.run(
            ["bash", tick_cli, *mode_args],
            check=True,
            capture_output=True,
            text=True,
        )


def update_session_body_atomic(plan_file, phase_id, green_data):
    if not os.path.isfile("SESSION.md"):
        return
    with open("SESSION.md", "r", encoding="utf-8") as f:
        content = f.read()

    fm_match = re.match(r"^(---\n.*?\n---\n)", content, flags=re.S)
    frontmatter = fm_match.group(1) if fm_match else ""

    head_res = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True
    )
    head_sha = (
        head_res.stdout.strip() if head_res.returncode == 0 else "uncommitted"
    )
    phase_start_match = re.search(
        r"^- \*\*Phase-start commit:\*\*\s*(\S+)", content, flags=re.M
    )
    phase_start_sha = (
        phase_start_match.group(1).strip() if phase_start_match else head_sha
    )
    now_utc = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    files_changed = green_data.get("files_changed", [])
    completed_bullets = (
        "\n".join(
            f"- `{fc['file']}`: {fc['summary']}" for fc in files_changed
        )
        or f"- Completada implementación y verificación de {phase_id}"
    )
    open_q = (
        "\n".join(f"- {q}" for q in green_data.get("open_questions", []))
        or "- None"
    )

    body = (
        f"{frontmatter}# Session Checkpoint\n\n"
        f"- **Plan:** {plan_file}\n"
        f"- **Phase:** {phase_id}\n"
        f"- **Phase-start commit:** {phase_start_sha}\n"
        f"- **Status:** phase-closed, awaiting human audit\n"
        f"- **Updated:** {now_utc}\n"
        f"- **Base commit:** {head_sha}\n\n"
        f"## Completed in this session\n"
        f"{completed_bullets}\n\n"
        f"## Current working state\n"
        f"- Clean working tree on {head_sha[:12]}; {phase_id} verified.\n\n"
        f"## Next action\n\n"
        f"Auditar el diff humano de {phase_id} y aprobar; luego iniciar la siguiente fase\n\n"
        f"## Open decisions\n"
        f"{open_q}\n\n"
        f"## Verification\n"
        f"- Human review: pending\n"
    )
    tmp_session = "SESSION.md.tmp"
    with open(tmp_session, "w", encoding="utf-8") as f:
        f.write(body)
    os.replace(tmp_session, "SESSION.md")


# Multi-agent parallel branch mode (when `phases` is a list of >1 phases)
if isinstance(phase_arg, list) and len(phase_arg) > 1:
    phase("Ejecución Multi-Agente por Rama (workspace='share')")
    results = await parallel(
        phase_arg,
        lambda p_id: agent(
            f"Creá la rama 'feat/{p_id}-workflow', reclamá la fase con `./scripts/sdd.sh start {p_id} agent_{p_id}`, "
            f"implementá los tests y el código de {p_id}, y ejecutá `./scripts/sdd.sh verify {p_id}`.",
            schema={"type": "string"},
            role=f"Phase Executor {p_id}",
            workspace="share",
        ),
    )
    for r in results:
        log(r)
    print(json.dumps({"parallel_phases": phase_arg, "results": results}, ensure_ascii=False, indent=2))
else:
    f_id = phase_arg[0] if isinstance(phase_arg, list) else str(phase_arg).strip()
    skill_dir = resolve_skill_dir()
    sdd_cli = os.path.join(skill_dir, "scripts", "sdd.sh")

    # 1. Deterministic Pre-Flight Checks (0 tokens)
    check_session_integrity()
    plan_file = resolve_plan_file()
    phase_slice = extract_phase_slice(plan_file, f_id)
    automated_crits, manual_crits = parse_phase_criteria(phase_slice)
    if not automated_crits and not manual_crits:
        raise RuntimeError(
            f"No CRIT-XX criteria found in phase {f_id} of {plan_file}."
        )

    test_cmd = discover_test_command()
    verify_env = {**os.environ, "TEST_COMMAND": test_cmd}

    # Activate phase via sdd.sh start F<N> <agent>
    subprocess.run(
        ["bash", sdd_cli, "start", f_id, agent_name],
        check=True,
        capture_output=True,
        text=True,
    )
    base_sha_res = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True
    )
    phase_start_sha = (
        base_sha_res.stdout.strip() if base_sha_res.returncode == 0 else "HEAD"
    )

    # 2. Step RED: Write specification/adversarial tests with CRIT-XX IDs
    if automated_crits:
        phase(f"{f_id} — Paso 1: TDD RED (Tests de Especificación)")
        RED_SCHEMA = {
            "type": "object",
            "properties": {
                "test_files": {"type": "array", "items": {"type": "string"}},
                "tests_added": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "crit_id": {"type": "string"},
                            "test_name": {"type": "string"},
                            "guards_against": {"type": "string"},
                        },
                        "required": ["crit_id", "test_name", "guards_against"],
                    },
                },
            },
            "required": ["test_files", "tests_added"],
        }

        crit_list_str = "\n".join(
            f"- {cid}: {desc}" for cid, desc in automated_crits
        )
        red_prompt = (
            f"Estás en el paso TDD RED de la fase {f_id}.\n"
            "REGLAS ESTRICTAS:\n"
            "1. Escribí ÚNICAMENTE los tests automatizados para los criterios listados abajo.\n"
            "2. Cada función o bloque de test DEBE incluir el identificador exacto `CRIT-XX` en su nombre o etiqueta.\n"
            "3. Principios TDD: probá estado/resultado (no interacciones internas), DAMP sobre DRY, preferí implementaciones reales > fakes > stubs > mocks (mockeá solo bordes externos), patrón Arrange-Act-Assert.\n"
            "4. PROHIBIDO modificar código de producción, `SESSION.md` o el archivo del plan.\n\n"
            f"COMANDO DE TEST DEL REPO: `{test_cmd}`\n\n"
            f"ESPECIFICACIÓN DE {f_id}:\n{phase_slice}\n\n"
            f"CRITERIOS AUTOMATIZADOS OBLIGATORIOS:\n{crit_list_str}\n"
        )

        red_data = await agent(
            red_prompt,
            schema=RED_SCHEMA,
            role=f"TDD Red ({f_id})",
        )

        # Deterministic check in Python: verify all automated CRIT-XX tags exist in code/tests
        for cid, _ in automated_crits:
            grep_res = subprocess.run(
                ["git", "grep", "--untracked", "-in", cid],
                capture_output=True,
                text=True,
            )
            non_md = [
                ln
                for ln in grep_res.stdout.splitlines()
                if not re.search(r"\.md:", ln)
            ]
            if not non_md:
                raise RuntimeError(
                    f"Fallo determinista en TDD RED: el agente no incluyó la etiqueta '{cid}' en ningún archivo de test/código."
                )
        log(f"TDD RED verificado: {len(automated_crits)} etiqueta(s) CRIT-XX presentes en tests.")
    else:
        red_data = {"test_files": [], "tests_added": []}

    # 3. Step GREEN: Implement minimal production code & phase-tagged commits
    phase(f"{f_id} — Paso 2: TDD GREEN & REFACTOR (Implementación)")
    GREEN_SCHEMA = {
        "type": "object",
        "properties": {
            "files_changed": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "file": {"type": "string"},
                        "summary": {"type": "string"},
                    },
                    "required": ["file", "summary"],
                },
            },
            "deviations": {"type": "array", "items": {"type": "string"}},
            "open_questions": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["files_changed", "deviations", "open_questions"],
    }

    green_prompt = (
        f"Estás en el paso TDD GREEN de la fase {f_id}.\n"
        "REGLAS ESTRICTAS:\n"
        f"1. Implementá el código mínimo limpio para que pasen todos los tests de {f_id} y la suite completa (`{test_cmd}`).\n"
        f"2. Hacé commits atómicos siguiendo Conventional Commits e incluyendo obligatoriamente el token de fase `{f_id}` (ej. `feat({f_id}): ...` o `test({f_id}): ...`).\n"
        "3. NO debilites ni borres las aserciones `CRIT-XX` creadas en el paso RED.\n"
        "4. PROHIBIDO editar manualmente `SESSION.md` o tildar `- [x]` en el archivo del plan (eso lo hace el motor Python al verificar).\n\n"
        f"ESPECIFICACIÓN DE {f_id}:\n{phase_slice}\n\n"
        f"ARCHIVOS DE TEST CREADOS EN RED: {json.dumps(red_data.get('test_files', []))}\n"
    )

    green_data = await agent(
        green_prompt,
        schema=GREEN_SCHEMA,
        role=f"TDD Green ({f_id})",
    )

    # 4. Conditional Security & Definition-of-Done Audit (0 tokens if diff is pure/safe)
    diff_res = subprocess.run(
        ["git", "diff", f"{phase_start_sha}..HEAD"],
        capture_output=True,
        text=True,
    )
    diff_text = diff_res.stdout
    sensitive_pattern = re.compile(
        r"(package\.json|pyproject\.toml|Cargo\.toml|go\.mod|password|secret|token|jwt|auth|cookie|cors|sql|SELECT |INSERT |realpath|unlink|rmtree| subprocess|eval\(|exec\()",
        flags=re.I,
    )

    if sensitive_pattern.search(diff_text) or args.get("force_security_audit"):
        phase(f"{f_id} — Paso 3: Auditoría Condicional de Seguridad y DoD")
        SEC_SCHEMA = {
            "type": "object",
            "properties": {
                "passed": {"type": "boolean"},
                "blocking_issues": {
                    "type": "array",
                    "items": {"type": "string"},
                },
            },
            "required": ["passed", "blocking_issues"],
        }
        sec_audit = await agent(
            "Auditá este git diff contra Definition of Done y Security Checklist:\n"
            "- Sin secretos hardcodeados ni exposición de stack traces/SQL en respuestas.\n"
            "- Validación de inputs con allowlists, queries parametrizadas, rutas destructivas con realpath dentro de roots permitidos.\n"
            "- Si se tocaron dependencias, un único lockfile autoritativo y sin scripts postinstall no auditados.\n"
            "- Sin código muerto ni cambios fuera del alcance de la fase.\n\n"
            f"FASE:\n{phase_slice}\n\nGIT DIFF:\n{diff_text[:30000]}",
            schema=SEC_SCHEMA,
            role=f"Security & DoD Auditor ({f_id})",
        )
        if not sec_audit.get("passed", True) and sec_audit.get("blocking_issues"):
            issues_str = "\n".join(f"- {i}" for i in sec_audit["blocking_issues"])
            await agent(
                f"Corregí estos problemas bloqueantes de seguridad/DoD y commiteá con el token ({f_id}):\n{issues_str}",
                schema={"type": "string"},
                role=f"Security Fixer ({f_id})",
            )

    # 5. Deterministic Gate: sdd.sh verify F<N> + Automated Plan Ticking
    phase(f"{f_id} — Paso 4: Gate Determinista (verify-crit.sh)")
    verify_proc = subprocess.run(
        ["bash", sdd_cli, "verify", f_id],
        capture_output=True,
        text=True,
        env=verify_env,
    )

    if verify_proc.returncode != 0:
        log(f"Primer intento de verify falló (exit {verify_proc.returncode}). Ejecutando auto-reparación...")
        await agent(
            f"El gate determinista `sdd.sh verify {f_id}` falló con la siguiente salida:\n"
            f"{verify_proc.stdout}\n{verify_proc.stderr}\n"
            f"Corregí el problema (tests faltantes, suite en rojo o commit sin token {f_id}) y commiteá.",
            schema={"type": "string"},
            role=f"Gate Healer ({f_id})",
        )
        verify_proc = subprocess.run(
            ["bash", sdd_cli, "verify", f_id],
            capture_output=True,
            text=True,
            env=verify_env,
        )
        if verify_proc.returncode != 0:
            raise RuntimeError(
                f"HARD FAIL: `sdd.sh verify {f_id}` rechazó el cierre de fase:\n"
                f"{verify_proc.stdout}\n{verify_proc.stderr}"
            )

    # Python ticks automated criteria in PLAN-N.md ONLY after verify_proc.returncode == 0
    tick_verified_criteria_in_plan(plan_file, f_id, skill_dir)
    update_session_body_atomic(plan_file, f_id, green_data)

    # Build the Spanish C1 Phase Closure Report
    files_table = "\n".join(
        f"| `{fc['file']}` | {fc['summary']} |"
        for fc in green_data.get("files_changed", [])
    ) or "| — | Sin archivos reportados |"

    tests_table = "\n".join(
        f"| `{t['crit_id']}` | `{t['test_name']}` | {t['guards_against']} |"
        for t in red_data.get("tests_added", [])
    ) or "| — | — | — |"

    devs = (
        "\n".join(f"- {d}" for d in green_data.get("deviations", []))
        or "- Ninguna."
    )
    open_q = (
        "\n".join(f"- {q}" for q in green_data.get("open_questions", []))
        or "- Ninguna."
    )

    closure_report = (
        f"## Reporte de Cierre de Fase {f_id}\n\n"
        f"### 1. Tabla de Verificación Determinista (`verify-crit.sh`)\n\n"
        f"{verify_proc.stdout.strip()}\n\n"
        f"### 2. Archivos Modificados\n\n"
        f"| Archivo | Cambio |\n| :--- | :--- |\n{files_table}\n\n"
        f"### 3. Tests Agregados y Defensa\n\n"
        f"| Criterio | Test | Qué previene / demuestra |\n| :--- | :--- | :--- |\n{tests_table}\n\n"
        f"### 4. Desviaciones del Plan\n{devs}\n\n"
        f"### 5. Preguntas Abiertas\n{open_q}\n\n"
        f"---\n"
        f"**Fase verificada y registrada (`Human review: pending`). ¿Avanzamos a la siguiente tras tu auditoría del diff?**"
    )
    print(closure_report)
