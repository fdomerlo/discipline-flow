#!/usr/bin/env bash
# scripts/reset.sh — Remove all discipline-flow initialization from a target
# project to start over from zero (plans, state, contract block, hooks).
# Destructive by design: interactive confirmation unless --force.
# Usage runs in place from the skill directory; nothing is copied.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

TARGET_DIR="."
DRY_RUN=false
FORCE=false
SELF_ACK=false

print_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -d, --target-dir <path>  Target project root (default: current directory ".")
      --dry-run            List what would be removed, change nothing
  -f, --force              Non-interactive: remove without asking
      --self               Acknowledge resetting the skill repo itself
  -h, --help               Show this help message

Removes (total fresh start):
  - SESSION.md, SESSION.md.tmp (runtime state)
  - PLAN-*.md at root and under plans/ (including plans/archive/)
  - The managed contract block in AGENTS.md (whole file if only ours)
  - .git/hooks/pre-commit and commit-msg (only if installed by this skill)
  - Legacy vendored scripts/ copies, only if byte-identical to the skill
  - CLAUDE.md, only if it is exactly the legacy '@AGENTS.md' shim

Preserved with a warning: foreign hooks, customized scripts, AGENTS.md
rules outside our block, and any non-shim CLAUDE.md content.

Examples:
  $(basename "$0") -d /path/to/repo
  $(basename "$0") --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--target-dir) TARGET_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -f|--force) FORCE=true; shift ;;
    --self) SELF_ACK=true; shift ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Error: Unknown argument '$1'" >&2; print_help; exit 1 ;;
  esac
done

TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")"
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: target directory '$TARGET_DIR' does not exist." >&2
  exit 1
fi

if [[ "$TARGET_DIR" -ef "$SKILL_DIR" && "$SELF_ACK" != true ]]; then
  echo "Error: target is the skill repo itself. Pass --self to acknowledge." >&2
  exit 1
fi

START_MARKER="<!-- BEGIN DISCIPLINE-FLOW -->"
END_MARKER="<!-- END DISCIPLINE-FLOW -->"

REMOVE=()
SKIP=()

note_remove() { REMOVE+=("$1"); }
note_skip() { SKIP+=("$1"); }

# ---- 1. Inventory (always runs, always shown) ----
# State files
for f in SESSION.md SESSION.md.tmp; do
  if [[ -f "$TARGET_DIR/$f" ]]; then note_remove "$f (state)"; fi
done

# Plans (root + plans/, archive included: total fresh start)
shopt -s nullglob
for f in "$TARGET_DIR"/PLAN-*.md "$TARGET_DIR"/plans/PLAN-*.md "$TARGET_DIR"/plans/archive/PLAN-*.md; do
  [[ -f "$f" ]] || continue
  note_remove "${f#"$TARGET_DIR"/} (plan)"
done
shopt -u nullglob

# AGENTS.md
if [[ -f "$TARGET_DIR/AGENTS.md" ]]; then
  if grep -q "$START_MARKER" "$TARGET_DIR/AGENTS.md"; then
    if awk -v b="$START_MARKER" -v e="$END_MARKER" '
      $0 ~ b {inb=1; next} $0 ~ e {inb=0; next}
      !inb && $0 ~ /[^[:space:]]/ {outside=1} END {exit outside}' "$TARGET_DIR/AGENTS.md"; then
      note_remove "AGENTS.md (whole file: only our block)"
    else
      note_remove "AGENTS.md (managed block only, custom rules preserved)"
    fi
  else
    note_skip "AGENTS.md (no managed block: left untouched)"
  fi
fi

# Legacy CLAUDE.md shim
if [[ -f "$TARGET_DIR/CLAUDE.md" ]]; then
  if [[ -z "$(grep -v '^[[:space:]]*$' "$TARGET_DIR/CLAUDE.md" | grep -v '^@AGENTS.md$' || true)" ]]; then
    note_remove "CLAUDE.md (legacy shim only)"
  else
    note_skip "CLAUDE.md (has custom content: left untouched)"
  fi
fi

# Hooks (only ours: fingerprinted by header)
for h in pre-commit commit-msg; do
  dest="$TARGET_DIR/.git/hooks/$h"
  if [[ -f "$dest" ]]; then
    if grep -q "discipline-flow" "$dest"; then
      note_remove ".git/hooks/$h (ours)"
    else
      note_skip ".git/hooks/$h (foreign hook: left untouched)"
    fi
  fi
done

# Legacy vendored scripts (only byte-identical copies of the skill)
for rel in scripts/sdd.sh scripts/verify-crit.sh scripts/new-plan.sh scripts/lib/sdd-common.sh; do
  if [[ -f "$TARGET_DIR/$rel" ]] && ! [[ "$TARGET_DIR/$rel" -ef "$SKILL_DIR/$rel" ]]; then
    if [[ -f "$SKILL_DIR/$rel" ]] && cmp -s "$TARGET_DIR/$rel" "$SKILL_DIR/$rel"; then
      note_remove "$rel (legacy vendored copy)"
    else
      note_skip "$rel (customized: left untouched)"
    fi
  fi
done

echo "=== discipline-flow reset inventory for $TARGET_DIR ==="
if [[ ${#REMOVE[@]} -eq 0 ]]; then
  echo "Nothing to remove."
else
  echo "Will remove:"
  printf '  - %s\n' "${REMOVE[@]}"
fi
if [[ ${#SKIP[@]} -gt 0 ]]; then
  echo "Will preserve:"
  printf '  - %s\n' "${SKIP[@]}"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry run: no changes made)"
  exit 0
fi

if [[ ${#REMOVE[@]} -eq 0 ]]; then
  exit 0
fi

if [[ "$FORCE" != true ]]; then
  if [[ ! -t 0 ]]; then
    echo "Error: refusing to remove without confirmation in non-interactive mode (pass --force)." >&2
    exit 1
  fi
  read -r -p "Remove the above? [y/N] " answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    echo "Aborted: no changes made."
    exit 0
  fi
fi

# ---- 2. Removal ----
rm -f "$TARGET_DIR/SESSION.md" "$TARGET_DIR/SESSION.md.tmp"

shopt -s nullglob
for f in "$TARGET_DIR"/PLAN-*.md "$TARGET_DIR"/plans/PLAN-*.md "$TARGET_DIR"/plans/archive/PLAN-*.md; do
  [[ -f "$f" ]] || continue
  rm -f "$f"
done
shopt -u nullglob
for d in "$TARGET_DIR/plans/archive" "$TARGET_DIR/plans"; do
  [[ -d "$d" ]] && rmdir "$d" 2>/dev/null || true
done

if [[ -f "$TARGET_DIR/AGENTS.md" ]] && grep -q "$START_MARKER" "$TARGET_DIR/AGENTS.md"; then
  if awk -v b="$START_MARKER" -v e="$END_MARKER" '
    $0 ~ b {inb=1; next} $0 ~ e {inb=0; next}
    !inb && $0 ~ /[^[:space:]]/ {outside=1} END {exit outside}' "$TARGET_DIR/AGENTS.md"; then
    rm -f "$TARGET_DIR/AGENTS.md"
  else
    tmp_strip=$(mktemp)
    awk -v b="$START_MARKER" -v e="$END_MARKER" '
      $0 ~ b {inb=1; next} $0 ~ e {inb=0; next} !inb {print}' "$TARGET_DIR/AGENTS.md" > "$tmp_strip"
    mv "$tmp_strip" "$TARGET_DIR/AGENTS.md"
  fi
fi

if [[ -f "$TARGET_DIR/CLAUDE.md" ]]; then
  if [[ -z "$(grep -v '^[[:space:]]*$' "$TARGET_DIR/CLAUDE.md" | grep -v '^@AGENTS.md$' || true)" ]]; then
    rm -f "$TARGET_DIR/CLAUDE.md"
  fi
fi

for h in pre-commit commit-msg; do
  dest="$TARGET_DIR/.git/hooks/$h"
  if [[ -f "$dest" ]] && grep -q "discipline-flow" "$dest"; then
    rm -f "$dest"
  fi
done

for rel in scripts/sdd.sh scripts/verify-crit.sh scripts/new-plan.sh scripts/lib/sdd-common.sh; do
  if [[ -f "$TARGET_DIR/$rel" ]] && ! [[ "$TARGET_DIR/$rel" -ef "$SKILL_DIR/$rel" ]]; then
    if [[ -f "$SKILL_DIR/$rel" ]] && cmp -s "$TARGET_DIR/$rel" "$SKILL_DIR/$rel"; then
      rm -f "$TARGET_DIR/$rel"
    fi
  fi
done
for d in "$TARGET_DIR/scripts/lib" "$TARGET_DIR/scripts"; do
  [[ -d "$d" ]] && rmdir "$d" 2>/dev/null || true
done

echo ""
echo "Reset complete. Removed ${#REMOVE[@]} item(s)."
if [[ ${#SKIP[@]} -gt 0 ]]; then
  echo "Preserved ${#SKIP[@]} item(s) (see inventory above)."
fi
echo "To start over: <skill-path>/scripts/init.sh -t \"<test-command>\" -d \"$TARGET_DIR\""
