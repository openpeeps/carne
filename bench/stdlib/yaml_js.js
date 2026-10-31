// Pure-JS subset of std/yaml, for bench/stdlib only (not for shipping).
// Parses the benchmarked subset: indentation-nested maps, sequences,
// scalars (null/~, bools, ints, floats, single/double-quoted and plain
// strings), comments, --- / ... markers. std/yaml (openparser) is a
// fuller YAML front end (anchors, tags, multi-doc, escapes); the bench
// sticks to plain config-shaped docs both sides agree on.
"use strict";

function scalar(s) {
  if (s === "" || s === "~" || s === "null" || s === "Null" || s === "NULL") return null;
  if (s === "true" || s === "True" || s === "TRUE") return true;
  if (s === "false" || s === "False" || s === "FALSE") return false;
  var q = s[0];
  if ((q === '"' || q === "'") && s.length >= 2 && s[s.length - 1] === q) {
    var inner = s.slice(1, -1);
    return q === '"' ? inner.replace(/\\"/g, '"').replace(/\\\\/g, "\\").replace(/\\n/g, "\n") : inner;
  }
  if (/^[+-]?\d+$/.test(s)) return parseInt(s, 10);
  if (/^[+-]?(\d+\.\d*|\.\d+|\d+)([eE][+-]?\d+)?$/.test(s)) return parseFloat(s);
  return s;
}

function indentOf(line) {
  var i = 0;
  while (i < line.length && line[i] === " ") i++;
  return i;
}

function stripComment(line) {
  // Cut " #..." outside quotes (good enough for the bench docs).
  var inS = false, inD = false;
  for (var i = 0; i < line.length; i++) {
    var c = line[i];
    if (c === "'" && !inD) inS = !inS;
    else if (c === '"' && !inS) inD = !inD;
    else if (c === "#" && !inS && !inD && (i === 0 || line[i - 1] === " ")) {
      return line.slice(0, i).replace(/\s+$/, "");
    }
  }
  return line;
}

function parse(text) {
  var raws = String(text).split("\n");
  var lines = [];
  for (var i = 0; i < raws.length; i++) {
    var noComment = stripComment(raws[i]);
    if (noComment.trim() === "" || noComment.trim() === "---" || noComment.trim() === "...") continue;
    lines.push({indent: indentOf(noComment), text: noComment.trim()});
  }
  var pos = 0;
  function peek() { return pos < lines.length ? lines[pos] : null; }
  function isSeqItem(t) { return t === "-" || t.slice(0, 2) === "- "; }
  function block(minIndent) {
    var l = peek();
    if (!l || l.indent < minIndent) return undefined;
    if (isSeqItem(l.text)) return seq(Math.max(minIndent, l.indent));
    return map(Math.max(minIndent, l.indent));
  }
  function map(ind) {
    var obj = {};
    while (true) {
      var l = peek();
      if (!l || l.indent !== ind || l.text[0] === "-") break;
      if (l.text === "-") break;
      var ci = l.text.indexOf(":");
      if (ci < 0) throw new Error("yaml: bad mapping line: " + l.text);
      var key = l.text.slice(0, ci).trim();
      var rest = l.text.slice(ci + 1).trim();
      pos++;
      if (rest !== "") {
        obj[key] = scalar(rest);
      } else {
        var child = block(ind + 1);
        obj[key] = child === undefined ? null : child;
      }
    }
    return obj;
  }
  function seq(ind) {
    var arr = [];
    while (true) {
      var l = peek();
      if (!l || l.indent !== ind || !isSeqItem(l.text)) break;
      var rest = l.text.slice(1).trim();
      pos++;
      if (rest !== "") {
        arr.push(scalar(rest));
      } else {
        var child = block(ind + 1);
        arr.push(child === undefined ? null : child);
      }
    }
    return arr;
  }
  if (lines.length === 0) return null;
  var top = block(0);
  return top === undefined ? null : top;
}

function strScalar(v) {
  if (v === null || v === undefined) return "null";
  if (v === true) return "true";
  if (v === false) return "false";
  if (typeof v === "number") return String(v);
  if (/^[A-Za-z0-9_\/\.\-]+$/.test(v)) return v;
  return JSON.stringify(v);
}

function stringify(value) {
  var out = [];
  function emit(v, ind) {
    var pad = "";
    for (var i = 0; i < ind; i++) pad += "  ";
    if (Array.isArray(v)) {
      if (v.length === 0) { out.push(pad + "[]"); return; }
      for (var k = 0; k < v.length; k++) {
        var item = v[k];
        if (item !== null && typeof item === "object") {
          out.push(pad + "-");
          emit(item, ind + 1);
        } else {
          out.push(pad + "- " + strScalar(item));
        }
      }
    } else if (v !== null && typeof v === "object") {
      var keys = Object.keys(v);
      if (keys.length === 0) { out.push(pad + "{}"); return; }
      for (var j = 0; j < keys.length; j++) {
        var val = v[keys[j]];
        if (val !== null && typeof val === "object") {
          out.push(pad + keys[j] + ":");
          emit(val, ind + 1);
        } else {
          out.push(pad + keys[j] + ": " + strScalar(val));
        }
      }
    } else {
      out.push(pad + strScalar(v));
    }
  }
  emit(value, 0);
  return out.join("\n") + "\n";
}

module.exports = {parse: parse, stringify: stringify};
