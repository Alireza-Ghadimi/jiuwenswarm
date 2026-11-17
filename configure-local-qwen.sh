#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${HOME}/.jiuwenswarm/config/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "JiuwenSwarm is not initialized: $ENV_FILE is missing." >&2
  echo "Run 'uv run jiuwenswarm-init' first." >&2
  exit 1
fi

set -a
source "${ROOT_DIR}/local-qwen.env"
set +a

python3 - "$ENV_FILE" <<'PY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
settings = {
    key: os.environ[key]
    for key in (
        "API_BASE",
        "API_KEY",
        "MODEL_NAME",
        "MODEL_PROVIDER",
        "ENDPOINT_PROFILE",
    )
}
lines = path.read_text().splitlines()
seen = set()
updated = []
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
path.write_text("\n".join(updated) + "\n")
print(f"Configured local Qwen in {path}")
print(f"Model API: {settings['API_BASE']}")
PY
