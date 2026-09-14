#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_FILE="SESSION.md"

# Resuelve el archivo PLAN actual
resolve_plan_file() {
    local plan=""
    if [[ -f "$SESSION_FILE" ]]; then
        plan=$(grep -oE '([a-zA-Z0-9_.-]+/)?PLAN-[0-9]+(\.[0-9]+)?\.md' "$SESSION_FILE" | head -n 1 || true)
    fi
    if [[ -z "$plan" || ! -f "$plan" ]]; then
        plan=$(ls plans/PLAN-*.md PLAN-*.md 2>/dev/null | sort -V | tail -n 1 || true)
    fi
    echo "$plan"
}

# Calcula sha256 nativo con coreutils
calc_plan_hash() {
    local plan="$1"
    if [[ -n "$plan" && -f "$plan" ]]; then
        sha256sum "$plan" | awk '{print $1}'
    else
        echo "none"
    fi
}

# Asegurar que SESSION.md existe con frontmatter básico si no está presente
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
        BEGIN { in_fm=0; updated=0 }
        /^---$/ {
            in_fm++
            print
            next
        }
        in_fm == 1 && $0 ~ ("^" k ":") {
            print k ": " v
            updated=1
            next
        }
        in_fm == 1 && in_fm_end == 0 && /^---$/ {
            if (!updated) print k ": " v
            print
            next
        }
        { print }
    ' "$SESSION_FILE" > "$tmp_file"

    mv "$tmp_file" "$SESSION_FILE"
}

COMMAND="${1:-status}"
ARG="${2:-}"

case "$COMMAND" in
    plan|new-plan)
        ensure_session_file
        TITLE="${ARG:-New Cycle}"
        # Si existe el script new-plan.sh, lo invocamos
        if [[ -x "$SCRIPT_DIR/new-plan.sh" ]]; then
            "$SCRIPT_DIR/new-plan.sh" "$TITLE"
        fi

        PLAN_FILE=$(resolve_plan_file)
        NEW_HASH="none"
        if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
            NEW_HASH=$(calc_plan_hash "$PLAN_FILE")
            # Actualizar linea de Plan en markdown
            sed -i "s|^- \*\*Plan:\*\*.*|- \*\*Plan:\*\* $PLAN_FILE|" "$SESSION_FILE" 2>/dev/null || true
        fi

        set_val "sdd_state" "plan"
        set_val "active_task" "none"
        set_val "plan_hash" "$NEW_HASH"

        echo "📋 Modo PLAN activo. El código fuente está bloqueado para commits hasta iniciar una fase."
        echo "🔒 Hash de especificación registrado: ${NEW_HASH:0:12}..."
        echo "👉 Cuando el plan esté listo y aprobado, inicia la fase con: ./scripts/sdd.sh start F1"
        ;;

    start)
        PHASE_OR_TASK="$ARG"
        if [[ -z "$PHASE_OR_TASK" ]]; then
            echo "Error: Debes especificar la fase o tarea a iniciar (ej: F1, F2)." >&2
            echo "Uso: $0 start <fase>  (ej: $0 start F1)" >&2
            exit 1
        fi

        ensure_session_file

        # Validar y congelar hash del plan
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

        set_val "sdd_state" "execute"
        set_val "active_task" "$PHASE_OR_TASK"
        echo "🚀 Iniciando fase '$PHASE_OR_TASK' en estado 'execute'."
        echo "🔓 Modificación de código desbloqueada para commits."
        echo "ℹ️  Recuerda incluir '$PHASE_OR_TASK' en tus mensajes de commit (ej: feat($PHASE_OR_TASK): descripción)."
        ;;

    verify)
        ensure_session_file
        PHASE_ID="$ARG"
        echo "🔍 Ejecutando verificación determinista de criterios..."

        # Verificar si la especificación cambió mientras estábamos en execute
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
            if [[ -n "$PHASE_ID" ]]; then
                "$SCRIPT_DIR/verify-crit.sh" "" "$PHASE_ID"
            else
                "$SCRIPT_DIR/verify-crit.sh"
            fi
            VERIFY_EXIT=$?
            if [[ $VERIFY_EXIT -eq 0 ]]; then
                set_val "sdd_state" "verify"
                echo "✅ Verificación exitosa. Estado avanzado a: verify"
                echo "🛑 ALTO: Detén la ejecución y presenta el reporte para auditoría humana del diff."
            else
                exit $VERIFY_EXIT
            fi
        else
            echo "Warning: $SCRIPT_DIR/verify-crit.sh no encontrado o no ejecutable." >&2
            set_val "sdd_state" "verify"
            echo "Estado cambiado a verify."
        fi
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
        fi
        echo "✅ Estado avanzado a: $NEW_STATE"
        ;;

    status)
        ensure_session_file
        CURRENT_STATE=$(get_val "sdd_state")
        ACTIVE_TASK=$(get_val "active_task")
        RECORDED_HASH=$(get_val "plan_hash")
        PLAN_FILE=$(resolve_plan_file)

        echo "=========================================="
        echo "         DISCIPLINE FLOW — ESTADO SDD     "
        echo "=========================================="
        echo " Estado actual  : $CURRENT_STATE"
        echo " Fase activa    : $ACTIVE_TASK"
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
                echo " 🔒 Código      : BLOQUEADO (pre-commit activo para .md/.txt)"
                echo " Siguiente paso : ./scripts/sdd.sh start F1"
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
        echo "Uso: $0 {start <fase>|plan [titulo]|verify [fase]|advance <plan|execute|verify>|status}"
        echo "Ejemplos:"
        echo "  $0 start F1              # Desbloquea código para trabajar en la Fase 1"
        echo "  $0 verify F1             # Corre suite y validación CRIT-XX para Fase 1"
        echo "  $0 plan \"Nueva función\"  # Inicia nuevo plan y bloquea commits de código"
        echo "  $0 status                # Consulta el estado SDD actual"
        exit 1
        ;;
esac
exit 0
