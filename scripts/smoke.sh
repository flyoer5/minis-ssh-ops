#!/bin/sh
set -e
BASE="${1:-http://127.0.0.1:18765}"
TOKEN="${OPSD_TOKEN:-devtoken123}"
H="X-Ops-Token: $TOKEN"

echo "== health =="
curl -sf -H "$H" "$BASE/api/health" | head -c 200
echo

echo "== llm mask =="
curl -sf -H "$H" "$BASE/api/llm"
echo

echo "== hosts =="
curl -sf -H "$H" "$BASE/api/hosts"
echo

echo "OK"
