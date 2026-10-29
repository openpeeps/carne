const ws = require("std/ws");

// Client for examples/ws-server.js: sends two messages, prints replies,
// closes. Run: ./bin/carne run examples/ws-client.js
(async () => {
  const c = await ws.connect("ws://127.0.0.1:8080/chat", {
    onMessage: (msg) => {
      console.log("got: " + msg.data);
      if (msg.data === "echo:bye") {
        c.close();
      }
    }
  });
  c.send("hello");
  c.send("bye");
})();
