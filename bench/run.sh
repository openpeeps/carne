#!/bin/bash
set -e
BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"

command -v hyperfine >/dev/null 2>&1 || { echo "hyperfine required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node required"; exit 1; }
command -v bun >/dev/null 2>&1 || { echo "bun required"; exit 1; }

BENCHMARKS="fib_recursive nested_loops prime_sieve string_concat tail_recursive range_sum collatz array_sum bubble_sort object_access float_math call_overhead fizzbuzz_count"

bench_one() {
  local cmd="$1" file="$2"
  local raw t
  RAW=$(hyperfine --warmup 2 --min-runs 3 --ignore-failure "$cmd $file" 2>&1) || true
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
echo "## Benchmark Results"
echo ""
echo "| Benchmark | carne | node | bun |"
echo "|-----------|-------|------|-----|"

for B in $BENCHMARKS; do
  FILE="$BENCH_DIR/js/$B.js"
  echo "  $B..." >&2
  C=$(bench_one "$BENCH_DIR/../bin/carne run" "$FILE")
  N=$(bench_one "node" "$FILE")
  U=$(bench_one "bun" "$FILE")
  echo "| $B | $C | $N | $U |"
done
