---
title: Gettext
description: ".po parsing and translation."
keywords: ['carne', 'javascript', 'std', 'gettext', 'i18n']
---

# Gettext

`.po` parsing and translation. Untranslated ids fall back to the msgid. `.mo` is out of scope in v1.

```js
const gettext = require("std/gettext");
const po = 'msgid "hi"\nmsgstr "salut"\n';

console.log(gettext.translate(po, "hi")); // "salut"
console.log(gettext.ntranslate(po, "file", "files", 2));
console.log(gettext.parse(po).entries.length);
```


## gettext.parse

`gettext.parse(text) -> {headers, entries}`

```js
const gettext = require("std/gettext");
gettext.parse("example");
```

## gettext.translate

`gettext.translate(text, msgid[, msgctxt]) -> string`

```js
const gettext = require("std/gettext");
gettext.translate("example", "example", "example");
```

## gettext.ntranslate

`gettext.ntranslate(text, singular, plural, n) -> string`

```js
const gettext = require("std/gettext");
gettext.ntranslate("example", "example", "example", "example");
```
