#!/usr/bin/env bash
set -euo pipefail
PORT="${SSH_AI_PORT:-17890}"
DATA="${SSH_AI_DATA_DIR:-$HOME/.ssh-ai-agent}"
BASE="http://127.0.0.1:${PORT}"
TOKEN="$(tr -d '\n' < "${DATA}/local.token")"
echo "== health =="
curl -sS "$BASE/v1/health" | head -c 400; echo
echo "== hosts (auth) =="
curl -sS -H "X-Local-Token: $TOKEN" "$BASE/v1/hosts"; echo
echo "== unauth expect 401 =="
code=$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/v1/hosts")
echo "status=$code"
