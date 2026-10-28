const regex = require("std/regex");

// Same call shapes as RegExp, same engine as Nim's openparser.
console.log(regex.test("\\d+", "order 66"));
console.log(regex.test("^\\d+$", "order 66"));

// exec with groups, or null.
const m = regex.exec("(?<y>\\d{4})-(?<m>\\d{2})-(?<d>\\d{2})", "born 1979-05-27, ok");
if (m) console.log(m.match + " at " + m.index + " :: " + m.groups.join("/"));
console.log(regex.exec("z+", "nothing here"));

// Every hit, for highlighting or counting.
const words = regex.matchAll("[a-z]+", "ada and grace slipped away");
console.log(words.length + " words, first at " + words[0].index);

// Validation comes free: bad patterns throw with position info.
try {
  regex.test("(unclosed", "x");
} catch (e) {
  console.log("bad pattern: " + e.message.split("\n").slice(-2, -1)[0].trim());
}
