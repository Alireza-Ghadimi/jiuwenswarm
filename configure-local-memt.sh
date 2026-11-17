#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${JIUWENSWARM_ENV_FILE:-${HOME}/.jiuwenswarm/config/.env}"
PORT="${1:-}"
MODE="${2:-configure}"

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( 10#$PORT < 1 || 10#$PORT > 65535 )); then
  echo "Usage: $0 PORT [--check] (a TCP port from 1 to 65535)" >&2
  exit 2
fi
if [[ $# -gt 2 || ( "$MODE" != "configure" && "$MODE" != "--check" ) ]]; then
  echo "Usage: $0 PORT [--check]" >&2
  exit 2
fi
if [[ ! -f "$ENV_FILE" ]]; then
  echo "JiuwenSwarm config is missing: $ENV_FILE" >&2
  exit 1
fi

python3 - "$ENV_FILE" "$PORT" "$MODE" <<'PY'
import json
from pathlib import Path
import shutil
import sys
from urllib.error import URLError
from urllib.request import urlopen

config_path = Path(sys.argv[1])
port = int(sys.argv[2])
mode = sys.argv[3]
base_url = f"http://127.0.0.1:{port}"
model_id = "MemTensor/MemT-1.0-Nano"

try:
    with urlopen(base_url + "/health", timeout=15) as response:
        health = json.load(response)
    with urlopen(base_url + "/v1/models", timeout=15) as response:
        models = json.load(response)
except (URLError, TimeoutError, ValueError) as exc:
    raise SystemExit(f"MemT API is not reachable at {base_url}: {exc}") from exc

if health.get("status") != "ok" or not any(
    item.get("id") == model_id for item in models.get("data", [])
):
    raise SystemExit(f"The server at {base_url} does not report {model_id}")

if mode == "--check":
    print(f"MemT API ready: {model_id} at {base_url}/v1")
    raise SystemExit(0)

backup_path = config_path.with_name(".env.before-memt")
if not backup_path.exists():
    shutil.copy2(config_path, backup_path)

settings = {
    "API_BASE": base_url + "/v1",
    "API_KEY": "local",
    "MODEL_NAME": model_id,
    "MODEL_PROVIDER": "OpenAI",
    "ENDPOINT_PROFILE": "openai_compatible",
}
lines = config_path.read_text().splitlines()
updated = []
seen = set()
for line in lines:
    key = line.split("=", 1)[0].strip()
    if key in settings:
        updated.append(f"{key}={settings[key]}")
        seen.add(key)
    else:
        updated.append(line)
for key, value in settings.items():
    if key not in seen:
        updated.append(f"{key}={value}")
config_path.write_text("\n".join(updated) + "\n")

print(f"JiuwenSwarm now points to {model_id} at {base_url}/v1")
print(f"Previous config saved at {backup_path}")
print("Restart JiuwenSwarm to load the new model settings.")
PY
