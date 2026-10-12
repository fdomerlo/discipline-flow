#!/usr/bin/env bash
# tests/run.sh — zero-dependency test runner (pure bash + coreutils).
# Discovers tests/test-*.sh, runs each hermetically, reports TAP-ish summary.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
FAILED_FILES=()

shopt -s nullglob
TEST_FILES=("$REPO_ROOT"/tests/test-*.sh)
shopt -u nullglob

if [[ ${#TEST_FILES[@]} -eq 0 ]]; then
    echo "No test files found in tests/test-*.sh" >&2
    exit 1
fi

for t in "${TEST_FILES[@]}"; do
    name=$(basename "$t")
    if bash "$t"; then
        echo "ok - $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL - $name" >&2
        FAIL=$((FAIL + 1))
        FAILED_FILES+=("$name")
    fi
done

echo "----------------------------------------------"
echo "Tests: $((PASS + FAIL)) passed, $PASS ok, $FAIL failed."

if [[ $FAIL -gt 0 ]]; then
    echo "Failed: ${FAILED_FILES[*]}" >&2
    exit 1
fi
exit 0
