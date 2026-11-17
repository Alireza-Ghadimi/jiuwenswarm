#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${ROOT_DIR}/.venv/bin/python"
START_CMD="${ROOT_DIR}/.venv/bin/jiuwenswarm-start"

if [[ $# -gt 1 || ( -n "${1:-}" && "${1:-}" != "--stop-only" ) ]]; then
  echo "Usage: $0 [--stop-only]" >&2
  exit 2
fi

if [[ ! -x "$PYTHON" || ! -x "$START_CMD" ]]; then
  echo "JiuwenSwarm is not installed in ${ROOT_DIR}/.venv." >&2
  exit 1
fi

echo "Stopping the default JiuwenSwarm instance..."
"$START_CMD" --stop default

# A Worker can remain resident after its Front exits. Retire only Workers
# launched from this checkout for this user's JiuwenSwarm runtime directory.
"$PYTHON" - "$ROOT_DIR" <<'PY'
import os
from pathlib import Path
import psutil
import sys

root = Path(sys.argv[1]).resolve()
run_dir = (Path.home() / ".jiuwenswarm" / "run").resolve()
expected_python = (root / ".venv" / "bin" / "python").resolve()
retired = 0

for process in psutil.process_iter(["pid", "cmdline", "exe", "uids"]):
    try:
        info = process.info
        command = info.get("cmdline") or []
        if len(command) < 5 or command[1:3] != ["-m", "jiuwenswarm.server.worker.main"]:
            continue
        if "--socket" not in command:
            continue
        socket_path = Path(command[command.index("--socket") + 1]).resolve()
        executable = Path(info["exe"] or "").resolve()
        if socket_path.parent != run_dir or executable != expected_python:
            continue
        if info["uids"].real != os.getuid():
            continue
        print(f"Retiring resident JiuwenSwarm Worker PID {process.pid}...", flush=True)
        process.terminate()
        try:
            process.wait(timeout=10)
        except psutil.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
        retired += 1
    except (psutil.NoSuchProcess, psutil.AccessDenied, IndexError, OSError):
        continue

print(f"Retired {retired} resident Worker process(es).", flush=True)
PY

if [[ "${1:-}" == "--stop-only" ]]; then
  exit 0
fi

echo "Starting JiuwenSwarm with a fresh Worker. Keep this terminal open."
exec "${ROOT_DIR}/start-jiuwenswarm.sh"
