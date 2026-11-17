#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TUI_DIR="${ROOT_DIR}/jiuwenswarm/channels/tui/frontend"
TUI_ENTRY="${TUI_DIR}/dist/index.js"
START_CMD="${ROOT_DIR}/.venv/bin/jiuwenswarm-start"
GATEWAY_PORT="${JIUWENSWARM_GATEWAY_PORT:-19001}"
backend_pid=""
log_file=""

cleanup() {
  if [[ -n "$backend_pid" ]]; then
    kill "$backend_pid" 2>/dev/null || true
    wait "$backend_pid" 2>/dev/null || true
  fi
  if [[ -n "$log_file" ]]; then
    rm -f "$log_file"
  fi
}
trap cleanup EXIT

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required to run the terminal UI." >&2
  exit 1
fi
if [[ ! -f "$TUI_ENTRY" || ! -d "${TUI_DIR}/node_modules/@mariozechner/pi-tui" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required for the first terminal UI build." >&2
    exit 1
  fi
  echo "Building the terminal UI (first run only)..."
  (
    cd "$TUI_DIR"
    npm ci --no-audit --no-fund
    npm run build
  )
fi
if [[ ! -f "$TUI_ENTRY" ]]; then
  echo "The terminal UI build did not create dist/index.js." >&2
  exit 1
fi

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  exec node "$TUI_ENTRY" "$@"
fi

if ! [[ "$GATEWAY_PORT" =~ ^[0-9]+$ ]] || (( 10#$GATEWAY_PORT < 1 || 10#$GATEWAY_PORT > 65535 )); then
  echo "JIUWENSWARM_GATEWAY_PORT must be a TCP port from 1 to 65535." >&2
  exit 2
fi
if [[ ! -x "$START_CMD" ]]; then
  echo "JiuwenSwarm is not installed in ${ROOT_DIR}/.venv. Run 'uv sync' first." >&2
  exit 1
fi
if ! command -v nc >/dev/null 2>&1; then
  echo "The nc command is needed to check the local Gateway." >&2
  exit 1
fi

cd "$ROOT_DIR"
if nc -z 127.0.0.1 "$GATEWAY_PORT" >/dev/null 2>&1; then
  echo "Using the existing JiuwenSwarm Gateway on port $GATEWAY_PORT."
else
  log_file="$(mktemp "${TMPDIR:-/tmp}/jiuwenswarm-tui.XXXXXX")"
  "$START_CMD" app >"$log_file" 2>&1 &
  backend_pid=$!
  echo "Starting the JiuwenSwarm backend for the terminal UI..."
  for ((attempt = 0; attempt < 90; attempt++)); do
    if nc -z 127.0.0.1 "$GATEWAY_PORT" >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "$backend_pid" 2>/dev/null; then
      echo "The JiuwenSwarm backend exited during startup:" >&2
      tail -n 30 "$log_file" >&2
      exit 1
    fi
    sleep 1
  done
  if ! nc -z 127.0.0.1 "$GATEWAY_PORT" >/dev/null 2>&1; then
    echo "The JiuwenSwarm Gateway did not open port $GATEWAY_PORT within 90 seconds:" >&2
    tail -n 30 "$log_file" >&2
    exit 1
  fi
fi

echo "Connecting terminal UI to ws://127.0.0.1:${GATEWAY_PORT}/tui"
node "$TUI_ENTRY" --url "ws://127.0.0.1:${GATEWAY_PORT}/tui" "$@"
