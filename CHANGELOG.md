# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `execute_task` in the daemon reported success for every run: it `wait`ed on `tee` (the last element of a backgrounded pipeline) instead of `claude`, so a crashed or failing task run logged "Task execution completed successfully", recorded `~/.claude-last-activity`, and was not retried until the 5-hour window elapsed. The run now happens in a subshell with `set -o pipefail` so the daemon sees Claude's real exit status (`test-immediate-execution.sh` had the inverse mistake — `${PIPESTATUS[0]}` is `echo`'s status, not Claude's — and now uses `pipefail` too).
- Graceful stop never worked: bash defers a trapped signal behind a foreground `sleep`, so the daemon slept through SIGTERM and `claude-nights-watch-manager.sh stop` always escalated to `kill -9` after its 10s grace period. All sleeps now go through `sleep_interruptible` (background sleep + interruptible `wait`), `stop` finishes in ~1s with the cleanup trap running, and cleanup stops an in-flight task run instead of orphaning it.
- `prepare_task_prompt` mixed its log lines into the captured prompt (log output went to stdout, which is the function's return channel), so every task sent to Claude carried `[timestamp] Applied rules from rules.md` noise. Log lines now go to stderr. Same fix in `test/test-immediate-execution.sh`.
- `local full_prompt=$(prepare_task_prompt)` masked the prepare failure (bash: `local` returns 0), so the "task file not found" branch never stopped execution. Declared and assigned separately in both the daemon and the test script; the same masking hid `get_minutes_until_reset`'s "ccusage missing" signal, which is now honored.
- Hooks read the daemon's PID file from the plugin directory while the daemon/manager write it to the project directory (`CLAUDE_NIGHTS_WATCH_DIR` or CWD) — the same bug PR #16 fixed in the MCP server. `check-daemon-status.sh` stayed silent about a running daemon and `session-end-prompt.sh` told users to start one that was already running.
- MCP `start_daemon` built a command string from its `start_time` argument and `eval`'d it, running any command substitution embedded in the tool argument (`09:00$(...)`). The manager is now called directly with the time as one quoted argument.
- `manager start --at 'YYYY-MM-DD HH:MM'` — the form documented in the usage text, README and MCP tool schema — was rejected on macOS because BSD `date -f` requires seconds. The seconds are appended when missing, and a failed parse is detected by an empty result instead of the masked `$?`.
- The author email in `plugin.json` and both marketplace manifests was the `[email protected]` placeholder; now `aniketkarne@gmail.com`.
- All three verify/test scripts (`verify-plugin.sh`, `test/test-plugin-comprehensive.sh`, `test/test-functional-realworld.sh`) were silently exiting after the first `[PASS]` because `set -e` plus the post-increment `((PASS++))` pattern made the first counter increment evaluate to 0 (a falsy exit code). The scripts printed headers and one pass line, then exited 0 with no test summary — meaning every CI run reported success while running zero tests. Removed `set -e` from all three, replaced `((PASS++))` with `PASS=$((PASS + 1))`, and added a comment explaining why a verification script must not use `set -e`. Replaced `mcp-server` copy step in functional test that was missing from `setup_test_environment`.
- `test/test-plugin-comprehensive.sh` "Checking component paths" block failed on every run after the Nov 2025 plugin refactor because the manifest no longer carries explicit `commands`/`agents` fields (Claude Code auto-discovers them). Test now accepts either an explicit manifest field OR the auto-discovered root-level directory. Replaced the test's hardcoded `claude plugins add` install hint with the current `claude plugin install` syntax.
- `test/test-functional-realworld.sh` had five latent post-refactor bugs that surfaced once the script could actually run to completion: (1) commands path resolution required the removed manifest field, (2) hooks test grep'd `CLAUDE_PLUGIN_ROOT` in the wrong file (it lives in `hooks/hooks.json`; the .sh scripts use `BASH_SOURCE`), (3) MCP server test grep'd `CLAUDE_PLUGIN_ROOT` but the server uses `NIGHTS_WATCH_ROOT`/`BASH_SOURCE`, (4) daemon "structural" test ran the daemon with `timeout 3s bash -c "$DAEMON --help"` which actually starts the daemon and never returns; replaced with `bash -n` syntax-only check, (5) manager "can access daemon components" test expected exit 0 but `manager.sh status` correctly exits 1 when the daemon is not running.
- README install instructions and the two marketplace README files used the wrong CLI syntax (`claude plugins add`, `claude plugins marketplace add`). Replaced with the current `claude plugin install`, `claude plugin marketplace add`, `claude plugin list`, `claude plugin uninstall` (singular `plugin`). Also replaced the `claude-plugins-marketplace` repository URL with `ClaudeNightsWatch` (the marketplace is shipped inside this repo via `.claude-plugin/marketplace.json`; the referenced separate repo does not exist on github.com/aniketkarne).

### Added
- `test/test-daemon-reliability.sh` (10 checks, sandboxed fake `claude` + private `HOME`): prompt cleanliness, failure/success propagation, SIGTERM interruptibility, `--at` parsing on BSD date, graceful stop timing, hook PID-dir resolution, and the MCP command-injection regression. 9 of 10 fail against the pre-fix scripts.
- `NIGHTS_WATCH_SOURCED=1` guard so tests can source the daemon's functions without starting `main`.

### Planned
- Web dashboard for monitoring and management
- Multiple task file support
- Task scheduling and queuing
- Integration with more timing tools
- Enhanced error recovery mechanisms

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
