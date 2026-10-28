const colors = require("std/colors");

// Parse anything: names, hex, functional notation.
for (const s of ["rebeccapurple", "#c0ffee", "rgb(255, 128, 0)",
    "hsl(210, 100%, 40%)"]) {
  const c = colors.parse(s);
  console.log(s + " -> " + colors.toHex(c) + " named " + colors.toName(c));
}

// Palettes from one seed color.
const base = colors.parse("#3498db");
console.log("triad: " + colors.triad(base).map(c => colors.toHex(c)).join(" "));
console.log("complement: " + colors.toHex(colors.complement(base)));
console.log("spin +120: " + colors.toHex(colors.spin(base, 120)));

// Shade scales for UI work.
console.log("scale: " + [0, 20, 40].map(a =>
  colors.toHex(colors.lighten(base, a))).join(" "));
console.log("dark text readable on it: " +
  colors.isReadable(colors.parse("black"), base));
console.log("contrast vs white: " +
  colors.contrastRatio(base, colors.parse("white")).toFixed(2));

// Dice-driven but reproducible enough for a demo.
console.log("random: " + colors.toHex(colors.random()));
