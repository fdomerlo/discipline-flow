# workflows/sdd_doubt.py
# Programmatic Doubt-Driven Development workflow for run_workflow.
# Replaces references/doubt-driven-development.md (~16.6 KB of prose) with
# zero-token deterministic orchestration:
#   1. Physical isolation: Reviewer receives ONLY artifact + contract (NEVER claim).
#   2. Strict JSON Schema output for both adversarial review and reconciliation.
#   3. Bounded loop (max 3 cycles) + deterministic "Doubt Theater" detection.

import os
import json

claim = (args.get("claim") or "").strip()
artifact_input = (args.get("artifact") or "").strip()
contract = (args.get("contract") or "").strip()
max_cycles = min(int(args.get("max_cycles", 3)), 3)

if not claim or not artifact_input or not contract:
    raise ValueError(
        "sdd_doubt requires Args={'claim': '...', 'artifact': '...', 'contract': '...'}"
    )

# If artifact_input is a path to an existing file, load its content automatically.
if os.path.isfile(artifact_input):
    with open(artifact_input, "r", encoding="utf-8") as f:
        current_artifact = f.read()
    artifact_label = f"File: {artifact_input}"
else:
    current_artifact = artifact_input
    artifact_label = "Inline artifact"

current_contract = contract

DOUBT_SCHEMA = {
    "type": "object",
    "properties": {
        "substantive_issues": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "severity": {
                        "type": "string",
                        "enum": ["critical", "high", "medium", "low"],
                    },
                    "description": {"type": "string"},
                    "failure_mode": {"type": "string"},
                },
                "required": ["id", "severity", "description", "failure_mode"],
            },
        }
    },
    "required": ["substantive_issues"],
}

RECONCILE_SCHEMA = {
    "type": "object",
    "properties": {
        "classifications": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "issue_id": {"type": "string"},
                    "category": {
                        "type": "string",
                        "enum": [
                            "contract_misread",
                            "actionable",
                            "trade_off",
                            "noise",
                        ],
                    },
                    "rationale": {"type": "string"},
                },
                "required": ["issue_id", "category", "rationale"],
            },
        },
        "updated_artifact": {"type": "string"},
        "updated_contract": {"type": "string"},
        "trade_offs": {"type": "array", "items": {"type": "string"}},
    },
    "required": [
        "classifications",
        "updated_artifact",
        "updated_contract",
        "trade_offs",
    ],
}

zero_actionable_streaks = 0
all_trade_offs = []
history = []
stop_reason = "max_cycles_reached"

for cycle in range(1, max_cycles + 1):
    phase(f"Ciclo de Duda {cycle}/{max_cycles} — DOUBT (Contexto Aislado)")

    # Physical context barrier: Reviewer NEVER sees `claim` or prior reasoning.
    doubt_prompt = (
        "Adversarial review. Find what is wrong with this artifact.\n"
        "Assume the author is overconfident. Look for:\n"
        "- Unstated assumptions\n"
        "- Edge cases not handled\n"
        "- Hidden coupling or shared state\n"
        "- Ways the contract could be violated\n"
        "- Existing conventions this might break\n"
        "- Failure modes under unexpected input\n\n"
        "Do NOT validate. Do NOT summarize. Find substantive issues, or return an empty list.\n\n"
        f"ARTIFACT ({artifact_label}):\n{current_artifact}\n\n"
        f"CONTRACT:\n{current_contract}\n"
    )

    review = await agent(
        doubt_prompt,
        schema=DOUBT_SCHEMA,
        role=f"Adversarial Reviewer C{cycle}",
    )

    issues = review.get("substantive_issues", [])
    non_trivial = [
        i for i in issues if i.get("severity") in ("critical", "high", "medium")
    ]
    log(
        f"Ciclo {cycle}: {len(issues)} hallazgos totales ({len(non_trivial)} sustantivos)."
    )

    if not non_trivial:
        stop_reason = f"clean_at_cycle_{cycle}"
        history.append({"cycle": cycle, "issues": issues, "classifications": []})
        break

    phase(f"Ciclo de Duda {cycle}/{max_cycles} — RECONCILE")
    reconcile_prompt = (
        "Sos el orquestador reconciliando hallazgos de una revisión adversarial contra el texto real del artefacto.\n"
        "Clasificá cada hallazgo en estricto orden de precedencia:\n"
        "1. contract_misread: el contrato estaba incompleto o ambiguo -> actualizá updated_contract.\n"
        "2. actionable: defecto real en el artefacto -> corregilo en updated_artifact.\n"
        "3. trade_off: defecto real pero el costo de corregirlo supera el beneficio -> documentalo en trade_offs.\n"
        "4. noise: falso positivo por contexto ausente.\n\n"
        f"CLAIM BAJO ESCRUTINIO:\n{claim}\n\n"
        f"ARTIFACT ACTUAL:\n{current_artifact}\n\n"
        f"CONTRACT ACTUAL:\n{current_contract}\n\n"
        f"HALLAZGOS DEL REVISOR:\n{json.dumps(non_trivial, ensure_ascii=False, indent=2)}\n"
    )

    reconciled = await agent(
        reconcile_prompt,
        schema=RECONCILE_SCHEMA,
        role=f"Reconciler C{cycle}",
    )

    classifications = reconciled.get("classifications", [])
    history.append(
        {"cycle": cycle, "issues": non_trivial, "classifications": classifications}
    )
    all_trade_offs.extend(reconciled.get("trade_offs", []))

    actionable_count = sum(
        1 for c in classifications if c.get("category") == "actionable"
    )
    contract_fixes = sum(
        1 for c in classifications if c.get("category") == "contract_misread"
    )

    # Deterministic Doubt Theater check: if reviewer found substantive issues
    # but 0 were classified as actionable across 2 cycles, stop and escalate.
    if actionable_count == 0:
        zero_actionable_streaks += 1
    else:
        zero_actionable_streaks = 0

    if zero_actionable_streaks >= 2:
        stop_reason = "doubt_theater_detected"
        log(
            "ALERTA: 'Doubt Theater' detectado (2 ciclos con hallazgos sustantivos y 0 accionables). Escalando al usuario."
        )
        break

    new_artifact = reconciled.get("updated_artifact", current_artifact)
    new_contract = reconciled.get("updated_contract", current_contract)

    if (
        actionable_count > 0
        and new_artifact == current_artifact
        and new_contract == current_contract
    ):
        stop_reason = f"stalled_unchanged_artifact_at_cycle_{cycle}"
        break

    current_artifact = new_artifact
    current_contract = new_contract

report = {
    "status": stop_reason,
    "cycles_run": len(history),
    "claim": claim,
    "trade_offs": all_trade_offs,
    "final_artifact": current_artifact,
    "final_contract": current_contract,
    "cross_model_prompt": (
        "Revisión single-model completada. ¿Querés una segunda opinión cross-model "
        "(Gemini CLI / Codex CLI / revisión externa manual) o continuamos?"
    ),
}

print(json.dumps(report, ensure_ascii=False, indent=2))
