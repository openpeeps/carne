// Carne std/benchmark: in-process microbenchmarking.
// Run: carne run examples/benchmark.js
const benchmark = require("std/benchmark");

const r = benchmark.measure(() => JSON.stringify({a: 1}), {iterations: 100});
console.log(r.iterations); // 100
console.log(r.opsPerSec > 0); // true
console.log(r.minMs <= r.medianMs && r.medianMs <= r.maxMs); // true

const c = benchmark.compare({
  stringify: () => JSON.stringify({a: 1}),
  manual: () => '{"a":1}'
}, {iterations: 100});
console.log(c.fastest); // "manual"
console.log(c.ranking.join(",")); // "manual,stringify"
console.log(c.speedup.stringify === 1); // true

console.log(benchmark.now() > 1700000000000); // true
console.log(benchmark.cpu() >= 0); // true
console.log(benchmark.memory().rssPeak > 0); // true
