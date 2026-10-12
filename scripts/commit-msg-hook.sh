#!/bin/sh
# Installed as .git/hooks/commit-msg by discipline-flow.
# 1. Rejects commit messages that don't follow Conventional Commits.
# 2. In SDD 'execute' state, verifies that commit references the active phase/task (e.g. F1).
# Bypass in an emergency with: git commit --no-verify (flagged later by verify's bypass audit).

msg_file="$1"
first_line=$(head -n1 "$msg_file")

# Allow native git automated operations and comments/empty lines.
# NOTE: Revert* is intentionally NOT auto-allowed: `git revert` creates a
# real code change, so in 'execute' state it must carry the phase token
# (usually inherited from the reverted message). Merge/fixup/squash are
# git mechanics and stay exempt.
case "$first_line" in
  Merge*|"fixup!"*|"squash!"*|"#"*|"")
    exit 0
    ;;
esac

REVERT_MSG=0
case "$first_line" in
  Revert*|revert*)
    REVERT_MSG=1
    ;;
esac

# Standard Conventional Commits 1.0.0 types
types="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|release"
pattern="^($types)(\([a-zA-Z0-9_.-]+\))?!?: .+"

if [ "$REVERT_MSG" = "0" ]; then
  if ! echo "$first_line" | grep -Eq "$pattern"; then
    echo "❌ commit-msg hook: El formato del mensaje no cumple Conventional Commits."
    echo "  Mensaje recibido: $first_line"
    echo "  Formato esperado: <type>(<scope>): <descripción>"
    echo "  Tipos válidos:    feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, release"
    echo "  Bypass:           git commit --no-verify (será auditado en verify)"
    exit 1
  fi
fi

SESSION_FILE="SESSION.md"

# Canonical parser when available, inline awk fallback otherwise.
# {{SKILL_PATH}} is baked by init.sh at install time (skill dir relative
# to the repo root); an unbaked source simply misses and falls back.
_GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || printf '.')
_SKILL_LIB="$_GIT_ROOT/{{SKILL_PATH}}/scripts/lib/sdd-common.sh"
if [ -f "$_SKILL_LIB" ]; then
    # shellcheck source=lib/sdd-common.sh
    . "$_SKILL_LIB"
fi

_cget() {
    if command -v sdd_get_val >/dev/null 2>&1; then
        sdd_get_val "$1" "$SESSION_FILE"
    else
        awk -v k="$1" '/^---$/ { if (c++ == 1) exit } c==1 && $0 ~ ("^" k ":") { sub("^" k ":[[:space:]]*", ""); gsub(/\r/, ""); print $1 }' "$SESSION_FILE"
    fi
}

if [ -f "$SESSION_FILE" ]; then
    # Extract sdd_state
    sdd_state=$(_cget "sdd_state")

    if [ "$sdd_state" = "execute" ]; then
        # Extract active_task (e.g. F1)
        active_task=$(_cget "active_task")

        if [ "$active_task" = "none" ] || [ -z "$active_task" ]; then
            echo "❌ commit-msg hook: El estado SDD es 'execute' pero no hay ninguna fase activa en SESSION.md."
            echo "👉 Inicia la fase con: {{SKILL_PATH}}/scripts/sdd.sh start F1  (o F2, etc.)"
            exit 1
        fi

        # Check if the commit message contains the active phase/task as an isolated token or scope
        if ! grep -qiE "(^|[^a-zA-Z0-9_-])${active_task}([^a-zA-Z0-9_-]|$)" "$msg_file"; then
            echo "❌ commit-msg hook: Estás en la fase '$active_task', pero el mensaje de commit no la menciona."
            echo "  Fase activa requerida: $active_task"
            echo "  Ejemplos válidos:"
            echo "    feat($active_task): implementar rotación de tokens"
            echo "    test: agregar caso de prueba para expiración ($active_task)"
            echo "👉 Ajusta el mensaje o cambia de fase con: {{SKILL_PATH}}/scripts/sdd.sh start <fase>"
            exit 1
        fi
    fi
fi

exit 0
