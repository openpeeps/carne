// bench/stdlib/bench_toml.js — std/toml (Nim/openparser, direct JS
// conversion) vs a pure-JS subset. Run: bin/carne run bench_toml.js
// from bench/stdlib. Equivalence asserted first.
var nim = require("std/toml");
var benchmark = require("std/benchmark");

function eq(a, b, what) {
  var sa = JSON.stringify(a), sb = JSON.stringify(b);
  if (sa !== sb) throw new Error("MISMATCH " + what + ": got=" + sa + " want=" + sb);
}

// Minimal TOML subset in pure JS: top-level key = value, [table],
// strings/ints/floats/bools, arrays of scalars. (std/toml covers the
// full grammar: datetimes, inline tables, [[arrays of tables]].)
function jsParse(text) {
  var root = {}, cur = root;
  var lines = String(text).split("\n");
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (line === "" || line[0] === "#") continue;
    if (line[0] === "[") {
      var name = line.replace(/^\[+|\]+$/g, "").trim();
      cur = root[name] = {};
      continue;
    }
    var ci = line.indexOf("=");
    if (ci < 0) throw new Error("toml: bad line " + line);
    var key = line.slice(0, ci).trim();
    var raw = line.slice(ci + 1).trim();
    cur[key] = jsScalar(raw);
  }
  return root;
}
function jsScalar(raw) {
  if (raw[0] === '"' && raw[raw.length - 1] === '"') return raw.slice(1, -1);
  if (raw[0] === "'") return raw.slice(1, -1);
  if (raw === "true") return true;
  if (raw === "false") return false;
  if (/^[+-]?\d+$/.test(raw)) return parseInt(raw, 10);
  if (/^[+-]?[\d.eE+-]+$/.test(raw)) return parseFloat(raw);
  if (raw[0] === "[") {
    var inner = raw.slice(1, -1).trim();
    if (inner === "") return [];
    return inner.split(",").map(function (p) { return jsScalar(p.trim()); });
  }
  throw new Error("toml: bad scalar " + raw);
}
function jsStringify(obj) {
  var out = [];
  for (var k of Object.keys(obj)) {
    var v = obj[k];
    if (v !== null && typeof v === "object" && !Array.isArray(v)) {
      out.push("[" + k + "]");
      for (var sk of Object.keys(v)) out.push(sk + " = " + jsVal(v[sk]));
    } else {
      out.push(k + " = " + jsVal(v));
    }
  }
  return out.join("\n") + "\n";
}
function jsVal(v) {
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "boolean" || typeof v === "number") return String(v);
  if (Array.isArray(v)) return "[" + v.map(jsVal).join(", ") + "]";
  throw new Error("toml: bad value");
}

var SMALL = 'title = "demo"\nport = 8080\nenabled = true\nratio = 0.5\n[server]\nhost = "localhost"\ntags = ["a", "b"]\n';
var MEDIUM = "";
for (var i = 0; i < 30; i++) {
  MEDIUM += "[svc" + i + "]\nhost = \"node" + i + ".local\"\nport = " +
    (8000 + i) + "\nenabled = true\nweight = 0.5\ntags = [\"web\", \"v" + (i % 3) + "\"]\n";
}
var medObj = nim.parse(MEDIUM);

eq(nim.parse(SMALL), jsParse(SMALL), "parse SMALL agree");
eq(nim.parse(MEDIUM), jsParse(MEDIUM), "parse MEDIUM agree");
eq(nim.parse(nim.stringify(medObj)), medObj, "nim roundtrip");
eq(jsParse(jsStringify(medObj)), medObj, "js roundtrip");
eq(nim.parse(jsStringify(medObj)), medObj, "nim reads js output");
eq(jsParse(nim.stringify(medObj)), medObj, "js reads nim output");

var out = benchmark.compare({
  "nim parse small": function () { nim.parse(SMALL); },
  "js parse small": function () { jsParse(SMALL); },
  "nim parse medium": function () { nim.parse(MEDIUM); },
  "js parse medium": function () { jsParse(MEDIUM); },
  "nim stringify": function () { nim.stringify(medObj); },
  "js stringify": function () { jsStringify(medObj); }
}, {iterations: 500, warmup: 50});

var names = ["nim parse small", "js parse small", "nim parse medium",
  "js parse medium", "nim stringify", "js stringify"];
console.log("op | nim us | js us | winner");
for (var i = 0; i < names.length; i += 2) {
  var n = out.results[names[i]], j = out.results[names[i + 1]];
  var w = n.meanMs < j.meanMs ? "nim" : "js";
  console.log(names[i].slice(4) + " | " + (n.meanMs * 1000).toFixed(2) + " | " +
    (j.meanMs * 1000).toFixed(2) + " | " + w + " x" +
    (Math.max(n.meanMs, j.meanMs) / Math.min(n.meanMs, j.meanMs)).toFixed(2));
}
