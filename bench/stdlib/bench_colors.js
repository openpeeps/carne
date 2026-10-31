// bench/stdlib/bench_colors.js — std/colors (JS) vs colors_js.js subset.
// Run: bin/carne run bench/stdlib/bench_colors.js
// Equivalence is asserted first; any mismatch throws before timing.
var nim = require("std/colors");
var js = require("./colors_js.js");
var benchmark = require("std/benchmark");

function eq(a, b, what) {
  var sa = JSON.stringify(a), sb = JSON.stringify(b);
  if (sa !== sb) throw new Error("MISMATCH " + what + ": nim=" + sa + " js=" + sb);
}

eq(nim.parse("#c0392b"), js.parse("#c0392b"), "parse hex");
eq(nim.parse("red"), js.parse("red"), "parse named");
eq(nim.parse("rgba(0, 255, 0, 0.5)"), js.parse("rgba(0, 255, 0, 0.5)"), "parse rgba");
eq(nim.toHex(nim.parse("red")), js.toHex(js.parse("red")), "toHex");
eq(nim.toHex(nim.lighten(nim.parse("#333333"), 20)),
   js.toHex(js.lighten(js.parse("#333333"), 20)), "lighten pipeline");
eq(nim.toHex(nim.mix(nim.parse("red"), nim.parse("blue"))),
   js.toHex(js.mix(js.parse("red"), js.parse("blue"))), "mix");
eq(nim.contrastRatio(nim.parse("black"), nim.parse("white")),
   js.contrastRatio(js.parse("black"), js.parse("white")), "contrast");

var redN = nim.parse("red"), blueN = nim.parse("blue");
var darkN = nim.parse("#333333"), blackN = nim.parse("black"), whiteN = nim.parse("white");
var redJ = js.parse("red"), blueJ = js.parse("blue");
var darkJ = js.parse("#333333"), blackJ = js.parse("black"), whiteJ = js.parse("white");

var out = benchmark.compare({
  "nim parse hex": function () { nim.parse("#c0392b"); },
  "js parse hex": function () { js.parse("#c0392b"); },
  "nim parse named": function () { nim.parse("red"); },
  "js parse named": function () { js.parse("red"); },
  "nim lighten+toHex": function () { nim.toHex(nim.lighten(darkN, 20)); },
  "js lighten+toHex": function () { js.toHex(js.lighten(darkJ, 20)); },
  "nim mix+toHex": function () { nim.toHex(nim.mix(redN, blueN)); },
  "js mix+toHex": function () { js.toHex(js.mix(redJ, blueJ)); },
  "nim contrast": function () { nim.contrastRatio(blackN, whiteN); },
  "js contrast": function () { js.contrastRatio(blackJ, whiteJ); }
}, {iterations: 3000, warmup: 200});

var names = ["nim parse hex", "js parse hex", "nim parse named", "js parse named",
  "nim lighten+toHex", "js lighten+toHex", "nim mix+toHex", "js mix+toHex",
  "nim contrast", "js contrast"];
console.log("op | nim us | js us | winner");
for (var i = 0; i < names.length; i += 2) {
  var n = out.results[names[i]], j = out.results[names[i + 1]];
  var w = n.meanMs < j.meanMs ? "nim" : "js";
  console.log(names[i].slice(4) + " | " + (n.meanMs * 1000).toFixed(2) + " | " +
    (j.meanMs * 1000).toFixed(2) + " | " + w + " x" +
    (Math.max(n.meanMs, j.meanMs) / Math.min(n.meanMs, j.meanMs)).toFixed(2));
}
