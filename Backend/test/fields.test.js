import assert from "node:assert/strict";
import test from "node:test";
import { encodeResponseFields } from "../src/fields.js";

test("string values pass through unchanged", () => {
  assert.deepEqual(encodeResponseFields({ sender: "Dana" }), { sender: "Dana" });
});

test("null and undefined are dropped, not stringified", () => {
  const encoded = encodeResponseFields({ sender: null, message: undefined, other: "x" });
  assert.deepEqual(encoded, { other: "x" });
});

test("a nested items array is JSON-stringified rather than dropped", () => {
  const messages = [{ from: "them", kind: "text", sender: "Dana", text: "hi" }];
  const encoded = encodeResponseFields({ messages, sender: "Dana" });
  assert.equal(typeof encoded.messages, "string");
  assert.deepEqual(JSON.parse(encoded.messages), messages);
});

test("every value in the result is a string, matching the client's compactMapValues", () => {
  const encoded = encodeResponseFields({ a: "x", b: [1, 2], c: 3, d: null, e: true });
  for (const value of Object.values(encoded)) assert.equal(typeof value, "string");
  assert.deepEqual(Object.keys(encoded).sort(), ["a", "b", "c", "e"]);
});

test("an empty input produces an empty object", () => {
  assert.deepEqual(encodeResponseFields({}), {});
  assert.deepEqual(encodeResponseFields(undefined), {});
});
