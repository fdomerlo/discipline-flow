# workflows/sdd_plan.py
# Programmatic SDD Planning & Self-Audit workflow for run_workflow.
# Replaces references/plan-cycle.md, references/task-breakdown.md, and
# references/spec-driven-development.md (~656 lines of prose) with deterministic
# schema enforcement, DAG validation, parallel self-audit, and OS-level locking.

import os
import re
import glob
import json
import subprocess

title = (args.get("title") or "Nuevo Ciclo SDD").strip()
spec_input = (args.get("spec") or args.get("objective") or "").strip()
allow_overwrite = bool(args.get("allow_overwrite", False))
decompose = bool(args.get("decompose", False))

if not spec_input:
    raise ValueError(
        "sdd_plan requires Args={'title': '...', 'spec': '...'} (or 'objective')."
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


def find_existing_plans():
    plans = sorted(glob.glob("plans/PLAN-*.md") + glob.glob("PLAN-*.md"))
    return [p for p in plans if os.path.isfile(p)]


# 1. Deterministic protection against overwriting an incomplete plan
existing_plans = find_existing_plans()
if existing_plans and not allow_overwrite:
    latest_plan = existing_plans[-1]
    with open(latest_plan, "r", encoding="utf-8") as f:
        plan_content = f.read()
    unticked = re.findall(r"^- \[ \] (CRIT-[0-9]+:.*)$", plan_content, flags=re.M)
    if unticked:
        raise RuntimeError(
            f"STOP: El plan activo '{latest_plan}' todavía tiene {len(unticked)} criterio(s) sin completar "
            f"(ej. {unticked[0]}). No se sobreescribe un plan en curso sin confirmación explícita "
            f"(Args={{'allow_overwrite': True}})."
        )

# 2. Optional Phase 0: Scope Check & Capability Map (DAG validation in Python)
capability_map_md = ""
if decompose:
    phase("Fase 0 — Mapa de Capacidades (Scope Check)")
    CAP_MAP_SCHEMA = {
        "type": "object",
        "properties": {
            "initiative": {"type": "string"},
            "modules": {
                "type": "array",
                "minItems": 2,
                "items": {
                    "type": "object",
                    "properties": {
                        "id": {
                            "type": "string",
                            "pattern": "^[a-z0-9]+(-[a-z0-9]+)*$",
                        },
                        "responsibility": {"type": "string"},
                        "depends_on": {
                            "type": "array",
                            "items": {"type": "string"},
                        },
                    },
                    "required": ["id", "responsibility", "depends_on"],
                },
            },
        },
        "required": ["initiative", "modules"],
    }

    cap_data = await agent(
        f"Descomponé este requerimiento en módulos independientemente verificables (kebab-case IDs, sin ciclos):\n{spec_input}",
        schema=CAP_MAP_SCHEMA,
        role="Capability Mapper",
    )

    # Validate DAG (no unknown deps, no cycles via topological sort)
    mods = {m["id"]: list(m.get("depends_on", [])) for m in cap_data["modules"]}
    for mid, deps in mods.items():
        for d in deps:
            if d not in mods:
                raise RuntimeError(
                    f"Capability Map inválido: el módulo '{mid}' depende de '{d}' que no existe."
                )

    visited = {}

    def has_cycle(node):
        state = visited.get(node, 0)
        if state == 1:
            return True
        if state == 2:
            return False
        visited[node] = 1
        for dep in mods.get(node, []):
            if has_cycle(dep):
                return True
        visited[node] = 2
        return False

    for mid in mods:
        if has_cycle(mid):
            raise RuntimeError(
                f"Capability Map inválido: ciclo de dependencias detectado involucrando '{mid}'."
            )

    lines = [
        f"# Capability Map: {cap_data['initiative']}",
        "",
        "| Module id | Responsibility | Depends on |",
        "|---|---|---|",
    ]
    for m in cap_data["modules"]:
        deps_str = ", ".join(m["depends_on"]) if m["depends_on"] else "—"
        lines.append(f"| {m['id']} | {m['responsibility']} | {deps_str} |")
    capability_map_md = "\n".join(lines) + "\n"
    with open("CAPABILITY_MAP.md", "w", encoding="utf-8") as f:
        f.write(capability_map_md)
    log("CAPABILITY_MAP.md validado como DAG sin ciclos y guardado.")

# 3. Draft Structured Plan (JSON Schema enforces SDD rules deterministically)
PLAN_SCHEMA = {
    "type": "object",
    "properties": {
        "objective": {
            "type": "string",
            "description": "Objetivo del plan en una sola oración clara en español.",
        },
        "diagnosis": {
            "type": "string",
            "description": "Evidencia o diagnóstico concreto del problema o necesidad en español.",
        },
        "phases": {
            "type": "array",
            "minItems": 1,
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "what_changes": {"type": "string"},
                    "spec": {"type": "string"},
                    "tests_proof": {"type": "string"},
                    "files_touched": {
                        "type": "array",
                        "items": {"type": "string"},
                        "minItems": 1,
                        "maxItems": 5,
                    },
                    "criteria": {
                        "type": "array",
                        "minItems": 2,
                        "maxItems": 7,
                        "items": {
                            "type": "object",
                            "properties": {
                                "manual": {"type": "boolean"},
                                "description": {"type": "string"},
                            },
                            "required": ["manual", "description"],
                        },
                    },
                },
                "required": [
                    "name",
                    "what_changes",
                    "spec",
                    "tests_proof",
                    "files_touched",
                    "criteria",
                ],
            },
        },
        "out_of_scope": {
            "type": "array",
            "minItems": 1,
            "items": {"type": "string"},
        },
        "open_decisions": {
            "type": "array",
            "items": {"type": "string"},
        },
    },
    "required": [
        "objective",
        "diagnosis",
        "phases",
        "out_of_scope",
        "open_decisions",
    ],
}

phase("Diseño del Plan Técnico SDD")
architect_prompt = (
    "Sos el Arquitecto SDD. Redactá el plan íntegramente en ESPAÑOL siguiendo estas reglas estrictas:\n"
    "1. Ordená las fases de abajo hacia arriba según el grafo de dependencias (cimientos primero).\n"
    "2. Cortá verticalmente (cada fase entrega una tajada funcional verificable y revisable en un solo diff, máx 5 archivos por fase).\n"
    "3. Cada fase debe tener entre 2 y 7 criterios de aceptación atómicos y verificables por comando (sin frases vagas como 'funciona bien' o 'es más limpio').\n"
    "4. Marcá manual=true SOLO si un criterio requiere inspección visual humana imposible de automatizar.\n"
    "5. Todo lo tentador pero tangencial va en out_of_scope.\n\n"
    f"TÍTULO: {title}\n"
    f"ESPECIFICACIÓN / REQUERIMIENTO:\n{spec_input}\n"
)

plan_data = await agent(
    architect_prompt,
    schema=PLAN_SCHEMA,
    role="Arquitecto SDD",
)

# 4. Self-Audit in parallel across 4 independent fresh-context reviewers
phase("Auto-Auditoría Paralela del Plan (4 Ejes)")
AUDIT_SCHEMA = {
    "type": "object",
    "properties": {
        "passed": {"type": "boolean"},
        "defects": {"type": "array", "items": {"type": "string"}},
    },
    "required": ["passed", "defects"],
}

plan_json_str = json.dumps(plan_data, ensure_ascii=False, indent=2)
audit_axes = [
    (
        "Checkability & Traceability",
        "Detectá cualquier criterio subjetivo o vago ('debería funcionar bien', 'más limpio') que no pueda comprobarse con un test automatizado determinista, o criterios manuales mal clasificados.",
    ),
    (
        "Scope Leak",
        "Verificá si algún ítem listado en 'out_of_scope' se filtró silenciosamente dentro de las fases o criterios.",
    ),
    (
        "Vertical Slicing & Sizing",
        "Verificá que cada fase toque como máximo 5 archivos, sea revisable como un solo diff coherente y no necesite una fase posterior para tener sentido.",
    ),
    (
        "Dependency Order",
        "Verificá que ninguna fase temprana dependa de componentes o cambios que recién se construyen en una fase posterior.",
    ),
]

audit_results = await parallel(
    audit_axes,
    lambda axis: agent(
        f"Auditá este plan JSON exclusivamente en el eje '{axis[0]}':\n{axis[1]}\n\nPLAN:\n{plan_json_str}",
        schema=AUDIT_SCHEMA,
        role=f"Auditor: {axis[0]}",
    ),
)

all_defects = []
for (axis_name, _), res in zip(audit_axes, audit_results):
    if not res.get("passed", True) or res.get("defects"):
        for d in res.get("defects", []):
            all_defects.append(f"[{axis_name}] {d}")

if all_defects:
    phase("Refinamiento del Plan tras Auto-Auditoría")
    log(f"Corrigiendo {len(all_defects)} hallazgo(s) de la auto-auditoría...")
    defects_text = "\n".join(f"- {d}" for d in all_defects)
    plan_data = await agent(
        f"Corregí estos defectos detectados por los auditores en el plan para '{title}':\n{defects_text}\n\nPLAN ORIGINAL:\n{plan_json_str}",
        schema=PLAN_SCHEMA,
        role="Arquitecto SDD (Refinamiento)",
    )


# 5. Deterministic Markdown Rendering & Physical Gate Activation via sdd.sh
def render_plan_markdown(plan_num, plan_title, data):
    out = [
        f"# PLAN-{plan_num} — {plan_title}",
        "",
        data["objective"].strip(),
        "",
        "## Diagnosis / evidence",
        "",
        data["diagnosis"].strip(),
        "",
    ]

    if data.get("open_decisions"):
        out.append("## DECISIÓN ABIERTA")
        out.append("")
        for dec in data["open_decisions"]:
            out.append(f"- ⚠️ **STOP:** {dec}")
        out.append("")

    crit_counter = 1
    for idx, ph in enumerate(data["phases"], start=1):
        files_list = ", ".join(f"`{f}`" for f in ph.get("files_touched", []))
        out.extend(
            [
                f"## F{idx} — {ph['name'].strip()}",
                "",
                ph["what_changes"].strip(),
                "",
                "**Spec:**",
                ph["spec"].strip(),
                f"\n**Archivos objetivo (máx 5):** {files_list}",
                "",
                "**Tests:**",
                ph["tests_proof"].strip(),
                "",
                "### Acceptance criteria",
            ]
        )
        for crit in ph["criteria"]:
            cid = f"CRIT-{crit_counter:02d}"
            crit_counter += 1
            prefix = "(manual) " if crit.get("manual") else ""
            out.append(f"- [ ] {cid}: {prefix}{crit['description'].strip()}")
        out.append("")

    out.extend(["## Out of scope", ""])
    for item in data["out_of_scope"]:
        out.append(f"- {item.strip()}")

    out.extend(
        [
            "",
            "## Criteria for the whole cycle",
            "",
            "- [ ] Full suite green.",
            "- [ ] Every phase's acceptance criteria met and demonstrated.",
            '- [ ] Nothing from "Out of scope" leaked into a phase diff.',
            "",
        ]
    )
    return "\n".join(out)


skill_dir = resolve_skill_dir()
sdd_cli = os.path.join(skill_dir, "scripts", "sdd.sh")

# Ensure canonical plans/ directory exists so new-plan.sh places PLAN-N.md in plans/
os.makedirs("plans", exist_ok=True)
subprocess.run(
    ["bash", sdd_cli, "plan", title],
    check=True,
    capture_output=True,
    text=True,
)

created_plans = find_existing_plans()
if not created_plans:
    raise RuntimeError("sdd.sh plan did not create a PLAN-*.md file.")
target_plan = created_plans[-1]
m_num = re.search(r"PLAN-([0-9]+)", os.path.basename(target_plan))
plan_num = int(m_num.group(1)) if m_num else 1

rendered_md = render_plan_markdown(plan_num, title, plan_data)
with open(target_plan, "w", encoding="utf-8") as f:
    f.write(rendered_md)

# Lock the updated SHA-256 hash of the populated plan in SESSION.md
subprocess.run(
    ["bash", sdd_cli, "advance", "plan"],
    check=True,
    capture_output=True,
    text=True,
)

log(f"Plan generado y bloqueado en: {target_plan}")
print(
    json.dumps(
        {
            "plan_file": target_plan,
            "phases": [
                f"F{i + 1}: {p['name']}"
                for i, p in enumerate(plan_data["phases"])
            ],
            "self_audit_defects_fixed": all_defects,
            "open_decisions": plan_data.get("open_decisions", []),
            "approval_prompt": "¿Apruebas este plan para comenzar la ejecución?",
        },
        ensure_ascii=False,
        indent=2,
    )
)
