#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="${ROOT_DIR}/jiuwenswarm/channels/web/frontend"
START_CMD="${ROOT_DIR}/.venv/bin/jiuwenswarm-start"

if [[ ! -x "$START_CMD" ]]; then
  echo "JiuwenSwarm is not installed in ${ROOT_DIR}/.venv. Run 'uv sync' first." >&2
  exit 1
fi

# A normal start needs the static Web UI. Build it once, then reuse it.
# Management commands that do not start services can run without the build.
needs_frontend=true
case "${1:-}" in
  --stop|--status|--list) needs_frontend=false ;;
esac
if [[ "$needs_frontend" == true && ! -f "${FRONTEND_DIR}/dist/index.html" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "The Web UI needs a first-time build, but npm is unavailable." >&2
    exit 1
  fi
  echo "Installing Web UI dependencies and building the frontend (first run only)..."
  (
    cd "$FRONTEND_DIR"
    npm ci --no-audit --no-fund
    npm run build
  )
  if [[ ! -f "${FRONTEND_DIR}/dist/index.html" ]]; then
    echo "The Web UI build did not create dist/index.html." >&2
    exit 1
  fi
fi

cd "$ROOT_DIR"
exec "$START_CMD" "$@"
