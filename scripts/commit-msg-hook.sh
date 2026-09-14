#!/bin/sh
# Installed as .git/hooks/commit-msg by discipline-flow.
# 1. Rejects commit messages that don't follow Conventional Commits.
# 2. In SDD 'execute' state, verifies that commit references the active phase/task (e.g. F1).
# Bypass in an emergency with: git commit --no-verify

msg_file="$1"
first_line=$(head -n1 "$msg_file")

# Allow native git automated operations and comments/empty lines
case "$first_line" in
  Merge*|revert*|Revert*|"fixup!"*|"squash!"*|"#"*|"")
    exit 0
    ;;
esac

# Standard Conventional Commits 1.0.0 types
types="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|release"
pattern="^($types)(\([a-zA-Z0-9_.-]+\))?!?: .+"

if ! echo "$first_line" | grep -Eq "$pattern"; then
  echo "❌ commit-msg hook: El formato del mensaje no cumple Conventional Commits."
  echo "  Mensaje recibido: $first_line"
  echo "  Formato esperado: <type>(<scope>): <descripción>"
  echo "  Tipos válidos:    feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, release"
  echo "  Bypass:           git commit --no-verify"
  exit 1
fi

SESSION_FILE="SESSION.md"
if [ -f "$SESSION_FILE" ]; then
    # Extract sdd_state
    sdd_state=$(awk '/^---$/ { if (c++ == 1) exit } c==1 && /^sdd_state:/ { sub(/^sdd_state:[[:space:]]*/, ""); gsub(/\r/, ""); print $1 }' "$SESSION_FILE")

    if [ "$sdd_state" = "execute" ]; then
        # Extract active_task (e.g. F1)
        active_task=$(awk '/^---$/ { if (c++ == 1) exit } c==1 && /^active_task:/ { sub(/^active_task:[[:space:]]*/, ""); gsub(/\r/, ""); print $1 }' "$SESSION_FILE")

        if [ "$active_task" = "none" ] || [ -z "$active_task" ]; then
            echo "❌ commit-msg hook: El estado SDD es 'execute' pero no hay ninguna fase activa en SESSION.md."
            echo "👉 Inicia la fase con: ./scripts/sdd.sh start F1  (o F2, etc.)"
            exit 1
        fi

        # Check if the commit message contains the active phase/task as an isolated token or scope
        if ! grep -qiE "(^|[^a-zA-Z0-9_-])${active_task}([^a-zA-Z0-9_-]|$)" "$msg_file"; then
            echo "❌ commit-msg hook: Estás en la fase '$active_task', pero el mensaje de commit no la menciona."
            echo "  Fase activa requerida: $active_task"
            echo "  Ejemplos válidos:"
            echo "    feat($active_task): implementar rotación de tokens"
            echo "    test: agregar caso de prueba para expiración ($active_task)"
            echo "👉 Ajusta el mensaje o cambia de fase con: ./scripts/sdd.sh start <fase>"
            exit 1
        fi
    fi
fi

exit 0
