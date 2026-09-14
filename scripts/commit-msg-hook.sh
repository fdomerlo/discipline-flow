#!/bin/sh
# Installed as .git/hooks/commit-msg by the disciplined-scaffold skill.
# Rejects commit messages that don't follow Conventional Commits.
# Checks against discipline-flow state (active_task).
# Bypass in an emergency with: git commit --no-verify

msg_file="$1"
first_line=$(head -n1 "$msg_file")

# Allow native git automated operations and comments/empty lines
case "$first_line" in
  Merge*|revert*|Revert*|"fixup!"*|"squash!"*|"#"*|"")
    exit 0
    ;;
esac

# Standard Conventional Commits 1.0.0 types
types="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|release"
pattern="^($types)(\([a-zA-Z0-9_.-]+\))?!?: .+"

if ! echo "$first_line" | grep -Eq "$pattern"; then
  echo "commit-msg hook: message doesn't look like a conventional commit."
  echo "  got:      $first_line"
  echo "  expected: <type>(<optional-scope>): <description>"
  echo "  types:    feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, release"
  echo "  bypass:   git commit --no-verify"
  exit 1
fi

SESSION_FILE="SESSION.md"
if [ -f "$SESSION_FILE" ]; then
    # Extract sdd_state
    sdd_state=$(awk '/^---$/ { if (c++ == 1) exit } c==1 && /^sdd_state:/ { gsub(/\r/, ""); print $2 }' "$SESSION_FILE")

    if [ "$sdd_state" = "execute" ]; then
        # Extract active_task
        active_task=$(awk '/^---$/ { if (c++ == 1) exit } c==1 && /^active_task:/ { sub(/^active_task:[[:space:]]*/, ""); gsub(/\r/, ""); print $0 }' "$SESSION_FILE")

        if [ "$active_task" = "none" ] || [ -z "$active_task" ]; then
            echo "commit-msg hook: sdd_state is 'execute' but no active_task is set."
            echo "Use: ./scripts/sdd.sh start <task> before committing."
            exit 1
        fi

        # Check if the commit message contains the active_task
        if ! grep -q "$active_task" "$msg_file"; then
            echo "commit-msg hook: sdd_state is 'execute' but commit message doesn't reference active_task."
            echo "  active_task: $active_task"
            echo "Ensure your commit message includes this task name."
            exit 1
        fi
    fi
fi

exit 0
