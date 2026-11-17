#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MEMT_LAUNCHER="${ROOT_DIR}/memt-1.0/deploy_mac_nano.sh"
TUI_LAUNCHER="${ROOT_DIR}/start-jiuwenswarm-tui.sh"
CONFIG_LAUNCHER="${ROOT_DIR}/configure-local-memt.sh"
ENV_FILE="${JIUWENSWARM_ENV_FILE:-${HOME}/.jiuwenswarm/config/.env}"
MEMT_PORT="${MEMT_PORT:-30000}"
MEMT_URL="http://127.0.0.1:${MEMT_PORT}"
SERVER_LOG="${ROOT_DIR}/memt-1.0/memt-state/server.log"
memt_pid=""

cleanup() {
  if [[ -n "$memt_pid" ]]; then
    echo "Stopping the MemT server started by this launcher..."
    kill "$memt_pid" 2>/dev/null || true
    wait "$memt_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0 [TUI options such as --session SESSION_ID]"
  echo "Starts MemT and JiuwenSwarm as needed, then opens the TUI in this terminal."
  exit 0
fi
if [[ ! "$MEMT_PORT" =~ ^[0-9]+$ ]] || (( 10#$MEMT_PORT < 1 || 10#$MEMT_PORT > 65535 )); then
  echo "MEMT_PORT must be a TCP port from 1 to 65535." >&2
  exit 2
fi
if [[ ! -x "$MEMT_LAUNCHER" || ! -x "$TUI_LAUNCHER" || ! -x "$CONFIG_LAUNCHER" ]]; then
  echo "A required local launcher is missing or not executable." >&2
  exit 1
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "JiuwenSwarm is not initialized: $ENV_FILE is missing." >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1 || ! command -v nc >/dev/null 2>&1; then
  echo "curl and nc are required to check the local services." >&2
  exit 1
fi

cd "$ROOT_DIR"
if nc -z 127.0.0.1 "$MEMT_PORT" >/dev/null 2>&1; then
  echo "Using the existing server on port $MEMT_PORT."
else
  mkdir -p "$(dirname "$SERVER_LOG")"
  echo "Starting MemT; model loading may take a few minutes..."
  echo "MemT server log: $SERVER_LOG"
  MEMT_PORT="$MEMT_PORT" "$MEMT_LAUNCHER" serve >>"$SERVER_LOG" 2>&1 &
  memt_pid=$!
  ready=false
  for ((attempt = 0; attempt < 450; attempt++)); do
    if curl --fail --silent --max-time 2 "$MEMT_URL/health" >/dev/null 2>&1; then
      ready=true
      break
    fi
    if ! kill -0 "$memt_pid" 2>/dev/null; then
      echo "MemT exited during startup. Recent log output:" >&2
      tail -n 40 "$SERVER_LOG" >&2
      exit 1
    fi
    sleep 2
  done
  if [[ "$ready" != true ]]; then
    echo "MemT did not become ready within 15 minutes. Recent log output:" >&2
    tail -n 40 "$SERVER_LOG" >&2
    exit 1
  fi
fi

"$CONFIG_LAUNCHER" "$MEMT_PORT" --check

# A running JiuwenSwarm process keeps its old model settings. Restart it only
# when this launcher needs to change the model configuration.
if ! python3 - "$ENV_FILE" "$MEMT_PORT" <<'PY'
from pathlib import Path
import sys

settings = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    key, separator, value = line.partition("=")
    if separator:
        settings[key.strip()] = value.strip()
port = sys.argv[2]
expected = {
    "API_BASE": f"http://127.0.0.1:{port}/v1",
    "API_KEY": "local",
    "MODEL_NAME": "MemTensor/MemT-1.0-Nano",
    "MODEL_PROVIDER": "OpenAI",
    "ENDPOINT_PROFILE": "openai_compatible",
}
raise SystemExit(0 if all(settings.get(key) == value for key, value in expected.items()) else 1)
PY
then
  echo "Switching JiuwenSwarm to MemT and restarting its backend..."
  "${ROOT_DIR}/repair-jiuwenswarm-memt.sh" --stop-only
  "$CONFIG_LAUNCHER" "$MEMT_PORT"
fi

echo "Opening the JiuwenSwarm terminal UI. Exit it to return to this shell."
"$TUI_LAUNCHER" "$@"
