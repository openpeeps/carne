// Pure-JS subset of std/colors, for bench/stdlib only (not for shipping).
// Covers the benchmarked surface: hex + rgb() + 16 named colors parse,
// {r,g,b,a} shape, toHex/toRgb, lighten, mix, complement, contrastRatio,
// isReadable. std/colors (openparser) covers far more: hsl()/hsv()/
// cmyk()/lab()/lch()/oklab()/oklch() strings, 148 named colors,
// saturate/spin/triad/greyscale/toHsl/toName. Perf comparison is fair
// only on the shared subset (hex-heavy inputs below).
"use strict";

var NAMED = {
  black: [0, 0, 0], white: [255, 255, 255], red: [255, 0, 0],
  green: [0, 128, 0], blue: [0, 0, 255], yellow: [255, 255, 0],
  cyan: [0, 255, 255], magenta: [255, 0, 255], gray: [128, 128, 128],
  grey: [128, 128, 128], orange: [255, 165, 0], purple: [128, 0, 128],
  pink: [255, 192, 203], brown: [165, 42, 42], lime: [0, 255, 0],
  navy: [0, 0, 128], teal: [0, 128, 128]
};

function hexByte(s) { return parseInt(s, 16); }

function parse(text) {
  if (typeof text !== "string") throw new Error("parse: text must be a string");
  var s = text.trim().toLowerCase();
  if (s === "transparent") return {r: 0, g: 0, b: 0, a: 0};
  if (Object.prototype.hasOwnProperty.call(NAMED, s)) {
    var n = NAMED[s];
    return {r: n[0], g: n[1], b: n[2], a: 1};
  }
  if (s[0] === "#") {
    var h = s.slice(1);
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    if (h.length === 6 || h.length === 8) {
      if (!/^[0-9a-f]+$/.test(h)) throw new Error("parse: bad hex " + text);
      var a = h.length === 8 ? hexByte(h.slice(6, 8)) / 255 : 1;
      return {r: hexByte(h.slice(0, 2)), g: hexByte(h.slice(2, 4)), b: hexByte(h.slice(4, 6)), a: a};
    }
    throw new Error("parse: bad hex " + text);
  }
  var m = s.match(/^rgba?\((.*)\)$/);
  if (m) {
    var parts = m[1].split(",").map(function (p) { return p.trim(); });
    if (parts.length < 3 || parts.length > 4) throw new Error("parse: bad rgb " + text);
    var ch = parts.slice(0, 3).map(function (p) {
      if (p[p.length - 1] === "%") return Math.round(parseFloat(p) * 2.55);
      return parseInt(p, 10);
    });
    var al = parts.length === 4 ? parseFloat(parts[3]) : 1;
    if (ch.some(function (c) { return isNaN(c) || c < 0 || c > 255; }) || isNaN(al)) {
      throw new Error("parse: bad rgb " + text);
    }
    return {r: ch[0], g: ch[1], b: ch[2], a: al};
  }
  throw new Error("parse: unknown color " + text);
}

function clamp255(x) { return Math.max(0, Math.min(255, Math.round(x))); }

function toHex(c) {
  function h(x) { var s = clamp255(x).toString(16); return s.length === 1 ? "0" + s : s; }
  return "#" + h(c.r) + h(c.g) + h(c.b);
}

function toRgb(c) {
  return "rgb(" + clamp255(c.r) + ", " + clamp255(c.g) + ", " + clamp255(c.b) + ")";
}

function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  var mx = Math.max(r, g, b), mn = Math.min(r, g, b), h = 0, s = 0;
  var l = (mx + mn) / 2;
  if (mx !== mn) {
    var d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (mx === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
  }
  return [h, s * 100, l * 100];
}

function hslToRgb(h, s, l) {
  h = ((h % 360) + 360) % 360; s /= 100; l /= 100;
  function f(n) {
    var k = (n + h / 30) % 12;
    var v = l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, Math.min(9 - k, 1)));
    return Math.round(v * 255);
  }
  return [f(0), f(8), f(4)];
}

function lighten(c, amount) {
  var hsl = rgbToHsl(c.r, c.g, c.b);
  var rgb = hslToRgb(hsl[0], hsl[1], Math.max(0, Math.min(100, hsl[2] + amount)));
  return {r: rgb[0], g: rgb[1], b: rgb[2], a: c.a};
}

function mix(a, b, weight) {
  if (weight === undefined) weight = 50;
  var w = weight / 100, iw = 1 - w;
  return {
    r: clamp255(a.r * w + b.r * iw),
    g: clamp255(a.g * w + b.g * iw),
    b: clamp255(a.b * w + b.b * iw),
    a: a.a * w + b.a * iw
  };
}

function complement(c) {
  var hsl = rgbToHsl(c.r, c.g, c.b);
  var rgb = hslToRgb(hsl[0] + 180, hsl[1], hsl[2]);
  return {r: rgb[0], g: rgb[1], b: rgb[2], a: c.a};
}

function luminance(c) {
  function lin(x) {
    x /= 255;
    return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
  }
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

function contrastRatio(a, b) {
  var l1 = luminance(a), l2 = luminance(b);
  if (l1 < l2) { var t = l1; l1 = l2; l2 = t; }
  return (l1 + 0.05) / (l2 + 0.05);
}

function isReadable(a, b) { return contrastRatio(a, b) >= 4.5; }

module.exports = {
  parse: parse, toHex: toHex, toRgb: toRgb, lighten: lighten,
  mix: mix, complement: complement, contrastRatio: contrastRatio,
  isReadable: isReadable
};
