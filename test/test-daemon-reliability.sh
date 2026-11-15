#!/bin/bash

# Daemon reliability regression tests
#
# Covers the failure modes that made the daemon lie about task success,
# made graceful stop impossible, made the hooks blind to a running daemon,
# and made the MCP start_daemon tool evaluate its argument:
#
#   1. prepare_task_prompt must not leak log lines into the prompt
#   2. execute_task must report a failing claude run (was: always success)
#   3. execute_task must record last-activity only on success
#   4. SIGTERM must interrupt the daemon's sleep immediately (was: trap
#      deferred behind a foreground sleep, stop escalated to kill -9)
#   5. manager --at 'YYYY-MM-DD HH:MM' must parse on macOS (BSD date)
#   6. manager stop must finish gracefully in well under the 10s grace
#   7. hooks must find the daemon's PID file in the project directory
#   8. MCP start_daemon must not evaluate command substitution in its
#      start_time argument
#
# Note: deliberately NO `set -e` - a test suite must keep running after
# individual failures so it can report a summary (see the note in
# test-plugin-comprehensive.sh).

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$PLUGIN_ROOT/test/temp-reliability"
PASS=0
FAIL=0

print_test() { echo -e "${BLUE}[TEST]${NC} $1"; }
print_pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
print_fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }

cleanup() {
    # Stop any daemon left behind by the tests
    if [ -f "$SANDBOX/proj/logs/claude-nights-watch-daemon.pid" ]; then
        PID=$(cat "$SANDBOX/proj/logs/claude-nights-watch-daemon.pid")
        kill -9 "$PID" 2>/dev/null
    fi
    rm -rf "$SANDBOX"
}

# Make a sandbox with a fake claude, a project dir and a private HOME so
# tests never touch the real ~/.claude-last-activity.
setup_sandbox() {
    rm -rf "$SANDBOX"
    mkdir -p "$SANDBOX/bin" "$SANDBOX/home" "$SANDBOX/proj"
    echo "test task body" > "$SANDBOX/proj/task.md"
    echo "test-rule-line" > "$SANDBOX/proj/rules.md"
    make_fake_claude 0
}

make_fake_claude() {
    cat > "$SANDBOX/bin/claude" << EOF
#!/bin/bash
echo "fake claude output"
exit $1
EOF
    chmod +x "$SANDBOX/bin/claude"
}

# Run a snippet inside a subshell that has sourced the daemon
sourced_daemon() {
    (
        export HOME="$SANDBOX/home"
        export PATH="$SANDBOX/bin:$PATH"
        export CLAUDE_NIGHTS_WATCH_DIR="$SANDBOX/proj"
        export NIGHTS_WATCH_SOURCED=1
        cd "$SANDBOX/proj" || exit 1
        . "$PLUGIN_ROOT/claude-nights-watch-daemon.sh" 2>/dev/null
        eval "$1"
    ) 2>/dev/null
}

# Test 1: prompt must not contain log lines
test_prompt_has_no_log_noise() {
    print_test "prepare_task_prompt output contains no log noise"
    OUT=$(sourced_daemon 'prepare_task_prompt')
    case "$OUT" in
        *"test-rule-line"*"TASK TO EXECUTE"*)
            if echo "$OUT" | grep -qE '\[20[0-9]{2}-[0-9]{2}-[0-9]{2} .*\]'; then
                print_fail "log timestamp leaked into the prompt sent to Claude"
            else
                print_pass "prompt carries rules + task, no log lines"
            fi
            ;;
        *)
            print_fail "prompt missing rules or task content"
            ;;
    esac
}

# Test 2: failing claude must be reported as failure
test_execute_task_reports_failure() {
    print_test "execute_task reports failure when claude exits non-zero"
    make_fake_claude 3
    rm -f "$SANDBOX/home/.claude-last-activity"
    OUT=$(sourced_daemon 'execute_task; echo "EXEC_RESULT=$?"')
    if echo "$OUT" | grep -q "EXEC_RESULT=0"; then
        print_fail "execute_task returned 0 although claude exited 3 (daemon logs success and never retries)"
    elif echo "$OUT" | grep -q "EXEC_RESULT=1"; then
        if [ -f "$SANDBOX/home/.claude-last-activity" ]; then
            print_fail "last-activity recorded despite failed run"
        else
            print_pass "failure propagated, last-activity not recorded"
        fi
    else
        print_fail "execute_task did not run to completion"
    fi
}

# Test 3: successful claude run records last-activity
test_execute_task_reports_success() {
    print_test "execute_task reports success when claude exits 0"
    make_fake_claude 0
    rm -f "$SANDBOX/home/.claude-last-activity"
    OUT=$(sourced_daemon 'execute_task; echo "EXEC_RESULT=$?"')
    if echo "$OUT" | grep -q "EXEC_RESULT=0" && [ -f "$SANDBOX/home/.claude-last-activity" ]; then
        print_pass "success propagated, last-activity recorded"
    else
        print_fail "successful run not reported as success"
    fi
}

# Test 4: SIGTERM must interrupt the daemon's sleep
test_sigterm_interrupts_sleep() {
    print_test "SIGTERM interrupts sleep_interruptible immediately"
    (
        export NIGHTS_WATCH_SOURCED=1
        . "$PLUGIN_ROOT/claude-nights-watch-daemon.sh" 2>/dev/null
        trap 'echo CLEANUP-RAN; exit 0' SIGTERM
        sleep_interruptible 30
        echo "SLEEP-FINISHED"
    ) > "$SANDBOX/sleep-out.txt" 2>&1 &
    local sleeper_pid=$!
    sleep 1
    kill -TERM "$sleeper_pid" 2>/dev/null
    sleep 2
    if kill -0 "$sleeper_pid" 2>/dev/null; then
        print_fail "still running 2s after SIGTERM during a 30s sleep (stop escalates to kill -9)"
        kill -9 "$sleeper_pid" 2>/dev/null
    else
        wait "$sleeper_pid" 2>/dev/null
        if grep -q "CLEANUP-RAN" "$SANDBOX/sleep-out.txt"; then
            print_pass "trap ran immediately on SIGTERM"
        else
            print_fail "process exited but cleanup trap did not run"
        fi
    fi
}

# Test 5: manager --at 'YYYY-MM-DD HH:MM' must parse on macOS
test_manager_at_full_format() {
    print_test "manager accepts --at 'YYYY-MM-DD HH:MM' (BSD date needs seconds)"
    CLAUDE_NIGHTS_WATCH_DIR="$SANDBOX/proj" HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" \
        "$PLUGIN_ROOT/claude-nights-watch-manager.sh" start --at "2099-01-01 10:00" > "$SANDBOX/manager-out.txt" 2>&1
    if [ $? -ne 0 ]; then
        print_fail "documented 'YYYY-MM-DD HH:MM' form rejected: $(tail -1 "$SANDBOX/manager-out.txt")"
        return
    fi
    # Expected epoch, computed with whichever date flavor this host has
    EXPECTED=$(date -d "2099-01-01 10:00:00" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "2099-01-01 10:00:00" +%s 2>/dev/null)
    ACTUAL=$(cat "$SANDBOX/proj/logs/claude-nights-watch-start-time" 2>/dev/null)
    if [ -n "$ACTUAL" ] && [ "$ACTUAL" = "$EXPECTED" ]; then
        print_pass "parsed to the expected epoch ($EXPECTED)"
    else
        print_fail "start time epoch mismatch: got '$ACTUAL', expected '$EXPECTED'"
    fi

    print_test "manager rejects garbage time values"
    CLAUDE_NIGHTS_WATCH_DIR="$SANDBOX/proj" HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" \
        "$PLUGIN_ROOT/claude-nights-watch-manager.sh" start --at "banana" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        print_pass "invalid time rejected"
    else
        print_fail "invalid time accepted"
    fi
}

# Test 6 + 7: graceful stop, and hooks seeing the project-dir PID file
test_graceful_stop_and_hooks() {
    # The daemon is waiting for 2099, started by the previous test
    print_test "hooks find the running daemon via the project-dir PID file"
    OUT=$(CLAUDE_NIGHTS_WATCH_DIR="$SANDBOX/proj" bash "$PLUGIN_ROOT/hooks/scripts/check-daemon-status.sh" 2>&1)
    case "$OUT" in
        *"daemon is running"*) print_pass "check-daemon-status.sh reports the running daemon" ;;
        *) print_fail "check-daemon-status.sh misses the running daemon (wrong PID dir?)" ;;
    esac

    OUT=$(cd "$SANDBOX/proj" && CLAUDE_NIGHTS_WATCH_DIR="$SANDBOX/proj" bash "$PLUGIN_ROOT/hooks/scripts/session-end-prompt.sh" 2>&1)
    case "$OUT" in
        *"isn't running"*) print_fail "session-end-prompt.sh claims the daemon isn't running while it is" ;;
        *) print_pass "session-end-prompt.sh does not contradict the running daemon" ;;
    esac

    print_test "manager stop shuts down gracefully (no kill -9)"
    T0=$(date +%s)
    CLAUDE_NIGHTS_WATCH_DIR="$SANDBOX/proj" HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" \
        "$PLUGIN_ROOT/claude-nights-watch-manager.sh" stop > "$SANDBOX/stop-out.txt" 2>&1
    T1=$(date +%s)
    DURATION=$((T1 - T0))
    if [ "$DURATION" -lt 8 ] && grep -q "stopped successfully" "$SANDBOX/stop-out.txt"; then
        print_pass "graceful stop completed in ${DURATION}s"
    else
        print_fail "stop took ${DURATION}s or did not stop gracefully: $(tail -2 "$SANDBOX/stop-out.txt" | tr '\n' ' ')"
    fi
}

# Test 8: MCP start_daemon must not evaluate its argument
test_mcp_start_no_eval() {
    print_test "MCP start_daemon does not evaluate command substitution in start_time"
    rm -f "$SANDBOX/EVAL-PWNED"
    sed "s|EVAL-MARKER|$SANDBOX/EVAL-PWNED|" "$PLUGIN_ROOT/test/mcp-injection-fixture.txt" \
        | CLAUDE_NIGHTS_WATCH_DIR="$SANDBOX/proj" HOME="$SANDBOX/home" PATH="$SANDBOX/bin:$PATH" \
          bash "$PLUGIN_ROOT/mcp-server/nights-watch-server.sh" > "$SANDBOX/mcp-out.txt" 2>&1
    if [ -f "$SANDBOX/EVAL-PWNED" ]; then
        print_fail "\$(...) in the start_time tool argument was executed (command injection)"
    else
        print_pass "tool argument passed through as data, nothing evaluated"
    fi
    if [ -f "$SANDBOX/proj/logs/claude-nights-watch-daemon.pid" ]; then
        print_fail "daemon started from an invalid start_time"
        cleanup
    fi
}

# Run
echo ""
echo "=== Claude Nights Watch Daemon Reliability Tests ==="
echo ""
setup_sandbox
test_prompt_has_no_log_noise
test_execute_task_reports_failure
test_execute_task_reports_success
test_sigterm_interrupts_sleep
test_manager_at_full_format
test_graceful_stop_and_hooks
test_mcp_start_no_eval
cleanup

echo ""
echo "================================"
echo "Test Summary"
echo "================================"
echo ""
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total: $((PASS + FAIL))"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ $FAIL test(s) failed${NC}"
    exit 1
fi
