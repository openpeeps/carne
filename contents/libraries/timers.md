---
title: Timers
description: "Global timers: setTimeout, setInterval, clearTimeout, clearInterval."
keywords: ['carne', 'javascript', 'timers', 'setTimeout', 'setInterval']
---

# Timers

```js
setTimeout(() => console.log("later"), 100);          // -> numeric id
const id = setInterval(() => console.log("tick"), 1000);
clearInterval(id); // or clearTimeout(id)
```

Extra args are forwarded to the callback (`setTimeout((a) => console.log(a), 10, "x")`).
Timer throws are recorded as uncaught (exit 1 after drain) without killing
the remaining timers.

