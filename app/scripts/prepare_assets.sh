#!/bin/sh
# Prepare Flutter assets + jniLibs from built opsd + web/static
set -e
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/app"
BIN="$ROOT/bin/opsd"
WEB="$ROOT/web/static"

echo "project: $ROOT"

if [ ! -x "$BIN" ]; then
  echo "building opsd (static arm64)..."
  (cd "$ROOT" && CGO_ENABLED=0 go build -ldflags='-s -w' -o bin/opsd ./cmd/opsd/)
fi

mkdir -p "$APP/assets/opsd" "$APP/assets/web" \
  "$APP/android/app/src/main/jniLibs/arm64-v8a"

cp -f "$BIN" "$APP/assets/opsd/opsd_arm64"
chmod 755 "$APP/assets/opsd/opsd_arm64"
# Android extracts jniLibs/*.so as executable
cp -f "$BIN" "$APP/android/app/src/main/jniLibs/arm64-v8a/libopsd.so"
chmod 755 "$APP/android/app/src/main/jniLibs/arm64-v8a/libopsd.so"

# web UI
mkdir -p "$APP/assets/web"
if [ -d "$WEB" ] && [ -f "$WEB/index.html" ]; then
  # keep README if any, overwrite UI files from source of truth
  cp -a "$WEB/." "$APP/assets/web/"
else
  echo "warn: $WEB missing, keeping existing app/assets/web" >&2
fi
# drop docs-only files from asset bundle if present
rm -f "$APP/assets/web/README.md" 2>/dev/null || true

# placeholder if someone builds without binary (keep flutter asset graph valid)
if [ ! -s "$APP/assets/opsd/opsd_arm64" ]; then
  echo "opsd binary missing" >&2
  exit 1
fi

echo "OK assets:"
ls -la "$APP/assets/opsd/opsd_arm64"
ls -la "$APP/android/app/src/main/jniLibs/arm64-v8a/libopsd.so"
ls -la "$APP/assets/web" | head
echo "size $(du -h "$APP/assets/opsd/opsd_arm64" | awk '{print $1}')"
