---
title: vCard
description: "vCard contact parsing."
keywords: ['carne', 'javascript', 'std', 'vcard', 'contacts']
---

# vCard

vCard contact parsing. Parse-only in v1: there is no object-to-vCard builder yet.

```js
const vcard = require("std/vcard");
const contacts = vcard.parse("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Ada\r\nEND:VCARD\r\n");
console.log(contacts.length); // 1 (one object per VCARD)
```


## vcard.parse

`vcard.parse(text) -> contact[] (one object per VCARD)`

```js
const vcard = require("std/vcard");
vcard.parse("example");
```
