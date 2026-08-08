import assert from "node:assert/strict";
import test from "node:test";
import { buildResponseSchema } from "../src/schema.js";

test("scalar field becomes an uppercase STRING type with nullable true", () => {
  const schema = buildResponseSchema([{ name: "decision", description: "the decision" }]);
  assert.deepEqual(schema.properties.decision, {
    type: "STRING",
    description: "the decision",
    nullable: true
  });
});

test("field order survives into required and propertyOrdering, unsorted", () => {
  const fields = [
    { name: "decision", description: "d" },
    { name: "versionA", description: "a" },
    { name: "versionB", description: "b" }
  ];
  const schema = buildResponseSchema(fields);
  assert.deepEqual(schema.required, ["decision", "versionA", "versionB"]);
  assert.deepEqual(schema.propertyOrdering, ["decision", "versionA", "versionB"]);
});

test("a field with items becomes an ARRAY of OBJECT, not a flattened string", () => {
  const fields = [
    {
      name: "messages",
      description: "every bubble",
      items: [
        { name: "from", description: "who sent it" },
        { name: "text", description: "the words" }
      ]
    }
  ];
  const schema = buildResponseSchema(fields);
  assert.equal(schema.properties.messages.type, "ARRAY");
  assert.equal(schema.properties.messages.items.type, "OBJECT");
  assert.deepEqual(schema.properties.messages.items.required, ["from", "text"]);
  assert.deepEqual(schema.properties.messages.items.propertyOrdering, ["from", "text"]);
  assert.deepEqual(schema.properties.messages.items.properties.from, {
    type: "STRING",
    description: "who sent it",
    nullable: true
  });
});

test("nested items order survives the same way top-level order does", () => {
  const fields = [
    {
      name: "messages",
      description: "every bubble",
      items: [
        { name: "from", description: "a" },
        { name: "kind", description: "b" },
        { name: "sender", description: "c" },
        { name: "text", description: "d" }
      ]
    }
  ];
  const schema = buildResponseSchema(fields);
  assert.deepEqual(schema.properties.messages.items.propertyOrdering, ["from", "kind", "sender", "text"]);
});

test("top-level schema is itself an OBJECT with every field required", () => {
  const schema = buildResponseSchema([
    { name: "a", description: "" },
    { name: "b", description: "" }
  ]);
  assert.equal(schema.type, "OBJECT");
  assert.deepEqual(schema.required, ["a", "b"]);
});
