#!/bin/bash

# Hook: Check daemon status on session start
# Displays a helpful message if daemon is running or suggests starting it

# PID file lives in the project directory (CLAUDE_NIGHTS_WATCH_DIR or CWD),
# where the daemon/manager write it — not the plugin directory.
TASK_DIR="${CLAUDE_NIGHTS_WATCH_DIR:-$(pwd)}"
PID_FILE="$TASK_DIR/logs/claude-nights-watch-daemon.pid"

# Only show status if PID file exists
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "🌙 Claude Nights Watch daemon is running (PID: $PID)"
        echo "   Use /nights-watch status for details"
    else
        echo "⚠️  Nights Watch daemon PID file found but process not running"
        echo "   Use /nights-watch start to restart"
    fi
fi

# Silent if daemon not configured (no PID file)
exit 0

