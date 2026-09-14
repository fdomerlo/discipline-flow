#!/usr/bin/env bash
set -euo pipefail

SESSION_FILE="SESSION.md"

if [ ! -f "$SESSION_FILE" ]; then
    echo "Error: $SESSION_FILE not found." >&2
    exit 1
fi

command="${1:-}"

get_state() {
    awk '/^---$/ { if (c++ == 1) exit } c==1 && /^sdd_state:/ { print $2 }' "$SESSION_FILE"
}

get_task() {
    # Match active_task and print everything after the colon and optional spaces
    awk '/^---$/ { if (c++ == 1) exit } c==1 && /^active_task:/ { sub(/^active_task:[[:space:]]*/, ""); print $0 }' "$SESSION_FILE"
}

update_yaml_field() {
    local field="$1"
    local value="$2"

    # We use sed to replace only between the YAML boundaries ---
    # Using pipe as delimiter to avoid issues with tasks containing slashes
    sed -i.bak -e "/^---$/,/^---$/ s|^${field}:.*|${field}: ${value}|" "$SESSION_FILE"
    rm -f "${SESSION_FILE}.bak"
}

case "$command" in
    start)
        task="${2:-}"
        if [ -z "$task" ]; then
            echo "Usage: $0 start <task>" >&2
            exit 1
        fi

        current_state=$(get_state)
        if [ "$current_state" != "execute" ]; then
             echo "Error: Can only start tasks in 'execute' state. Current state is '$current_state'." >&2
             exit 1
        fi

        update_yaml_field "active_task" "$task"
        echo "Started task: $task"
        ;;
    advance)
        new_state="${2:-}"
        if [[ ! "$new_state" =~ ^(plan|execute|verify)$ ]]; then
            echo "Usage: $0 advance <plan|execute|verify>" >&2
            exit 1
        fi

        current_state=$(get_state)

        # Validations
        if [ "$new_state" == "execute" ] && [ "$current_state" != "plan" ]; then
             echo "Error: Can only advance to 'execute' from 'plan'." >&2
             exit 1
        fi
        if [ "$new_state" == "verify" ] && [ "$current_state" != "execute" ]; then
             echo "Error: Can only advance to 'verify' from 'execute'." >&2
             exit 1
        fi
        if [ "$new_state" == "plan" ] && [ "$current_state" != "verify" ]; then
             echo "Error: Can only advance to 'plan' from 'verify'." >&2
             exit 1
        fi

        update_yaml_field "sdd_state" "$new_state"

        # If going to plan or verify, clear active_task
        if [ "$new_state" == "plan" ] || [ "$new_state" == "verify" ]; then
            update_yaml_field "active_task" "none"
        fi

        echo "Advanced state to: $new_state"
        ;;
    status)
        state=$(get_state)
        task=$(get_task)
        echo "State: $state"
        echo "Active task: $task"
        ;;
    *)
        echo "Usage: $0 {start <task>|advance <plan|execute|verify>|status}" >&2
        exit 1
        ;;
esac
