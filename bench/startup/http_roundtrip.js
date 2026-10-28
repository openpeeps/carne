(async () => {
  const http = require("std/http");
  const srv = http.serve(18299, req => ({body: "ok"}));
  const res = await http.get("http://127.0.0.1:18299/");
  http.close(srv.port);
  console.log(res.status + " " + res.body);
})();
