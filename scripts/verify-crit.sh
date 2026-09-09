#!/usr/bin/env bash
# discipline-flow/scripts/verify-crit.sh
# Deterministic CRIT-XX verification for phase closure.

set -euo pipefail

PLAN_FILE="${1:-}"
PHASE_ID="${2:-}"

# 1. Resolver el archivo de plan si no se pasó como argumento
if [ -z "$PLAN_FILE" ]; then
  if [ -f "SESSION.md" ]; then
    PLAN_FILE=$(grep -oE 'PLAN-[0-9]+(\.[0-9]+)?\.md' SESSION.md | head -n 1 || true)
  fi
  if [ -z "$PLAN_FILE" ]; then
    PLAN_FILE=$(ls PLAN-*.md 2>/dev/null | sort -V | tail -n 1 || true)
  fi
fi

if [ -z "$PLAN_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
  echo "ERROR: No se encontró ningún archivo PLAN-*.md válido." >&2
  exit 1
fi

echo "=== VERIFICACIÓN DETERMINISTA DE CRITERIOS ==="
echo "Plan: $PLAN_FILE"
if [ -n "$PHASE_ID" ]; then
  echo "Fase objetivo: $PHASE_ID"
fi
echo "----------------------------------------------"

# 2. Extraer criterios según la fase o de todo el plan
TEMP_CRITS=$(mktemp)
trap 'rm -f "$TEMP_CRITS"' EXIT

if [ -n "$PHASE_ID" ]; then
  # Extrae solo el bloque de la fase indicada: desde su encabezado de nivel 2
  # ("## F1 — ...") hasta el siguiente encabezado de nivel 2. Nunca hasta un
  # subtítulo de nivel 3 como "### Acceptance criteria", que pertenece a la
  # misma fase y antes cortaba la captura antes de llegar a los CRIT-XX.
  # El ancla exige que el ID de fase no siga con otro dígito, para no
  # confundir F1 con F10.
  awk -v phase="$PHASE_ID" '
    $0 ~ ("^## " phase "([^0-9]|$)") { in_phase=1; next }
    in_phase && ($0 ~ /^## /) { in_phase=0 }
    in_phase { print }
  ' "$PLAN_FILE" | grep -E '\- \[[ xX]\] CRIT-[0-9]+' > "$TEMP_CRITS" || true
else
  grep -E '\- \[[ xX]\] CRIT-[0-9]+' "$PLAN_FILE" > "$TEMP_CRITS" || true
fi

if [ ! -s "$TEMP_CRITS" ]; then
  echo "ERROR: No se encontraron criterios CRIT-XX para auditar en $PLAN_FILE." >&2
  exit 1
fi

FAILURES=0
MANUAL_COUNT=0
AUTOMATED_COUNT=0

echo "| Criterio | Tipo | Evidencia en Tests / Estado |"
echo "| :--- | :--- | :--- |"

while IFS= read -r line; do
  CRIT_ID=$(echo "$line" | grep -oE 'CRIT-[0-9]+')

  # Si está marcado explícitamente como manual
  if echo "$line" | grep -qi '(manual)'; then
    echo "| $CRIT_ID | Manual | Pendiente de verificación humana |"
    MANUAL_COUNT=$((MANUAL_COUNT + 1))
    continue
  fi

  AUTOMATED_COUNT=$((AUTOMATED_COUNT + 1))

  # Busca el identificador en directorios estándar de tests o código fuente.
  # --untracked es obligatorio: un test recién escrito en esta misma sesión
  # todavía no está en el índice de git, y sin esta bandera git grep lo
  # ignora por completo, reportando un falso FALLO sobre evidencia que sí
  # existe en el disco.
  MATCHES=$(git grep --untracked -in "$CRIT_ID" -- tests/ test/ spec/ src/ 2>/dev/null || true)

  if [ -z "$MATCHES" ]; then
    echo "| $CRIT_ID | Automatizado | ❌ FALLO: No existe test asociado con la etiqueta $CRIT_ID |"
    FAILURES=$((FAILURES + 1))
  else
    # Toma el primer archivo y línea representativos
    LOCATION=$(echo "$MATCHES" | head -n 1 | awk -F: '{print $1 ":" $2}')
    echo "| $CRIT_ID | Automatizado | ✅ Localizado en \`$LOCATION\` |"
  fi
done < "$TEMP_CRITS"

echo "----------------------------------------------"

if [ "$FAILURES" -gt 0 ]; then
  echo "VEREDICTO: ❌ FALLÓ la verificación de trazabilidad ($FAILURES criterio(s) sin test demostrable)." >&2
  exit 2
fi

echo "Trazabilidad completa: $AUTOMATED_COUNT automatizados vinculados, $MANUAL_COUNT manuales pendientes."

# 3. Detección y ejecución determinista del test-runner
echo "Ejecutando suite de pruebas..."
if [ -f "pyproject.toml" ] || [ -f "pytest.ini" ] || [ -f "setup.cfg" ]; then
  pytest -q
elif [ -f "package.json" ]; then
  npm test
elif [ -f "composer.json" ]; then
  vendor/bin/phpunit
elif [ -f "Cargo.toml" ]; then
  cargo test -q
elif [ -f "go.mod" ]; then
  go test ./...
elif [ -f "pom.xml" ]; then
  mvn test
else
  echo "AVISO: No se detectó runner automático estándar. Ejecución omitida."
fi

echo "VEREDICTO: ✅ Criterios verificados y suite de pruebas en verde."
exit 0
