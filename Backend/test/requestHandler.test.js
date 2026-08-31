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
  const { status, body } = await handleRequest("text", validBody, { vertexClient });
  assert.equal(status, 200);
  assert.deepEqual(body, { fields: { corrections: "none", text: "hi" } });
});

test("ok result stringifies nested items rather than dropping them", async () => {
  const vertexClient = fakeClient(async () => ({
    kind: "ok",
    fields: { messages: [{ from: "them", text: "hi" }], sender: "Dana" }
  }));
  const { status, body } = await handleRequest("text", validBody, { vertexClient });
  assert.equal(status, 200);
  assert.equal(typeof body.fields.messages, "string");
  assert.deepEqual(JSON.parse(body.fields.messages), [{ from: "them", text: "hi" }]);
});

test("refused result becomes 200 with refused:true, no fields key", async () => {
  const vertexClient = fakeClient(async () => ({ kind: "refused" }));
  const { status, body } = await handleRequest("text", validBody, { vertexClient });
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
    const result = await handleRequest("text", validBody, { vertexClient });
    assert.equal(result.status, status);
    assert.deepEqual(result.body, { error: `${kind} happened` });
  });
}

test("an unrecognized result kind still answers rather than throwing", async () => {
  const vertexClient = fakeClient(async () => ({ kind: "somethingNew" }));
  const { status, body } = await handleRequest("text", validBody, { vertexClient });
  assert.equal(status, 502);
  assert.match(body.error, /somethingNew/);
});

test("a malformed body is rejected before the network seam is ever called", async () => {
  let called = false;
  const vertexClient = fakeClient(async () => {
    called = true;
    return { kind: "ok", fields: {} };
  });
  const { status, body } = await handleRequest("text", { instructions: "x" }, { vertexClient });
  assert.equal(status, 400);
  assert.equal(typeof body.error, "string");
  assert.equal(called, false);
});

test("fields must be an array of {name, description}", async () => {
  const bad = { ...validBody, fields: [{ description: "missing a name" }] };
  const { status } = await handleRequest("text", bad, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(status, 400);
});

test("nested items fields are validated recursively", async () => {
  const bad = {
    ...validBody,
    fields: [{ name: "messages", description: "d", items: [{ description: "no name" }] }]
  };
  const { status } = await handleRequest("text", bad, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(status, 400);
});

test("unknown request and field keys are rejected", async () => {
  const withRequestKey = { ...validBody, surprise: "not part of the contract" };
  const requestResult = await handleRequest("text", withRequestKey, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(requestResult.status, 400);
  assert.match(requestResult.body.error, /surprise/);

  const withFieldKey = {
    ...validBody,
    fields: [{ name: "text", description: "d", surprise: true }]
  };
  const fieldResult = await handleRequest("text", withFieldKey, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(fieldResult.status, 400);
  assert.match(fieldResult.body.error, /surprise/);
});

test("an image with a non-string data field is rejected", async () => {
  const bad = { ...validBody, image: { mimeType: "image/jpeg", data: 12345 } };
  const { status } = await handleRequest("screen", bad, {
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
  await handleRequest("text", { ...validBody, fields }, { vertexClient });
  assert.deepEqual(
    seenFields.map((f) => f.name),
    ["decision", "versionA", "versionB"]
  );
});

test("an audio object with a non-string data field is rejected", async () => {
  const bad = { ...validBody, audio: { mimeType: "audio/wav", data: 12345 } };
  const result = await handleRequest("audio", bad, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(result.status, 400);
  assert.match(result.body.error, /audio\.data/);
});

test("audio is forwarded to the vertex client", async () => {
  let seen;
  const vertexClient = {
    call: async (request) => {
      seen = request;
      return { kind: "ok", fields: { speech: "yes", languages: "he,en", text: "shalom" } };
    }
  };
  const result = await handleRequest(
    "audio",
    { ...validBody, audio: { mimeType: "audio/wav", data: "UklGRgAAAABXQVZF" } },
    { vertexClient }
  );
  assert.equal(result.status, 200);
  assert.deepEqual(seen.audio, { mimeType: "audio/wav", data: "UklGRgAAAABXQVZF" });
  assert.equal(result.body.fields.text, "shalom");
});

test("a declared media type with the wrong bytes is rejected", async () => {
  const result = await handleRequest(
    "screen",
    { ...validBody, image: { mimeType: "image/jpeg", data: "Zm9v" } },
    { vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} })) }
  );
  assert.equal(result.status, 400);
  assert.match(result.body.error, /image\/jpeg bytes/);
});

// Guessing which endpoint a two-media body meant is worse than refusing it.
test("a body carrying both image and audio is rejected", async () => {
  const both = {
    ...validBody,
    image: { mimeType: "image/jpeg", data: "/9j/2Q==" },
    audio: { mimeType: "audio/wav", data: "UklGRgAAAABXQVZF" }
  };
  const result = await handleRequest("screen", both, {
    vertexClient: fakeClient(async () => ({ kind: "ok", fields: {} }))
  });
  assert.equal(result.status, 400);
  assert.match(result.body.error, /cannot carry audio/);
});
