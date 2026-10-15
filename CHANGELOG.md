# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-15

### Added
- Initial release of Claude Nights Watch
- Autonomous task execution from task.md files
- Safety rules enforcement from rules.md files
- Comprehensive logging system with full prompt/response capture
- Interactive setup wizard (`setup-nights-watch.sh`)
- Daemon management system (`claude-nights-watch-manager.sh`)
- Interactive log viewer (`view-logs.sh`)
- Test suite with immediate execution testing
- Scheduled start time support
- Integration with ccusage for accurate timing
- Fallback to time-based checking without ccusage
- Adaptive monitoring intervals based on remaining time

### Features
- **Core Daemon**: Monitors Claude usage windows and executes tasks
- **Task Management**: Reads and executes tasks from markdown files
- **Safety System**: Enforces rules and constraints for autonomous execution
- **Logging**: Complete audit trail of all executions and responses
- **Scheduling**: Start monitoring at specific times
- **Testing**: Comprehensive test suite for validation

### Documentation
- Complete README with installation and usage instructions
- Example task and rules files
- Testing documentation
- Contributing guidelines
- MIT License

### Safety
- Uses `--dangerously-skip-permissions` with safety rule enforcement
- Comprehensive example rules for common safety scenarios
- Logging of all prompts and responses for audit purposes
- Test scripts for validation before production use

## [Unreleased]

### Fixed
- All three verify/test scripts (`verify-plugin.sh`, `test/test-plugin-comprehensive.sh`, `test/test-functional-realworld.sh`) were silently exiting after the first `[PASS]` because `set -e` plus the post-increment `((PASS++))` pattern made the first counter increment evaluate to 0 (a falsy exit code). The scripts printed headers and one pass line, then exited 0 with no test summary — meaning every CI run reported success while running zero tests. Removed `set -e` from all three, replaced `((PASS++))` with `PASS=$((PASS + 1))`, and added a comment explaining why a verification script must not use `set -e`. Replaced `mcp-server` copy step in functional test that was missing from `setup_test_environment`.
- `test/test-plugin-comprehensive.sh` "Checking component paths" block failed on every run after the Nov 2025 plugin refactor because the manifest no longer carries explicit `commands`/`agents` fields (Claude Code auto-discovers them). Test now accepts either an explicit manifest field OR the auto-discovered root-level directory. Replaced the test's hardcoded `claude plugins add` install hint with the current `claude plugin install` syntax.
- `test/test-functional-realworld.sh` had five latent post-refactor bugs that surfaced once the script could actually run to completion: (1) commands path resolution required the removed manifest field, (2) hooks test grep'd `CLAUDE_PLUGIN_ROOT` in the wrong file (it lives in `hooks/hooks.json`; the .sh scripts use `BASH_SOURCE`), (3) MCP server test grep'd `CLAUDE_PLUGIN_ROOT` but the server uses `NIGHTS_WATCH_ROOT`/`BASH_SOURCE`, (4) daemon "structural" test ran the daemon with `timeout 3s bash -c "$DAEMON --help"` which actually starts the daemon and never returns; replaced with `bash -n` syntax-only check, (5) manager "can access daemon components" test expected exit 0 but `manager.sh status` correctly exits 1 when the daemon is not running.
- README install instructions and the two marketplace README files used the wrong CLI syntax (`claude plugins add`, `claude plugins marketplace add`). Replaced with the current `claude plugin install`, `claude plugin marketplace add`, `claude plugin list`, `claude plugin uninstall` (singular `plugin`). Also replaced the `claude-plugins-marketplace` repository URL with `ClaudeNightsWatch` (the marketplace is shipped inside this repo via `.claude-plugin/marketplace.json`; the referenced separate repo does not exist on github.com/aniketkarne).

### Planned
- Web dashboard for monitoring and management
- Multiple task file support
- Task scheduling and queuing
- Integration with more timing tools
- Enhanced error recovery mechanisms