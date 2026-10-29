# workflows/sdd_close.py
# Programmatic SDD Cycle Close (C2) workflow for run_workflow.
# Replaces references/phase-close.md (C2) with deterministic parsing of unticked
# criteria and parallel fresh-context audits of Reality vs. Plan and Scope Leaks.

import os
import re
import glob
import json
import subprocess


def resolve_plan_file():
    explicit = args.get("plan_file")
    if explicit and os.path.isfile(explicit):
        return explicit
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


plan_file = resolve_plan_file()
base_ref = (args.get("base_ref") or "").strip()

with open(plan_file, "r", encoding="utf-8") as f:
    plan_text = f.read()

# 1. Deterministically parse phases, unticked boxes, ticked boxes, and Out of scope
current_section = "Header"
unticked_boxes = []
ticked_boxes = []
out_of_scope_lines = []

for line in plan_text.splitlines():
    if line.startswith("## "):
        current_section = line[3:].strip()
        continue
    m_unticked = re.match(r"^- \[ \] (CRIT-[0-9]+:\s*.*)$", line)
    if m_unticked:
        unticked_boxes.append({"phase": current_section, "criterion": m_unticked.group(1)})
        continue
    m_ticked = re.match(r"^- \[[xX]\] (CRIT-[0-9]+:\s*.*)$", line)
    if m_ticked:
        ticked_boxes.append({"phase": current_section, "criterion": m_ticked.group(1)})
        continue
    if current_section.lower().startswith("out of scope") and line.strip().startswith("-"):
        out_of_scope_lines.append(line.strip())

# 2. Gather Git cycle history and diff stat deterministically
log_cmd = ["git", "log", "--oneline", "-n", "40"]
if base_ref:
    log_cmd = ["git", "log", "--oneline", f"{base_ref}..HEAD"]
git_log = subprocess.run(log_cmd, capture_output=True, text=True).stdout.strip()

diff_cmd = ["git", "diff", "--stat", f"{base_ref}..HEAD"] if base_ref else ["git", " status", "--short"]
if not base_ref:
    diff_stat = subprocess.run(
        ["git", "log", "--stat", "--oneline", "-n", "15"],
        capture_output=True,
        text=True,
    ).stdout.strip()
else:
    diff_stat = subprocess.run(diff_cmd, capture_output=True, text=True).stdout.strip()

# 3. Parallel Cycle Audits (Reality vs Plan + Scope Leaks + Unticked Classification)
phase("Auditoría Paralela de Cierre de Ciclo (C2)")

REALITY_SCHEMA = {
    "type": "object",
    "properties": {
        "unrequested_changes": {"type": "array", "items": {"type": "string"}},
        "missing_deliverables": {"type": "array", "items": {"type": "string"}},
        "unticked_analysis": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "criterion": {"type": "string"},
                    "status": {
                        "type": "string",
                        "enum": [
                            "not_done",
                            "done_unverifiable_by_agent",
                            "obsolete_by_design_change",
                        ],
                    },
                    "explanation": {"type": "string"},
                },
                "required": ["criterion", "status", "explanation"],
            },
        },
    },
    "required": [
        "unrequested_changes",
        "missing_deliverables",
        "unticked_analysis",
    ],
}

SCOPE_SCHEMA = {
    "type": "object",
    "properties": {
        "scope_leaks": {"type": "array", "items": {"type": "string"}},
        "leftovers_for_backlog": {"type": "array", "items": {"type": "string"}},
        "honest_verdict": {
            "type": "string",
            "description": "Veredicto honesto en 2 o 3 líneas en español sobre si el ciclo logró su objetivo.",
        },
    },
    "required": ["scope_leaks", "leftovers_for_backlog", "honest_verdict"],
}

reality_task = agent(
    "Sos el Auditor C2 de Realidad vs. Plan.\n"
    "Compará el plan completo contra el historial de commits y archivos tocados:\n"
    "1. ¿Hay algo en el repositorio que ninguna fase pidió (unrequested_changes)?\n"
    "2. ¿Hay algo que una fase pidió y no está en el repositorio (missing_deliverables)?\n"
    "3. Clasificá cada criterio aún sin tildar (`[ ]`).\n\n"
    f"PLAN ({plan_file}):\n{plan_text}\n\n"
    f"CRITERIOS SIN TILDAR:\n{json.dumps(unticked_boxes, ensure_ascii=False, indent=2)}\n\n"
    f"HISTORIAL GIT:\n{git_log}\n\nESTADÍSTICAS GIT:\n{diff_stat}\n",
    schema=REALITY_SCHEMA,
    role="Auditor: Reality vs Plan",
)

scope_task = agent(
    "Sos el Auditor C2 de Alcance y Remanentes.\n"
    "1. Verificá si algo de la sección 'Out of scope' se construyó igual (scope_leaks).\n"
    "2. Listá todo trabajo pendiente, hallazgos o decisiones diferidas para el backlog (leftovers_for_backlog).\n"
    "3. Redactá en español un veredicto honesto de 2 a 3 líneas (honest_verdict).\n\n"
    f"OUT OF SCOPE DECLARADO:\n{chr(10).join(out_of_scope_lines)}\n\n"
    f"PLAN ({plan_file}):\n{plan_text}\n\n"
    f"HISTORIAL GIT:\n{git_log}\n",
    schema=SCOPE_SCHEMA,
    role="Auditor: Scope Leaks & Verdict",
)

reality_res, scope_res = await parallel(
    [reality_task, scope_task], lambda t: t
)

unticked_md = (
    "\n".join(
        f"- **{u['criterion']}** (`{u['status']}`): {u['explanation']}"
        for u in reality_res.get("unticked_analysis", [])
    )
    or "- Todos los criterios automatizados están tildados (`[x]`)."
)
unreq_md = (
    "\n".join(f"- {x}" for x in reality_res.get("unrequested_changes", []))
    or "- Ninguno."
)
missing_md = (
    "\n".join(f"- {x}" for x in reality_res.get("missing_deliverables", []))
    or "- Ninguno."
)
leaks_md = (
    "\n".join(f"- {x}" for x in scope_res.get("scope_leaks", []))
    or "- Ninguna filtración de 'Out of scope' detectada."
)
leftovers_md = (
    "\n".join(f"- {x}" for x in scope_res.get("leftovers_for_backlog", []))
    or "- Sin remanentes pendientes."
)

# 4. Deterministic ticking of the cycle criteria (single writer: tick-plan.sh).
# "Full suite green" / "Every phase's criteria" derive from the phase ticks;
# the "Out of scope" line is ticked only if the scope audit found no leaks.
def _find_tick_cli():
    for cand in [args.get("skill_dir") or "", ".", ".agents/skills/discipline-flow"]:
        if cand and os.path.isfile(os.path.join(cand, "scripts", "tick-plan.sh")):
            return os.path.join(cand, "scripts", "tick-plan.sh")
    if os.path.isfile("AGENTS.md"):
        with open("AGENTS.md", "r", encoding="utf-8") as fh:
            m = re.search(r"([A-Za-z0-9_./-]+?)/scripts/sdd\.sh", fh.read())
        if m and os.path.isfile(os.path.join(m.group(1), "scripts", "tick-plan.sh")):
            return os.path.join(m.group(1), "scripts", "tick-plan.sh")
    return None


tick_cli = _find_tick_cli()
cycle_ticks_note = "tick-plan.sh no encontrado: criterios de ciclo sin actualizar."
if tick_cli:
    subprocess.run(["bash", tick_cli, "cycle", plan_file], check=True, capture_output=True, text=True)
    if not scope_res.get("scope_leaks"):
        subprocess.run(["bash", tick_cli, "scope-clean", plan_file], check=True, capture_output=True, text=True)
    cycle_ticks_note = "Criterios de ciclo actualizados en el plan según los resultados deterministas."

c2_report = (
    f"## Reporte de Cierre de Ciclo (C2) — `{plan_file}`\n\n"
    f"### 1. Cajas sin Tildar (`- [ ]`) — {len(unticked_boxes)} pendientes / {len(ticked_boxes)} completadas\n"
    f"{unticked_md}\n\n"
    f"### 2. Realidad vs. Plan\n"
    f"**Cambios no solicitados por ninguna fase:**\n{unreq_md}\n\n"
    f"**Entregables solicitados ausentes en el repo:**\n{missing_md}\n\n"
    f"### 3. Filtraciones de Alcance (Scope Leaks)\n"
    f"{leaks_md}\n\n"
    f"### 4. Remanentes (para `BACKLOG.md` / Issues)\n"
    f"{leftovers_md}\n\n"
    f"### 5. Veredicto Honesto\n"
    f"{scope_res.get('honest_verdict', '')}\n\n"
    f"_{cycle_ticks_note}_\n"
)

print(c2_report)
