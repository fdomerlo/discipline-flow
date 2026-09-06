#!/usr/bin/env bash
# scripts/init.sh — Bootstrap repository with discipline-flow conventions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="$SKILL_DIR/assets/AGENTS.md.template"
HOOK_SRC="$SKILL_DIR/scripts/commit-msg-hook.sh"

PROJECT_NAME=""
TEST_COMMAND=""
COMMIT_TYPES="feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, release"
INSTALL_HOOK=false
TARGET_DIR="."
FORCE=false

print_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -p, --project-name <name>    Project name (default: directory name of target)
  -t, --test-cmd <command>     Command to run test suite (e.g. "pytest", "npm test")
  -c, --commit-types <types>   Allowed commit types (default: standard Conventional Commits)
  -d, --target-dir <path>      Target directory to bootstrap (default: current directory ".")
      --with-hook              Install .git/hooks/commit-msg
      --no-hook                Skip git hook installation (default)
  -f, --force                  Overwrite existing AGENTS.md and CLAUDE.md files (default: safe append/update)
  -h, --help                   Show this help message

Behavior with pre-existing AGENTS.md:
  By default, init.sh preserves any pre-existing AGENTS.md by appending the Discipline Flow
  contract inside delimited markers (<!-- BEGIN DISCIPLINE-FLOW -->). If the markers already
  exist, it updates that section in-place without touching your custom instructions.
  Use --force to completely replace the file.

Examples:
  $(basename "$0") -t "pytest" --with-hook
  $(basename "$0") -p "my-service" -t "npm test" -d /path/to/repo --with-hook
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project-name)
      PROJECT_NAME="$2"
      shift 2
      ;;
    -t|--test-cmd)
      TEST_COMMAND="$2"
      shift 2
      ;;
    -c|--commit-types)
      COMMIT_TYPES="$2"
      shift 2
      ;;
    -d|--target-dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --with-hook)
      INSTALL_HOOK=true
      shift
      ;;
    --no-hook)
      INSTALL_HOOK=false
      shift
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'" >&2
      print_help
      exit 1
      ;;
  esac
done

# Resolve absolute target path
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")"
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Target directory '$TARGET_DIR' does not exist. Creating..."
  mkdir -p "$TARGET_DIR"
  TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
fi

# Fallback for PROJECT_NAME
if [[ -z "$PROJECT_NAME" ]]; then
  PROJECT_NAME="$(basename "$TARGET_DIR")"
fi

# Fallback for TEST_COMMAND
if [[ -z "$TEST_COMMAND" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Enter test command (e.g., pytest, npm test, cargo test): " TEST_COMMAND
  fi
  if [[ -z "$TEST_COMMAND" ]]; then
    echo "Error: Test command (--test-cmd) is required." >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
  fi
fi

# Check template existence
if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "Error: Template file not found at '$TEMPLATE_FILE'" >&2
  exit 1
fi

AGENTS_TARGET="$TARGET_DIR/AGENTS.md"
CLAUDE_TARGET="$TARGET_DIR/CLAUDE.md"

# Generate content from template safely
content="$(<"$TEMPLATE_FILE")"
content="${content//\{\{PROJECT_NAME\}\}/$PROJECT_NAME}"
content="${content//\{\{TEST_COMMAND\}\}/$TEST_COMMAND}"
content="${content//\{\{COMMIT_TYPES\}\}/$COMMIT_TYPES}"

START_MARKER="<!-- BEGIN DISCIPLINE-FLOW -->"
END_MARKER="<!-- END DISCIPLINE-FLOW -->"

# Manage AGENTS.md (Safe append / update / create)
if [[ ! -f "$AGENTS_TARGET" ]]; then
  printf '%s\n' "$content" > "$AGENTS_TARGET"
  echo "Created: $AGENTS_TARGET"
elif [[ "$FORCE" == true ]]; then
  printf '%s\n' "$content" > "$AGENTS_TARGET"
  echo "Overwritten (--force): $AGENTS_TARGET"
else
  if grep -q "$START_MARKER" "$AGENTS_TARGET"; then
    python3 -c '
import sys
content, target, start, end = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(target, "r", encoding="utf-8") as f:
    text = f.read()
if start in text and end in text:
    pre = text.split(start)[0]
    post = text.split(end, 1)[1]
    new_text = pre.rstrip() + "\n\n" + content.strip() + "\n" + post.lstrip("\n")
    with open(target, "w", encoding="utf-8") as f:
        f.write(new_text)
' "$content" "$AGENTS_TARGET" "$START_MARKER" "$END_MARKER"
    echo "Updated existing Discipline Flow contract block in: $AGENTS_TARGET"
  else
    printf '\n\n%s\n' "$content" >> "$AGENTS_TARGET"
    echo "Appended Discipline Flow contract to existing: $AGENTS_TARGET (preserved custom rules)"
  fi
fi

# Manage CLAUDE.md (Safe create / append)
if [[ ! -f "$CLAUDE_TARGET" ]]; then
  printf '@AGENTS.md\n' > "$CLAUDE_TARGET"
  echo "Created: $CLAUDE_TARGET (pointing to @AGENTS.md)"
elif [[ "$FORCE" == true ]]; then
  printf '@AGENTS.md\n' > "$CLAUDE_TARGET"
  echo "Overwritten (--force): $CLAUDE_TARGET (pointing to @AGENTS.md)"
else
  if grep -q '@AGENTS.md' "$CLAUDE_TARGET"; then
    echo "Notice: $CLAUDE_TARGET already references @AGENTS.md"
  else
    printf '\n@AGENTS.md\n' >> "$CLAUDE_TARGET"
    echo "Appended: @AGENTS.md reference to existing $CLAUDE_TARGET"
  fi
fi

# Install commit-msg hook if requested
if [[ "$INSTALL_HOOK" == true ]]; then
  GIT_DIR="$TARGET_DIR/.git"
  if [[ ! -d "$GIT_DIR" ]]; then
    echo "Notice: Target is not a git repository yet. Initializing git..."
    git -C "$TARGET_DIR" init
  fi

  HOOKS_DIR="$TARGET_DIR/.git/hooks"
  mkdir -p "$HOOKS_DIR"
  HOOK_DEST="$HOOKS_DIR/commit-msg"

  if [[ ! -f "$HOOK_SRC" ]]; then
    echo "Warning: Hook source '$HOOK_SRC' not found. Skipping hook installation." >&2
  else
    cp "$HOOK_SRC" "$HOOK_DEST"
    chmod +x "$HOOK_DEST"
    echo "Installed git hook: $HOOK_DEST (bypass in emergency with 'git commit --no-verify')"
  fi
fi

echo ""
echo "Bootstrap complete for '$PROJECT_NAME'."
echo "Contract file: $AGENTS_TARGET"
echo "Claude import: $CLAUDE_TARGET"
if [[ "$INSTALL_HOOK" == true ]]; then
  echo "Commit hook:   $TARGET_DIR/.git/hooks/commit-msg"
fi
