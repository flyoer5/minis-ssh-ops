#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${PATH}:/usr/local/go/bin:${HOME}/go/bin"
export SSH_AI_DATA_DIR="${SSH_AI_DATA_DIR:-$HOME/.ssh-ai-agent}"
export SSH_AI_PORT="${SSH_AI_PORT:-17890}"
mkdir -p "$SSH_AI_DATA_DIR"
cd "$ROOT/backend"
if [[ ! -x "$ROOT/backend/bin/server" ]] || [[ "${REBUILD:-}" == "1" ]]; then
  mkdir -p "$ROOT/backend/bin"
  go build -o "$ROOT/backend/bin/server" ./cmd/server
fi
echo "data: $SSH_AI_DATA_DIR"
echo "listen: 127.0.0.1:$SSH_AI_PORT"
echo "token file: $SSH_AI_DATA_DIR/local.token"
exec "$ROOT/backend/bin/server"
