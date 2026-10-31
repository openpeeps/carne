// bench/stdlib/bench_xml.js — std/xml (Nim/openparser, direct JS
// conversion) vs a pure-JS subset. Run: bin/carne run bench_xml.js
// from bench/stdlib. Equivalence asserted first.
var nim = require("std/xml");
var benchmark = require("std/benchmark");

function eq(a, b, what) {
  var sa = JSON.stringify(a), sb = JSON.stringify(b);
  if (sa !== sb) throw new Error("MISMATCH " + what + ": got=" + sa + " want=" + sb);
}

// Minimal XML subset: elements with attrs, text children, nesting.
// (std/xml handles entities, cdata, and drops comments/prologs.)
function jsParse(text) {
  var pos = 0;
  function ws() { while (pos < text.length && /\s/.test(text[pos])) pos++; }
  function parseNode() {
    ws();
    if (text[pos] !== "<") return jsText();
    if (text[pos + 1] === "/") return null;
    pos++;
    var tag = "";
    while (pos < text.length && /[A-Za-z0-9_:-]/.test(text[pos])) tag += text[pos++];
    var attrs = {};
    while (true) {
      ws();
      if (text[pos] === "/" && text[pos + 1] === ">") { pos += 2; return {tag: tag, attrs: attrs, children: []}; }
      if (text[pos] === ">") { pos++; break; }
      var k = "";
      while (pos < text.length && /[A-Za-z0-9_:-]/.test(text[pos])) k += text[pos++];
      ws(); pos++; ws();
      var q = text[pos++];
      var v = "";
      while (text[pos] !== q) v += text[pos++];
      pos++;
      attrs[k] = v;
    }
    var children = [];
    while (true) {
      ws();
      if (text[pos] === "<" && text[pos + 1] === "/") {
        pos += 2;
        while (text[pos] !== ">") pos++;
        pos++;
        return {tag: tag, attrs: attrs, children: children};
      }
      var c = parseNode();
      if (c !== null) children.push(c);
    }
  }
  function jsText() {
    var s = "";
    while (pos < text.length && text[pos] !== "<") s += text[pos++];
    return s.trim();
  }
  ws();
  return parseNode();
}
function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
function jsStringify(n) {
  if (typeof n === "string") return esc(n);
  var a = "";
  for (var k of Object.keys(n.attrs)) a += " " + k + '="' + esc(n.attrs[k]) + '"';
  if (n.children.length === 0) return "<" + n.tag + a + "/>";
  return "<" + n.tag + a + ">" + n.children.map(jsStringify).join("") + "</" + n.tag + ">";
}

var SMALL = '<user id="7" admin="false"><name>ada</name><tags><t>fast</t><t>typed</t></tags></user>';
var MEDIUM = "<feed>";
for (var i = 0; i < 30; i++) {
  MEDIUM += '<item id="' + i + '" kind="post"><title>hello ' + i +
    '</title><author ref="u' + (i % 5) + '">name ' + i + "</author></item>";
}
MEDIUM += "</feed>";
var medObj = nim.parse(MEDIUM);

eq(nim.parse(SMALL), jsParse(SMALL), "parse SMALL agree");
eq(nim.parse(MEDIUM), jsParse(MEDIUM), "parse MEDIUM agree");
eq(nim.parse(nim.stringify(medObj)), medObj, "nim roundtrip");
eq(jsParse(jsStringify(medObj)), medObj, "js roundtrip");

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
