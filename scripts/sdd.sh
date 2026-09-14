#!/usr/bin/env bash
set -e

SESSION_FILE="SESSION.md"

if [[ ! -f "$SESSION_FILE" ]]; then
    echo "Error: No se encontró $SESSION_FILE."
    exit 1
fi

COMMAND=$1
ARG=$2

# Utilidades coreutils para mutar el YAML inmutable
get_val() { grep "^$1:" "$SESSION_FILE" | awk '{print $2}'; }
set_val() { sed -i "s/^$1:.*/$1: $2/" "$SESSION_FILE"; }

CURRENT_STATE=$(get_val "sdd_state")

case "$COMMAND" in
    advance)
        NEW_STATE=$ARG
        if [[ ! "$NEW_STATE" =~ ^(plan|execute|verify)$ ]]; then
            echo "Error: Estado inválido. Usa plan, execute o verify."
            exit 1
        fi

        set_val "sdd_state" "$NEW_STATE"
        echo "✅ Estado avanzado a: $NEW_STATE"
        ;;

    start)
        TASK=$ARG
        if [[ -z "$TASK" ]]; then
            echo "Error: Debes especificar un nombre de tarea."
            exit 1
        fi

        set_val "sdd_state" "execute"
        set_val "active_task" "$TASK"
        echo "🚀 Iniciando tarea '$TASK' en fase execute."
        ;;

    status)
        echo "Estado actual: $CURRENT_STATE"
        echo "Tarea activa: $(get_val 'active_task')"
        ;;

    *)
        echo "Uso: $0 {advance <fase>|start <tarea>|status}"
        exit 1
        ;;
esac
exit 0