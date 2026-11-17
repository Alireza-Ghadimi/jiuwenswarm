#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOFTSKILL_DIR="${ROOT_DIR}/../experiments/Softskill"
RUN_DIR="${SOFTSKILL_DIR}/softskill-two-hour-runs"
PYTHON="${SOFTSKILL_DIR}/.venv-mlx/bin/python"
SERVER="${RUN_DIR}/cache_fix/mlx_server.py"
MODEL="${RUN_DIR}/models/qwen3.5-9b-mlx-4bit"
URL="http://127.0.0.1:8023"

for required in "$PYTHON" "$SERVER" "$MODEL/config.json"; do
  if [[ ! -e "$required" ]]; then
    echo "Missing required file: $required" >&2
    exit 1
  fi
done

if curl -fsS --max-time 2 "$URL/v1/models" >/dev/null 2>&1; then
  echo "A model server is already responding at $URL/v1/models"
  curl -fsS --max-time 5 "$URL/v1/models"
  echo
  exit 0
fi

export PYTHONPATH="${SOFTSKILL_DIR}/pdfbench${PYTHONPATH:+:${PYTHONPATH}}"
export PYTHONDONTWRITEBYTECODE=1

"$PYTHON" "$SERVER" \
  --model "$MODEL" \
  --mode text \
  --host 127.0.0.1 \
  --port 8023 \
  --served-model-name qwen3.5-9b-mlx \
  --max-model-len 131072 \
  --verify-embeddings \
  --prefix-cache &
server_pid=$!

stop_server() {
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
}
trap stop_server EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for ((attempt = 0; attempt < 180; attempt++)); do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo "Qwen server exited before becoming ready." >&2
    wait "$server_pid" || true
    exit 1
  fi
  if curl -fsS --max-time 2 "$URL/v1/models" >/dev/null 2>&1; then
    echo "Qwen server ready. Model API: $URL/v1"
    echo "Models:"
    curl -fsS --max-time 5 "$URL/v1/models"
    echo
    echo "Keep this terminal open; press Ctrl-C to stop the server."
    wait "$server_pid"
    exit $?
  fi
  sleep 1
done

echo "Qwen server did not become ready within 180 seconds." >&2
exit 1
