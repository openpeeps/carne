#!/bin/bash
# bench/stdlib: std (Nim) vs pure-JS head-to-heads. Work in progress,
# do not commit yet. Usage: ./run.sh (from this dir).
set -e
CARNE_BIN="$(cd ../.. && pwd)/bin/carne"
echo "## colors: std/colors vs colors_js.js"
timeout 120 "$CARNE_BIN" run bench_colors.js
echo ""
echo "## yaml: std/yaml vs yaml_js.js"
timeout 180 "$CARNE_BIN" run bench_yaml.js
echo ""
echo "## toml: std/toml vs inline JS subset"
timeout 180 "$CARNE_BIN" run bench_toml.js
echo ""
echo "## xml: std/xml vs inline JS subset"
timeout 180 "$CARNE_BIN" run bench_xml.js
