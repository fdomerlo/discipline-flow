#!/usr/bin/env bash
# discipline-flow/scripts/tick-plan.sh
# Single deterministic writer of `- [x]` checkboxes in PLAN-*.md.
# Called by verify-crit.sh ONLY after traceability + suite are green, so the
# agent never ticks by hand (and never forgets to).
#
# Usage:
#   tick-plan.sh phase <plan> <F-id>   Tick automated CRIT-XX of that phase
#   tick-plan.sh all <plan>            Tick automated CRIT-XX of every phase
#   tick-plan.sh cycle <plan>          Tick derivable "whole cycle" criteria
#   tick-plan.sh scope-clean <plan>    Tick the "Out of scope" line (the C2
#                                      audit found no leaks)
# Manual criteria `(manual)` are never ticked here: only a human does that.
# Prints the number of boxes ticked on stdout.

set -euo pipefail

MODE="${1:-}"
PLAN="${2:-}"
PHASE="${3:-}"

if [[ -z "$MODE" || -z "$PLAN" || ! -f "$PLAN" ]]; then
  echo "Usage: $0 {phase <plan> <F-id>|all <plan>|cycle <plan>|scope-clean <plan>}" >&2
  exit 1
fi
if [[ "$MODE" == "phase" && -z "$PHASE" ]]; then
  echo "Error: 'phase' mode requires a phase id (e.g. F1)." >&2
  exit 1
fi

# Count unticked criteria lines. $1 = "auto" (automated only) | "any".
count_unticked() {
  local kind="$1"
  awk -v kind="$kind" '
    /^- \[ \] CRIT-[0-9]+/ {
      if (kind == "auto" && tolower($0) ~ /\(manual\)/) next
      n++
    }
    END { print n + 0 }
  ' "$PLAN"
}

count_ticked_total() {
  grep -cE '^- \[[xX]\] ' "$PLAN" || true
}

BEFORE=$(count_ticked_total)
TMP="${PLAN}.tick.$$"
trap 'rm -f "$TMP"' EXIT

case "$MODE" in
  phase|all)
    awk -v phase="$PHASE" -v all="$([[ "$MODE" == all ]] && echo 1 || echo 0)" '
      all == 1 { inp = 1 }
      all == 0 && $0 ~ ("^## " phase "([^0-9]|$)") { inp = 1; print; next }
      all == 0 && inp && /^## / { inp = 0 }
      inp && /^- \[ \] CRIT-[0-9]+/ && tolower($0) !~ /\(manual\)/ {
        sub(/^- \[ \]/, "- [x]")
      }
      { print }
    ' "$PLAN" > "$TMP"
    ;;
  cycle)
    AUTO_LEFT=$(count_unticked auto)
    ANY_LEFT=$(count_unticked any)
    awk -v auto_left="$AUTO_LEFT" -v any_left="$ANY_LEFT" '
      /^## / { cyc = (tolower($0) ~ /^## criteria for the whole cycle/) }
      cyc && /^- \[ \] Full suite green/ && auto_left == 0 { sub(/^- \[ \]/, "- [x]") }
      cyc && /^- \[ \] Every phase/ && any_left == 0 { sub(/^- \[ \]/, "- [x]") }
      { print }
    ' "$PLAN" > "$TMP"
    ;;
  scope-clean)
    awk '
      /^## / { cyc = (tolower($0) ~ /^## criteria for the whole cycle/) }
      cyc && /^- \[ \] Nothing from/ { sub(/^- \[ \]/, "- [x]") }
      { print }
    ' "$PLAN" > "$TMP"
    ;;
  *)
    echo "Error: unknown mode '$MODE'." >&2
    exit 1
    ;;
esac

# Only replace the file when something changed (keeps mtime/hash stable).
if ! cmp -s "$PLAN" "$TMP"; then
  mv "$TMP" "$PLAN"
fi

AFTER=$(count_ticked_total)
echo $((AFTER - BEFORE))
