---
title: Diff
description: "Unified diffs (Myers/patience/histogram)."
keywords: ['carne', 'javascript', 'std', 'diff']
---

# Diff

Unified diffs (Myers/patience/histogram)

```js
const diff = require("std/diff");
console.log(diff.diff("a\nb\n", "a\nc\n").identical); // false
console.log(diff.unified("a\nb\n", "a\nc\n", {context: 1}));
// "diff --git ...\n--- /dev/null\n+++ /dev/null\n@@ ...\n a\n-b\n+c\n"
```

`diff()` returns `{identical, stats, hunks}`; hunk lines are
`{kind: "equal"|"insert"|"delete", text, spans?}`. Both functions take
an optional `{context}` options object (default 3).


## diff.diff

`diff.diff(a, b[, {context}]) -> {identical, stats, hunks}`

```js
const diff = require("std/diff");
diff.diff({}, {}, {});
```

## diff.unified

`diff.unified(a, b[, {context}]) -> unified diff text`

```js
const diff = require("std/diff");
diff.unified({}, {}, {});
```
