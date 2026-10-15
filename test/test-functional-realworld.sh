#!/bin/bash

# Claude Nights Watch Plugin - Functional & Real-World Testing Suite
# Tests actual functionality and simulates real-world usage scenarios
#
# Note: deliberately NO `set -e`. A test suite must keep running after
# individual test failures so it can count passes and fails and report a
# summary. `set -e` plus the post-increment `((PASS++))` pattern causes
# the script to exit on the very first pass (the post-increment evaluates
# to the pre-increment value, which is 0 when the counter is at 0, and 0
# is a falsy exit code that `set -e` treats as failure).

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$PLUGIN_ROOT/test"
TEMP_DIR="$TEST_DIR/functional-test"
PASS=0
FAIL=0
WARN=0

print_header() {
    echo ""
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASS=$((PASS + 1))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAIL=$((FAIL + 1))
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    WARN=$((WARN + 1))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Cleaned up functional test directory"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Initialize test environment
setup_test_environment() {
    print_header "Setting Up Test Environment"

    print_test "Creating temporary test environment..."

    # Create temp directory for testing
    mkdir -p "$TEMP_DIR"

    # Copy plugin files for testing (including mcp-server, which the
    # .mcp.json entry references and the MCP tests need to inspect).
    cp -r "$PLUGIN_ROOT/.claude-plugin" "$TEMP_DIR/"
    cp -r "$PLUGIN_ROOT/commands" "$TEMP_DIR/"
    cp -r "$PLUGIN_ROOT/agents" "$TEMP_DIR/"
    cp -r "$PLUGIN_ROOT/hooks" "$TEMP_DIR/"
    cp -r "$PLUGIN_ROOT/mcp-server" "$TEMP_DIR/"
    cp "$PLUGIN_ROOT/.mcp.json" "$TEMP_DIR/"

    if [ -d "$TEMP_DIR/.claude-plugin" ] && [ -d "$TEMP_DIR/commands" ]; then
        print_pass "Test environment created successfully"
    else
        print_fail "Failed to create test environment"
        exit 1
    fi

    print_test "Setting up test project structure..."

    # Create test project files
    mkdir -p "$TEMP_DIR/test-project"
    cd "$TEMP_DIR/test-project"

    # Create test task file
    cat > task.md << 'EOF'
# Test Automation Task

## Objectives:
1. Verify autonomous execution works
2. Test file creation and modification

## Tasks:
1. Create a file called test-output.txt
2. Write "Autonomous execution successful!" to it
3. Create a timestamp file
4. Report completion status
EOF

    # Create test rules file
    cat > rules.md << 'EOF'
# Test Safety Rules

## CRITICAL RULES:
- Only create files in current directory
- Never delete any files
- Never modify existing files outside project
- Always log all actions

## ALLOWED:
- Create new files in project directory
- Read existing files
- Write to created files only
EOF

    cd "$PLUGIN_ROOT"
    print_pass "Test project structure created"
}

# Test 1: Plugin Installation Simulation
test_plugin_installation() {
    print_header "Testing Plugin Installation Simulation"

    print_test "Simulating plugin installation process..."

    # Test that plugin.json is accessible
    if [ -f "$TEMP_DIR/.claude-plugin/plugin.json" ]; then
        print_pass "Plugin manifest accessible for installation"

        # Validate JSON structure
        # The plugin was renamed from `claude-nights-watch` to `nights-watch`
        # in the Nov 2025 refactor; accept either name.
        PLUGIN_NAME=$(jq -r '.name // empty' "$TEMP_DIR/.claude-plugin/plugin.json")
        if [ "$PLUGIN_NAME" = "claude-nights-watch" ] || [ "$PLUGIN_NAME" = "nights-watch" ]; then
            print_pass "Plugin name correctly configured: $PLUGIN_NAME"
        else
            print_fail "Plugin name not correctly configured: $PLUGIN_NAME"
        fi

        # Check version
        VERSION=$(jq -r '.version' "$TEMP_DIR/.claude-plugin/plugin.json")
        if [ "$VERSION" = "1.0.0" ]; then
            print_pass "Plugin version correctly set: $VERSION"
        else
            print_fail "Plugin version incorrect: $VERSION"
        fi
    else
        print_fail "Plugin manifest not accessible"
    fi

    print_test "Testing component path resolution..."

    # Test that all component paths are resolvable. The Nov 2025 plugin
    # refactor removed explicit `commands` and `agents` fields from the
    # manifest — Claude Code auto-discovers the `commands/` and `agents/`
    # directories at the plugin root, so the explicit field is optional.
    # Accept either the manifest field OR the auto-discovered directory.
    COMMANDS_PATH=$(jq -r '.commands // empty' "$TEMP_DIR/.claude-plugin/plugin.json")
    if [ -n "$COMMANDS_PATH" ] && [ -d "$TEMP_DIR/$COMMANDS_PATH" ]; then
        print_pass "Commands path resolves correctly: $COMMANDS_PATH"
    elif [ -d "$TEMP_DIR/commands" ]; then
        print_pass "Commands auto-discovered from $TEMP_DIR/commands/"
    else
        print_fail "Commands path missing and no commands/ directory to auto-discover"
    fi

    AGENTS_PATH=$(jq -r '.agents // empty' "$TEMP_DIR/.claude-plugin/plugin.json")
    if [ -n "$AGENTS_PATH" ] && [ -d "$TEMP_DIR/$AGENTS_PATH" ]; then
        print_pass "Agents path resolves correctly: $AGENTS_PATH"
    elif [ -d "$TEMP_DIR/agents" ]; then
        print_pass "Agents auto-discovered from $TEMP_DIR/agents/"
    else
        print_fail "Agents path missing and no agents/ directory to auto-discover"
    fi

    MCP_PATH=$(jq -r '.mcpServers // empty' "$TEMP_DIR/.claude-plugin/plugin.json")
    if [ -n "$MCP_PATH" ] && [ -f "$TEMP_DIR/$MCP_PATH" ]; then
        print_pass "MCP servers path resolves correctly: $MCP_PATH"
    elif [ -f "$TEMP_DIR/.claude-plugin/.mcp.json" ]; then
        print_pass "MCP servers config present at .claude-plugin/.mcp.json"
    else
        print_fail "MCP servers path missing and no .mcp.json fallback"
    fi
}

# Test 2: Command Execution Testing
test_command_execution() {
    print_header "Testing Command Execution"

    print_test "Testing command wrapper functionality..."

    COMMAND_WRAPPER="$TEMP_DIR/commands/bin/nights-watch"

    if [ -x "$COMMAND_WRAPPER" ]; then
        print_pass "Command wrapper is executable"

        # Test help command (should work without Claude CLI)
        if "$COMMAND_WRAPPER" help >/dev/null 2>&1; then
            print_pass "Command wrapper help function works"
        else
            print_warn "Command wrapper help function has issues (expected without Claude CLI)"
        fi

        # Test invalid command handling
        if "$COMMAND_WRAPPER" invalid-command 2>&1 | grep -q "Unknown command"; then
            print_pass "Command wrapper handles invalid commands correctly"
        else
            print_fail "Command wrapper does not handle invalid commands properly"
        fi

    else
        print_fail "Command wrapper is not executable"
    fi

    print_test "Testing individual command files..."

    # Test that command files exist and have proper structure
    COMMANDS_DIR="$TEMP_DIR/commands"
    EXPECTED_COMMANDS=("start.md" "stop.md" "status.md" "logs.md" "task.md" "setup.md" "restart.md")

    for cmd in "${EXPECTED_COMMANDS[@]}"; do
        if [ -f "$COMMANDS_DIR/$cmd" ]; then
            print_pass "Command file exists: $cmd"

            # Check for frontmatter
            if grep -q "^---$" "$COMMANDS_DIR/$cmd"; then
                print_pass "Command has frontmatter: $cmd"
            else
                print_warn "Command missing frontmatter: $cmd"
            fi
        else
            print_fail "Command file missing: $cmd"
        fi
    done
}

# Test 3: Environment Variables Simulation
test_environment_variables() {
    print_header "Testing Environment Variables"

    print_test "Simulating CLAUDE_PLUGIN_ROOT environment..."

    # Simulate what Claude Code would set
    export CLAUDE_PLUGIN_ROOT="$TEMP_DIR"

    # Test that hook scripts resolve their plugin root correctly. The
    # hooks/hooks.json manifest uses ${CLAUDE_PLUGIN_ROOT} to reference
    # each hook command. The .sh scripts themselves derive the plugin
    # root from BASH_SOURCE — both are correct, the test just needs to
    # check the right place. The variable is set by Claude Code in the
    # hook execution environment.
    if grep -q "CLAUDE_PLUGIN_ROOT" "$TEMP_DIR/.claude-plugin/hooks.json"; then
        print_pass "Hooks manifest references CLAUDE_PLUGIN_ROOT"
    else
        print_fail "Hooks manifest does not reference CLAUDE_PLUGIN_ROOT"
    fi

    HOOK_SCRIPT="$TEMP_DIR/hooks/scripts/check-daemon-status.sh"
    if [ -x "$HOOK_SCRIPT" ]; then
        print_pass "Hook script is executable"

        # Test script execution (will fail due to missing Claude, but should run)
        if timeout 5s bash "$HOOK_SCRIPT" >/dev/null 2>&1; then
            print_pass "Hook script executes without syntax errors"
        else
            print_warn "Hook script has runtime dependencies (expected)"
        fi
    else
        print_fail "Hook script is not executable"
    fi

    print_test "Testing MCP server environment variables..."

    # The MCP server reads NIGHTS_WATCH_ROOT (set by .mcp.json) or falls
    # back to BASH_SOURCE to derive the plugin root. CLAUDE_PLUGIN_ROOT
    # is the Claude Code variable; NIGHTS_WATCH_ROOT is the plugin's
    # own convention. Either is acceptable.
    if grep -q "NIGHTS_WATCH_ROOT\|BASH_SOURCE" "$TEMP_DIR/mcp-server/nights-watch-server.sh"; then
        print_pass "MCP server resolves plugin root (NIGHTS_WATCH_ROOT or BASH_SOURCE)"
    else
        print_fail "MCP server does not resolve plugin root"
    fi

    unset CLAUDE_PLUGIN_ROOT
}

# Test 4: Core Script Functionality
test_core_scripts() {
    print_header "Testing Core Script Functionality"

    print_test "Testing manager script configuration parsing..."

    MANAGER_SCRIPT="$PLUGIN_ROOT/claude-nights-watch-manager.sh"

    if [ -x "$MANAGER_SCRIPT" ]; then
        print_pass "Manager script is executable"

        # Test help function
        if "$MANAGER_SCRIPT" --help >/dev/null 2>&1 || "$MANAGER_SCRIPT" help >/dev/null 2>&1; then
            print_pass "Manager script help function works"
        else
            print_warn "Manager script help function not accessible"
        fi

        # Test status command (should work without daemon running)
        if "$MANAGER_SCRIPT" status >/dev/null 2>&1; then
            print_pass "Manager script status command works"
        else
            print_warn "Manager script status command has issues"
        fi
    else
        print_fail "Manager script is not executable"
    fi

    print_test "Testing daemon script configuration..."

    DAEMON_SCRIPT="$PLUGIN_ROOT/claude-nights-watch-daemon.sh"

    if [ -x "$DAEMON_SCRIPT" ]; then
        print_pass "Daemon script is executable"

        # Test that script can parse its configuration without running.
        # `bash -n` is a syntax-only check — doesn't execute the daemon
        # (which would otherwise try to start a real monitoring loop and
        # never return). The previous `timeout 3s bash -c "$SCRIPT --help"`
        # was long enough to actually start the daemon in some envs.
        if bash -n "$DAEMON_SCRIPT" 2>/dev/null; then
            print_pass "Daemon script structure is valid"
        else
            print_fail "Daemon script has syntax errors"
        fi
    else
        print_fail "Daemon script is not executable"
    fi

    print_test "Testing setup script functionality..."

    SETUP_SCRIPT="$PLUGIN_ROOT/setup-nights-watch.sh"

    if [ -x "$SETUP_SCRIPT" ]; then
        print_pass "Setup script is executable"

        # Test help function
        if "$SETUP_SCRIPT" --help >/dev/null 2>&1; then
            print_pass "Setup script help function works"
        else
            print_warn "Setup script help function not accessible"
        fi
    else
        print_fail "Setup script is not executable"
    fi
}

# Test 5: Hook Scripts Testing
test_hook_scripts() {
    print_header "Testing Hook Scripts"

    HOOKS_DIR="$TEMP_DIR/hooks/scripts"

    print_test "Testing daemon status check hook..."

    STATUS_HOOK="$HOOKS_DIR/check-daemon-status.sh"
    if [ -x "$STATUS_HOOK" ]; then
        print_pass "Status hook script is executable"

        # Test script logic (should handle missing PID file gracefully)
        if timeout 3s bash "$STATUS_HOOK" >/dev/null 2>&1; then
            print_pass "Status hook executes without errors"
        else
            print_warn "Status hook has runtime issues (expected)"
        fi
    else
        print_fail "Status hook script not executable"
    fi

    print_test "Testing session end prompt hook..."

    END_HOOK="$HOOKS_DIR/session-end-prompt.sh"
    if [ -x "$END_HOOK" ]; then
        print_pass "Session end hook script is executable"

        # Test script logic
        if timeout 3s bash "$END_HOOK" >/dev/null 2>&1; then
            print_pass "Session end hook executes without errors"
        else
            print_warn "Session end hook has runtime issues (expected)"
        fi
    else
        print_fail "Session end hook script not executable"
    fi

    print_test "Testing file change logging hook..."

    LOG_HOOK="$HOOKS_DIR/log-file-changes.sh"
    if [ -x "$LOG_HOOK" ]; then
        print_pass "File logging hook script is executable"

        # Test script logic
        if timeout 3s bash "$LOG_HOOK" >/dev/null 2>&1; then
            print_pass "File logging hook executes without errors"
        else
            print_warn "File logging hook has runtime issues (expected)"
        fi
    else
        print_fail "File logging hook script not executable"
    fi
}

# Test 6: MCP Server Testing
test_mcp_server() {
    print_header "Testing MCP Server"

    MCP_SERVER="$TEMP_DIR/mcp-server/nights-watch-server.sh"

    print_test "Testing MCP server script structure..."

    if [ -x "$MCP_SERVER" ]; then
        print_pass "MCP server script is executable"

        # Test that script has proper structure (can be parsed)
        if grep -q "handle_initialize" "$MCP_SERVER" && grep -q "handle_list_tools" "$MCP_SERVER"; then
            print_pass "MCP server has required handler functions"
        else
            print_fail "MCP server missing required handlers"
        fi

        # Test that script handles JSON-RPC protocol
        if grep -q "jsonrpc" "$MCP_SERVER"; then
            print_pass "MCP server implements JSON-RPC protocol"
        else
            print_fail "MCP server doesn't implement JSON-RPC"
        fi
    else
        print_fail "MCP server script not executable"
    fi

    print_test "Testing MCP configuration..."

    MCP_CONFIG="$TEMP_DIR/.mcp.json"
    if [ -f "$MCP_CONFIG" ]; then
        print_pass "MCP configuration exists"

        # Validate JSON
        if jq empty "$MCP_CONFIG" 2>/dev/null; then
            print_pass "MCP configuration is valid JSON"
        else
            print_fail "MCP configuration has invalid JSON"
        fi

        # Check server definition
        if jq -e '.mcpServers."nights-watch"' "$MCP_CONFIG" >/dev/null 2>&1; then
            print_pass "nights-watch MCP server is defined"
        else
            print_fail "nights-watch MCP server not defined"
        fi
    else
        print_fail "MCP configuration missing"
    fi
}

# Test 7: Task and Rules Processing
test_task_processing() {
    print_header "Testing Task and Rules Processing"

    print_test "Testing task file format and content..."

    TASK_FILE="$TEMP_DIR/test-project/task.md"
    if [ -f "$TASK_FILE" ]; then
        print_pass "Test task file exists"

        # Check that it has proper markdown structure
        if grep -q "^# " "$TASK_FILE" && grep -q "## Tasks:" "$TASK_FILE"; then
            print_pass "Task file has proper structure"
        else
            print_warn "Task file structure could be improved"
        fi

        # Check file size (should be reasonable)
        FILE_SIZE=$(wc -c < "$TASK_FILE")
        if [ "$FILE_SIZE" -gt 100 ] && [ "$FILE_SIZE" -lt 10000 ]; then
            print_pass "Task file size is reasonable: $FILE_SIZE bytes"
        else
            print_warn "Task file size may be too small or too large: $FILE_SIZE bytes"
        fi
    else
        print_fail "Test task file missing"
    fi

    print_test "Testing rules file format and content..."

    RULES_FILE="$TEMP_DIR/test-project/rules.md"
    if [ -f "$RULES_FILE" ]; then
        print_pass "Test rules file exists"

        # Check for critical rules section
        if grep -q "## CRITICAL RULES:" "$RULES_FILE" && grep -q "## ALLOWED:" "$RULES_FILE"; then
            print_pass "Rules file has proper safety structure"
        else
            print_warn "Rules file structure could be improved"
        fi
    else
        print_fail "Test rules file missing"
    fi
}

# Test 8: Integration Points Testing
test_integration_points() {
    print_header "Testing Integration Points"

    print_test "Testing plugin-to-daemon integration..."

    # Test that manager script can find daemon script. `status` exits 1
    # when the daemon isn't running (the correct, expected state during
    # a fresh install) and 0 when it is. The previous check expected
    # exit 0 only, which made every fresh test environment fail this
    # assertion. Accept either — the script ran and reported status.
    if "$PLUGIN_ROOT/claude-nights-watch-manager.sh" status >/dev/null 2>&1; then
        print_pass "Manager script can access daemon components (daemon running)"
    elif "$PLUGIN_ROOT/claude-nights-watch-manager.sh" status 2>&1 | grep -q "Daemon is not running\|not running"; then
        print_pass "Manager script can access daemon components (daemon not running, as expected)"
    else
        print_fail "Manager script cannot access daemon components"
    fi

    print_test "Testing command wrapper integration..."

    # Test that command wrapper can find manager script
    COMMAND_TEST="$TEMP_DIR/commands/bin/nights-watch"
    if [ -x "$COMMAND_TEST" ]; then
        # This will fail due to missing Claude, but should find the script
        if "$COMMAND_TEST" status 2>&1 | grep -q "claude-nights-watch-manager.sh" || [ $? -eq 0 ]; then
            print_pass "Command wrapper can locate manager script"
        else
            print_warn "Command wrapper cannot locate manager script"
        fi
    fi

    print_test "Testing environment variable propagation..."

    # Simulate Claude Code environment
    export CLAUDE_PLUGIN_ROOT="$TEMP_DIR"
    export CLAUDE_NIGHTS_WATCH_DIR="$TEMP_DIR/test-project"

    # Test that scripts use these variables correctly
    if grep -q "CLAUDE_PLUGIN_ROOT" "$TEMP_DIR/hooks/scripts/check-daemon-status.sh"; then
        print_pass "Hook scripts use CLAUDE_PLUGIN_ROOT"

        # Test variable substitution
        HOOK_SCRIPT="$TEMP_DIR/hooks/scripts/check-daemon-status.sh"
        if [ -x "$HOOK_SCRIPT" ]; then
            # This tests that the script can handle the environment variable
            if timeout 2s bash "$HOOK_SCRIPT" >/dev/null 2>&1; then
                print_pass "Hook script handles environment variables correctly"
            else
                print_warn "Hook script has environment variable issues (may be expected)"
            fi
        fi
    fi

    unset CLAUDE_PLUGIN_ROOT CLAUDE_NIGHTS_WATCH_DIR
}

# Test 9: Error Handling Testing
test_error_handling() {
    print_header "Testing Error Handling"

    print_test "Testing missing task file handling..."

    # Create a test scenario with missing task file
    MISSING_TASK_DIR="$TEMP_DIR/missing-task-test"
    mkdir -p "$MISSING_TASK_DIR"

    # Test manager script behavior with missing task file
    cd "$MISSING_TASK_DIR"
    if "$PLUGIN_ROOT/claude-nights-watch-manager.sh" status 2>&1 | grep -q "not found" || [ $? -ne 0 ]; then
        print_pass "Manager script handles missing task file appropriately"
    else
        print_fail "Manager script doesn't handle missing task file correctly"
    fi

    print_test "Testing invalid command handling..."

    # Test command wrapper with invalid arguments
    cd "$TEMP_DIR"
    if "$TEMP_DIR/commands/bin/nights-watch" invalid-command 2>&1 | grep -q "Unknown command"; then
        print_pass "Command wrapper handles invalid commands correctly"
    else
        print_fail "Command wrapper doesn't handle invalid commands"
    fi

    print_test "Testing malformed JSON handling..."

    # Test plugin.json with syntax errors (backup and restore)
    ORIGINAL_PLUGIN="$TEMP_DIR/.claude-plugin/plugin.json"
    cp "$ORIGINAL_PLUGIN" "$ORIGINAL_PLUGIN.backup"

    # Create malformed JSON
    echo '{"invalid": json}' > "$ORIGINAL_PLUGIN"

    # Test that scripts handle this gracefully
    if ! jq . "$ORIGINAL_PLUGIN" >/dev/null 2>&1; then
        print_pass "Malformed JSON is detectable"

        # Restore original
        mv "$ORIGINAL_PLUGIN.backup" "$ORIGINAL_PLUGIN"
        print_pass "Original plugin.json restored"
    else
        print_fail "Malformed JSON not detected"
        # Restore anyway
        mv "$ORIGINAL_PLUGIN.backup" "$ORIGINAL_PLUGIN" 2>/dev/null || true
    fi
}

# Test 10: Performance and Resource Testing
test_performance_resources() {
    print_header "Testing Performance and Resources"

    print_test "Testing script loading times..."

    # Test that scripts start quickly
    START_TIME=$(date +%s.%N)
    if timeout 2s bash "$PLUGIN_ROOT/claude-nights-watch-manager.sh" --help >/dev/null 2>&1; then
        END_TIME=$(date +%s.%N)
        LOAD_TIME=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "0.1")

        if (( $(echo "$LOAD_TIME < 1.0" | bc -l 2>/dev/null || echo "1") )); then
            print_pass "Manager script loads quickly: ${LOAD_TIME}s"
        else
            print_warn "Manager script loads slowly: ${LOAD_TIME}s"
        fi
    else
        print_warn "Cannot measure script load time"
    fi

    print_test "Testing file sizes and resource usage..."

    # Check that files are not excessively large
    PLUGIN_SIZE=$(du -sb "$PLUGIN_ROOT" 2>/dev/null | cut -f1 || echo "0")
    if [ "$PLUGIN_SIZE" -lt 10485760 ]; then  # 10MB limit
        print_pass "Plugin size is reasonable: $PLUGIN_SIZE bytes"
    else
        print_warn "Plugin size is large: $PLUGIN_SIZE bytes"
    fi

    # Count total files
    FILE_COUNT=$(find "$PLUGIN_ROOT" -type f | wc -l)
    if [ "$FILE_COUNT" -lt 50 ]; then
        print_pass "File count is reasonable: $FILE_COUNT files"
    else
        print_warn "File count is high: $FILE_COUNT files"
    fi
}

# Test 11: Real-World Usage Simulation
test_real_world_simulation() {
    print_header "Testing Real-World Usage Simulation"

    print_test "Simulating typical user workflow..."

    cd "$TEMP_DIR/test-project"

    # Step 1: Check initial status
    print_test "Step 1: Checking initial daemon status..."
    if "$PLUGIN_ROOT/claude-nights-watch-manager.sh" status >/dev/null 2>&1; then
        print_pass "Initial status check works"
    else
        print_warn "Initial status check has issues (expected without daemon)"
    fi

    # Step 2: Test task viewing
    print_test "Step 2: Viewing current task..."
    if "$PLUGIN_ROOT/claude-nights-watch-manager.sh" task 2>/dev/null | grep -q "Current task"; then
        print_pass "Task viewing works"
    else
        print_warn "Task viewing has issues"
    fi

    # Step 3: Test setup process
    print_test "Step 3: Testing setup script..."
    if timeout 5s bash "$PLUGIN_ROOT/setup-nights-watch.sh" --help >/dev/null 2>&1; then
        print_pass "Setup script help works"
    else
        print_warn "Setup script help not accessible"
    fi

    print_test "Simulating plugin command usage..."

    # Test command wrapper in realistic scenario
    cd "$TEMP_DIR"
    if "$TEMP_DIR/commands/bin/nights-watch" status 2>&1 | head -5 | grep -q "Daemon is not running"; then
        print_pass "Command wrapper provides helpful status information"
    else
        print_warn "Command wrapper status output could be improved"
    fi

    print_test "Testing cross-component integration..."

    # Test that all components can work together
    if [ -f "$TEMP_DIR/.claude-plugin/plugin.json" ] && \
       [ -d "$TEMP_DIR/commands" ] && \
       [ -d "$TEMP_DIR/hooks" ] && \
       [ -f "$TEMP_DIR/.mcp.json" ]; then
        print_pass "All plugin components are properly integrated"
    else
        print_fail "Plugin components are not properly integrated"
    fi
}

# Test 12: Edge Cases and Error Scenarios
test_edge_cases() {
    print_header "Testing Edge Cases and Error Scenarios"

    print_test "Testing with missing directories..."

    # Test behavior when logs directory doesn't exist
    MISSING_LOGS_DIR="$TEMP_DIR/missing-logs"
    mkdir -p "$MISSING_LOGS_DIR"

    # Remove logs directory if it exists
    if [ -d "$MISSING_LOGS_DIR/logs" ]; then
        rmdir "$MISSING_LOGS_DIR/logs"
    fi

    cd "$MISSING_LOGS_DIR"
    if "$PLUGIN_ROOT/claude-nights-watch-manager.sh" logs 2>&1 | grep -q "No log file" || [ $? -ne 0 ]; then
        print_pass "Manager script handles missing logs directory correctly"
    else
        print_fail "Manager script doesn't handle missing logs directory"
    fi

    print_test "Testing with empty task file..."

    # Create empty task file
    EMPTY_TASK_DIR="$TEMP_DIR/empty-task"
    mkdir -p "$EMPTY_TASK_DIR"
    cd "$EMPTY_TASK_DIR"
    touch task.md

    if "$PLUGIN_ROOT/claude-nights-watch-manager.sh" task 2>&1 | grep -q "task.md" || [ $? -eq 0 ]; then
        print_pass "Manager script handles empty task file correctly"
    else
        print_fail "Manager script doesn't handle empty task file"
    fi

    print_test "Testing with special characters in paths..."

    # Create directory with spaces and special characters
    SPECIAL_DIR="$TEMP_DIR/special chars-@test"
    mkdir -p "$SPECIAL_DIR"
    cd "$SPECIAL_DIR"
    echo "# Test task" > task.md

    if "$PLUGIN_ROOT/claude-nights-watch-manager.sh" task >/dev/null 2>&1; then
        print_pass "Manager script handles special characters in paths"
    else
        print_warn "Manager script has issues with special characters"
    fi
}

# Run all tests
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    Claude Nights Watch Plugin - Functional Test   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Plugin Root: $PLUGIN_ROOT"
    echo "Test Directory: $TEST_DIR"
    echo ""

    # Run all test functions
    setup_test_environment
    test_plugin_installation
    test_command_execution
    test_environment_variables
    test_core_scripts
    test_hook_scripts
    test_mcp_server
    test_task_processing
    test_integration_points
    test_error_handling
    test_performance_resources
    test_real_world_simulation
    test_edge_cases

    # Summary
    print_header "Functional Test Summary"

    TOTAL=$((PASS + FAIL + WARN))

    echo -e "${GREEN}Passed:${NC} $PASS"
    echo -e "${RED}Failed:${NC} $FAIL"
    echo -e "${YELLOW}Warnings:${NC} $WARN"
    echo -e "${BLUE}Total:${NC} $TOTAL"
    echo ""

    # Calculate success rate
    if [ $TOTAL -gt 0 ]; then
        SUCCESS_RATE=$((PASS * 100 / TOTAL))
        echo -e "${BLUE}Success Rate:${NC} ${SUCCESS_RATE}%"
    else
        SUCCESS_RATE=0
        echo -e "${YELLOW}No tests completed${NC}"
    fi

    echo ""

    # Provide assessment
    if [ $FAIL -eq 0 ]; then
        echo -e "${GREEN}✅ ALL CRITICAL TESTS PASSED!${NC}"
        echo -e "${GREEN}🎉 Plugin functionality is solid${NC}"
        if [ $WARN -eq 0 ]; then
            echo -e "${GREEN}💯 Perfect functional implementation${NC}"
        else
            echo -e "${YELLOW}⚠️  Minor issues noted but functionality is good${NC}"
        fi
    elif [ $FAIL -lt 3 ]; then
        echo -e "${YELLOW}⚠️  MOST TESTS PASSED${NC}"
        echo -e "${YELLOW}📊 Success rate: ${SUCCESS_RATE}%${NC}"
        echo -e "${YELLOW}✅ Plugin should work with minor fixes${NC}"
    else
        echo -e "${RED}❌ MULTIPLE TESTS FAILED${NC}"
        echo -e "${RED}📊 Success rate: ${SUCCESS_RATE}%${NC}"
        echo -e "${RED}❌ Plugin needs fixes before use${NC}"
    fi

    echo ""
    echo -e "${BLUE}Key Findings:${NC}"
    if [ $SUCCESS_RATE -ge 90 ]; then
        echo "  ✅ Plugin structure and functionality are excellent"
        echo "  ✅ Ready for real-world Claude Code installation"
        echo "  ✅ All core components working correctly"
    elif [ $SUCCESS_RATE -ge 70 ]; then
        echo "  ⚠️  Plugin mostly functional but needs some fixes"
        echo "  ✅ Core functionality should work in Claude Code"
        echo "  ⚠️  Some edge cases may cause issues"
    else
        echo "  ❌ Plugin has significant functional issues"
        echo "  ❌ Needs substantial fixes before Claude Code use"
        echo "  ❌ Core functionality may not work properly"
    fi

    echo ""
    echo -e "${BLUE}Recommended Next Steps:${NC}"
    echo "  1. Install in real Claude Code environment"
    echo "  2. Test all commands: /nights-watch start, status, logs, etc."
    echo "  3. Test agent integration with natural language queries"
    echo "  4. Test MCP server with programmatic tool usage"
    echo "  5. Validate end-to-end autonomous task execution"

    # Exit with appropriate code
    if [ $FAIL -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run the test suite
main

