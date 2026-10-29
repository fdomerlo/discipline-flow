#!/usr/bin/env bash
# discipline-flow/scripts/verify-crit.sh
# Deterministic CRIT-XX verification for phase closure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/sdd-common.sh" ]; then
    # shellcheck source=lib/sdd-common.sh
    . "$SCRIPT_DIR/lib/sdd-common.sh"
fi

PLAN_FILE="${1:-}"
PHASE_ID="${2:-}"

# Directorios de código donde buscar evidencia CRIT-XX.
# Override: CRIT_SEARCH_PATHS="tests src pkg" ./scripts/verify-crit.sh
: "${CRIT_SEARCH_PATHS:=tests test __tests__ spec e2e src lib pkg internal app}"

# 1. Validar el estado actual en SESSION.md y resolver el archivo de plan
if [ -f "SESSION.md" ]; then
  if command -v sdd_get_val >/dev/null 2>&1; then
    sdd_state=$(sdd_get_val "sdd_state" "SESSION.md" || echo "")
  else
    sdd_state=$(awk '/^---$/ { if (c++ == 1) exit } c==1 && /^sdd_state:/ { print $2 }' "SESSION.md" || echo "")
  fi
  if [ "$sdd_state" != "verify" ] && [ "$sdd_state" != "execute" ]; then
    echo "ERROR: sdd_state in SESSION.md is '$sdd_state'. Validations require 'verify' or 'execute' state." >&2
    exit 1
  fi
fi

if [ -z "$PLAN_FILE" ]; then
  if command -v sdd_resolve_plan >/dev/null 2>&1; then
    PLAN_FILE=$(sdd_resolve_plan "SESSION.md" || true)
  else
    if [ -f "SESSION.md" ]; then
      PLAN_FILE=$(grep -oE '([a-zA-Z0-9_.-]+/)?PLAN-[0-9]+(\.[0-9]+)?\.md' SESSION.md | head -n 1 || true)
    fi
    if [ -z "$PLAN_FILE" ]; then
      PLAN_FILE=$(ls plans/PLAN-*.md 2>/dev/null | sort -V | tail -n 1 || true)
    fi
    if [ -z "$PLAN_FILE" ]; then
      PLAN_FILE=$(ls PLAN-*.md 2>/dev/null | sort -V | tail -n 1 || true)
    fi
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
  # ("## F1 — ...") hasta el siguiente encabezado de nivel 2.
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

  # Busca el identificador en directorios de código (no en prosa *.md para
  # evitar el falso positivo del propio PLAN-*.md que declara el criterio).
  # --untracked es obligatorio para tests recién creados aún no en git index.
  # Solo se consultan directorios existentes de CRIT_SEARCH_PATHS.
  _SEARCH=""
  # shellcheck disable=SC2086
  for _d in $CRIT_SEARCH_PATHS; do
    if [ -e "$_d" ]; then
      _SEARCH="$_SEARCH $_d"
    fi
  done
  if [ -z "$_SEARCH" ]; then
    _SEARCH="."
  fi
  # shellcheck disable=SC2086
  MATCHES=$(git grep --untracked -in "$CRIT_ID" -- $_SEARCH 2>/dev/null | grep -v '\.md:' || true)

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

# 3. Auditoría de bypass (P2-10): ningún hook corre con --no-verify por
# definición, así que verify detecta a posteriori los commits de código
# posteriores al inicio de la fase cuyo mensaje evadió el commit-msg hook
# (sin token de fase). Alcance: solo non-merge commits con cambios de código
# (no .md/.txt); los merges se informan sin bloquear.
if [ -n "$PHASE_ID" ] && [ -f "SESSION.md" ]; then
  _BASE=$(sed -n 's/^- \*\*Phase-start commit:\*\* *//p' SESSION.md 2>/dev/null | head -n 1 | tr -d ' \r' || true)
  if [ -z "$_BASE" ]; then
    echo "Bypass audit: sin marcador de inicio de fase (sesión previa a P2), omitida."
  elif ! git merge-base --is-ancestor "$_BASE" HEAD 2>/dev/null; then
    echo "Bypass audit: marcador '$_BASE' no es ancestro de HEAD (rebase/reset?), omitida." >&2
  else
    _BYPASS=0
    _MERGES=0
    while IFS= read -r _line; do
      [ -n "$_line" ] || continue
      _sha=${_line%% *}
      _subj=${_line#* }
      if printf '%s' "$_subj" | grep -qiE "(^|[^a-zA-Z0-9_-])${PHASE_ID}([^a-zA-Z0-9_-]|$)"; then
        continue
      fi
      if git diff-tree --no-commit-id --name-only -r "$_sha" 2>/dev/null | grep -vE '\.(md|txt|markdown)$' | grep -q .; then
        echo "| ⚠️ bypass | $_sha | $_subj |" >&2
        _BYPASS=$((_BYPASS + 1))
      fi
    done < <(git log --no-merges --format='%H %s' "$_BASE..HEAD" 2>/dev/null || true)
    _MERGES=$(git log --merges --format='%H' "$_BASE..HEAD" 2>/dev/null | wc -l | tr -d ' ' || true)
    if [ "$_BYPASS" -gt 0 ]; then
      echo "VEREDICTO: ❌ FALLÓ la auditoría de bypass ($_BYPASS commit(s) de código sin token '$PHASE_ID' desde el inicio de fase)." >&2
      echo "   Reescribí el mensaje con el token o documentá la emergencia para el auditor humano." >&2
      exit 2
    fi
    echo "Bypass audit: limpia (0 commits evasores, $_MERGES merges informativos)."
  fi
fi

# 4. Detección y ejecución determinista del test-runner
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
elif [ -x "tests/run.sh" ]; then
  ./tests/run.sh
elif [ -n "${TEST_COMMAND:-}" ]; then
  # bash -c preserva quoted-args y cadenas (ej: pytest -k "foo bar").
  bash -c "$TEST_COMMAND"
else
  echo "ERROR: ❌ No se detectó suite de pruebas ejecutable para validar los criterios. El gate de verificación requiere pruebas reales demostrables." >&2
  exit 1
fi

# 5. Auto-tick (única vía de escritura de `- [x]`): solo se llega aquí si la
# trazabilidad, la auditoría de bypass y la suite están en verde. Se tildan los
# criterios automatizados verificados y los criterios de ciclo derivables.
# Los criterios `(manual)` quedan para el humano.
if [ -x "$SCRIPT_DIR/tick-plan.sh" ]; then
  if [ -n "$PHASE_ID" ]; then
    _T1=$("$SCRIPT_DIR/tick-plan.sh" phase "$PLAN_FILE" "$PHASE_ID")
  else
    _T1=$("$SCRIPT_DIR/tick-plan.sh" all "$PLAN_FILE")
  fi
  _T2=$("$SCRIPT_DIR/tick-plan.sh" cycle "$PLAN_FILE")
  echo "Plan actualizado: $_T1 criterio(s) de fase y $((_T2)) de ciclo tildados en $PLAN_FILE."
else
  echo "Warning: $SCRIPT_DIR/tick-plan.sh no encontrado; el plan NO fue actualizado." >&2
fi

echo "VEREDICTO: ✅ Criterios verificados y suite de pruebas en verde."
exit 0
