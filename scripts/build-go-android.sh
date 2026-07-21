#!/usr/bin/env bash
# Cross-compile Go backend for Android arm64 into the Flutter Android assets.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${PATH}:/usr/local/go/bin:${HOME}/go/bin"
OUT_DIR="$ROOT/app/android/app/src/main/assets/go"
mkdir -p "$OUT_DIR" "$ROOT/app/assets/go"
echo "Building GOOS=android GOARCH=arm64 ..."
cd "$ROOT/backend"
CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build -ldflags='-s -w' \
  -o "$OUT_DIR/ssh-ai-agent" ./cmd/server
cp -f "$OUT_DIR/ssh-ai-agent" "$ROOT/app/assets/go/ssh-ai-agent-arm64"
ls -la "$OUT_DIR/ssh-ai-agent"
echo "OK -> $OUT_DIR/ssh-ai-agent"
