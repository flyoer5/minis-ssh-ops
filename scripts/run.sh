#!/bin/sh
set -e
cd "$(dirname "$0")/.."
mkdir -p data bin
if [ ! -x bin/opsd ]; then
  export CGO_ENABLED=0
  go build -ldflags='-s -w' -o bin/opsd ./cmd/opsd/
fi
export OPSD_TOKEN="${OPSD_TOKEN:-devtoken123}"
exec ./bin/opsd -addr "${OPSD_ADDR:-127.0.0.1:18765}" -data ./data -web ./web/static
