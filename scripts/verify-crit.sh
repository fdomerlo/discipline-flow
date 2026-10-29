#!/usr/bin/env bash
# discipline-flow/scripts/verify-crit.sh
# Deterministic CRIT-XX verification for phase closure.
# Supports human/Markdown output (default) and machine-readable JSON (--json or SDD_OUTPUT_FORMAT=json).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/sdd-common.sh" ]; then
    # shellcheck source=lib/sdd-common.sh
    . "$SCRIPT_DIR/lib/sdd-common.sh"
fi

JSON_OUTPUT=0
if [ "${SDD_OUTPUT_FORMAT:-}" = "json" ]; then
    JSON_OUTPUT=1
fi

POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --json)
            JSON_OUTPUT=1
            shift
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

PLAN_FILE="${POSITIONAL[0]:-}"
PHASE_ID="${POSITIONAL[1]:-}"

# Helper to escape strings for JSON output without external jq dependency
json_escape() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

emit_json() {
    local passed="$1"
    local exit_code="$2"
    local stage="$3"
    local err_msg="${4:-}"
    local test_passed="${5:-false}"

    local missing_json=""
    local item
    for item in "${MISSING_CRITS[@]:-}"; do
        [ -n "$item" ] || continue
        if [ -n "$missing_json" ]; then missing_json="${missing_json},"; fi
        missing_json="${missing_json}\"$(json_escape "$item")\""
    done

    local verified_json=""
    for item in "${VERIFIED_CRITS[@]:-}"; do
        [ -n "$item" ] || continue
        local cid="${item%%|*}"
        local cloc="${item#*|}"
        if [ -n "$verified_json" ]; then verified_json="${verified_json},"; fi
        verified_json="${verified_json}{\"id\":\"$(json_escape "$cid")\",\"location\":\"$(json_escape "$cloc")\"}"
    done

    local bypass_json=""
    for item in "${BYPASS_SHAS[@]:-}"; do
        [ -n "$item" ] || continue
        if [ -n "$bypass_json" ]; then bypass_json="${bypass_json},"; fi
        bypass_json="${bypass_json}\"$(json_escape "$item")\""
    done

    local err_field="null"
    if [ -n "$err_msg" ]; then
        err_field="\"$(json_escape "$err_msg")\""
    fi

    printf '{"passed":%s,"exit_code":%d,"stage":"%s","plan_file":"%s","phase_id":"%s","automated_count":%d,"manual_count":%d,"failures":%d,"missing_crits":[%s],"verified_crits":[%s],"bypass_commits":[%s],"test_suite_passed":%s,"error":%s}\n' \
        "$passed" \
        "$exit_code" \
        "$(json_escape "$stage")" \
        "$(json_escape "$PLAN_FILE")" \
        "$(json_escape "$PHASE_ID")" \
        "${AUTOMATED_COUNT:-0}" \
        "${MANUAL_COUNT:-0}" \
        "${FAILURES:-0}" \
        "$missing_json" \
        "$verified_json" \
        "$bypass_json" \
        "$test_passed" \
        "$err_field"
}

FAILURES=0
MANUAL_COUNT=0
AUTOMATED_COUNT=0
MISSING_CRITS=()
VERIFIED_CRITS=()
BYPASS_SHAS=()

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
    if [ "$JSON_OUTPUT" -eq 1 ]; then
      emit_json "false" 1 "precondition" "sdd_state in SESSION.md is '$sdd_state'. Validations require 'verify' or 'execute' state." "false"
    else
      echo "ERROR: sdd_state in SESSION.md is '$sdd_state'. Validations require 'verify' or 'execute' state." >&2
    fi
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
  if [ "$JSON_OUTPUT" -eq 1 ]; then
    emit_json "false" 1 "precondition" "No se encontró ningún archivo PLAN-*.md válido." "false"
  else
    echo "ERROR: No se encontró ningún archivo PLAN-*.md válido." >&2
  fi
  exit 1
fi

# 1b. Bloqueo determinista de bloques '## DECISIÓN ABIERTA' sin resolver
if grep -qiE '^##+[[:space:]]+DECISI(Ó|O)N ABIERTA' "$PLAN_FILE"; then
  if [ "$JSON_OUTPUT" -eq 1 ]; then
    emit_json "false" 2 "open_decision" "El plan '$PLAN_FILE' contiene un bloque 'DECISIÓN ABIERTA' sin resolver." "false"
  else
    echo "ERROR: ❌ El plan '$PLAN_FILE' contiene un bloque 'DECISIÓN ABIERTA' sin resolver." >&2
  fi
  exit 2
fi

if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "=== VERIFICACIÓN DETERMINISTA DE CRITERIOS ==="
  echo "Plan: $PLAN_FILE"
  if [ -n "$PHASE_ID" ]; then
    echo "Fase objetivo: $PHASE_ID"
  fi
  echo "----------------------------------------------"
fi

# 2. Extraer criterios según la fase o de todo el plan
TEMP_CRITS=$(mktemp)
trap 'rm -f "$TEMP_CRITS"' EXIT

if [ -n "$PHASE_ID" ]; then
  awk -v phase="$PHASE_ID" '
    $0 ~ ("^## " phase "([^0-9]|$)") { in_phase=1; next }
    in_phase && ($0 ~ /^## /) { in_phase=0 }
    in_phase { print }
  ' "$PLAN_FILE" | grep -E '\- \[[ xX]\] CRIT-[0-9]+' > "$TEMP_CRITS" || true
else
  grep -E '\- \[[ xX]\] CRIT-[0-9]+' "$PLAN_FILE" > "$TEMP_CRITS" || true
fi

if [ ! -s "$TEMP_CRITS" ]; then
  if [ "$JSON_OUTPUT" -eq 1 ]; then
    emit_json "false" 1 "precondition" "No se encontraron criterios CRIT-XX para auditar en $PLAN_FILE." "false"
  else
    echo "ERROR: No se encontraron criterios CRIT-XX para auditar en $PLAN_FILE." >&2
  fi
  exit 1
fi

if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "| Criterio | Tipo | Evidencia en Tests / Estado |"
  echo "| :--- | :--- | :--- |"
fi

while IFS= read -r line; do
  CRIT_ID=$(echo "$line" | grep -oE 'CRIT-[0-9]+')

  # Si está marcado explícitamente como manual
  if echo "$line" | grep -qi '(manual)'; then
    if [ "$JSON_OUTPUT" -eq 0 ]; then
      echo "| $CRIT_ID | Manual | Pendiente de verificación humana |"
    fi
    MANUAL_COUNT=$((MANUAL_COUNT + 1))
    continue
  fi

  AUTOMATED_COUNT=$((AUTOMATED_COUNT + 1))

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
    if [ "$JSON_OUTPUT" -eq 0 ]; then
      echo "| $CRIT_ID | Automatizado | ❌ FALLO: No existe test asociado con la etiqueta $CRIT_ID |"
    fi
    MISSING_CRITS+=("$CRIT_ID")
    FAILURES=$((FAILURES + 1))
  else
    LOCATION=$(echo "$MATCHES" | head -n 1 | awk -F: '{print $1 ":" $2}')
    VERIFIED_CRITS+=("${CRIT_ID}|${LOCATION}")
    if [ "$JSON_OUTPUT" -eq 0 ]; then
      echo "| $CRIT_ID | Automatizado | ✅ Localizado en \`$LOCATION\` |"
    fi
  fi
done < "$TEMP_CRITS"

if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "----------------------------------------------"
fi

if [ "$FAILURES" -gt 0 ]; then
  if [ "$JSON_OUTPUT" -eq 1 ]; then
    emit_json "false" 2 "traceability" "FALLÓ la verificación de trazabilidad ($FAILURES criterio(s) sin test demostrable)." "false"
  else
    echo "VEREDICTO: ❌ FALLÓ la verificación de trazabilidad ($FAILURES criterio(s) sin test demostrable)." >&2
  fi
  exit 2
fi

if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "Trazabilidad completa: $AUTOMATED_COUNT automatizados vinculados, $MANUAL_COUNT manuales pendientes."
fi

# 3. Auditoría de bypass (P2-10)
if [ -n "$PHASE_ID" ] && [ -f "SESSION.md" ]; then
  _BASE=$(sed -n 's/^- \*\*Phase-start commit:\*\* *//p' SESSION.md 2>/dev/null | head -n 1 | tr -d ' \r' || true)
  if [ -z "$_BASE" ]; then
    if [ "$JSON_OUTPUT" -eq 0 ]; then
      echo "Bypass audit: sin marcador de inicio de fase (sesión previa a P2), omitida."
    fi
  elif ! git merge-base --is-ancestor "$_BASE" HEAD 2>/dev/null; then
    if [ "$JSON_OUTPUT" -eq 0 ]; then
      echo "Bypass audit: marcador '$_BASE' no es ancestro de HEAD (rebase/reset?), omitida." >&2
    fi
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
        BYPASS_SHAS+=("$_sha")
        if [ "$JSON_OUTPUT" -eq 0 ]; then
          echo "| ⚠️ bypass | $_sha | $_subj |" >&2
        fi
        _BYPASS=$((_BYPASS + 1))
      fi
    done < <(git log --no-merges --format='%H %s' "$_BASE..HEAD" 2>/dev/null || true)
    _MERGES=$(git log --merges --format='%H' "$_BASE..HEAD" 2>/dev/null | wc -l | tr -d ' ' || true)
    if [ "$_BYPASS" -gt 0 ]; then
      if [ "$JSON_OUTPUT" -eq 1 ]; then
        emit_json "false" 2 "bypass_audit" "FALLÓ la auditoría de bypass ($_BYPASS commit(s) de código sin token '$PHASE_ID' desde el inicio de fase)." "false"
      else
        echo "VEREDICTO: ❌ FALLÓ la auditoría de bypass ($_BYPASS commit(s) de código sin token '$PHASE_ID' desde el inicio de fase)." >&2
        echo "   Reescribí el mensaje con el token o documentá la emergencia para el auditor humano." >&2
      fi
      exit 2
    fi
    if [ "$JSON_OUTPUT" -eq 0 ]; then
      echo "Bypass audit: limpia (0 commits evasores, $_MERGES merges informativos)."
    fi
  fi
fi

# 4. Detección y ejecución determinista del test-runner
if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "Ejecutando suite de pruebas..."
fi

run_test_suite() {
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
    bash -c "$TEST_COMMAND"
  else
    return 127
  fi
}

if [ "$JSON_OUTPUT" -eq 1 ]; then
  set +e
  TEST_OUT=$(run_test_suite 2>&1)
  TEST_RC=$?
  set -e
  if [ "$TEST_RC" -eq 127 ]; then
    emit_json "false" 1 "test_suite" "No se detectó suite de pruebas ejecutable para validar los criterios." "false"
    exit 1
  elif [ "$TEST_RC" -ne 0 ]; then
    emit_json "false" 1 "test_suite" "Test suite failed (exit $TEST_RC): $TEST_OUT" "false"
    exit 1
  fi
  emit_json "true" 0 "complete" "" "true"
  exit 0
else
  set +e
  run_test_suite
  TEST_RC=$?
  set -e
  if [ "$TEST_RC" -eq 127 ]; then
    echo "ERROR: ❌ No se detectó suite de pruebas ejecutable para validar los criterios. El gate de verificación requiere pruebas reales demostrables." >&2
    exit 1
  elif [ "$TEST_RC" -ne 0 ]; then
    exit "$TEST_RC"
  fi
  echo "VEREDICTO: ✅ Criterios verificados y suite de pruebas en verde."
  exit 0
fi
