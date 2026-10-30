---
title: Feed
description: "RSS and Atom feed parsing."
keywords: ['carne', 'javascript', 'std', 'feed', 'rss', 'atom']
---

# Feed

RSS and Atom feed parsing. Parse-only in v1

```js
const feed = require("std/feed");
const rss = feed.parseRss('<rss version="2.0"><channel><title>T</title><item><title>Hi</title></item></channel></rss>');
console.log(rss.items.length); // 1 (feed object with items[])
const atom = feed.parseAtom(text); // feed object with entries[]
```


## feed.parseRss

`feed.parseRss(text) -> feed object with items[]`

```js
const feed = require("std/feed");
feed.parseRss("example");
```

## feed.parseAtom

`feed.parseAtom(text) -> feed object with entries[]`

```js
const feed = require("std/feed");
feed.parseAtom("example");
```
