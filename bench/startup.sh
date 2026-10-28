#!/bin/bash
set -e
BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
CARNE_BIN="$BENCH_DIR/../bin/carne"

command -v hyperfine >/dev/null 2>&1 || { echo "hyperfine required"; exit 1; }

bench_one() {
  local file="$1"
  local raw t
  RAW=$(hyperfine --warmup 2 --min-runs 5 --ignore-failure "$CARNE_BIN run $file" 2>&1) || true
  if echo "$RAW" | grep -q "Ignoring non-zero exit code"; then
    echo "CRASHED"
  else
    T=$(echo "$RAW" | grep "Time.*mean" | head -1 | sed 's/.*mean.*): *//;s/ *\[User.*//')
    if [ -z "$T" ]; then
      echo "FAILED"
    else
      echo "$T"
    fi
  fi
}

echo ""
echo "## carne Startup Results"
echo ""
echo "| Case | carne |"
echo "|------|-------|"
echo "| empty | $(bench_one "$BENCH_DIR/startup/empty.js") |"
echo "| hello | $(bench_one "$BENCH_DIR/startup/hello.js") |"
echo "| require-all-22 | $(bench_one "$BENCH_DIR/startup/require_all.js") |"
echo "| http-roundtrip | $(bench_one "$BENCH_DIR/startup/http_roundtrip.js") |"
