---
title: UUID
description: "UUID generation and inspection."
keywords: ['carne', 'javascript', 'std', 'uuid']
---

# UUID

UUID generation (v1-v8) and inspection over openparser. Both call
styles work: flat `uuid4()` (destructurable) and `v4()` methods.
`parse`, `version`, `variant` and `isNil` throw on invalid input;
`isValid` never throws.

```js
const {uuid4} = require("std/uuid");
console.log(uuid4().length); // 36

const uuid = require("std/uuid");
console.log(uuid.v4().length); // 36
console.log(uuid.v7()); // time-ordered v7
console.log(uuid.v5(uuid.NAMESPACE_DNS, "www.widgets.com")); // "21f7f8de-8051-5b89-8680-0195ef798b6a"
console.log(uuid.version(uuid4()), uuid.variant(uuid4())); // 4 "rfc4122"
console.log(uuid.isValid("nope"), uuid.isNil(uuid.NIL)); // false true
```


## uuid.uuid1

`uuid.uuid1() -> time-based v1 UUID string`

```js
const uuid = require("std/uuid");
uuid.uuid1();
```

## uuid.v1

`uuid.v1() -> time-based v1 UUID string (alias for uuid1)`

```js
const uuid = require("std/uuid");
uuid.v1();
```

## uuid.uuid2

`uuid.uuid2(domain, localId) -> DCE Security v2 UUID string`

```js
const uuid = require("std/uuid");
uuid.uuid2("example", "example");
```

## uuid.v2

`uuid.v2(domain, localId) -> DCE Security v2 UUID string (alias)`

```js
const uuid = require("std/uuid");
uuid.v2("example", "example");
```

## uuid.uuid3

`uuid.uuid3(namespace, name) -> MD5 name-based v3 UUID string`

```js
const uuid = require("std/uuid");
uuid.uuid3("example", "example");
```

## uuid.v3

`uuid.v3(namespace, name) -> MD5 name-based v3 UUID string (alias)`

```js
const uuid = require("std/uuid");
uuid.v3("example", "example");
```

## uuid.uuid4

`uuid.uuid4() -> random v4 UUID string`

```js
const uuid = require("std/uuid");
uuid.uuid4();
```

## uuid.v4

`uuid.v4() -> random v4 UUID string (alias for uuid4)`

```js
const uuid = require("std/uuid");
uuid.v4();
```

## uuid.uuid5

`uuid.uuid5(namespace, name) -> SHA-1 name-based v5 UUID string`

```js
const uuid = require("std/uuid");
uuid.uuid5("example", "example");
```

## uuid.v5

`uuid.v5(namespace, name) -> SHA-1 name-based v5 UUID string (alias)`

```js
const uuid = require("std/uuid");
uuid.v5("example", "example");
```

## uuid.uuid6

`uuid.uuid6() -> reordered-timestamp v6 UUID string`

```js
const uuid = require("std/uuid");
uuid.uuid6();
```

## uuid.v6

`uuid.v6() -> reordered-timestamp v6 UUID string (alias for uuid6)`

```js
const uuid = require("std/uuid");
uuid.v6();
```

## uuid.uuid7

`uuid.uuid7() -> Unix-ms time-ordered v7 UUID string`

```js
const uuid = require("std/uuid");
uuid.uuid7();
```

## uuid.v7

`uuid.v7() -> Unix-ms time-ordered v7 UUID string (alias for uuid7)`

```js
const uuid = require("std/uuid");
uuid.v7();
```

## uuid.uuid8

`uuid.uuid8(data) -> custom v8 UUID string (32 hex chars, dashes ok)`

```js
const uuid = require("std/uuid");
uuid.uuid8("example");
```

## uuid.v8

`uuid.v8(data) -> custom v8 UUID string (alias for uuid8)`

```js
const uuid = require("std/uuid");
uuid.v8("example");
```

## uuid.parse

`uuid.parse(s) -> normalized lowercase UUID string (throws if invalid)`

```js
const uuid = require("std/uuid");
uuid.parse("example");
```

## uuid.isValid

`uuid.isValid(s) -> bool`

```js
const uuid = require("std/uuid");
uuid.isValid("example");
```

## uuid.version

`uuid.version(s) -> version number 1..8 (throws if invalid)`

```js
const uuid = require("std/uuid");
uuid.version("example");
```

## uuid.variant

`uuid.variant(s) -> "ncs" | "rfc4122" | "microsoft" | "future"`

```js
const uuid = require("std/uuid");
uuid.variant("example");
```

## uuid.isNil

`uuid.isNil(s) -> true for the all-zeros UUID (throws if invalid)`

```js
const uuid = require("std/uuid");
uuid.isNil("example");
```
