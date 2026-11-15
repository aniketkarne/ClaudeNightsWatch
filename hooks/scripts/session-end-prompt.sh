#!/bin/bash

# Hook: Session end prompt
# Reminds users about daemon if task.md exists but daemon isn't running

# PID file lives in the project directory (CLAUDE_NIGHTS_WATCH_DIR or CWD),
# where the daemon/manager write it — not the plugin directory.
TASK_DIR="${CLAUDE_NIGHTS_WATCH_DIR:-$(pwd)}"
PID_FILE="$TASK_DIR/logs/claude-nights-watch-daemon.pid"
TASK_FILE="$TASK_DIR/task.md"

# Check if task.md exists in current directory
if [ -f "$TASK_FILE" ]; then
    # Check if daemon is running
    DAEMON_RUNNING=false
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            DAEMON_RUNNING=true
        fi
    fi
    
    # If task exists but daemon not running, suggest starting it
    if [ "$DAEMON_RUNNING" = false ]; then
        echo ""
        echo "💡 You have a task.md file but Nights Watch daemon isn't running."
        echo "   Start autonomous execution: /nights-watch start"
    fi
fi

exit 0

