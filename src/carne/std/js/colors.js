// Carne std/colors: color parsing, formatting and math (pure JS).
//
// Colors cross the boundary as {r, g, b, a} objects (r/g/b 0..255
// integers, a 0..1):
//
//   const colors = require("std/colors");
//   colors.parse("red")             -> {r: 255, g: 0, b: 0, a: 1}
//   colors.toHex(colors.parse("red")) -> "#ff0000"
//   colors.lighten(colors.parse("#333"), 20) -> {r, g, b, a}
//   colors.contrastRatio(a, b)      -> 1..21
//
// Accepts hex, rgb()/hsl()/hsv()/cmyk()/lab()/lch()/oklab()/oklch()
// strings and named colors. Internally colors are sRGB 0..1 floats;
// the boundary converts to/from {r, g, b, a}.
"use strict";
/*
 * @typedef {object} Rgb01 - Internal color with r/g/b/a as 0..1 floats.
 * @typedef {object} Rgba255 - Boundary color: r/g/b are 0..255 integers, a is 0..1.
 */

/*
 * Clamps v into [lo, hi].
 * @param {number} v - Value.
 * @param {number} lo - Lower bound.
 * @param {number} hi - Upper bound.
 * @returns {number} Clamped value.
 */
function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }
/*
 * Clamps v into [0, 1].
 * @param {number} v - Value.
 * @returns {number} Clamped value.
 */
function clamp01(v) { return clamp(v, 0, 1); }
/*
 * Wraps degrees into [0, 360).
 * @param {number} h - Hue in degrees.
 * @returns {number} Wrapped hue.
 */
function hueMod(h) { return ((h % 360) + 360) % 360; }
/*
 * Degrees to radians.
 * @param {number} d - Degrees.
 * @returns {number} Radians.
 */
function degToRad(d) { return d * Math.PI / 180; }
/*
 * Radians to degrees.
 * @param {number} r - Radians.
 * @returns {number} Degrees.
 */
function radToDeg(r) { return r * 180 / Math.PI; }

// D65 reference white + conversion matrices (same constants as before).
var Xn = 95.047, Yn = 100.0, Zn = 108.883;
var OklabM1 = [
  [0.4122214708, 0.5363325363, 0.0514459929],
  [0.2119034982, 0.6806995451, 0.1073969566],
  [0.0883024619, 0.2817188376, 0.6299787005]
];
var OklabM2 = [
  [0.2104542553, 0.7936177850, -0.0040720468],
  [1.9779984951, -2.4285922050, 0.4505937099],
  [0.0259040371, 0.7827717662, -0.8086757660]
];
var OklabM1Inv = [
  [4.0767416621, -3.3077115913, 0.2309699292],
  [-1.2684380046, 2.6097574011, -0.3413193965],
  [-0.0041960863, -0.7034186147, 1.7076147010]
];

// -- argument validation (same throw shapes as the typed surface) -------

/*
 * JS typeof name for type-mismatch errors (null/array distinguished).
 * @param {any} v - Value to classify.
 * @returns {string} The JS type name.
 */
function jsKind(v) {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  var t = typeof v;
  if (t === "number" || t === "string" || t === "boolean" ||
      t === "undefined" || t === "function" || t === "symbol" ||
      t === "bigint") return t;
  return "object";
}

/*
 * Strict string check; throws a type-mismatch Error otherwise.
 * @param {any} v - Candidate value.
 * @param {string} fname - Calling function name for the error.
 * @param {string} pname - Parameter name for the error.
 * @returns {string} v unchanged.
 */
function needString(v, fname, pname) {
  if (typeof v !== "string") {
    throw new Error(fname + ": type mismatch parameter: `" + pname +
      "`. Got `" + jsKind(v) + "`, expected `string`");
  }
  return v;
}

/*
 * Strict number check; throws a type-mismatch Error otherwise.
 * @param {any} v - Candidate value.
 * @param {string} fname - Calling function name for the error.
 * @param {string} pname - Parameter name for the error.
 * @returns {number} v unchanged.
 */
function needNumber(v, fname, pname) {
  if (typeof v !== "number") {
    throw new Error(fname + ": type mismatch parameter: `" + pname +
      "`. Got `" + jsKind(v) + "`, expected `number`");
  }
  return v;
}

/*
 * Reads a {r, g, b, a?} boundary object into 0..1 floats (a defaults to 1). Throws on missing, non-numeric, or out-of-range fields.
 * @param {object} v - Boundary color object.
 * @param {string} fname - Calling function name for the error.
 * @returns {Rgb01} Internal color.
 */
function needColor(v, fname) {
  if (typeof v !== "object" || v === null || Array.isArray(v)) {
    throw new Error(fname + ": color must be an {r, g, b, a?} object");
  }
  for (var i = 0; i < 3; i++) {
    var k = ["r", "g", "b"][i];
    if (typeof v[k] !== "number" || Number.isNaN(v[k])) {
      throw new Error(fname + ': color needs numeric "' + k + '"');
    }
  }
  var a = v.a === undefined ? 1 : v.a;
  if (typeof a !== "number" || Number.isNaN(a)) {
    throw new Error(fname + ': color needs numeric "a"');
  }
  var r = v.r / 255, g = v.g / 255, b = v.b / 255;
  if (r < 0 || r > 1 || g < 0 || g > 1 || b < 0 || b > 1 ||
      a < 0 || a > 1) {
    throw new Error(fname + ": r/g/b must be 0..255 and a 0..1");
  }
  return {r: r, g: g, b: b, a: a};
}

/*
 * Internal 0..1 color to the boundary {r, g, b, a} shape (r/g/b rounded 0..255).
 * @param {Rgb01} c - Internal color.
 * @returns {Rgba255} Boundary color.
 */
function toOut(c) {
  return {
    r: Math.round(clamp01(c.r) * 255),
    g: Math.round(clamp01(c.g) * 255),
    b: Math.round(clamp01(c.b) * 255),
    a: c.a
  };
}

// -- convert -------------------------------------------------------------

/*
 * Helper for fromHsl: interpolates one sRGB channel.
 * @param {number} p - Lower bound.
 * @param {number} q - Upper bound.
 * @param {number} t - Position.
 * @returns {number} Channel value 0..1.
 */
function hue2rgb(p, q, t) {
  if (t < 0) t += 1;
  if (t > 1) t -= 1;
  if (t < 1 / 6) return p + (q - p) * 6 * t;
  if (t < 0.5) return q;
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
  return p;
}

/*
 * sRGB 0..1 to {h 0..360, s/l/a 0..1}.
 * @param {Rgb01} c - Internal color.
 * @returns {object} HSL record.
 */
function rgbToHsl(c) {
  var r = c.r, g = c.g, b = c.b;
  var maxc = Math.max(r, Math.max(g, b));
  var minc = Math.min(r, Math.min(g, b));
  var l = (maxc + minc) / 2;
  var h = 0, s = 0;
  if (maxc !== minc) {
    var d = maxc - minc;
    s = l > 0.5 ? d / (2 - maxc - minc) : d / (maxc + minc);
    if (maxc === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (maxc === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h = h / 6;
  }
  return {h: hueMod(h * 360), s: clamp01(s), l: clamp01(l), a: c.a};
}

/*
 * HSL to sRGB 0..1.
 * @param {object} hsl - {h 0..360, s/l/a 0..1}.
 * @returns {Rgb01} Internal color.
 */
function fromHsl(hsl) {
  var h = hueMod(hsl.h) / 360;
  var s = clamp01(hsl.s), l = clamp01(hsl.l);
  var r, g, b;
  if (s === 0) {
    r = l; g = l; b = l;
  } else {
    var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    var p = 2 * l - q;
    r = hue2rgb(p, q, h + 1 / 3);
    g = hue2rgb(p, q, h);
    b = hue2rgb(p, q, h - 1 / 3);
  }
  return {r: clamp01(r), g: clamp01(g), b: clamp01(b), a: clamp01(hsl.a)};
}

/*
 * sRGB 0..1 to {h 0..360, s/v/a 0..1}.
 * @param {Rgb01} c - Internal color.
 * @returns {object} HSV record.
 */
function toHsv(c) {
  var r = c.r, g = c.g, b = c.b;
  var maxc = Math.max(r, Math.max(g, b));
  var minc = Math.min(r, Math.min(g, b));
  var d = maxc - minc;
  var h = 0;
  var s = maxc === 0 ? 0 : d / maxc;
  var v = maxc;
  if (maxc !== minc) {
    if (maxc === r) h = (g - b) / d + (g < b ? 6 : 0);
    else if (maxc === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h = h / 6;
  }
  return {h: hueMod(h * 360), s: clamp01(s), v: clamp01(v), a: c.a};
}

/*
 * HSV to sRGB 0..1.
 * @param {object} hsv - {h, s, v, a}.
 * @returns {Rgb01} Internal color.
 */
function fromHsv(hsv) {
  var h = hueMod(hsv.h) / 360;
  var s = clamp01(hsv.s), v = clamp01(hsv.v);
  var i = Math.floor(h * 6);
  var f = h * 6 - i;
  var p = v * (1 - s);
  var q = v * (1 - f * s);
  var t = v * (1 - (1 - f) * s);
  var r, g, b;
  switch (i % 6) {
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    default: r = v; g = p; b = q; break;
  }
  return {r: clamp01(r), g: clamp01(g), b: clamp01(b), a: clamp01(hsv.a)};
}

/*
 * sRGB 0..1 to {h, w/b 0..1, a} via HSV.
 * @param {Rgb01} c - Internal color.
 * @returns {object} HWB record.
 */
function toHwb(c) {
  var hsv = toHsv(c);
  var w = (1 - hsv.s) * hsv.v;
  var b = 1 - hsv.v;
  return {h: hsv.h, w: clamp01(w), b: clamp01(b), a: c.a};
}

/*
 * HWB to sRGB 0..1 (flat gray when w + b >= 1).
 * @param {object} hwb - {h, w, b, a}.
 * @returns {Rgb01} Internal color.
 */
function fromHwb(hwb) {
  var h = hueMod(hwb.h);
  var w = clamp01(hwb.w), bv = clamp01(hwb.b);
  if (w + bv >= 1) {
    var gray = w / (w + bv);
    return {r: gray, g: gray, b: gray, a: clamp01(hwb.a)};
  }
  var v = 1 - bv;
  var s = v === 0 ? 0 : 1 - w / v;
  return fromHsv({h: h, s: clamp01(s), v: clamp01(v), a: hwb.a});
}

/*
 * sRGB 0..1 to {c/m/y/k/a 0..1}.
 * @param {Rgb01} c - Internal color.
 * @returns {object} CMYK record.
 */
function toCmyk(c) {
  var r = c.r, g = c.g, b = c.b;
  var k = 1 - Math.max(r, Math.max(g, b));
  if (k >= 1 - 1e-10) return {c: 0, m: 0, y: 0, k: 1, a: c.a};
  var denom = 1 - k;
  return {
    c: (1 - r - k) / denom, m: (1 - g - k) / denom,
    y: (1 - b - k) / denom, k: k, a: c.a
  };
}

/*
 * CMYK to sRGB 0..1.
 * @param {object} cmyk - {c, m, y, k, a}.
 * @returns {Rgb01} Internal color.
 */
function fromCmyk(cmyk) {
  var cc = clamp01(cmyk.c), m = clamp01(cmyk.m);
  var y = clamp01(cmyk.y), k = clamp01(cmyk.k);
  return {
    r: clamp01((1 - cc) * (1 - k)), g: clamp01((1 - m) * (1 - k)),
    b: clamp01((1 - y) * (1 - k)), a: clamp01(cmyk.a)
  };
}

/*
 * sRGB 0..1 to CIE Lab (D65).
 * @param {Rgb01} c - Internal color.
 * @returns {object} Lab record.
 */
function toLab(c) {
/*
 * Linearizes one sRGB channel.
 * @param {number} v - Channel 0..1.
 * @returns {number} Linear value.
 */
  function lin(v) {
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  }
  var rl = lin(c.r), gl = lin(c.g), bl = lin(c.b);
  var x = (rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375) * 100;
  var y = (rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750) * 100;
  var z = (rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041) * 100;
/*
 * Lab f(t) nonlinearity.
 * @param {number} t - Normalized tristimulus.
 * @returns {number} f(t).
 */
  function f(t) {
    return t > 0.008856 ? Math.pow(t, 1 / 3) : 7.787 * t + 16 / 116;
  }
  var fx = f(x / Xn), fy = f(y / Yn), fz = f(z / Zn);
  return {l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz),
    alpha: c.a};
}

/*
 * CIE Lab to sRGB 0..1.
 * @param {object} lab - {l, a, b, alpha}.
 * @returns {Rgb01} Internal color.
 */
function fromLab(lab) {
/*
 * Inverse Lab f(t).
 * @param {number} t - f value.
 * @returns {number} Tristimulus.
 */
  function finv(t) {
    var t3 = t * t * t;
    return t3 > 0.008856 ? t3 : (t - 16 / 116) / 7.787;
  }
  var fy = (lab.l + 16) / 116;
  var fx = lab.a / 500 + fy;
  var fz = fy - lab.b / 200;
  var x = Xn * finv(fx), y = Yn * finv(fy), z = Zn * finv(fz);
  var xn = x / 100, yn = y / 100, zn = z / 100;
  var rl = xn * 3.2404542 + yn * (-1.5371385) + zn * (-0.4985314);
  var gl = xn * (-0.9692660) + yn * 1.8760108 + zn * 0.0415560;
  var bl = xn * 0.0556434 + yn * (-0.2040259) + zn * 1.0572252;
/*
 * De-linearizes one channel back to sRGB.
 * @param {number} v - Linear value.
 * @returns {number} Channel 0..1.
 */
  function delin(v) {
    return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
  }
  return {
    r: clamp01(delin(rl)), g: clamp01(delin(gl)), b: clamp01(delin(bl)),
    a: clamp01(lab.alpha)
  };
}

/*
 * sRGB 0..1 to CIE LCh.
 * @param {Rgb01} c - Internal color.
 * @returns {object} LCh record.
 */
function toLch(c) {
  var lab = toLab(c);
  var ch = Math.sqrt(lab.a * lab.a + lab.b * lab.b);
  return {l: lab.l, c: ch, h: hueMod(radToDeg(Math.atan2(lab.b, lab.a))),
    alpha: lab.alpha};
}

/*
 * CIE LCh to sRGB 0..1 via Lab.
 * @param {object} lch - {l, c, h, alpha}.
 * @returns {Rgb01} Internal color.
 */
function fromLch(lch) {
  var a = lch.c * Math.cos(degToRad(lch.h));
  var b = lch.c * Math.sin(degToRad(lch.h));
  return fromLab({l: lch.l, a: a, b: b, alpha: lch.alpha});
}

/*
 * sRGB 0..1 to Oklab.
 * @param {Rgb01} c - Internal color.
 * @returns {object} Oklab record.
 */
function toOklab(c) {
/*
 * Linearizes one sRGB channel.
 * @param {number} v - Channel 0..1.
 * @returns {number} Linear value.
 */
  function lin(v) {
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  }
  var rl = lin(c.r), gl = lin(c.g), bl = lin(c.b);
  var l = OklabM1[0][0] * rl + OklabM1[0][1] * gl + OklabM1[0][2] * bl;
  var m = OklabM1[1][0] * rl + OklabM1[1][1] * gl + OklabM1[1][2] * bl;
  var s = OklabM1[2][0] * rl + OklabM1[2][1] * gl + OklabM1[2][2] * bl;
  l = Math.pow(l, 1 / 3); m = Math.pow(m, 1 / 3); s = Math.pow(s, 1 / 3);
  return {
    l: OklabM2[0][0] * l + OklabM2[0][1] * m + OklabM2[0][2] * s,
    a: OklabM2[1][0] * l + OklabM2[1][1] * m + OklabM2[1][2] * s,
    b: OklabM2[2][0] * l + OklabM2[2][1] * m + OklabM2[2][2] * s,
    alpha: c.a
  };
}

/*
 * Oklab to sRGB 0..1.
 * @param {object} ok - {l, a, b, alpha}.
 * @returns {Rgb01} Internal color.
 */
function fromOklab(ok) {
  var l1 = ok.l + ok.a * 0.3963377774 + ok.b * 0.2158037573;
  var m1 = ok.l + ok.a * (-0.1055613458) + ok.b * (-0.0638541728);
  var s1 = ok.l + ok.a * (-0.0894841775) + ok.b * (-1.2914855480);
  l1 = l1 * l1 * l1; m1 = m1 * m1 * m1; s1 = s1 * s1 * s1;
  var rl = OklabM1Inv[0][0] * l1 + OklabM1Inv[0][1] * m1 +
    OklabM1Inv[0][2] * s1;
  var gl = OklabM1Inv[1][0] * l1 + OklabM1Inv[1][1] * m1 +
    OklabM1Inv[1][2] * s1;
  var bl = OklabM1Inv[2][0] * l1 + OklabM1Inv[2][1] * m1 +
    OklabM1Inv[2][2] * s1;
/*
 * De-linearizes one channel back to sRGB.
 * @param {number} v - Linear value.
 * @returns {number} Channel 0..1.
 */
  function delin(v) {
    return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
  }
  return {
    r: clamp01(delin(rl)), g: clamp01(delin(gl)), b: clamp01(delin(bl)),
    a: clamp01(ok.alpha)
  };
}

/*
 * sRGB 0..1 to Oklch.
 * @param {Rgb01} c - Internal color.
 * @returns {object} Oklch record.
 */
function toOklch(c) {
  var lab = toOklab(c);
  var ch = Math.sqrt(lab.a * lab.a + lab.b * lab.b);
  return {l: lab.l, c: ch, h: hueMod(radToDeg(Math.atan2(lab.b, lab.a))),
    alpha: lab.alpha};
}

/*
 * Oklch to sRGB 0..1 via Oklab.
 * @param {object} oklch - {l, c, h, alpha}.
 * @returns {Rgb01} Internal color.
 */
function fromOklchToColor(oklch) {
  var a = oklch.c * Math.cos(degToRad(oklch.h));
  var b = oklch.c * Math.sin(degToRad(oklch.h));
  return fromOklab({l: oklch.l, a: a, b: b, alpha: oklch.alpha});
}

// -- parse ---------------------------------------------------------------

/*
 * Throws a parse Error with the std prefix.
 * @param {string} msg - Reason.
 * @returns {never} Always throws.
 */
function perr(msg) { throw new Error("parse: " + msg); }

/*
 * parseFloat that throws a parse Error on NaN.
 * @param {string} t - Text to parse.
 * @param {string|undefined} what - Optional message override.
 * @returns {number} Parsed value.
 */
function num(t, what) {
  var v = parseFloat(t);
  if (Number.isNaN(v)) perr(what || ("invalid number: " + t));
  return v;
}

/*
 * ASCII hex-digit test.
 * @param {string} ch - Single character.
 * @returns {boolean} True for 0-9/a-f/A-F.
 */
function isHexDigit(ch) {
  return (ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f") ||
    (ch >= "A" && ch <= "F");
}

/*
 * Parses 3/4/6/8-digit hex (leading # optional) to 0..1.
 * @param {string} s - Hex text.
 * @returns {Rgb01} Internal color.
 */
function parseHexColor(s) {
  var hex = String(s).trim();
  if (hex.length === 0) perr("empty color");
  if (hex[0] === "#") hex = hex.slice(1);
  for (var i = 0; i < hex.length; i++) {
    if (!isHexDigit(hex[i])) perr("invalid hex color: " + s);
  }
  /*
   * Two hex digits to a byte.
   * @param {number} a - First index.
   * @param {number} b - Second index.
   * @returns {number} 0..255.
   */
  function hb(a, b) { return parseInt(hex[a] + hex[b], 16); }
  /*
   * One hex digit duplicated to a byte (e.g. F -> FF).
   * @param {number} a - Index.
   * @returns {number} 0..255.
   */
  function hn(a) { var v = parseInt(hex[a], 16); return v * 16 + v; }
  if (hex.length === 3) {
    return {r: hn(0) / 255, g: hn(1) / 255, b: hn(2) / 255, a: 1};
  } else if (hex.length === 4) {
    return {r: hn(0) / 255, g: hn(1) / 255, b: hn(2) / 255, a: hn(3) / 255};
  } else if (hex.length === 6) {
    return {r: hb(0, 1) / 255, g: hb(2, 3) / 255, b: hb(4, 5) / 255, a: 1};
  } else if (hex.length === 8) {
    return {
      r: hb(0, 1) / 255, g: hb(2, 3) / 255, b: hb(4, 5) / 255,
      a: hb(6, 7) / 255
    };
  }
  perr("invalid hex length: " + s);
}

/*
 * True when the string is shaped like hex (valid length + digits).
 * @param {string} s - Candidate text.
 * @returns {boolean} Hex-shaped or not.
 */
function looksLikeHex(s) {
  var h = String(s).trim();
  if (h.length === 0) return false;
  if (h[0] === "#") h = h.slice(1);
  if (h.length !== 3 && h.length !== 4 && h.length !== 6 && h.length !== 8) {
    return false;
  }
  for (var i = 0; i < h.length; i++) {
    if (!isHexDigit(h[i])) return false;
  }
  return true;
}

/*
 * Lowercased function name before the first paren.
 * @param {string} s - Functional notation.
 * @returns {string} Name or "" when absent.
 */
function extractFuncName(s) {
  var idx = s.indexOf("(");
  if (idx < 0) return "";
  return s.slice(0, idx).trim().toLowerCase();
}

/*
 * Text between the first ( and the last ).
 * @param {string} s - Functional notation.
 * @returns {string} Inner text.
 */
function extractInside(s) {
  var a = s.indexOf("(");
  var b = s.lastIndexOf(")");
  if (a < 0 || b < 0 || b <= a) return "";
  return s.slice(a + 1, b);
}

/*
 * Splits functional notation on commas/whitespace, keeping / as its own token.
 * @param {string} s - Inner text.
 * @returns {Array<string>} Tokens.
 */
function splitValues(s) {
  var out = [], cur = "";
  for (var i = 0; i < s.length; i++) {
    var ch = s[i];
    if (ch === ",") {
      if (cur.trim().length > 0) out.push(cur.trim());
      cur = "";
    } else if (ch === "/") {
      if (cur.trim().length > 0) out.push(cur.trim());
      out.push("/");
      cur = "";
    } else if (ch === " " || ch === "\t" || ch === "\n" || ch === "\r") {
      if (cur.trim().length > 0) { out.push(cur.trim()); cur = ""; }
    } else {
      cur += ch;
    }
  }
  if (cur.trim().length > 0) out.push(cur.trim());
  return out;
}

/*
 * One channel/alpha token; trailing % handled (alpha-aware).
 * @param {string} s - Token.
 * @param {boolean} isAlpha - Whether this token is alpha.
 * @returns {number} Normalized value.
 */
function parseComponent(s, isAlpha) {
  var t = String(s).trim();
  if (t.length === 0) perr("empty component");
  var isPct = t.endsWith("%");
  if (isPct) t = t.slice(0, -1);
  var v = num(t);
  if (isPct) return isAlpha ? clamp01(v / 100) : v / 100;
  return isAlpha ? clamp01(v) : v;
}

/*
 * Parses rgb()/rgba() to 0..1 (slash alpha + legacy comma alpha).
 * @param {string} s - Full notation.
 * @returns {Rgb01} Internal color.
 */
function parseRgbString(s) {
  var parts = splitValues(extractInside(s));
  var alpha = 1;
  var slash = parts.indexOf("/");
  if (slash >= 0) {
    if (slash + 1 < parts.length) {
      alpha = parseComponent(parts[slash + 1], true);
    }
    parts = parts.slice(0, slash);
  }
  if (parts.length < 3) perr("rgb requires 3 components");
  var comps = [];
  for (var i = 0; i < 3; i++) {
    var p = parts[i], c;
    if (p.endsWith("%")) c = num(p.slice(0, -1)) / 100;
    else c = clamp01(num(p) / 255);
    if (Number.isNaN(c)) perr("invalid rgb component: " + p);
    comps.push(c);
  }
  if (parts.length >= 4 && slash < 0) alpha = parseComponent(parts[3], true);
  return {
    r: clamp01(comps[0]), g: clamp01(comps[1]), b: clamp01(comps[2]),
    a: clamp01(alpha)
  };
}

/*
 * Parses hsl()/hsla() to 0..1 via fromHsl.
 * @param {string} s - Full notation.
 * @returns {Rgb01} Internal color.
 */
function parseHslString(s) {
  var parts = splitValues(extractInside(s));
  var alpha = 1;
  var slash = parts.indexOf("/");
  if (slash >= 0) {
    if (slash + 1 < parts.length) {
      alpha = parseComponent(parts[slash + 1], true);
    }
    parts = parts.slice(0, slash);
  }
  if (parts.length < 3) perr("hsl requires 3 components");
  var h = num(parts[0].replace(/turn|grad|deg|rad/g, ""));
  var sVal = parts[1].endsWith("%") ? num(parts[1].slice(0, -1)) / 100 :
    num(parts[1]);
  var lVal = parts[2].endsWith("%") ? num(parts[2].slice(0, -1)) / 100 :
    num(parts[2]);
  if (parts.length >= 4 && slash < 0) alpha = parseComponent(parts[3], true);
  return fromHsl({h: hueMod(h), s: clamp01(sVal), l: clamp01(lVal),
    a: clamp01(alpha)});
}

/*
 * Parses hsv()/hsva()/hsb()/hsba() to 0..1 via fromHsv.
 * @param {string} s - Full notation.
 * @returns {Rgb01} Internal color.
 */
function parseHsvString(s) {
  var parts = splitValues(extractInside(s));
  var alpha = 1;
  var slash = parts.indexOf("/");
  if (slash >= 0) {
    if (slash + 1 < parts.length) {
      alpha = parseComponent(parts[slash + 1], true);
    }
    parts = parts.slice(0, slash);
  }
  if (parts.length < 3) perr("hsv requires 3 components");
  var h = num(parts[0]);
  var sVal = parts[1].endsWith("%") ? num(parts[1].slice(0, -1)) / 100 :
    num(parts[1]);
  var vVal = parts[2].endsWith("%") ? num(parts[2].slice(0, -1)) / 100 :
    num(parts[2]);
  if (parts.length >= 4 && slash < 0) alpha = parseComponent(parts[3], true);
  return fromHsv({h: hueMod(h), s: clamp01(sVal), v: clamp01(vVal),
    a: clamp01(alpha)});
}

/*
 * Parses cmyk()/device-cmyk() to 0..1 via fromCmyk.
 * @param {string} s - Full notation.
 * @returns {Rgb01} Internal color.
 */
function parseCmykString(s) {
  var parts = splitValues(extractInside(s));
  if (parts.length < 4) perr("cmyk requires 4 components");
  var vals = [];
  for (var i = 0; i < 4; i++) {
    var p = parts[i], v;
    if (p.endsWith("%")) v = num(p.slice(0, -1)) / 100;
    else v = num(p);
    vals.push(clamp01(v));
  }
  var alpha = 1;
  if (parts.length >= 5) alpha = parseComponent(parts[4], true);
  return fromCmyk({c: vals[0], m: vals[1], y: vals[2], k: vals[3],
    a: clamp01(alpha)});
}

/*
 * Parses lab() to 0..1 via fromLab.
 * @param {string} s - Full notation.
 * @returns {Rgb01} Internal color.
 */
function parseLabString(s) {
  var parts = splitValues(extractInside(s));
  if (parts.length < 3) perr("lab requires 3 components");
  var l = parts[0].endsWith("%") ? num(parts[0].slice(0, -1)) :
    num(parts[0]);
  var a = num(parts[1]), b = num(parts[2]);
  var alpha = 1;
  var slash = parts.indexOf("/");
  if (slash >= 0 && slash + 1 < parts.length) {
    alpha = parseComponent(parts[slash + 1], true);
  }
  return fromLab({l: l, a: a, b: b, alpha: clamp01(alpha)});
}

/*
 * Parses lch() to 0..1 via fromLch.
 * @param {string} s - Full notation.
 * @returns {Rgb01} Internal color.
 */
function parseLchString(s) {
  var parts = splitValues(extractInside(s));
  if (parts.length < 3) perr("lch requires 3 components");
  var l = parts[0].endsWith("%") ? num(parts[0].slice(0, -1)) :
    num(parts[0]);
  var cc = parts[1].endsWith("%") ? num(parts[1].slice(0, -1)) :
    num(parts[1]);
  var h = num(parts[2]);
  var alpha = 1;
  var slash = parts.indexOf("/");
  if (slash >= 0 && slash + 1 < parts.length) {
    alpha = parseComponent(parts[slash + 1], true);
  }
  return fromLch({l: l, c: cc, h: hueMod(h), alpha: clamp01(alpha)});
}

/*
 * Parses oklab() to 0..1 via fromOklab.
 * @param {string} s - Full notation.
 * @returns {Rgb01} Internal color.
 */
function parseOklabString(s) {
  var parts = splitValues(extractInside(s));
  if (parts.length < 3) perr("oklab requires 3 components");
  var l = parts[0].endsWith("%") ? num(parts[0].slice(0, -1)) / 100 :
    num(parts[0]);
  var a = num(parts[1]), b = num(parts[2]);
  var alpha = 1;
  var slash = parts.indexOf("/");
  if (slash >= 0 && slash + 1 < parts.length) {
    alpha = parseComponent(parts[slash + 1], true);
  }
  return fromOklab({l: l, a: a, b: b, alpha: clamp01(alpha)});
}

/*
 * Parses oklch() to 0..1 via fromOklchToColor.
 * @param {string} s - Full notation.
 * @returns {Rgb01} Internal color.
 */
function parseOklchString(s) {
  var parts = splitValues(extractInside(s));
  if (parts.length < 3) perr("oklch requires 3 components");
  var l = parts[0].endsWith("%") ? num(parts[0].slice(0, -1)) / 100 :
    num(parts[0]);
  var cc = parts[1].endsWith("%") ? num(parts[1].slice(0, -1)) / 100 :
    num(parts[1]);
  var h = num(parts[2]);
  var alpha = 1;
  var slash = parts.indexOf("/");
  if (slash >= 0 && slash + 1 < parts.length) {
    alpha = parseComponent(parts[slash + 1], true);
  }
  return fromOklchToColor({l: l, c: cc, h: hueMod(h), alpha: clamp01(alpha)});
}

var NAMED = {
  aliceblue: [240, 248, 255], antiquewhite: [250, 235, 215],
  aqua: [0, 255, 255], aquamarine: [127, 255, 212],
  azure: [240, 255, 255], beige: [245, 245, 220],
  bisque: [255, 228, 196], black: [0, 0, 0],
  blanchedalmond: [255, 235, 205], blue: [0, 0, 255],
  blueviolet: [138, 43, 226], brown: [165, 42, 42],
  burlywood: [222, 184, 135], cadetblue: [95, 158, 160],
  chartreuse: [127, 255, 0], chocolate: [210, 105, 30],
  coral: [255, 127, 80], cornflowerblue: [100, 149, 237],
  cornsilk: [255, 248, 220], crimson: [220, 20, 60],
  cyan: [0, 255, 255], darkblue: [0, 0, 139],
  darkcyan: [0, 139, 139], darkgoldenrod: [184, 134, 11],
  darkgray: [169, 169, 169], darkgreen: [0, 100, 0],
  darkgrey: [169, 169, 169], darkkhaki: [189, 183, 107],
  darkmagenta: [139, 0, 139], darkolivegreen: [85, 107, 47],
  darkorange: [255, 140, 0], darkorchid: [153, 50, 204],
  darkred: [139, 0, 0], darksalmon: [233, 150, 122],
  darkseagreen: [143, 188, 143], darkslateblue: [72, 61, 139],
  darkslategray: [47, 79, 79], darkslategrey: [47, 79, 79],
  darkturquoise: [0, 206, 209], darkviolet: [148, 0, 211],
  deeppink: [255, 20, 147], deepskyblue: [0, 191, 255],
  dimgray: [105, 105, 105], dimgrey: [105, 105, 105],
  dodgerblue: [30, 144, 255], firebrick: [178, 34, 34],
  floralwhite: [255, 250, 240], forestgreen: [34, 139, 34],
  fuchsia: [255, 0, 255], gainsboro: [220, 220, 220],
  ghostwhite: [248, 248, 255], gold: [255, 215, 0],
  goldenrod: [218, 165, 32], gray: [128, 128, 128],
  green: [0, 128, 0], greenyellow: [173, 255, 47],
  grey: [128, 128, 128], honeydew: [240, 255, 240],
  hotpink: [255, 105, 180], indianred: [205, 92, 92],
  indigo: [75, 0, 130], ivory: [255, 255, 240],
  khaki: [240, 230, 140], lavender: [230, 230, 250],
  lavenderblush: [255, 240, 245], lawngreen: [124, 252, 0],
  lemonchiffon: [255, 250, 205], lightblue: [173, 216, 230],
  lightcoral: [240, 128, 128], lightcyan: [224, 255, 255],
  lightgoldenrodyellow: [250, 250, 210], lightgray: [211, 211, 211],
  lightgreen: [144, 238, 144], lightgrey: [211, 211, 211],
  lightpink: [255, 182, 193], lightsalmon: [255, 160, 122],
  lightseagreen: [32, 178, 170], lightskyblue: [135, 206, 235],
  lightslategray: [119, 136, 153], lightslategrey: [119, 136, 153],
  lightsteelblue: [176, 196, 222], lightyellow: [255, 255, 224],
  lime: [0, 255, 0], limegreen: [50, 205, 50],
  linen: [250, 240, 230], magenta: [255, 0, 255],
  maroon: [128, 0, 0], mediumaquamarine: [102, 205, 170],
  mediumblue: [0, 0, 205], mediumorchid: [186, 85, 211],
  mediumpurple: [147, 112, 219], mediumseagreen: [60, 179, 113],
  mediumslateblue: [123, 104, 238], mediumspringgreen: [0, 250, 154],
  mediumturquoise: [72, 209, 204], mediumvioletred: [199, 21, 133],
  midnightblue: [25, 25, 112], mintcream: [245, 255, 250],
  mistyrose: [255, 228, 225], moccasin: [255, 228, 181],
  navajowhite: [255, 222, 173], navy: [0, 0, 128],
  oldlace: [253, 245, 230], olive: [128, 128, 0],
  olivedrab: [107, 142, 35], orange: [255, 165, 0],
  orangered: [255, 69, 0], orchid: [218, 112, 214],
  palegoldenrod: [238, 232, 170], palegreen: [152, 251, 152],
  paleturquoise: [175, 238, 238], palevioletred: [219, 112, 147],
  papayawhip: [255, 239, 213], peachpuff: [255, 218, 185],
  peru: [205, 133, 63], pink: [255, 192, 203],
  plum: [221, 160, 221], powderblue: [176, 224, 230],
  purple: [128, 0, 128], rebeccapurple: [102, 51, 153],
  red: [255, 0, 0], rosybrown: [188, 143, 143],
  royalblue: [65, 105, 225], saddlebrown: [139, 69, 19],
  salmon: [250, 128, 114], sandybrown: [244, 164, 96],
  seagreen: [46, 139, 87], seashell: [255, 245, 238],
  sienna: [160, 82, 45], silver: [192, 192, 192],
  skyblue: [135, 206, 235], slateblue: [106, 90, 205],
  slategray: [112, 128, 144], slategrey: [112, 128, 144],
  snow: [255, 250, 250], springgreen: [0, 255, 127],
  steelblue: [70, 130, 180], tan: [210, 180, 140],
  teal: [0, 128, 128], thistle: [216, 191, 216],
  tomato: [255, 99, 71], turquoise: [64, 224, 208],
  violet: [238, 130, 238], wheat: [245, 222, 179],
  white: [255, 255, 255], whitesmoke: [245, 245, 245],
  yellow: [255, 255, 0], yellowgreen: [154, 205, 50]
};

/*
 * Full string to 0..1 color: transparent, named, hex, then functional.
 * @param {string} s - Color text.
 * @returns {Rgb01} Internal color.
 */
function parseColorInner(s) {
  var input = String(s).trim();
  if (input.length === 0) perr("empty color string");
  var lower = input.toLowerCase();
  if (lower === "transparent") return {r: 0, g: 0, b: 0, a: 0};
  if (Object.prototype.hasOwnProperty.call(NAMED, lower)) {
    var n = NAMED[lower];
    return {r: n[0] / 255, g: n[1] / 255, b: n[2] / 255, a: 1};
  }
  if (looksLikeHex(input)) return parseHexColor(input);
  if (lower.indexOf("(") >= 0 && lower.indexOf(")") >= 0) {
    var fname = extractFuncName(lower);
    if (fname === "rgb" || fname === "rgba") return parseRgbString(input);
    if (fname === "hsl" || fname === "hsla") return parseHslString(input);
    if (fname === "hsv" || fname === "hsva" || fname === "hsb" ||
        fname === "hsba") return parseHsvString(input);
    if (fname === "hwb") {
      var inside = extractInside(input);
      var parts = splitValues(inside);
      var alpha = 1;
      var slash = parts.indexOf("/");
      if (slash >= 0) {
        if (slash + 1 < parts.length) {
          alpha = parseComponent(parts[slash + 1], true);
        }
        parts = parts.slice(0, slash);
      }
      if (parts.length < 3) perr("hwb requires 3 components");
      var h = num(parts[0]);
      var w = parts[1].endsWith("%") ? num(parts[1].slice(0, -1)) / 100 :
        num(parts[1]);
      var bv = parts[2].endsWith("%") ? num(parts[2].slice(0, -1)) / 100 :
        num(parts[2]);
      return fromHwb({h: hueMod(h), w: clamp01(w), b: clamp01(bv),
        a: clamp01(alpha)});
    }
    if (fname === "cmyk" || fname === "device-cmyk") {
      return parseCmykString(input);
    }
    if (fname === "lab") return parseLabString(input);
    if (fname === "lch") return parseLchString(input);
    if (fname === "oklab") return parseOklabString(input);
    if (fname === "oklch") return parseOklchString(input);
    if (fname === "color") {
      var tokens = splitValues(extractInside(input).trim().toLowerCase());
      var start = 0;
      if (tokens.length > 0 &&
          (tokens[0] === "srgb" || tokens[0] === "srgb-linear" ||
           tokens[0] === "display-p3" || tokens[0] === "a98-rgb" ||
           tokens[0] === "prophoto-rgb" || tokens[0] === "rec2020" ||
           tokens[0] === "xyz" || tokens[0] === "xyz-d50" ||
           tokens[0] === "xyz-d65")) {
        start = 1;
      }
      var vals = [];
      for (var i = start; i < tokens.length; i++) {
        if (tokens[i] === "/") continue;
        vals.push(num(tokens[i]));
      }
      if (vals.length >= 3) {
        var ca = 1;
        var si = tokens.indexOf("/");
        if (si >= 0 && si + 1 < tokens.length) {
          ca = parseComponent(tokens[si + 1], true);
        }
        return {
          r: clamp01(vals[0]), g: clamp01(vals[1]), b: clamp01(vals[2]),
          a: clamp01(ca)
        };
      }
      perr("invalid color()");
    }
    perr("unsupported color function: " + fname);
  }
  perr("unable to parse color: " + s);
}

// -- stringify -------------------------------------------------------------

/*
 * 0..1 color to lowercase #rrggbb.
 * @param {Rgb01} c - Internal color.
 * @returns {string} Hex string.
 */
function toHexInner(c) {
/*
 * One channel to 2-digit hex.
 * @param {number} x - Channel 0..1.
 * @returns {string} Two hex digits.
 */
  function h(x) {
    var s = Math.round(clamp01(x) * 255).toString(16);
    return s.length === 1 ? "0" + s : s;
  }
  return "#" + h(c.r) + h(c.g) + h(c.b);
}

/*
 * Alpha to minimal decimals (0.5, never 0.500).
 * @param {number} a - Alpha 0..1.
 * @returns {string} Formatted alpha.
 */
function formatAlpha(a) {
  var s = clamp01(a).toFixed(3).replace(/0+$/, "");
  if (s.endsWith(".")) s = s.slice(0, -1);
  if (s === "") s = "0";
  return s;
}

/*
 * 0..1 color to an rgb()/rgba() string.
 * @param {Rgb01} c - Internal color.
 * @returns {string} CSS string.
 */
function toRgbInner(c) {
  var r = Math.round(clamp01(c.r) * 255);
  var g = Math.round(clamp01(c.g) * 255);
  var b = Math.round(clamp01(c.b) * 255);
  if (c.a >= 1 - 1e-9) {
    return "rgb(" + r + ", " + g + ", " + b + ")";
  }
  return "rgba(" + r + ", " + g + ", " + b + ", " + formatAlpha(c.a) + ")";
}

/*
 * 0..1 color to an hsl()/hsla() string.
 * @param {Rgb01} c - Internal color.
 * @returns {string} CSS string.
 */
function toHslInner(c) {
  var hsl = rgbToHsl(c);
  var h = Math.round(hsl.h);
  var s = Math.round(hsl.s * 100), l = Math.round(hsl.l * 100);
  if (c.a >= 1 - 1e-9) {
    return "hsl(" + h + ", " + s + "%, " + l + "%)";
  }
  return "hsla(" + h + ", " + s + "%, " + l + "%, " + formatAlpha(c.a) + ")";
}

// -- names -----------------------------------------------------------------

/*
 * Linearized sRGB to CIE XYZ (x100). Helper for toName.
 * @param {number} r - Red 0..1.
 * @param {number} g - Green 0..1.
 * @param {number} b - Blue 0..1.
 * @returns {object} {x, y, z}.
 */
function rgbToXyz(r, g, b) {
/*
 * Linearizes one sRGB channel.
 * @param {number} v - Channel 0..1.
 * @returns {number} Linear value.
 */
  function lin(v) {
    return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  }
  var rl = lin(r), gl = lin(g), bl = lin(b);
  return {
    x: (rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375) * 100,
    y: (rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750) * 100,
    z: (rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041) * 100
  };
}

/*
 * CIE XYZ to Lab. Helper for toName.
 * @param {number} x - X.
 * @param {number} y - Y.
 * @param {number} z - Z.
 * @returns {object} {l, a, b}.
 */
function xyzToLab(x, y, z) {
/*
 * Lab f(t) nonlinearity.
 * @param {number} t - Normalized tristimulus.
 * @returns {number} f(t).
 */
  function f(t) {
    return t > 0.008856 ? Math.pow(t, 1 / 3) : 7.787 * t + 16 / 116;
  }
  var fx = f(x / Xn), fy = f(y / Yn), fz = f(z / Zn);
  return {l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz)};
}

/*
 * 0..1 color to Lab. Helper for toName.
 * @param {Rgb01} c - Internal color.
 * @returns {object} {l, a, b}.
 */
function colorToLab(c) {
  var xyz = rgbToXyz(c.r, c.g, c.b);
  return xyzToLab(xyz.x, xyz.y, xyz.z);
}

/*
 * Nearest of the 148 named colors by squared Lab distance.
 * @param {Rgb01} c - Internal color.
 * @returns {string} Color name.
 */
function toNameInner(c) {
  var lab = colorToLab(c);
  var best = "", bestDist = Infinity;
  for (var name in NAMED) {
    if (!Object.prototype.hasOwnProperty.call(NAMED, name)) continue;
    var rgb = NAMED[name];
    var xyz = rgbToXyz(rgb[0] / 255, rgb[1] / 255, rgb[2] / 255);
    var lab2 = xyzToLab(xyz.x, xyz.y, xyz.z);
    var dl = lab.l - lab2.l, da = lab.a - lab2.a, db = lab.b - lab2.b;
    var d = dl * dl + da * da + db * db;
    if (d < bestDist) { bestDist = d; best = name; }
  }
  return best === "" ? "black" : best;
}

// -- manipulate ------------------------------------------------------------

/*
 * HSL lightness + amount; alpha preserved.
 * @param {Rgb01} c - Internal color.
 * @param {number} amount - Points to add.
 * @returns {Rgb01} Adjusted color.
 */
function lightenInner(c, amount) {
  var hsl = rgbToHsl(c);
  hsl.l = clamp01(hsl.l + amount / 100);
  var out = fromHsl(hsl);
  out.a = c.a;
  return out;
}

/*
 * HSL lightness - amount; alpha preserved.
 * @param {Rgb01} c - Internal color.
 * @param {number} amount - Points to subtract.
 * @returns {Rgb01} Adjusted color.
 */
function darkenInner(c, amount) {
  var hsl = rgbToHsl(c);
  hsl.l = clamp01(hsl.l - amount / 100);
  var out = fromHsl(hsl);
  out.a = c.a;
  return out;
}

/*
 * HSL saturation + amount; alpha preserved.
 * @param {Rgb01} c - Internal color.
 * @param {number} amount - Points to add.
 * @returns {Rgb01} Adjusted color.
 */
function saturateInner(c, amount) {
  var hsl = rgbToHsl(c);
  hsl.s = clamp01(hsl.s + amount / 100);
  var out = fromHsl(hsl);
  out.a = c.a;
  return out;
}

/*
 * Hue rotation by degrees; alpha preserved.
 * @param {Rgb01} c - Internal color.
 * @param {number} amount - Degrees to add.
 * @returns {Rgb01} Adjusted color.
 */
function spinInner(c, amount) {
  var hsl = rgbToHsl(c);
  hsl.h = hueMod(hsl.h + amount);
  var out = fromHsl(hsl);
  out.a = c.a;
  return out;
}

/*
 * spin(180).
 * @param {Rgb01} c - Internal color.
 * @returns {Rgb01} Complement.
 */
function complementInner(c) { return spinInner(c, 180); }

/*
 * Full desaturation (s - 1, clamped).
 * @param {Rgb01} c - Internal color.
 * @returns {Rgb01} Gray with the same lightness.
 */
function greyscaleInner(c) {
  var hsl = rgbToHsl(c);
  hsl.s = clamp01(hsl.s - 1);
  var out = fromHsl(hsl);
  out.a = c.a;
  return out;
}

/*
 * Linear sRGB mix; weight 0..100 as a*(1-w) + b*w, clamped.
 * @param {Rgb01} a - First color.
 * @param {Rgb01} b - Second color.
 * @param {number} weight - 0..100 toward b.
 * @returns {Rgb01} Mixed color.
 */
function mixInner(a, b, weight) {
  var w = clamp(weight / 100, 0, 1);
  var w1 = 1 - w;
  return {
    r: clamp01(a.r * w1 + b.r * w), g: clamp01(a.g * w1 + b.g * w),
    b: clamp01(a.b * w1 + b.b * w), a: clamp01(a.a * w1 + b.a * w)
  };
}

/*
 * [c, spin +120, spin +240].
 * @param {Rgb01} c - Internal color.
 * @returns {Array<Rgb01>} Three colors.
 */
function triadInner(c) {
  return [c, spinInner(c, 120), spinInner(c, 240)];
}

// -- contrast --------------------------------------------------------------

/*
 * WCAG relative luminance.
 * @param {Rgb01} c - Internal color.
 * @returns {number} 0..1.
 */
function luminance(c) {
/*
 * Linearizes one sRGB channel.
 * @param {number} v - Channel 0..1.
 * @returns {number} Linear value.
 */
  function lin(v) {
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  }
  return 0.2126 * lin(clamp01(c.r)) + 0.7152 * lin(clamp01(c.g)) +
    0.0722 * lin(clamp01(c.b));
}

/*
 * WCAG contrast ratio, 1..21.
 * @param {Rgb01} a - First color.
 * @param {Rgb01} b - Second color.
 * @returns {number} Ratio.
 */
function contrastRatioInner(a, b) {
  var la = luminance(a), lb = luminance(b);
  var l1 = Math.max(la, lb), l2 = Math.min(la, lb);
  return (l1 + 0.05) / (l2 + 0.05);
}

/*
 * AA small-text readability (ratio >= 4.5).
 * @param {Rgb01} a - First color.
 * @param {Rgb01} b - Second color.
 * @returns {boolean} Readable or not.
 */
function isReadableInner(a, b) {
  return contrastRatioInner(a, b) >= 4.5;
}

/*
 * True when luminance > 0.5.
 * @param {Rgb01} c - Internal color.
 * @returns {boolean} Light or not.
 */
function isLightInner(c) { return luminance(c) > 0.5; }

// -- random ------------------------------------------------------------------

/*
 * Hue interval for one random-color family.
 * @param {string} name - Family name.
 * @returns {Array<number>} [lo, hi] degrees.
 */
function hueRange(name) {
  switch (String(name).toLowerCase()) {
    case "red": return [0, 20];
    case "orange": return [20, 45];
    case "yellow": return [45, 70];
    case "green": return [70, 175];
    case "blue": return [175, 260];
    case "purple": return [260, 290];
    case "pink": return [290, 350];
    default: return [0, 360];
  }
}

/*
 * Random vivid color (HSV with s >= 0.1, v >= 0.2), opaque.
 * @returns {Rgba255} Boundary color.
 */
function randomInner() {
  var h = Math.random() * 360;
  var s = Math.random(), v = Math.random();
  if (s < 0.1) s = 0.1 + Math.random() * 0.9;
  if (v < 0.2) v = 0.2 + Math.random() * 0.8;
  var col = fromHsv({h: hueMod(h), s: clamp01(s), v: clamp01(v), a: 1});
  return toOut(col);
}

// -- public API --------------------------------------------------------------

/*
 * colors.parse(text) -> {r, g, b, a}. Throws on unknown colors and non-strings.
 * @param {string} text - Color text.
 * @returns {Rgba255} Boundary color.
 */
function parse(text) {
  needString(text, "parse", "text");
  return toOut(parseColorInner(text));
}

/*
 * colors.random() -> {r, g, b, a}.
 * @returns {Rgba255} Boundary color.
 */
function random() {
  return randomInner();
}

/*
 * colors.toHex(color) -> "#rrggbb".
 * @param {object} color - Boundary color.
 * @returns {string} Hex string.
 */
function toHex(color) {
  return toHexInner(needColor(color, "toHex"));
}

/*
 * colors.toRgb(color) -> "rgb()" / "rgba()".
 * @param {object} color - Boundary color.
 * @returns {string} CSS string.
 */
function toRgb(color) {
  return toRgbInner(needColor(color, "toRgb"));
}

/*
 * colors.toHsl(color) -> "hsl()" / "hsla()".
 * @param {object} color - Boundary color.
 * @returns {string} CSS string.
 */
function toHsl(color) {
  return toHslInner(needColor(color, "toHsl"));
}

/*
 * colors.toName(color) -> nearest named color.
 * @param {object} color - Boundary color.
 * @returns {string} Color name.
 */
function toName(color) {
  return toNameInner(needColor(color, "toName"));
}

/*
 * colors.lighten(color, amount) -> color (HSL L + amount).
 * @param {object} color - Boundary color.
 * @param {number} amount - Points to add.
 * @returns {Rgba255} Boundary color.
 */
function lighten(color, amount) {
  var c = needColor(color, "lighten");
  needNumber(amount, "lighten", "amount");
  return toOut(lightenInner(c, amount));
}

/*
 * colors.darken(color, amount) -> color (HSL L - amount).
 * @param {object} color - Boundary color.
 * @param {number} amount - Points to subtract.
 * @returns {Rgba255} Boundary color.
 */
function darken(color, amount) {
  var c = needColor(color, "darken");
  needNumber(amount, "darken", "amount");
  return toOut(darkenInner(c, amount));
}

/*
 * colors.saturate(color, amount) -> color (HSL S + amount).
 * @param {object} color - Boundary color.
 * @param {number} amount - Points to add.
 * @returns {Rgba255} Boundary color.
 */
function saturate(color, amount) {
  var c = needColor(color, "saturate");
  needNumber(amount, "saturate", "amount");
  return toOut(saturateInner(c, amount));
}

/*
 * colors.spin(color, degrees) -> color (hue + amount).
 * @param {object} color - Boundary color.
 * @param {number} amount - Degrees to add.
 * @returns {Rgba255} Boundary color.
 */
function spin(color, amount) {
  var c = needColor(color, "spin");
  needNumber(amount, "spin", "amount");
  return toOut(spinInner(c, amount));
}

/*
 * colors.complement(color) -> color (hue + 180).
 * @param {object} color - Boundary color.
 * @returns {Rgba255} Boundary color.
 */
function complement(color) {
  return toOut(complementInner(needColor(color, "complement")));
}

/*
 * colors.greyscale(color) -> color (no saturation).
 * @param {object} color - Boundary color.
 * @returns {Rgba255} Boundary color.
 */
function greyscale(color) {
  return toOut(greyscaleInner(needColor(color, "greyscale")));
}

/*
 * colors.mix(a, b[, weight]) -> color (weight 0..100, default 50).
 * @param {object} a - First boundary color.
 * @param {object} b - Second boundary color.
 * @param {number|undefined} weight - 0..100 toward b.
 * @returns {Rgba255} Boundary color.
 */
function mix(a, b, weight) {
  var ca = needColor(a, "mix"), cb = needColor(b, "mix");
  if (weight === undefined) weight = 50;
  needNumber(weight, "mix", "weight");
  return toOut(mixInner(ca, cb, weight));
}

/*
 * colors.triad(color) -> 3 colors.
 * @param {object} color - Boundary color.
 * @returns {Array<Rgba255>} Boundary colors.
 */
function triad(color) {
  var c = needColor(color, "triad");
  return triadInner(c).map(toOut);
}

/*
 * colors.contrastRatio(a, b) -> 1..21.
 * @param {object} a - First boundary color.
 * @param {object} b - Second boundary color.
 * @returns {number} Ratio.
 */
function contrastRatio(a, b) {
  return contrastRatioInner(needColor(a, "contrastRatio"),
    needColor(b, "contrastRatio"));
}

/*
 * colors.isReadable(a, b) -> bool (WCAG AA, small text).
 * @param {object} a - First boundary color.
 * @param {object} b - Second boundary color.
 * @returns {boolean} Readable or not.
 */
function isReadable(a, b) {
  return isReadableInner(needColor(a, "isReadable"),
    needColor(b, "isReadable"));
}

/*
 * colors.isLight(color) -> bool.
 * @param {object} color - Boundary color.
 * @returns {boolean} Light or not.
 */
function isLight(color) {
  return isLightInner(needColor(color, "isLight"));
}

module.exports = {
  parse: parse, random: random, toHex: toHex, toRgb: toRgb, toHsl: toHsl,
  toName: toName, lighten: lighten, darken: darken, saturate: saturate,
  spin: spin, complement: complement, greyscale: greyscale, mix: mix,
  triad: triad, contrastRatio: contrastRatio, isReadable: isReadable,
  isLight: isLight
};
