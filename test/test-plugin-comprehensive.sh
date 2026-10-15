#!/bin/bash

# Claude Nights Watch Plugin Comprehensive Test Suite
# Tests all aspects of the plugin implementation and functionality
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
TEMP_DIR="$TEST_DIR/temp-test"
PASS=0
FAIL=0

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
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "Cleaned up temporary test directory"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Test 1: Plugin Structure Validation
test_plugin_structure() {
    print_header "Testing Plugin Structure"

    print_test "Checking required plugin directories..."

    # Required directories for Claude Code plugin
    REQUIRED_DIRS=(
        ".claude-plugin"
        "commands"
        "agents"
        "hooks"
        "mcp-server"
    )

    for dir in "${REQUIRED_DIRS[@]}"; do
        if [ -d "$PLUGIN_ROOT/$dir" ]; then
            print_pass "Directory exists: $dir"
        else
            print_fail "Directory missing: $dir"
        fi
    done

    print_test "Checking required plugin files..."

    # Required files
    REQUIRED_FILES=(
        ".claude-plugin/plugin.json"
        ".mcp.json"
        "hooks/hooks.json"
    )

    for file in "${REQUIRED_FILES[@]}"; do
        if [ -f "$PLUGIN_ROOT/$file" ]; then
            print_pass "File exists: $file"
        else
            print_fail "File missing: $file"
        fi
    done
}

# Test 2: Plugin Manifest Validation
test_plugin_manifest() {
    print_header "Testing Plugin Manifest"

    MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"

    print_test "Validating plugin.json JSON syntax..."
    if jq empty "$MANIFEST" 2>/dev/null; then
        print_pass "plugin.json is valid JSON"
    else
        print_fail "plugin.json has invalid JSON syntax"
        return 1
    fi

    print_test "Checking required manifest fields..."

    # Required fields
    REQUIRED_FIELDS=("name" "version" "description" "author")

    for field in "${REQUIRED_FIELDS[@]}"; do
        value=$(jq -r ".${field} // empty" "$MANIFEST")
        if [ -n "$value" ] && [ "$value" != "null" ]; then
            print_pass "Field present: $field = $value"
        else
            print_fail "Field missing or null: $field"
        fi
    done

    print_test "Checking component paths..."

    # Check that component paths are specified OR auto-discoverable.
    # Claude Code auto-discovers `commands/` and `agents/` at the plugin
    # root, so explicit fields are optional. (The Nov 2025 plugin refactor
    # removed these from the manifest on purpose.)
    commands_path=$(jq -r '.commands // empty' "$MANIFEST")
    agents_path=$(jq -r '.agents // empty' "$MANIFEST")
    hooks_path=$(jq -r '.hooks // empty' "$MANIFEST")
    mcp_path=$(jq -r '.mcpServers // empty' "$MANIFEST")

    if [ -n "$commands_path" ]; then
        print_pass "Commands path: $commands_path"
    elif [ -d "$PLUGIN_ROOT/commands" ]; then
        print_pass "Commands auto-discovered from $PLUGIN_ROOT/commands/"
    else
        print_fail "Commands path missing and no commands/ directory to auto-discover"
    fi

    if [ -n "$agents_path" ]; then
        print_pass "Agents path: $agents_path"
    elif [ -d "$PLUGIN_ROOT/agents" ]; then
        print_pass "Agents auto-discovered from $PLUGIN_ROOT/agents/"
    else
        print_fail "Agents path missing and no agents/ directory to auto-discover"
    fi

    if [ -n "$hooks_path" ]; then
        print_pass "Hooks path: $hooks_path"
    else
        print_fail "Hooks path missing"
    fi

    if [ -n "$mcp_path" ]; then
        print_pass "MCP servers path: $mcp_path"
    else
        print_fail "MCP servers path missing"
    fi
}

# Test 3: Command Files Validation
test_command_files() {
    print_header "Testing Command Files"

    COMMANDS_DIR="$PLUGIN_ROOT/commands"

    print_test "Checking for command files..."

    # Expected command files
    EXPECTED_COMMANDS=(
        "start.md"
        "stop.md"
        "restart.md"
        "status.md"
        "logs.md"
        "task.md"
        "setup.md"
    )

    for cmd in "${EXPECTED_COMMANDS[@]}"; do
        if [ -f "$COMMANDS_DIR/$cmd" ]; then
            print_pass "Command file exists: $cmd"

            # Check for required frontmatter
            if grep -q "^---$" "$COMMANDS_DIR/$cmd"; then
                print_pass "Command has frontmatter: $cmd"
            else
                print_warn "Command missing frontmatter: $cmd"
            fi

            # Check for description field
            if grep -q "description:" "$COMMANDS_DIR/$cmd"; then
                print_pass "Command has description: $cmd"
            else
                print_warn "Command missing description: $cmd"
            fi
        else
            print_fail "Command file missing: $cmd"
        fi
    done

    print_test "Checking command wrapper..."

    if [ -f "$COMMANDS_DIR/bin/nights-watch" ]; then
        print_pass "Command wrapper exists"

        if [ -x "$COMMANDS_DIR/bin/nights-watch" ]; then
            print_pass "Command wrapper is executable"
        else
            print_fail "Command wrapper not executable"
        fi
    else
        print_fail "Command wrapper missing"
    fi
}

# Test 4: Agent Files Validation
test_agent_files() {
    print_header "Testing Agent Files"

    AGENTS_DIR="$PLUGIN_ROOT/agents"

    print_test "Checking for agent files..."

    if [ -f "$AGENTS_DIR/task-executor.md" ]; then
        print_pass "Task Executor agent exists"

        # Check for required frontmatter
        if grep -q "^---$" "$AGENTS_DIR/task-executor.md"; then
            print_pass "Agent has frontmatter"

            # Check for required fields
            if grep -q "description:" "$AGENTS_DIR/task-executor.md"; then
                print_pass "Agent has description"
            else
                print_fail "Agent missing description"
            fi

            if grep -q "capabilities:" "$AGENTS_DIR/task-executor.md"; then
                print_pass "Agent has capabilities"
            else
                print_fail "Agent missing capabilities"
            fi
        else
            print_fail "Agent missing frontmatter"
        fi
    else
        print_fail "Task Executor agent missing"
    fi
}

# Test 5: Hooks Configuration Validation
test_hooks_config() {
    print_header "Testing Hooks Configuration"

    HOOKS_FILE="$PLUGIN_ROOT/hooks/hooks.json"

    print_test "Validating hooks.json..."

    if [ -f "$HOOKS_FILE" ]; then
        print_pass "hooks.json exists"

        if jq empty "$HOOKS_FILE" 2>/dev/null; then
            print_pass "hooks.json is valid JSON"
        else
            print_fail "hooks.json has invalid JSON"
        fi

        # Check for expected hook events
        if jq -e '.hooks.SessionStart // empty' "$HOOKS_FILE" >/dev/null 2>&1; then
            print_pass "SessionStart hook configured"
        else
            print_warn "SessionStart hook not configured"
        fi

        if jq -e '.hooks.PostToolUse // empty' "$HOOKS_FILE" >/dev/null 2>&1; then
            print_pass "PostToolUse hook configured"
        else
            print_warn "PostToolUse hook not configured"
        fi
    else
        print_fail "hooks.json missing"
    fi

    print_test "Checking hook scripts..."

    HOOK_SCRIPTS_DIR="$PLUGIN_ROOT/hooks/scripts"
    EXPECTED_SCRIPTS=(
        "check-daemon-status.sh"
        "session-end-prompt.sh"
        "log-file-changes.sh"
    )

    for script in "${EXPECTED_SCRIPTS[@]}"; do
        script_path="$HOOK_SCRIPTS_DIR/$script"
        if [ -f "$script_path" ]; then
            print_pass "Hook script exists: $script"

            if [ -x "$script_path" ]; then
                print_pass "Hook script executable: $script"
            else
                print_fail "Hook script not executable: $script"
            fi
        else
            print_fail "Hook script missing: $script"
        fi
    done
}

# Test 6: MCP Server Validation
test_mcp_server() {
    print_header "Testing MCP Server"

    MCP_CONFIG="$PLUGIN_ROOT/.mcp.json"
    MCP_SERVER="$PLUGIN_ROOT/mcp-server/nights-watch-server.sh"

    print_test "Checking MCP configuration..."

    if [ -f "$MCP_CONFIG" ]; then
        print_pass "MCP config exists"

        if jq empty "$MCP_CONFIG" 2>/dev/null; then
            print_pass "MCP config is valid JSON"
        else
            print_fail "MCP config has invalid JSON"
        fi

        # Check for nights-watch server
        if jq -e '.mcpServers."nights-watch" // empty' "$MCP_CONFIG" >/dev/null 2>&1; then
            print_pass "nights-watch MCP server configured"
        else
            print_fail "nights-watch MCP server not configured"
        fi
    else
        print_fail "MCP config missing"
    fi

    print_test "Checking MCP server script..."

    if [ -f "$MCP_SERVER" ]; then
        print_pass "MCP server script exists"

        if [ -x "$MCP_SERVER" ]; then
            print_pass "MCP server script executable"
        else
            print_fail "MCP server script not executable"
        fi
    else
        print_fail "MCP server script missing"
    fi
}

# Test 7: Core Scripts Validation
test_core_scripts() {
    print_header "Testing Core Scripts"

    CORE_SCRIPTS=(
        "claude-nights-watch-daemon.sh"
        "claude-nights-watch-manager.sh"
        "setup-nights-watch.sh"
        "view-logs.sh"
    )

    for script in "${CORE_SCRIPTS[@]}"; do
        if [ -f "$PLUGIN_ROOT/$script" ]; then
            print_pass "Core script exists: $script"

            if [ -x "$PLUGIN_ROOT/$script" ]; then
                print_pass "Core script executable: $script"
            else
                print_warn "Core script not executable: $script"
            fi
        else
            print_fail "Core script missing: $script"
        fi
    done
}

# Test 8: Documentation Validation
test_documentation() {
    print_header "Testing Documentation"

    DOC_FILES=(
        "README.md"
        "CHANGELOG.md"
        "CONTRIBUTING.md"
        "LICENSE"
    )

    for doc in "${DOC_FILES[@]}"; do
        if [ -f "$PLUGIN_ROOT/$doc" ]; then
            print_pass "Documentation exists: $doc"
        else
            print_fail "Documentation missing: $doc"
        fi
    done

    # Check for plugin-specific docs
    PLUGIN_DOCS=(
        "PLUGIN_README.md"
        "PLUGIN_INSTALLATION.md"
        "PLUGIN_TESTING.md"
        "MARKETPLACE_SETUP.md"
    )

    for doc in "${PLUGIN_DOCS[@]}"; do
        if [ -f "$PLUGIN_ROOT/$doc" ]; then
            print_info "Plugin doc exists: $doc"
        fi
    done
}

# Test 9: Examples Validation
test_examples() {
    print_header "Testing Example Files"

    if [ -d "$PLUGIN_ROOT/examples" ]; then
        print_pass "examples/ directory exists"

        EXAMPLE_FILES=(
            "task.example.md"
            "rules.example.md"
        )

        for example in "${EXAMPLE_FILES[@]}"; do
            if [ -f "$PLUGIN_ROOT/examples/$example" ]; then
                print_pass "Example file exists: $example"
            else
                print_warn "Example file missing: $example"
            fi
        done
    else
        print_warn "examples/ directory missing"
    fi
}

# Test 10: Marketplace Files Validation
test_marketplace() {
    print_header "Testing Marketplace Files"

    MARKETPLACE_DIR="$PLUGIN_ROOT/marketplace-example"

    if [ -d "$MARKETPLACE_DIR" ]; then
        print_pass "marketplace-example/ directory exists"

        if [ -f "$MARKETPLACE_DIR/plugins.json" ]; then
            print_pass "Marketplace plugins.json exists"

            if jq empty "$MARKETPLACE_DIR/plugins.json" 2>/dev/null; then
                print_pass "Marketplace plugins.json is valid JSON"
            else
                print_fail "Marketplace plugins.json has invalid JSON"
            fi
        else
            print_fail "Marketplace plugins.json missing"
        fi

        if [ -f "$MARKETPLACE_DIR/README.md" ]; then
            print_pass "Marketplace README exists"
        else
            print_warn "Marketplace README missing"
        fi
    else
        print_warn "marketplace-example/ directory missing"
    fi
}

# Test 11: Integration Test Simulation
test_integration_simulation() {
    print_header "Testing Integration Simulation"

    print_test "Creating temporary test environment..."

    # Create temp directory for testing
    mkdir -p "$TEMP_DIR"

    print_test "Copying plugin files to temp directory..."

    # Copy essential plugin components
    cp -r "$PLUGIN_ROOT/.claude-plugin" "$TEMP_DIR/"
    cp -r "$PLUGIN_ROOT/commands" "$TEMP_DIR/"
    cp -r "$PLUGIN_ROOT/agents" "$TEMP_DIR/"
    cp -r "$PLUGIN_ROOT/hooks" "$TEMP_DIR/"
    cp "$PLUGIN_ROOT/.mcp.json" "$TEMP_DIR/"

    if [ -d "$TEMP_DIR/.claude-plugin" ] && [ -d "$TEMP_DIR/commands" ] && [ -d "$TEMP_DIR/agents" ]; then
        print_pass "Plugin structure copied successfully"
    else
        print_fail "Failed to copy plugin structure"
    fi

    print_test "Testing plugin.json in temp environment..."

    if [ -f "$TEMP_DIR/.claude-plugin/plugin.json" ]; then
        print_pass "Plugin manifest accessible in temp environment"

        # Test JSON validity
        if jq empty "$TEMP_DIR/.claude-plugin/plugin.json" 2>/dev/null; then
            print_pass "Plugin manifest valid in temp environment"
        else
            print_fail "Plugin manifest invalid in temp environment"
        fi
    else
        print_fail "Plugin manifest not accessible in temp environment"
    fi

    print_test "Testing command structure..."

    if [ -f "$TEMP_DIR/commands/bin/nights-watch" ]; then
        print_pass "Command wrapper accessible"

        # Test if wrapper can find manager script (would fail in real env but structure ok)
        if "$TEMP_DIR/commands/bin/nights-watch" help >/dev/null 2>&1; then
            print_pass "Command wrapper functional"
        else
            print_warn "Command wrapper has dependency issues (expected in test env)"
        fi
    else
        print_fail "Command wrapper not accessible"
    fi
}

# Test 12: Environment Variables Test
test_environment_variables() {
    print_header "Testing Environment Variables"

    print_test "Testing CLAUDE_PLUGIN_ROOT simulation..."

    # This simulates what would happen when Claude Code sets the environment variable
    export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

    # Test that scripts can access this (they use it in practice)
    if [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ "$CLAUDE_PLUGIN_ROOT" = "$PLUGIN_ROOT" ]; then
        print_pass "CLAUDE_PLUGIN_ROOT environment variable works"
    else
        print_fail "CLAUDE_PLUGIN_ROOT environment variable issue"
    fi

    # Test that the variable is used correctly in the hooks manifest.
    # The variable appears in hooks/hooks.json (the manifest that names
    # each hook command) — the .sh scripts themselves use BASH_SOURCE
    # to derive a local path, which is the right pattern for portable
    # direct invocation.
    if grep -q "CLAUDE_PLUGIN_ROOT" "$PLUGIN_ROOT/hooks/hooks.json"; then
        print_pass "Hooks manifest uses CLAUDE_PLUGIN_ROOT correctly"
    else
        print_fail "Hooks manifest does not use CLAUDE_PLUGIN_ROOT"
    fi

    # The MCP server is configured via .claude-plugin/.mcp.json which
    # passes NIGHTS_WATCH_ROOT in the env block. The script accepts
    # NIGHTS_WATCH_ROOT or falls back to BASH_SOURCE derivation.
    if grep -q "NIGHTS_WATCH_ROOT\|BASH_SOURCE" "$PLUGIN_ROOT/mcp-server/nights-watch-server.sh"; then
        print_pass "MCP server resolves plugin root (NIGHTS_WATCH_ROOT or BASH_SOURCE)"
    else
        print_fail "MCP server does not resolve plugin root"
    fi

    unset CLAUDE_PLUGIN_ROOT
}

# Test 13: File Permissions Test
test_file_permissions() {
    print_header "Testing File Permissions"

    print_test "Checking script executability..."

    # Core scripts
    CORE_SCRIPTS=(
        "claude-nights-watch-daemon.sh"
        "claude-nights-watch-manager.sh"
        "setup-nights-watch.sh"
        "view-logs.sh"
    )

    for script in "${CORE_SCRIPTS[@]}"; do
        if [ -x "$PLUGIN_ROOT/$script" ]; then
            print_pass "Core script executable: $script"
        else
            print_warn "Core script not executable: $script"
        fi
    done

    # Plugin scripts
    PLUGIN_SCRIPTS=(
        "commands/bin/nights-watch"
        "mcp-server/nights-watch-server.sh"
    )

    for script in "${PLUGIN_SCRIPTS[@]}"; do
        if [ -x "$PLUGIN_ROOT/$script" ]; then
            print_pass "Plugin script executable: $script"
        else
            print_fail "Plugin script not executable: $script"
        fi
    done
}

# Test 14: Content Validation
test_content_validation() {
    print_header "Testing Content Validation"

    print_test "Checking for placeholder content..."

    # Check that files don't contain placeholder text
    if grep -r "PLACEHOLDER\|TODO\|FIXME" "$PLUGIN_ROOT/commands/" "$PLUGIN_ROOT/agents/" "$PLUGIN_ROOT/hooks/"; then
        print_warn "Found placeholder content in plugin files"
    else
        print_pass "No placeholder content found"
    fi

    print_test "Checking for broken links..."

    # Check for common broken link patterns
    if grep -r "https://example.com\|http://example.com" "$PLUGIN_ROOT/"; then
        print_warn "Found example URLs in documentation"
    else
        print_pass "No broken example URLs found"
    fi
}

# Test 15: Dependencies Check
test_dependencies() {
    print_header "Testing Dependencies"

    print_test "Checking for jq (JSON validation)..."

    if command -v jq >/dev/null 2>&1; then
        print_pass "jq is available for JSON validation"
    else
        print_warn "jq not available - JSON validation limited"
    fi

    print_test "Checking for required external tools..."

    # These are needed for the plugin to function
    REQUIRED_TOOLS=("bash" "cat" "echo" "date" "grep" "sed" "awk")

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            print_pass "Required tool available: $tool"
        else
            print_fail "Required tool missing: $tool"
        fi
    done
}

# Run all tests
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Claude Nights Watch Plugin Comprehensive Test   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Plugin Root: $PLUGIN_ROOT"
    echo "Test Directory: $TEST_DIR"
    echo ""

    # Run all test functions
    test_plugin_structure
    test_plugin_manifest
    test_command_files
    test_agent_files
    test_hooks_config
    test_mcp_server
    test_core_scripts
    test_documentation
    test_examples
    test_marketplace
    test_integration_simulation
    test_environment_variables
    test_file_permissions
    test_content_validation
    test_dependencies

    # Summary
    print_header "Test Summary"

    TOTAL=$((PASS + FAIL))

    echo -e "${GREEN}Passed:${NC} $PASS"
    echo -e "${RED}Failed:${NC} $FAIL"
    echo -e "${BLUE}Total:${NC} $TOTAL"
    echo ""

    # Calculate confidence percentage
    if [ $TOTAL -gt 0 ]; then
        CONFIDENCE=$((PASS * 100 / TOTAL))
        echo -e "${BLUE}Confidence Score:${NC} ${CONFIDENCE}%"
    else
        CONFIDENCE=0
        echo -e "${YELLOW}No tests completed${NC}"
    fi

    echo ""

    # Provide assessment
    if [ $FAIL -eq 0 ]; then
        echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
        echo -e "${GREEN}🎉 Plugin structure is 100% correct and ready for distribution${NC}"
        echo -e "${GREEN}📦 Plugin should install and function properly in Claude Code${NC}"
    elif [ $FAIL -lt 3 ]; then
        echo -e "${YELLOW}⚠️  MOST TESTS PASSED${NC}"
        echo -e "${YELLOW}📊 Plugin structure is ${CONFIDENCE}% correct${NC}"
        if [ $CONFIDENCE -ge 90 ]; then
            echo -e "${YELLOW}✅ Plugin should work with minor fixes${NC}"
        else
            echo -e "${YELLOW}⚠️  Plugin needs fixes before distribution${NC}"
        fi
    else
        echo -e "${RED}❌ MULTIPLE TESTS FAILED${NC}"
        echo -e "${RED}📊 Plugin structure is ${CONFIDENCE}% correct${NC}"
        echo -e "${RED}❌ Plugin needs significant fixes before distribution${NC}"
    fi

    echo ""
    echo -e "${BLUE}Plugin can be installed with:${NC}"
    echo "  claude plugin marketplace add $PLUGIN_ROOT"
    echo "  claude plugin install claude-nights-watch@claude-nights-watch-marketplace"
    echo ""
    echo -e "${BLUE}Or directly from GitHub:${NC}"
    echo "  claude plugin install https://github.com/aniketkarne/ClaudeNightsWatch"
    echo ""

    # Exit with appropriate code
    if [ $FAIL -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run the test suite
main

