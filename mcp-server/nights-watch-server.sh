#!/bin/bash

# Claude Nights Watch MCP Server
# Provides programmatic tools for Claude to control and query the daemon

PLUGIN_ROOT="${NIGHTS_WATCH_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
MANAGER_SCRIPT="$PLUGIN_ROOT/claude-nights-watch-manager.sh"
DAEMON_SCRIPT="$PLUGIN_ROOT/claude-nights-watch-daemon.sh"
# PID and log files are written to the project directory by the daemon/manager,
# not the plugin directory. Use CLAUDE_NIGHTS_WATCH_DIR (or CWD) to match.
TASK_DIR="${CLAUDE_NIGHTS_WATCH_DIR:-$(pwd)}"
PID_FILE="$TASK_DIR/logs/claude-nights-watch-daemon.pid"
LOG_FILE="$TASK_DIR/logs/claude-nights-watch-daemon.log"

# MCP Protocol Implementation
# This is a simplified MCP server that responds to tool calls

handle_initialize() {
    cat << 'EOF'
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "tools": {}
    },
    "serverInfo": {
      "name": "nights-watch",
      "version": "1.0.0"
    }
  }
}
EOF
}

handle_list_tools() {
    cat << 'EOF'
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "get_daemon_status",
        "description": "Get the current status of the Nights Watch daemon including PID, running state, and configuration",
        "inputSchema": {
          "type": "object",
          "properties": {},
          "required": []
        }
      },
      {
        "name": "start_daemon",
        "description": "Start the Nights Watch daemon with optional scheduled start time",
        "inputSchema": {
          "type": "object",
          "properties": {
            "start_time": {
              "type": "string",
              "description": "Optional start time in format HH:MM or YYYY-MM-DD HH:MM"
            }
          }
        }
      },
      {
        "name": "stop_daemon",
        "description": "Stop the running Nights Watch daemon",
        "inputSchema": {
          "type": "object",
          "properties": {},
          "required": []
        }
      },
      {
        "name": "get_logs",
        "description": "Retrieve recent log entries from the daemon",
        "inputSchema": {
          "type": "object",
          "properties": {
            "lines": {
              "type": "number",
              "description": "Number of recent lines to retrieve (default: 50)"
            }
          }
        }
      },
      {
        "name": "read_task",
        "description": "Read the current task.md file content",
        "inputSchema": {
          "type": "object",
          "properties": {
            "path": {
              "type": "string",
              "description": "Optional path to task.md (default: ./task.md)"
            }
          }
        }
      },
      {
        "name": "read_rules",
        "description": "Read the current rules.md file content",
        "inputSchema": {
          "type": "object",
          "properties": {
            "path": {
              "type": "string",
              "description": "Optional path to rules.md (default: ./rules.md)"
            }
          }
        }
      },
      {
        "name": "write_task",
        "description": "Write or update the task.md file",
        "inputSchema": {
          "type": "object",
          "properties": {
            "content": {
              "type": "string",
              "description": "The task content to write"
            },
            "path": {
              "type": "string",
              "description": "Optional path to task.md (default: ./task.md)"
            }
          },
          "required": ["content"]
        }
      },
      {
        "name": "write_rules",
        "description": "Write or update the rules.md file",
        "inputSchema": {
          "type": "object",
          "properties": {
            "content": {
              "type": "string",
              "description": "The rules content to write"
            },
            "path": {
              "type": "string",
              "description": "Optional path to rules.md (default: ./rules.md)"
            }
          },
          "required": ["content"]
        }
      }
    ]
  }
}
EOF
}

get_daemon_status() {
    local status="stopped"
    local pid=""
    local details=""

    if [ -f "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            status="running"
            details="Daemon is running with PID $pid"
        else
            details="PID file exists but process not running"
        fi
    else
        details="Daemon is not running (no PID file)"
    fi

    cat << EOF
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": $(jq -n --arg s "$status" --arg p "$pid" --arg d "$details" '({status: $s, pid: $p, details: $d} | tojson)')
      }
    ]
  }
}
EOF
}

start_daemon() {
    local start_time="$1"
    local args=""

    if [ -n "$start_time" ]; then
        args="--at \"$start_time\""
    fi

    local output=$(eval "$MANAGER_SCRIPT start $args" 2>&1)
    local exit_code=$?

    cat << EOF
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "content": [
      {
        "type": "text",
        "text": $(echo "$output" | jq -Rs .)
      }
    ],
    "isError": $([ $exit_code -ne 0 ] && echo "true" || echo "false")
  }
}
EOF
}

stop_daemon() {
    local output=$("$MANAGER_SCRIPT" stop 2>&1)
    local exit_code=$?

    cat << EOF
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "content": [
      {
        "type": "text",
        "text": $(echo "$output" | jq -Rs .)
      }
    ],
    "isError": $([ $exit_code -ne 0 ] && echo "true" || echo "false")
  }
}
EOF
}

get_logs() {
    local lines="${1:-50}"

    if [ -f "$LOG_FILE" ]; then
        local logs=$(tail -n "$lines" "$LOG_FILE")
        cat << EOF
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "content": [
      {
        "type": "text",
        "text": $(echo "$logs" | jq -Rs .)
      }
    ]
  }
}
EOF
    else
        cat << EOF
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "No log file found"
      }
    ]
  }
}
EOF
    fi
}

read_task() {
    local path="${1:-./task.md}"

    if [ -f "$path" ]; then
        local content=$(cat "$path")
        cat << EOF
{
  "jsonrpc": "2.0",
  "id": 7,
  "result": {
    "content": [
      {
        "type": "text",
        "text": $(echo "$content" | jq -Rs .)
      }
    ]
  }
}
EOF
    else
        cat << EOF
{
  "jsonrpc": "2.0",
  "id": 7,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Task file not found at $path"
      }
    ],
    "isError": true
  }
}
EOF
    fi
}

read_rules() {
    local path="${1:-./rules.md}"

    if [ -f "$path" ]; then
        local content=$(cat "$path")
        cat << EOF
{
  "jsonrpc": "2.0",
  "id": 8,
  "result": {
    "content": [
      {
        "type": "text",
        "text": $(echo "$content" | jq -Rs .)
      }
    ]
  }
}
EOF
    else
        cat << EOF
{
  "jsonrpc": "2.0",
  "id": 8,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Rules file not found at $path"
      }
    ],
    "isError": true
  }
}
EOF
    fi
}

write_task() {
    local content="$1"
    local path="${2:-./task.md}"

    echo "$content" > "$path"

    cat << EOF
{
  "jsonrpc": "2.0",
  "id": 9,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Task file written to $path"
      }
    ]
  }
}
EOF
}

write_rules() {
    local content="$1"
    local path="${2:-./rules.md}"

    echo "$content" > "$path"

    cat << EOF
{
  "jsonrpc": "2.0",
  "id": 10,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Rules file written to $path"
      }
    ]
  }
}
EOF
}

# Helper: send response as compact single-line JSON with correct request ID
# MCP stdio transport requires NDJSON (one JSON object per line).
# JSON-RPC requires the response id to match the request id.
send_response() {
    local id="$1"
    if [ "$id" != "null" ] && [ -n "$id" ]; then
        jq -c --argjson id "$id" '.id = $id'
    else
        jq -c .
    fi
}

# Main MCP server loop
# Read JSON-RPC requests from stdin and respond on stdout
while IFS= read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    method=$(echo "$line" | jq -r '.method // empty')
    id=$(echo "$line" | jq '.id // null')

    case "$method" in
        "initialize")
            handle_initialize | send_response "$id"
            ;;
        "notifications/initialized")
            # Notification — no response needed
            ;;
        "tools/list")
            handle_list_tools | send_response "$id"
            ;;
        "tools/call")
            tool_name=$(echo "$line" | jq -r '.params.name')
            case "$tool_name" in
                "get_daemon_status")
                    get_daemon_status | send_response "$id"
                    ;;
                "start_daemon")
                    start_time=$(echo "$line" | jq -r '.params.arguments.start_time // empty')
                    start_daemon "$start_time" | send_response "$id"
                    ;;
                "stop_daemon")
                    stop_daemon | send_response "$id"
                    ;;
                "get_logs")
                    lines=$(echo "$line" | jq -r '.params.arguments.lines // 50')
                    get_logs "$lines" | send_response "$id"
                    ;;
                "read_task")
                    path=$(echo "$line" | jq -r '.params.arguments.path // "./task.md"')
                    read_task "$path" | send_response "$id"
                    ;;
                "read_rules")
                    path=$(echo "$line" | jq -r '.params.arguments.path // "./rules.md"')
                    read_rules "$path" | send_response "$id"
                    ;;
                "write_task")
                    content=$(echo "$line" | jq -r '.params.arguments.content')
                    path=$(echo "$line" | jq -r '.params.arguments.path // "./task.md"')
                    write_task "$content" "$path" | send_response "$id"
                    ;;
                "write_rules")
                    content=$(echo "$line" | jq -r '.params.arguments.content')
                    path=$(echo "$line" | jq -r '.params.arguments.path // "./rules.md"')
                    write_rules "$content" "$path" | send_response "$id"
                    ;;
            esac
            ;;
    esac
done
