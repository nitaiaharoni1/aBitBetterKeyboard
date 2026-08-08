import assert from "node:assert/strict";
import test from "node:test";
import { handleRequest } from "../src/requestHandler.js";

function fakeClient(call) {
  return { call };
}

const validBody = {
  instructions: "be helpful",
  prompt: "fix this",
  fields: [{ name: "corrections", description: "what changed" }]
};

test("ok result becomes 200 with fields, already-string values untouched", async () => {
  const vertexClient = fakeClient(async () => ({ kind: "ok", fields: { corrections: "none", text: "hi" } }));
  const { status, body } = await handleRequest(validBody, { vertexClient });
  assert.equal(status, 200);
  assert.deepEqual(body, { fields: { corrections: "none", text: "hi" } });
});

test("ok result stringifies nested items rather than dropping them", async () => {
  const vertexClient = fakeClient(async () => ({
    kind: "ok",
    fields: { messages: [{ from: "them", text: "hi" }], sender: "Dana" }
  }));
  const { status, body } = await handleRequest(validBody, { vertexClient });
  assert.equal(status, 200);
  assert.equal(typeof body.fields.messages, "string");
  assert.deepEqual(JSON.parse(body.fields.messages), [{ from: "them", text: "hi" }]);
});

test("refused result becomes 200 with refused:true, no fields key", async () => {
  const vertexClient = fakeClient(async () => ({ kind: "refused" }));
  const { status, body } = await handleRequest(validBody, { vertexClient });
  assert.equal(status, 200);
  assert.deepEqual(body, { refused: true });
});

const errorCases = [
  ["blocked", 422],
  ["unauthorized", 401],
  ["rateLimited", 429],
  ["unavailable", 502],
  ["badRequest", 400]
];

for (const [kind, status] of errorCases) {
  test(`${kind} result becomes HTTP ${status} with the message surfaced verbatim`, async () => {
    const vertexClient = fakeClient(async () => ({ kind, message: `${kind} happened` }));
    const result = await handleRequest(validBody, { vertexClient });
    assert.equal(result.status, status);
    assert.deepEqual(result.body, { error: `${kind} happened` });
  });
}

test("an unrecognized result kind still answers rather than throwing", async () => {
  const vertexClient = fakeClient(async () => ({ kind: "somethingNew" }));
  const { status, body } = await handleRequest(validBody, { vertexClient });
  assert.equal(status, 502);
  assert.match(body.error, /somethingNew/);
});

test("a malformed body is rejected before the network seam is ever called", async () => {
  let called = false;
  const vertexClient = fakeClient(async () => {
    called = true;
    return { kind: "ok", fields: {} };
  });
  const { status, body } = await handleRequest({ instructions: "x" }, { vertexClient });
  assert.equal(status, 400);
  assert.equal(typeof body.error, "string");
  assert.equal(called, false);
});

test("fields must be an array of {name, description}", async () => {
  const bad = { ...validBody, fields: [{ description: "missing a name" }] };
  const { status } = await handleRequest(bad, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(status, 400);
});

test("nested items fields are validated recursively", async () => {
  const bad = {
    ...validBody,
    fields: [{ name: "messages", description: "d", items: [{ description: "no name" }] }]
  };
  const { status } = await handleRequest(bad, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(status, 400);
});

test("an image with a non-string data field is rejected", async () => {
  const bad = { ...validBody, image: { mimeType: "image/jpeg", data: 12345 } };
  const { status } = await handleRequest(bad, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(status, 400);
});

test("field order reaches the vertex client unmodified", async () => {
  let seenFields;
  const vertexClient = fakeClient(async (request) => {
    seenFields = request.fields;
    return { kind: "ok", fields: {} };
  });
  const fields = [
    { name: "decision", description: "d" },
    { name: "versionA", description: "a" },
    { name: "versionB", description: "b" }
  ];
  await handleRequest({ ...validBody, fields }, { vertexClient });
  assert.deepEqual(
    seenFields.map((f) => f.name),
    ["decision", "versionA", "versionB"]
  );
});
