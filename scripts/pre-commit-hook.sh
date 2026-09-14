#!/usr/bin/env bash
# discipline-flow/scripts/pre-commit-hook.sh
# Installed as .git/hooks/pre-commit.
# Bloquea cambios de código fuente mientras el proyecto esté en fase de diseño/planificación (sdd_state: plan).

SESSION_FILE="SESSION.md"
if [[ ! -f "$SESSION_FILE" ]]; then
    exit 0
fi

STATE=$(awk '/^---$/ { if (c++ == 1) exit } c==1 && /^sdd_state:/ { sub(/^sdd_state:[[:space:]]*/, ""); gsub(/\r/, ""); print $1 }' "$SESSION_FILE")

# Barrera: Prohibido tocar código en fase de planificación
if [[ "$STATE" == "plan" ]]; then
    # Detecta cambios staged en archivos que no sean Markdown o texto de documentación
    STAGED_CODE=$(git diff --cached --name-only | grep -vE '\.(md|txt|markdown)$' || true)
    if [[ -n "$STAGED_CODE" ]]; then
        echo "❌ Bloqueo Discipline Flow: El proyecto está en fase de diseño ('sdd_state: plan')."
        echo "   El contrato SDD prohíbe commitear código fuente sin haber iniciado una fase activa."
        echo ""
        echo "Archivos restringidos en este commit:"
        echo "$STAGED_CODE" | sed 's/^/  - /'
        echo ""
        echo "👉 Para iniciar la fase y desbloquear código, ejecuta:"
        echo "   ./scripts/sdd.sh start F1   (o la fase correspondiente)"
        echo ""
        echo "   (En caso de emergencia extrema, puedes eludir con: git commit --no-verify)"
        exit 1
    fi
fi

exit 0
