#!/usr/bin/env bash
# scripts/init.sh — Bootstrap repository with discipline-flow conventions and deterministic gates
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_FILE="$SKILL_DIR/assets/AGENTS.md.template"

PROJECT_NAME=""
TEST_COMMAND=""
COMMIT_TYPES="feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, release"
INSTALL_HOOKS=true
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
      --no-hooks               Skip git hooks installation (default: hooks are always installed)
      --with-hooks             Explicitly enable git hooks installation (default behavior)
  -f, --force                  Overwrite existing files and scripts (default: safe append/update)
  -h, --help                   Show this help message

Behavior:
  - Bootstraps AGENTS.md preserving custom rules inside managed delimiters.
  - Links CLAUDE.md with @AGENTS.md.
  - Installs mandatory runtime scripts (scripts/sdd.sh, scripts/verify-crit.sh, scripts/new-plan.sh).
  - Installs deterministic git hooks (.git/hooks/pre-commit and .git/hooks/commit-msg).

Examples:
  $(basename "$0") -t "pytest"
  $(basename "$0") -p "my-service" -t "npm test" -d /path/to/repo
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
    --no-hooks)
      INSTALL_HOOKS=false
      shift
      ;;
    --with-hooks|--with-hook)
      INSTALL_HOOKS=true
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
    tmp_content_file=$(mktemp)
    tmp_target_file=$(mktemp)
    printf '%s\n' "$content" > "$tmp_content_file"
    awk -v repl_file="$tmp_content_file" '
      /<!-- BEGIN DISCIPLINE-FLOW -->/ {
        in_block=1
        while ((getline line < repl_file) > 0) {
          print line
        }
        close(repl_file)
        next
      }
      /<!-- END DISCIPLINE-FLOW -->/ {
        in_block=0
        next
      }
      !in_block { print }
    ' "$AGENTS_TARGET" > "$tmp_target_file"
    mv "$tmp_target_file" "$AGENTS_TARGET"
    rm -f "$tmp_content_file"
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

# Install mandatory SDD scripts in target project
SCRIPTS_DEST_DIR="$TARGET_DIR/scripts"
mkdir -p "$SCRIPTS_DEST_DIR"

install_script() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$src" ]]; then
    echo "Warning: Source script '$src' not found. Skipping." >&2
  elif [[ -f "$dest" && "$FORCE" != true ]]; then
    echo "Notice: $dest already exists, left untouched (use --force to overwrite)."
  else
    cp "$src" "$dest"
    chmod +x "$dest"
    echo "Installed: $dest"
  fi
}

install_script "$SKILL_DIR/scripts/sdd.sh" "$SCRIPTS_DEST_DIR/sdd.sh"
install_script "$SKILL_DIR/scripts/verify-crit.sh" "$SCRIPTS_DEST_DIR/verify-crit.sh"
install_script "$SKILL_DIR/scripts/new-plan.sh" "$SCRIPTS_DEST_DIR/new-plan.sh"

# Install Git hooks (pre-commit & commit-msg) by default
if [[ "$INSTALL_HOOKS" == true ]]; then
  GIT_DIR="$TARGET_DIR/.git"
  if [[ ! -d "$GIT_DIR" ]]; then
    echo "Notice: Target is not a git repository yet. Initializing git..."
    git -C "$TARGET_DIR" init
  fi

  HOOKS_DIR="$TARGET_DIR/.git/hooks"
  mkdir -p "$HOOKS_DIR"

  # 1. Install pre-commit hook (guards code edits during plan phase)
  PRE_COMMIT_SRC="$SKILL_DIR/scripts/pre-commit-hook.sh"
  PRE_COMMIT_DEST="$HOOKS_DIR/pre-commit"
  if [[ -f "$PRE_COMMIT_SRC" ]]; then
    cp "$PRE_COMMIT_SRC" "$PRE_COMMIT_DEST"
    chmod +x "$PRE_COMMIT_DEST"
    echo "Installed git hook: $PRE_COMMIT_DEST (blocks code commits during 'plan' phase)"
  fi

  # 2. Install commit-msg hook (enforces Conventional Commits & active phase)
  COMMIT_MSG_SRC="$SKILL_DIR/scripts/commit-msg-hook.sh"
  COMMIT_MSG_DEST="$HOOKS_DIR/commit-msg"
  if [[ -f "$COMMIT_MSG_SRC" ]]; then
    cp "$COMMIT_MSG_SRC" "$COMMIT_MSG_DEST"
    chmod +x "$COMMIT_MSG_DEST"
    echo "Installed git hook: $COMMIT_MSG_DEST (enforces conventional commits & active phase reference)"
  fi
fi

echo ""
echo "Bootstrap complete for '$PROJECT_NAME'."
echo "Contract file: $AGENTS_TARGET"
echo "Claude import: $CLAUDE_TARGET"
echo "Scripts:       $SCRIPTS_DEST_DIR/{sdd.sh, verify-crit.sh, new-plan.sh}"
if [[ "$INSTALL_HOOKS" == true ]]; then
  echo "Git hooks:     $TARGET_DIR/.git/hooks/{pre-commit, commit-msg}"
fi
