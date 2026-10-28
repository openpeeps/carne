console.log("start");

setTimeout(() => console.log("timeout 50ms"), 50);
setTimeout(() => console.log("timeout 10ms"), 10);

let n = 0;
const id = setInterval(() => {
  n++;
  console.log("tick " + n);
  if (n == 3) clearInterval(id);
}, 20);

setTimeout((a, b) => console.log("args: " + a + b), 5, "x", "y");
