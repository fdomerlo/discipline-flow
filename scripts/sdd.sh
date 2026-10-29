#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION_FILE="SESSION.md"

# Shared helpers (canonical): scripts/lib/sdd-common.sh.
if [[ -f "$SCRIPT_DIR/lib/sdd-common.sh" ]]; then
    # shellcheck source=lib/sdd-common.sh
    . "$SCRIPT_DIR/lib/sdd-common.sh"
fi

# Resuelve el archivo PLAN actual (canonical: plans/, legacy: root).
resolve_plan_file() {
    if command -v sdd_resolve_plan >/dev/null 2>&1; then
        sdd_resolve_plan "$SESSION_FILE"
        return
    fi
    local plan=""
    if [[ -f "$SESSION_FILE" ]]; then
        plan=$(grep -oE '([a-zA-Z0-9_.-]+/)?PLAN-[0-9]+(\.[0-9]+)?\.md' "$SESSION_FILE" | head -n 1 || true)
    fi
    if [[ -n "$plan" && -f "$plan" ]]; then
        echo "$plan"
        return
    fi
    plan=$(ls plans/PLAN-*.md 2>/dev/null | sort -V | tail -n 1 || true)
    if [[ -n "$plan" && -f "$plan" ]]; then
        echo "$plan"
        return
    fi
    plan=$(ls PLAN-*.md 2>/dev/null | sort -V | tail -n 1 || true)
    echo "$plan"
}

calc_plan_hash() {
    if command -v sdd_calc_hash >/dev/null 2>&1; then
        sdd_calc_hash "$1"
        return
    fi
    local plan="$1"
    if [[ -n "$plan" && -f "$plan" ]]; then
        sha256sum "$plan" | awk '{print $1}'
    else
        echo "none"
    fi
}

scaffold_new_plan() {
    local title="${1:-New Cycle}"
    local tpl="$SKILL_DIR/assets/PLAN.md.template"
    [[ -f "$tpl" ]] || return 0

    local target_dir="plans"
    mkdir -p "$target_dir"

    local highest=0
    local f base num
    shopt -s nullglob
    for f in "$target_dir"/PLAN-*.md PLAN-*.md; do
        if [[ -f "$f" ]]; then
            base="$(basename "$f")"
            if [[ "$base" =~ ^PLAN-([0-9]+) ]]; then
                num="${BASH_REMATCH[1]}"
                (( num > highest )) && highest=$num
            fi
        fi
    done
    shopt -u nullglob

    local next_n=$((highest + 1))
    local out_file="$target_dir/PLAN-$next_n.md"
    local content
    content="$(<"$tpl")"
    content="${content//\{\{N\}\}/$next_n}"
    content="${content//\{\{TITLE\}\}/$title}"
    printf '%s\n' "$content" > "$out_file"
    echo "Created new plan: $out_file"
}

ensure_session_file() {
    if [[ ! -f "$SESSION_FILE" ]]; then
        local current_plan
        current_plan=$(resolve_plan_file)
        local initial_hash="none"
        if [[ -n "$current_plan" && -f "$current_plan" ]]; then
            initial_hash=$(calc_plan_hash "$current_plan")
        fi

        cat <<EOF > "$SESSION_FILE"
---
sdd_state: plan
active_task: none
active_agent: none
plan_hash: $initial_hash
---
# Session Checkpoint

- **Plan:** ${current_plan:-None}
- **Phase:** None
- **Status:** Initialized
- **Updated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- **Base commit:** $(git rev-parse HEAD 2>/dev/null || echo "uncommitted")

## Completed in this session
- Initialized SDD session

## Current working state
- Awaiting plan definition

## Next action
- Create plan with ./scripts/sdd.sh plan "<title>"

## Open decisions
- None

## Verification
- Human review: pending
EOF
        echo "Created baseline $SESSION_FILE"
    fi
}

get_val() {
    if command -v sdd_get_val >/dev/null 2>&1; then
        sdd_get_val "$1" "$SESSION_FILE"
        return
    fi
    local key="$1"
    if [[ ! -f "$SESSION_FILE" ]]; then
        echo "none"
        return
    fi
    awk -v k="$key" '/^---$/ { if (c++ == 1) exit } c==1 && $0 ~ ("^" k ":") { sub("^" k ":[[:space:]]*", ""); gsub(/\r/, ""); print $0 }' "$SESSION_FILE"
}

set_val() {
    local key="$1"
    local val="$2"
    ensure_session_file

    local tmp_file="${SESSION_FILE}.tmp.$$"
    awk -v k="$key" -v v="$val" '
        BEGIN { delim=0; updated=0 }
        /^---$/ {
            delim++
            if (delim == 2 && !updated) {
                print k ": " v
                updated=1
            }
            print
            next
        }
        delim == 1 && $0 ~ ("^" k ":") {
            print k ": " v
            updated=1
            next
        }
        { print }
    ' "$SESSION_FILE" > "$tmp_file"

    mv "$tmp_file" "$SESSION_FILE"
}

cli_path() {
    if command -v realpath >/dev/null 2>&1; then
        realpath --relative-to=. "$SCRIPT_DIR/sdd.sh" 2>/dev/null || echo "./scripts/sdd.sh"
    else
        echo "./scripts/sdd.sh"
    fi
}

refresh_body() {
    local new_status="$1"
    local new_next="$2"
    local set_base="${3:-}"
    local f="$SESSION_FILE"
    [[ -f "$f" ]] || return 0

    if [[ -n "$new_status" ]] && grep -q '^- \*\*Status:' "$f"; then
        sed -i "s|^- \*\*Status:.*|- **Status:** $new_status|" "$f" 2>/dev/null || true
    fi
    if grep -q '^- \*\*Updated:' "$f"; then
        sed -i "s|^- \*\*Updated:.*|- **Updated:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")|" "$f" 2>/dev/null || true
    fi
    if [[ -n "$set_base" ]]; then
        local head
        head=$(git rev-parse HEAD 2>/dev/null || echo "uncommitted")
        if grep -q '^- \*\*Base commit:' "$f"; then
            sed -i "s|^- \*\*Base commit:.*|- **Base commit:** $head|" "$f" 2>/dev/null || true
        fi
    fi
    if [[ -n "$new_next" ]]; then
        local tmp_next="${f}.tmp.$$"
        if grep -q '^## Next action' "$f"; then
            awk -v nxt="$new_next" '
                /^## Next action[[:space:]]*$/ {print; print ""; print nxt; print ""; in_next=1; next}
                in_next && /^## / {in_next=0}
                in_next {next}
                {print}
            ' "$f" > "$tmp_next"
            mv "$tmp_next" "$f"
        else
            printf '\n## Next action\n\n%s\n' "$new_next" >> "$f"
        fi
    fi
}

COMMAND="${1:-status}"
ARG="${2:-}"

case "$COMMAND" in
    plan|new-plan)
        ensure_session_file
        TITLE="${ARG:-New Cycle}"
        scaffold_new_plan "$TITLE"

        PLAN_FILE=$(resolve_plan_file)
        NEW_HASH="none"
        if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
            NEW_HASH=$(calc_plan_hash "$PLAN_FILE")
            sed -i "s|^- \*\*Plan:\*\*.*|- \*\*Plan:\*\* $PLAN_FILE|" "$SESSION_FILE" 2>/dev/null || true
        fi

        set_val "sdd_state" "plan"
        set_val "active_task" "none"
        set_val "active_agent" "none"
        set_val "plan_hash" "$NEW_HASH"
        refresh_body "Plan review, awaiting approval" "Revisar y aprobar el plan; luego arrancar la primera fase ($(cli_path) start F1)" "base"

        echo "📋 Modo PLAN activo. El código fuente está bloqueado para commits hasta iniciar una fase."
        echo "🔒 Hash de especificación registrado: ${NEW_HASH:0:12}..."
        echo "👉 Cuando el plan esté listo y aprobado, inicia la fase con: ./scripts/sdd.sh start F1"
        ;;

    start)
        PHASE_OR_TASK="$ARG"
        AGENT="${3:-}"
        if [[ -z "$PHASE_OR_TASK" ]]; then
            echo "Error: Debes especificar la fase o tarea a iniciar (ej: F1, F2)." >&2
            echo "Uso: $0 start <fase> [agente]  (ej: $0 start F1 alice)" >&2
            exit 1
        fi

        ensure_session_file

        PREV_TASK=$(get_val "active_task")
        PREV_AGENT=$(get_val "active_agent")
        if [[ -n "$AGENT" && "$PREV_TASK" == "$PHASE_OR_TASK" && -n "$PREV_AGENT" && "$PREV_AGENT" != "none" && "$PREV_AGENT" != "$AGENT" ]]; then
            echo "⚠️  La fase '$PHASE_OR_TASK' está reclamada por el agente '$PREV_AGENT'." >&2
            echo "   Si trabajás en paralelo, coordiná con tu contraparte o usá branch-per-phase." >&2
            echo "   Ver references/protocol-invariants.md. Continuando con el reclamo de '$AGENT'." >&2
        fi

        PLAN_FILE=$(resolve_plan_file)
        if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
            CURRENT_HASH=$(calc_plan_hash "$PLAN_FILE")
            RECORDED_HASH=$(get_val "plan_hash")

            if [[ "$RECORDED_HASH" != "none" && "$RECORDED_HASH" != "$CURRENT_HASH" ]]; then
                echo "⚠️  AVISO: El archivo de especificación ($PLAN_FILE) ha cambiado desde su creación." >&2
                echo "   Hash anterior : ${RECORDED_HASH:0:12}..." >&2
                echo "   Hash actual   : ${CURRENT_HASH:0:12}..." >&2
                echo "   Congelando nuevo hash de especificación para la fase $PHASE_OR_TASK." >&2
            fi
            set_val "plan_hash" "$CURRENT_HASH"
            sed -i "s|^- \*\*Plan:\*\*.*|- \*\*Plan:\*\* $PLAN_FILE|" "$SESSION_FILE" 2>/dev/null || true
            sed -i "s|^- \*\*Phase:\*\*.*|- \*\*Phase:\*\* $PHASE_OR_TASK|" "$SESSION_FILE" 2>/dev/null || true
        fi

        PHASE_BASE=$(git rev-parse HEAD 2>/dev/null || echo "uncommitted")
        if grep -q '^- \*\*Phase-start commit:' "$SESSION_FILE"; then
            sed -i "s|^- \*\*Phase-start commit:.*|- **Phase-start commit:** $PHASE_BASE|" "$SESSION_FILE" 2>/dev/null || true
        elif grep -q '^- \*\*Phase:' "$SESSION_FILE"; then
            sed -i "/^- \*\*Phase:/a - **Phase-start commit:** $PHASE_BASE" "$SESSION_FILE" 2>/dev/null || true
        else
            printf -- '- **Phase-start commit:** %s\n' "$PHASE_BASE" >> "$SESSION_FILE"
        fi

        set_val "sdd_state" "execute"
        set_val "active_task" "$PHASE_OR_TASK"
        if [[ -n "$AGENT" ]]; then
            set_val "active_agent" "$AGENT"
        else
            set_val "active_agent" "none"
        fi
        refresh_body "Phase $PHASE_OR_TASK in progress" "Completar los criterios de $PHASE_OR_TASK y correr $(cli_path) verify $PHASE_OR_TASK" "base"
        echo "🚀 Iniciando fase '$PHASE_OR_TASK' en estado 'execute'."
        echo "🔓 Modificación de código desbloqueada para commits."
        echo "ℹ️  Recuerda incluir '$PHASE_OR_TASK' en tus mensajes de commit (ej: feat($PHASE_OR_TASK): descripción)."
        ;;

    verify)
        ensure_session_file
        shift || true
        VERIFY_JSON=0
        PHASE_ID=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --json)
                    VERIFY_JSON=1
                    shift
                    ;;
                *)
                    PHASE_ID="$1"
                    shift
                    ;;
            esac
        done

        if [[ "$VERIFY_JSON" -eq 0 ]]; then
            echo "🔍 Ejecutando verificación determinista de criterios..."
        fi

        PLAN_FILE=$(resolve_plan_file)
        if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
            RECORDED_HASH=$(get_val "plan_hash")
            CURRENT_HASH=$(calc_plan_hash "$PLAN_FILE")
            if [[ "$RECORDED_HASH" != "none" && "$RECORDED_HASH" != "$CURRENT_HASH" ]]; then
                echo "⚠️  ALERTA SDD: El archivo de plan ($PLAN_FILE) fue modificado durante la fase 'execute'." >&2
                echo "   Posible desvío de especificación detectado." >&2
            fi
        fi

        if [[ -x "$SCRIPT_DIR/verify-crit.sh" ]]; then
            VERIFY_ARGS=()
            [[ "$VERIFY_JSON" -eq 1 ]] && VERIFY_ARGS+=("--json")
            if [[ -n "$PHASE_ID" ]]; then
                VERIFY_ARGS+=("" "$PHASE_ID")
            fi
            set +e
            "$SCRIPT_DIR/verify-crit.sh" "${VERIFY_ARGS[@]}"
            VERIFY_EXIT=$?
            set -e
            if [[ $VERIFY_EXIT -eq 0 ]]; then
                set_val "sdd_state" "verify"
                refresh_body "phase-closed, awaiting human audit" "Auditar el diff humano de ${PHASE_ID:-la fase} y aprobar; luego iniciar la siguiente fase"
                if [[ "$VERIFY_JSON" -eq 0 ]]; then
                    echo "✅ Verificación exitosa. Estado avanzado a: verify"
                    echo "🛑 ALTO: Detén la ejecución y presenta el reporte para auditoría humana del diff."
                fi
            else
                exit $VERIFY_EXIT
            fi
        else
            echo "Warning: $SCRIPT_DIR/verify-crit.sh no encontrado o no ejecutable." >&2
            set_val "sdd_state" "verify"
            refresh_body "phase-closed, awaiting human audit" "Auditar el diff humano de ${PHASE_ID:-la fase} y aprobar; luego iniciar la siguiente fase"
            if [[ "$VERIFY_JSON" -eq 0 ]]; then
                echo "Estado cambiado a verify."
            fi
        fi
        ;;

    orchestrate|run)
        ensure_session_file >/dev/null
        shift || true
        ORCH_PHASE=""
        ORCH_PLAN=""
        ORCH_TEST_CMD="${TEST_COMMAND:-}"
        ORCH_LINT_CMD="none"
        ORCH_MAX_CYCLES=3

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --plan)
                    ORCH_PLAN="${2:-}"
                    shift 2
                    ;;
                --test-cmd)
                    ORCH_TEST_CMD="${2:-}"
                    shift 2
                    ;;
                --lint-cmd)
                    ORCH_LINT_CMD="${2:-}"
                    shift 2
                    ;;
                --max-cycles)
                    ORCH_MAX_CYCLES="${2:-3}"
                    shift 2
                    ;;
                --json)
                    shift
                    ;;
                *)
                    if [[ -z "$ORCH_PHASE" ]]; then
                        ORCH_PHASE="$1"
                    fi
                    shift
                    ;;
            esac
        done

        if [[ -z "$ORCH_PLAN" ]]; then
            ORCH_PLAN=$(resolve_plan_file)
        fi
        if [[ -z "$ORCH_PHASE" ]]; then
            ORCH_PHASE=$(get_val "active_task")
            if [[ -z "$ORCH_PHASE" || "$ORCH_PHASE" == "none" ]]; then
                ORCH_PHASE="F1"
            fi
        fi

        WORKFLOW_SCRIPT="$SKILL_DIR/workflows/sdd_cycle.py"
        if [[ ! -f "$WORKFLOW_SCRIPT" ]]; then
            echo "Error: Workflow script no encontrado en '$WORKFLOW_SCRIPT'." >&2
            exit 1
        fi
        if [[ -z "$ORCH_PLAN" || ! -f "$ORCH_PLAN" ]]; then
            echo "Error: No se encontró un archivo PLAN-*.md válido para orquestar." >&2
            exit 1
        fi

        WORKSPACE_ROOT="$(pwd)"
        printf '{\n  "tool": "run_workflow",\n  "ScriptPath": "%s",\n  "Cwd": "%s",\n  "Description": "Execute Discipline Flow SDD cycle for %s (%s)",\n  "Args": {\n    "plan_file": "%s",\n    "phase_id": "%s",\n    "workspace_root": "%s",\n    "skill_root": "%s",\n    "test_cmd": "%s",\n    "lint_cmd": "%s",\n    "max_doubt_cycles": %d\n  }\n}\n' \
            "$WORKFLOW_SCRIPT" \
            "$WORKSPACE_ROOT" \
            "$ORCH_PHASE" \
            "$ORCH_PLAN" \
            "$ORCH_PLAN" \
            "$ORCH_PHASE" \
            "$WORKSPACE_ROOT" \
            "$SKILL_DIR" \
            "$ORCH_TEST_CMD" \
            "$ORCH_LINT_CMD" \
            "$ORCH_MAX_CYCLES"
        ;;

    advance)
        NEW_STATE="$ARG"
        if [[ ! "$NEW_STATE" =~ ^(plan|execute|verify)$ ]]; then
            echo "Error: Estado inválido '$NEW_STATE'. Valores permitidos: plan, execute, verify." >&2
            exit 1
        fi

        ensure_session_file
        set_val "sdd_state" "$NEW_STATE"
        if [[ "$NEW_STATE" == "plan" ]]; then
            set_val "active_task" "none"
            set_val "active_agent" "none"
            refresh_body "Plan review, awaiting approval" "Revisar y aprobar el plan; luego arrancar la primera fase ($(cli_path) start F1)" "base"
        else
            refresh_body "" ""
        fi
        echo "✅ Estado avanzado a: $NEW_STATE"
        ;;

    status)
        ensure_session_file
        CURRENT_STATE=$(get_val "sdd_state")
        ACTIVE_TASK=$(get_val "active_task")
        ACTIVE_AGENT=$(get_val "active_agent")
        [[ -z "$ACTIVE_AGENT" ]] && ACTIVE_AGENT="none"
        RECORDED_HASH=$(get_val "plan_hash")
        PLAN_FILE=$(resolve_plan_file)

        echo "=========================================="
        echo "         DISCIPLINE FLOW — ESTADO SDD     "
        echo "=========================================="
        echo " Estado actual  : $CURRENT_STATE"
        echo " Fase activa    : $ACTIVE_TASK"
        echo " Agente activo  : $ACTIVE_AGENT"
        echo " Plan activo    : ${PLAN_FILE:-Ninguno}"
        if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
            CURRENT_HASH=$(calc_plan_hash "$PLAN_FILE")
            if [[ "$RECORDED_HASH" != "none" && "$RECORDED_HASH" != "$CURRENT_HASH" ]]; then
                echo " Hash de Plan   : ⚠️  ALTERADO (grabado: ${RECORDED_HASH:0:8}, actual: ${CURRENT_HASH:0:8})"
            else
                echo " Hash de Plan   : ✅ ÍNTEGRO (${RECORDED_HASH:0:12}...)"
            fi
        else
            echo " Hash de Plan   : $RECORDED_HASH"
        fi
        case "$CURRENT_STATE" in
            plan)
                echo " 🔒 Código      : BLOQUEADO (solo .md/.txt permitidos, resto bloqueado por pre-commit)"
                echo " Siguiente paso : ./scripts/sdd.sh start F1 (o ./scripts/sdd.sh orchestrate F1)"
                ;;
            execute)
                echo " 🔓 Código      : DESBLOQUEADO (commits deben incluir '$ACTIVE_TASK')"
                echo " Siguiente paso : ./scripts/sdd.sh verify $ACTIVE_TASK"
                ;;
            verify)
                echo " 🛑 Auditoría   : En espera de aprobación humana del diff."
                echo " Siguiente paso : Aprobar diff y pasar a la siguiente fase."
                ;;
        esac
        echo "=========================================="
        ;;

    *)
        echo "Uso: $0 {start <fase> [agente]|plan [titulo]|verify [--json] [fase]|orchestrate [fase] [--plan <path>]|advance <plan|execute|verify>|status}"
        echo "Ejemplos:"
        echo "  $0 start F1                  # Desbloquea código para trabajar en la Fase 1"
        echo "  $0 start F1 alice            # Igual, reclamando la fase para el agente 'alice'"
        echo "  $0 verify F1                 # Corre suite y validación CRIT-XX para Fase 1"
        echo "  $0 verify --json F1          # Igual, emitiendo resultado JSON determinista"
        echo "  $0 orchestrate F1            # Emite el descriptor run_workflow para workflows/sdd_cycle.py"
        echo "  $0 plan \"Nueva función\"      # Inicia nuevo plan y bloquea commits de código"
        echo "  $0 status                    # Consulta el estado SDD actual"
        exit 1
        ;;
esac
exit 0
