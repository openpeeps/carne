const xml = require("std/xml");

const doc = xml.parse(
  '<catalog store="main">' +
  '<book id="1" lang="en"><title>Nim in Action</title><price>30</price></book>' +
  '<book id="2"><title>JS Good Parts</title><price>25</price></book>' +
  '</catalog>');

console.log("store: " + doc.attrs.store);
console.log("books: " + doc.children.length);
console.log("first title: " + doc.children[0].children[0].children[0]);
console.log("second id: " + doc.children[1].attrs.id);

const rebuilt = xml.stringify(doc);
console.log("roundtrip parses: " +
  (xml.parse(rebuilt).children.length === 2));
