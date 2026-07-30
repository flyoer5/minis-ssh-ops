#!/bin/sh
set -eu

APK=${1:?usage: verify-apk-packaging.sh APK [REPORT] [MAX_BYTES]}
REPORT=${2:-}
MAX_BYTES=${3:-}
test -s "$APK"

ENTRIES=$(mktemp)
SIZES=$(mktemp)
trap 'rm -f "$ENTRIES" "$SIZES"' EXIT
unzip -Z1 "$APK" > "$ENTRIES"
unzip -l "$APK" | awk 'NF >= 4 && $1 ~ /^[0-9]+$/ { print $1 "\t" $4 }' > "$SIZES"

BACKEND_PATH='lib/arm64-v8a/libssh_ai_agent.so'
BACKEND_COUNT=$(awk -v path="$BACKEND_PATH" '$0 == path { count++ } END { print count + 0 }' "$ENTRIES")
if [ "$BACKEND_COUNT" -ne 1 ]; then
  echo "Expected exactly one packaged Go backend, found $BACKEND_COUNT: $APK" >&2
  exit 1
fi

if grep -Eq '^assets/(go/)?(ssh-ai-agent|libssh_ai_agent\.so)$' "$ENTRIES"; then
  echo "Go backend is duplicated in APK assets: $APK" >&2
  grep -E '^assets/(go/)?(ssh-ai-agent|libssh_ai_agent\.so)$' "$ENTRIES" >&2
  exit 1
fi

UNEXPECTED_ABIS=$(awk -F/ '/^lib\/[^/]+\// && $2 != "arm64-v8a" { print $2 }' "$ENTRIES" | sort -u)
if [ -n "$UNEXPECTED_ABIS" ]; then
  echo "APK contains unexpected native ABIs; arm64-v8a is required: $APK" >&2
  echo "$UNEXPECTED_ABIS" >&2
  exit 1
fi

APK_BYTES=$(wc -c < "$APK" | tr -d ' ')
if [ -n "$MAX_BYTES" ] && [ "$APK_BYTES" -gt "$MAX_BYTES" ]; then
  echo "APK exceeds size limit: $APK_BYTES > $MAX_BYTES bytes ($APK)" >&2
  exit 1
fi

echo "APK backend packaging verified: $APK"

if [ -n "$REPORT" ]; then
  TOTAL_BYTES=$(awk '{ total += $1 } END { print total + 0 }' "$SIZES")
  BACKEND_BYTES=$(awk -F '\t' -v path="$BACKEND_PATH" '$2 == path { print $1; exit }' "$SIZES")
  BACKEND_BYTES=${BACKEND_BYTES:-0}
  APK_MIB=$(awk -v bytes="$APK_BYTES" 'BEGIN { printf "%.2f", bytes / 1048576 }')
  TOTAL_MIB=$(awk -v bytes="$TOTAL_BYTES" 'BEGIN { printf "%.2f", bytes / 1048576 }')
  BACKEND_MIB=$(awk -v bytes="$BACKEND_BYTES" 'BEGIN { printf "%.2f", bytes / 1048576 }')
  BACKEND_PERCENT=$(awk -v part="$BACKEND_BYTES" -v total="$TOTAL_BYTES" 'BEGIN { if (total == 0) print "0.0"; else printf "%.1f", part * 100 / total }')

  {
    echo "### $(basename "$APK") contents"
    echo
    echo "- APK size: $APK_BYTES bytes ($APK_MIB MiB)"
    if [ -n "$MAX_BYTES" ]; then
      MAX_MIB=$(awk -v bytes="$MAX_BYTES" 'BEGIN { printf "%.2f", bytes / 1048576 }')
      echo "- Size limit: $MAX_BYTES bytes ($MAX_MIB MiB)"
    fi
    echo "- Native ABI: arm64-v8a only"
    echo "- Uncompressed entries: $TOTAL_BYTES bytes ($TOTAL_MIB MiB)"
    echo "- Go backend: $BACKEND_BYTES bytes ($BACKEND_MIB MiB, $BACKEND_PERCENT% of uncompressed entries)"
    echo
    echo "| Largest entries | Bytes | MiB |"
    echo "| --- | ---: | ---: |"
    sort -nr "$SIZES" | head -20 | while IFS="$(printf '\t')" read -r bytes name; do
      mib=$(awk -v bytes="$bytes" 'BEGIN { printf "%.2f", bytes / 1048576 }')
      echo "| \`$name\` | $bytes | $mib |"
    done
  } > "$REPORT"
fi