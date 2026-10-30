---
title: Colors
description: "Color parsing, formatting and math."
keywords: ['carne', 'javascript', 'std', 'colors']
---

# Colors

Colors cross the boundary as `{r, g, b, a}` objects (`r`/`g`/`b` are 0..255
integers, `a` is 0..1). Accepts hex, `rgb()`/`hsl()`/`hsv()`/`cmyk()`/
`lab()`/`lch()`/`oklab()`/`oklch()` strings and named colors.

```js
const colors = require("std/colors");
console.log(colors.toHex(colors.parse("red"))); // "#ff0000"
```

## parse

`colors.parse(text)` parses a color string into a `{r, g, b, a}` object.

```js
const colors = require("std/colors");
console.log(colors.parse("red")); // {r: 255, g: 0, b: 0, a: 1}
console.log(colors.parse("#333")); // {r: 51, g: 51, b: 51, a: 1}
```

## random

`colors.random()` returns a random color.

```js
const colors = require("std/colors");
console.log(colors.random()); // {r, g, b, a}
```

## toHex

`colors.toHex(color)` formats a color as `#rrggbb`.

```js
const colors = require("std/colors");
console.log(colors.toHex(colors.parse("red"))); // "#ff0000"
```

## toRgb

`colors.toRgb(color)` formats a color as `rgb(r, g, b)`.

```js
const colors = require("std/colors");
console.log(colors.toRgb(colors.parse("red"))); // "rgb(255, 0, 0)"
```

## toHsl

`colors.toHsl(color)` formats a color as `hsl(h, s%, l%)`.

```js
const colors = require("std/colors");
console.log(colors.toHsl(colors.parse("red")));
```

## toName

`colors.toName(color)` returns the nearest named color.

```js
const colors = require("std/colors");
console.log(colors.toName(colors.parse("#ff0000"))); // "red"
```

## lighten

`colors.lighten(color, amount)` lightens a color by `amount`.

```js
const colors = require("std/colors");
console.log(colors.lighten(colors.parse("#333"), 20));
```

## darken

`colors.darken(color, amount)` darkens a color by `amount`.

```js
const colors = require("std/colors");
console.log(colors.darken(colors.parse("#ccc"), 20));
```

## saturate

`colors.saturate(color, amount)` increases saturation by `amount`.

```js
const colors = require("std/colors");
console.log(colors.saturate(colors.parse("#808080"), 20));
```

## spin

`colors.spin(color, degrees)` rotates the hue by `degrees`.

```js
const colors = require("std/colors");
console.log(colors.spin(colors.parse("red"), 120));
```

## complement

`colors.complement(color)` returns the complementary color.

```js
const colors = require("std/colors");
console.log(colors.complement(colors.parse("red")));
```

## greyscale

`colors.greyscale(color)` converts a color to greyscale.

```js
const colors = require("std/colors");
console.log(colors.greyscale(colors.parse("red")));
```

## mix

`colors.mix(a, b[, weight])` mixes two colors. `weight` is 0..100, default 50.

```js
const colors = require("std/colors");
console.log(colors.mix(colors.parse("red"), colors.parse("blue")));
console.log(colors.mix(colors.parse("red"), colors.parse("blue"), 25));
```

## triad

`colors.triad(color)` returns an array of three colors.

```js
const colors = require("std/colors");
console.log(colors.triad(colors.parse("red")).length); // 3
```

## contrastRatio

`colors.contrastRatio(a, b)` returns the contrast ratio (1..21).

```js
const colors = require("std/colors");
console.log(colors.contrastRatio(colors.parse("black"), colors.parse("white"))); // 21
```

## isReadable

`colors.isReadable(a, b)` checks WCAG AA readability for small text.

```js
const colors = require("std/colors");
console.log(colors.isReadable(colors.parse("black"), colors.parse("white"))); // true
```

## isLight

`colors.isLight(color)` returns whether the color is light.

```js
const colors = require("std/colors");
console.log(colors.isLight(colors.parse("white"))); // true
```
