#!/bin/bash
# Hello-world HTTP throughput bench: carne vs node vs bun via wrk.
# Usage: bench/http-hello/run.sh
# Each server answers 200 text/plain "hello world" on port 3000.
# Measured with wrk -t4 -c100 -d10s after a 2s warmup discard.
set -u
BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
CARNE_BIN="$BENCH_DIR/../../bin/carne"
PORT=3000
URL="http://127.0.0.1:$PORT/"
THREADS=4
CONNS=100
WARMUP=2s
DURATION=10s

command -v wrk >/dev/null 2>&1 || { echo "wrk required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node required"; exit 1; }
command -v bun >/dev/null 2>&1 || { echo "bun required"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl required"; exit 1; }
[ -x "$CARNE_BIN" ] || { echo "build carne first (clue build)"; exit 1; }

if curl -sf "$URL" >/dev/null 2>&1; then
  echo "port $PORT already in use, aborting"; exit 1
fi

bench_one() {
  local name="$1"; shift
  local log out rps lat
  log="$(mktemp /tmp/carne_http_hello_XXXX.log)"
  "$@" >"$log" 2>&1 &
  local pid=$!
  trap "kill $pid 2>/dev/null; wait $pid 2>/dev/null" RETURN
  local i
  for i in $(seq 1 100); do
    if curl -sf "$URL" >/dev/null 2>&1; then break; fi
    if ! kill -0 $pid 2>/dev/null; then
      echo "== $name failed to start =="; cat "$log"; rm -f "$log"; return 1
    fi
    sleep 0.1
  done
  if ! curl -sf "$URL" >/dev/null 2>&1; then
    echo "== $name never became ready =="; cat "$log"; rm -f "$log"; return 1
  fi
  wrk -t$THREADS -c$CONNS -d$WARMUP "$URL" >/dev/null 2>&1
  out="$(wrk -t$THREADS -c$CONNS -d$DURATION "$URL" 2>&1)"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; trap - RETURN
  rm -f "$log"
  sleep 2
  rps="$(echo "$out" | awk '/Requests\/sec:/ {print $2}')"
  lat="$(echo "$out" | awk '$1 == "Latency" {print $2}')"
  [ -z "$rps" ] && rps="FAILED"
  [ -z "$lat" ] && lat="FAILED"
  echo "== $name =="; echo "$out" | tail -n 6; echo ""
  echo "| $name | $rps | $lat |"
}

echo ""
echo "## HTTP hello-world Results (wrk -t$THREADS -c$CONNS -d$DURATION, port $PORT)"
echo ""
echo "| Runtime | Requests/sec | Avg latency |"
echo "|---------|--------------|-------------|"

bench_one "carne" "$CARNE_BIN" run "$BENCH_DIR/server.carne.js"
bench_one "node" node "$BENCH_DIR/server.node.js"
bench_one "bun" bun "$BENCH_DIR/server.bun.js"
