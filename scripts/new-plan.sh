#!/usr/bin/env bash
# scripts/new-plan.sh — Scaffold the next PLAN-N.md from template
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="$SKILL_DIR/assets/PLAN.md.template"

TITLE="New Cycle"
TARGET_DIR="."

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Error: Template file not found at '$TEMPLATE_FILE'" >&2
  exit 1
fi

print_help() {
  cat <<EOF
Usage: $(basename "$0") [TITLE] [OPTIONS]

Options:
  -t, --title <title>   Title of the plan (default: "New Cycle")
  -d, --dir <directory> Target directory for the plan (canonical: 'plans/' when present, otherwise '.')
  -h, --help            Show this help message

Examples:
  $(basename "$0") "Migrate auth to JWT"
  $(basename "$0") -t "Refactor database layer" -d plans
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--title)
      TITLE="$2"
      shift 2
      ;;
    -d|--dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      if [[ "$TITLE" == "New Cycle" ]]; then
        TITLE="$1"
        shift
      else
        echo "Error: Unknown argument '$1'" >&2
        print_help
        exit 1
      fi
      ;;
  esac
done

# If 'plans/' exists and target was left as default '.', place plan in 'plans/'
if [[ "$TARGET_DIR" == "." && -d "plans" ]]; then
  TARGET_DIR="plans"
fi

mkdir -p "$TARGET_DIR"

# Find highest N among PLAN-N*.md in TARGET_DIR and root
highest=0
shopt -s nullglob
for f in "$TARGET_DIR"/PLAN-*.md PLAN-*.md; do
  if [[ -f "$f" ]]; then
    base="$(basename "$f")"
    if [[ "$base" =~ ^PLAN-([0-9]+) ]]; then
      num="${BASH_REMATCH[1]}"
      if (( num > highest )); then
        highest=$num
      fi
    fi
  fi
done
shopt -u nullglob

NEXT_N=$((highest + 1))
PLAN_FILE="$TARGET_DIR/PLAN-$NEXT_N.md"

if [[ -f "$PLAN_FILE" ]]; then
  echo "Error: '$PLAN_FILE' already exists." >&2
  exit 1
fi

content="$(<"$TEMPLATE_FILE")"
content="${content//\{\{N\}\}/$NEXT_N}"
content="${content//\{\{TITLE\}\}/$TITLE}"

printf '%s\n' "$content" > "$PLAN_FILE"
echo "Created new plan: $PLAN_FILE"

