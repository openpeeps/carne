---
title: Benchmark
description: "In-process microbenchmarking."
keywords: ['carne', 'javascript', 'std', 'benchmark']
---

# Benchmark

In-process microbenchmarking on Nim clocks. `measure` runs a sync function N times
(plus discarded warmup) and returns wall stats in ms with `opsPerSec`, process
`cpuMs`, peak `rssPeak` and Nim-heap `heapDelta`. `compare` ranks named functions
fastest-first with `speedup` anchored at the slowest (= 1). `rssPeak` is the
getrusage high-water mark in bytes, not live RSS; async functions are out of
scope (only body time would be measured).

```js
const benchmark = require("std/benchmark");
const r = benchmark.measure(() => JSON.stringify({a: 1}), {iterations: 100});
console.log(r.iterations); // 100
console.log(r.minMs <= r.medianMs && r.medianMs <= r.maxMs); // true
const c = benchmark.compare({s: () => JSON.stringify({a: 1}), m: () => '{"a":1}'});
console.log(c.fastest); // "m"
console.log(benchmark.memory().rssPeak > 0); // true
```


## benchmark.measure

`benchmark.measure(fn[, {iterations, warmup}]) -> stats object`

```js
const benchmark = require("std/benchmark");
benchmark.measure("example", {});
```

## benchmark.compare

`benchmark.compare({name: fn}[, {iterations, warmup}])`

-> {results, ranking, fastest, speedup}

```js
const benchmark = require("std/benchmark");
benchmark.compare("example", {});
```

## benchmark.now

`benchmark.now() -> wall ms since the Unix epoch`

```js
const benchmark = require("std/benchmark");
benchmark.now();
```

## benchmark.cpu

`benchmark.cpu() -> process CPU ms`

```js
const benchmark = require("std/benchmark");
benchmark.cpu();
```

## benchmark.memory

`benchmark.memory() -> {rssPeak, heap} in bytes`

```js
const benchmark = require("std/benchmark");
benchmark.memory();
```
