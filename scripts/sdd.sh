#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_FILE="SESSION.md"

# Asegurar que SESSION.md existe con frontmatter básico si no está presente
ensure_session_file() {
    if [[ ! -f "$SESSION_FILE" ]]; then
        cat <<EOF > "$SESSION_FILE"
---
sdd_state: plan
active_task: none
plan_hash: none
---
# Session Checkpoint

- **Plan:** None
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
        BEGIN { in_fm=0 }
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
        set_val "sdd_state" "plan"
        set_val "active_task" "none"
        echo "📋 Modo PLAN activo. El código fuente está bloqueado para commits hasta iniciar una fase."
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
            echo "Estado cambiado manualmente a verify."
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
        echo "=========================================="
        echo "         DISCIPLINE FLOW — ESTADO SDD     "
        echo "=========================================="
        echo " Estado actual : $CURRENT_STATE"
        echo " Fase activa   : $ACTIVE_TASK"
        case "$CURRENT_STATE" in
            plan)
                echo " 🔒 Código     : BLOQUEADO (pre-commit activo para .md/.txt)"
                echo " Siguiente paso: ./scripts/sdd.sh start F1"
                ;;
            execute)
                echo " 🔓 Código     : DESBLOQUEADO (commits deben incluir '$ACTIVE_TASK')"
                echo " Siguiente paso: ./scripts/sdd.sh verify $ACTIVE_TASK"
                ;;
            verify)
                echo " 🛑 Auditoría  : En espera de aprobación humana del diff."
                echo " Siguiente paso: Aprobar diff y pasar a la siguiente fase."
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
