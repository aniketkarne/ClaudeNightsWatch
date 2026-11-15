#!/bin/bash

# Test script to execute task immediately without waiting for renewal window

LOG_FILE="${CLAUDE_NIGHTS_WATCH_DIR:-$(pwd)}/logs/claude-nights-watch-test.log"
TASK_FILE="${TASK_FILE:-task.md}"
RULES_FILE="${RULES_FILE:-rules.md}"
TASK_DIR="${CLAUDE_NIGHTS_WATCH_DIR:-$(pwd)}"

# Ensure logs directory exists
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to prepare task with rules
prepare_task_prompt() {
    local prompt=""
    
    # Add rules if they exist
    if [ -f "$TASK_DIR/$RULES_FILE" ]; then
        prompt="IMPORTANT RULES TO FOLLOW:\n\n"
        prompt+=$(cat "$TASK_DIR/$RULES_FILE")
        prompt+="\n\n---END OF RULES---\n\n"
        # >&2: this function's stdout is captured into the prompt,
        # so log lines must not leak into what Claude receives
        log_message "Applied rules from $RULES_FILE" >&2
    fi
    
    # Add task content
    if [ -f "$TASK_DIR/$TASK_FILE" ]; then
        prompt+="TASK TO EXECUTE:\n\n"
        prompt+=$(cat "$TASK_DIR/$TASK_FILE")
        prompt+="\n\n---END OF TASK---\n\n"
        prompt+="Please read the above task, create a todo list from it, and then execute it step by step."
    else
        log_message "ERROR: Task file not found at $TASK_DIR/$TASK_FILE"
        return 1
    fi
    
    echo -e "$prompt"
}

# Main execution
main() {
    log_message "=== Claude Nights Watch Test Execution Started ==="
    log_message "Task directory: $TASK_DIR"
    log_message "Log file: $LOG_FILE"
    
    # Check if task file exists
    if [ ! -f "$TASK_DIR/$TASK_FILE" ]; then
        log_message "ERROR: Task file not found at $TASK_DIR/$TASK_FILE"
        exit 1
    fi
    
    # Check if rules file exists
    if [ -f "$TASK_DIR/$RULES_FILE" ]; then
        log_message "Rules file found at $TASK_DIR/$RULES_FILE"
    else
        log_message "No rules file found. Consider creating $RULES_FILE for safety constraints"
    fi
    
    # Prepare the full prompt with rules and task
    log_message "Preparing task prompt..."
    # (declare and assign separately: `local var=$(...)` masks the
    # command's exit status, so a failed prepare was never detected)
    local full_prompt
    full_prompt=$(prepare_task_prompt)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    log_message "Task prompt prepared ($(echo -e "$full_prompt" | wc -l) lines)"
    
    # Show what will be sent to Claude
    echo ""
    echo "=== PROMPT PREVIEW ==="
    echo -e "$full_prompt" | head -20
    echo "..."
    echo "=== END PREVIEW ==="
    echo ""
    
    read -p "Execute this task with Claude? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_message "Execution cancelled by user"
        exit 0
    fi
    
    log_message "Executing task with Claude (autonomous mode)..."
    
    # Log the full prompt being sent
    echo "" >> "$LOG_FILE"
    echo "=== PROMPT SENT TO CLAUDE ===" >> "$LOG_FILE"
    echo -e "$full_prompt" >> "$LOG_FILE"
    echo "=== END OF PROMPT ===" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
    
    # Execute task with Claude and log everything
    log_message "=== CLAUDE RESPONSE START ==="
    # pipefail: capture claude's status, not tee's (PIPESTATUS[0] would
    # be echo's status — the first pipeline element)
    set -o pipefail
    echo -e "$full_prompt" | claude --dangerously-skip-permissions 2>&1 | tee -a "$LOG_FILE"
    local result=$?
    set +o pipefail
    log_message "=== CLAUDE RESPONSE END ==="
    
    if [ $result -eq 0 ]; then
        log_message "Task execution completed successfully"
    else
        log_message "ERROR: Task execution failed with code $result"
    fi
    
    log_message "=== Test Execution Completed ==="
    echo ""
    echo "Full log saved to: $LOG_FILE"
}

# Run main function
main