#!/bin/sh
# Cross-compile Go backend for Android arm64 into jniLibs.
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export PATH="${PATH}:/usr/local/go/bin:${HOME}/go/bin"

JNI_DIR="$ROOT/app/android/app/src/main/jniLibs/arm64-v8a"
LEGACY_ASSET="$ROOT/app/android/app/src/main/assets/go/ssh-ai-agent"
LEGACY_TOOLING_BINARY="$ROOT/app/assets/go/ssh-ai-agent-arm64"

mkdir -p "$JNI_DIR"
rm -f "$LEGACY_ASSET" "$LEGACY_TOOLING_BINARY"

# Single source of truth for version: app/pubspec.yaml → inject into Go binary.
VER=$(grep '^version:' "$ROOT/app/pubspec.yaml" | head -1 | awk '{print $2}' | cut -d+ -f1)
echo "Building GOOS=android GOARCH=arm64 (version=$VER) ..."
cd "$ROOT/backend"
CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build -trimpath -buildvcs=false \
  -ldflags="-s -w -buildid= -X github.com/flyoer5/ssh-ai-agent/backend/internal/api.Version=$VER" \
  -o "$JNI_DIR/libssh_ai_agent.so" ./cmd/server

chmod 755 "$JNI_DIR/libssh_ai_agent.so"

ls -la "$JNI_DIR/libssh_ai_agent.so"
file "$JNI_DIR/libssh_ai_agent.so" || true
echo "OK"
