#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_USER="Alireza-Ghadimi"
MEMT_REMOTE="https://github.com/${GITHUB_USER}/MemT-1.0"
JIUWEN_REMOTE="https://github.com/${GITHUB_USER}/jiuwenswarm"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  echo "Usage: $0"
  echo "Save a GitHub token in macOS Keychain and push the prepared MemT and JiuwenSwarm commits."
  exit 0
fi
if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 2
fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script requires macOS Keychain." >&2
  exit 1
fi
if [[ ! -r /dev/tty ]]; then
  echo "Run this script in an interactive Terminal." >&2
  exit 1
fi

check_remote() {
  local repository="$1" expected="$2" actual
  actual="$(git -C "$repository" remote get-url forked)"
  if [[ "$actual" != "$expected" && "$actual" != "${expected}.git" ]]; then
    echo "Unexpected forked remote in $repository: $actual" >&2
    exit 1
  fi
}

check_remote "${ROOT_DIR}/memt-1.0" "$MEMT_REMOTE"
check_remote "$ROOT_DIR" "$JIUWEN_REMOTE"
git -C "$ROOT_DIR" rev-parse --verify codex/local-memt-launchers >/dev/null
git -C "${ROOT_DIR}/memt-1.0" rev-parse --verify main >/dev/null

git config --global credential.helper osxkeychain

echo "Paste your GitHub fine-grained token. It will not appear on screen."
IFS= read -r -s -p "Token: " github_token < /dev/tty
echo >&2
if [[ -z "$github_token" ]]; then
  echo "No token entered." >&2
  exit 1
fi

printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' \
  "$GITHUB_USER" "$github_token" | git credential approve
unset github_token

echo "Pushing MemT main..."
GIT_TERMINAL_PROMPT=0 git -C "${ROOT_DIR}/memt-1.0" push -u forked main
echo "Pushing JiuwenSwarm to forked develop..."
GIT_TERMINAL_PROMPT=0 git -C "$ROOT_DIR" push forked codex/local-memt-launchers:develop
echo "Both pushes completed. The token remains in macOS Keychain until it expires or is revoked."
