#!/bin/bash

# Claude Nights Watch Manager - Start, stop, and manage the task execution daemon

DAEMON_SCRIPT="$(cd "$(dirname "$0")" && pwd)/claude-nights-watch-daemon.sh"
TASK_DIR="${CLAUDE_NIGHTS_WATCH_DIR:-$(pwd)}"
PID_FILE="$TASK_DIR/logs/claude-nights-watch-daemon.pid"
LOG_FILE="$TASK_DIR/logs/claude-nights-watch-daemon.log"
START_TIME_FILE="$TASK_DIR/logs/claude-nights-watch-start-time"
TASK_FILE="task.md"
RULES_FILE="rules.md"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_task() {
    echo -e "${BLUE}[TASK]${NC} $1"
}

start_daemon() {
    # Parse --at parameter if provided
    START_TIME=""
    if [ "$2" = "--at" ] && [ -n "$3" ]; then
        START_TIME="$3"
        
        # Validate and convert start time to epoch
        if [[ "$START_TIME" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
            # Format: "HH:MM" - assume today
            START_TIME="$(date '+%Y-%m-%d') $START_TIME:00"
        elif [[ "$START_TIME" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
            # Format: "YYYY-MM-DD HH:MM" - append seconds so BSD date can
            # parse it too (its -f format requires the full date-time)
            START_TIME="$START_TIME:00"
        fi
        
        # Convert to epoch timestamp
        START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$START_TIME" +%s 2>/dev/null)
        
        if [ -z "$START_EPOCH" ]; then
            print_error "Invalid time format. Use 'HH:MM' or 'YYYY-MM-DD HH:MM'"
            return 1
        fi
        
        # Store start time
        echo "$START_EPOCH" > "$START_TIME_FILE"
        print_status "Daemon will start monitoring at: $(date -d "@$START_EPOCH" 2>/dev/null || date -r "$START_EPOCH")"
    else
        # Remove any existing start time (start immediately)
        rm -f "$START_TIME_FILE" 2>/dev/null
    fi
    
    # Check if task file exists
    if [ ! -f "$TASK_DIR/$TASK_FILE" ]; then
        print_warning "Task file not found at $TASK_DIR/$TASK_FILE"
        print_warning "Please create a task.md file with your tasks before starting the daemon"
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            print_error "Daemon is already running with PID $PID"
            return 1
        fi
    fi
    
    print_status "Starting Claude Nights Watch daemon..."
    print_status "Task directory: $TASK_DIR"
    
    # Export task directory for daemon
    export CLAUDE_NIGHTS_WATCH_DIR="$TASK_DIR"
    nohup "$DAEMON_SCRIPT" > /dev/null 2>&1 &
    
    # Wait for daemon to start with retry logic
    for i in {1..5}; do
        sleep 1
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
                print_status "Daemon started successfully with PID $PID"
                
                if [ -f "$START_TIME_FILE" ]; then
                    START_EPOCH=$(cat "$START_TIME_FILE")
                    print_status "Will begin task execution at: $(date -d "@$START_EPOCH" 2>/dev/null || date -r "$START_EPOCH")"
                fi
                print_status "Logs: $LOG_FILE"
                
                # Show task preview
                if [ -f "$TASK_DIR/$TASK_FILE" ]; then
                    echo ""
                    print_task "Task preview (first 5 lines):"
                    head -5 "$TASK_DIR/$TASK_FILE" | sed 's/^/  /'
                    echo "  ..."
                fi
                
                return 0
            fi
        fi
        if [ $i -eq 5 ]; then
            print_error "Failed to start daemon"
            return 1
        fi
    done
}

stop_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        print_warning "Daemon is not running (no PID file found)"
        return 1
    fi
    
    PID=$(cat "$PID_FILE")
    
    if ! kill -0 "$PID" 2>/dev/null; then
        print_warning "Daemon is not running (process $PID not found)"
        rm -f "$PID_FILE"
        return 1
    fi
    
    print_status "Stopping daemon with PID $PID..."
    kill "$PID"
    
    # Wait for graceful shutdown
    for i in {1..10}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            print_status "Daemon stopped successfully"
            rm -f "$PID_FILE"
            return 0
        fi
        sleep 1
    done
    
    # Force kill if still running
    print_warning "Daemon did not stop gracefully, forcing..."
    kill -9 "$PID" 2>/dev/null
    rm -f "$PID_FILE"
    print_status "Daemon stopped"
}

status_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        print_status "Daemon is not running"
        return 1
    fi
    
    PID=$(cat "$PID_FILE")
    
    if kill -0 "$PID" 2>/dev/null; then
        print_status "Daemon is running with PID $PID"
        
        # Check start time status
        if [ -f "$START_TIME_FILE" ]; then
            start_epoch=$(cat "$START_TIME_FILE")
            current_epoch=$(date +%s)
            
            if [ "$current_epoch" -ge "$start_epoch" ]; then
                print_status "Status: ✅ ACTIVE - Task execution monitoring enabled"
            else
                time_until_start=$((start_epoch - current_epoch))
                hours=$((time_until_start / 3600))
                minutes=$(((time_until_start % 3600) / 60))
                print_status "Status: ⏰ WAITING - Will activate in ${hours}h ${minutes}m"
                print_status "Start time: $(date -d "@$start_epoch" 2>/dev/null || date -r "$start_epoch")"
            fi
        else
            print_status "Status: ✅ ACTIVE - Task execution monitoring enabled"
        fi
        
        # Show task status
        echo ""
        if [ -f "$TASK_DIR/$TASK_FILE" ]; then
            print_task "Task file: $TASK_DIR/$TASK_FILE ($(wc -l < "$TASK_DIR/$TASK_FILE") lines)"
        else
            print_warning "Task file not found at $TASK_DIR/$TASK_FILE"
        fi
        
        if [ -f "$TASK_DIR/$RULES_FILE" ]; then
            print_task "Rules file: $TASK_DIR/$RULES_FILE ($(wc -l < "$TASK_DIR/$RULES_FILE") lines)"
        else
            print_status "No rules file (consider creating $RULES_FILE for safety)"
        fi
        
        # Show recent activity
        if [ -f "$LOG_FILE" ]; then
            echo ""
            print_status "Recent activity:"
            tail -5 "$LOG_FILE" | sed 's/^/  /'
        fi
        
        # Show next execution estimate (only if active)
        if [ ! -f "$START_TIME_FILE" ] || [ "$current_epoch" -ge "$(cat "$START_TIME_FILE" 2>/dev/null || echo 0)" ]; then
            if [ -f "$HOME/.claude-last-activity" ]; then
                last_activity=$(cat "$HOME/.claude-last-activity")
                current_time=$(date +%s)
                time_diff=$((current_time - last_activity))
                remaining=$((18000 - time_diff))
                
                if [ $remaining -gt 0 ]; then
                    hours=$((remaining / 3600))
                    minutes=$(((remaining % 3600) / 60))
                    echo ""
                    print_status "Estimated time until next task execution: ${hours}h ${minutes}m"
                fi
            fi
        fi
        
        return 0
    else
        print_warning "Daemon is not running (process $PID not found)"
        rm -f "$PID_FILE"
        return 1
    fi
}

restart_daemon() {
    print_status "Restarting daemon..."
    stop_daemon
    sleep 2
    start_daemon "$@"
}

show_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        print_error "No log file found"
        return 1
    fi
    
    if [ "$1" = "-f" ]; then
        tail -f "$LOG_FILE"
    else
        tail -50 "$LOG_FILE"
    fi
}

show_task() {
    if [ ! -f "$TASK_DIR/$TASK_FILE" ]; then
        print_error "No task file found at $TASK_DIR/$TASK_FILE"
        return 1
    fi
    
    echo ""
    print_task "Current task ($TASK_DIR/$TASK_FILE):"
    echo "============================================"
    cat "$TASK_DIR/$TASK_FILE"
    echo "============================================"
    
    if [ -f "$TASK_DIR/$RULES_FILE" ]; then
        echo ""
        print_task "Current rules ($TASK_DIR/$RULES_FILE):"
        echo "============================================"
        cat "$TASK_DIR/$RULES_FILE"
        echo "============================================"
    fi
}

# Main command handling
case "$1" in
    start)
        start_daemon "$@"
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon
        sleep 2
        start_daemon "$@"
        ;;
    status)
        status_daemon
        ;;
    logs)
        show_logs "$2"
        ;;
    task)
        show_task
        ;;
    *)
        echo "Claude Nights Watch - Autonomous Task Execution Daemon"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs|task} [options]"
        echo ""
        echo "Commands:"
        echo "  start           - Start the daemon"
        echo "  start --at TIME - Start daemon but begin monitoring at specified time"
        echo "                    Examples: --at '09:00' or --at '2025-01-28 14:30'"
        echo "  stop            - Stop the daemon"
        echo "  restart         - Restart the daemon"
        echo "  status          - Show daemon status"
        echo "  logs            - Show recent logs (use 'logs -f' to follow)"
        echo "  task            - Display current task and rules"
        echo ""
        echo "The daemon will:"
        echo "  - Monitor your Claude usage blocks"
        echo "  - Execute tasks from task.md when renewal is needed"
        echo "  - Apply rules from rules.md for safe autonomous execution"
        echo "  - Prevent gaps in your 5-hour usage windows"
        echo ""
        echo "Environment:"
        echo "  CLAUDE_NIGHTS_WATCH_DIR - Set task directory (default: current dir)"
        ;;
esac