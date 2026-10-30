const http = require("std/http");
http.serve(3000, {workers: 4}, req => "hello world");
