import assert from "node:assert/strict";
import test from "node:test";
import { createVertexClient } from "../src/vertexClient.js";

// `Response` is a global in Node 22, so these build real response objects
// without a real socket — no test in this file makes a network call.

function tokenProviderStub(token = "test-token") {
  return { getAccessToken: async () => token };
}

function okResponse(fieldsObject = {}) {
  return new Response(
    JSON.stringify({ candidates: [{ content: { parts: [{ text: JSON.stringify(fieldsObject) }] } }] }),
    { status: 200 }
  );
}

test("the request matches the measured shape: endpoint, systemInstruction, one user turn, no temperature on the text path, capped thinking, propertyOrdering, bearer token", async () => {
  let captured;
  const fetchImpl = async (url, init) => {
    captured = { url, init };
    return okResponse();
  };
  const client = createVertexClient({
    project: "proj",
    model: "gemini-2.5-flash",
    tokenProvider: tokenProviderStub(),
    fetchImpl
  });
  await client.call({
    instructions: "be terse",
    prompt: "say hi",
    fields: [{ name: "reply", description: "the reply" }],
    image: null
  });

  assert.equal(
    captured.url,
    "https://aiplatform.googleapis.com/v1/projects/proj/locations/global/publishers/google/models/gemini-2.5-flash:generateContent"
  );
  const body = JSON.parse(captured.init.body);
  assert.deepEqual(body.systemInstruction, { parts: [{ text: "be terse" }] });
  assert.deepEqual(body.contents, [{ role: "user", parts: [{ text: "say hi" }] }]);
  // No temperature: this call has no image, so it is a text action, and every
  // ai-text score was taken with `VertexTransport.swift`'s generationConfig,
  // which sets none. See the dedicated test at the end of this file.
  assert.ok(!("temperature" in body.generationConfig));
  assert.equal(body.generationConfig.responseMimeType, "application/json");
  assert.equal(body.generationConfig.thinkingConfig.thinkingBudget, 512);
  assert.deepEqual(body.generationConfig.responseSchema.propertyOrdering, ["reply"]);
  assert.equal(captured.init.headers.authorization, "Bearer test-token");
});

test("an image part is added before the prompt text", async () => {
  let captured;
  const fetchImpl = async (url, init) => {
    captured = init;
    return okResponse();
  };
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  await client.call({
    instructions: "read the screen",
    prompt: "who sent the last message",
    fields: [],
    image: { mimeType: "image/jpeg", data: "Zm9v" }
  });
  const body = JSON.parse(captured.body);
  assert.deepEqual(body.contents[0].parts[0], { inlineData: { mimeType: "image/jpeg", data: "Zm9v" } });
  assert.deepEqual(body.contents[0].parts[1], { text: "who sent the last message" });
});

test("no image means no inlineData part at all", async () => {
  let captured;
  const fetchImpl = async (url, init) => {
    captured = init;
    return okResponse();
  };
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  const body = JSON.parse(captured.body);
  assert.equal(body.contents[0].parts.length, 1);
  assert.deepEqual(body.contents[0].parts[0], { text: "y" });
});

test("a blocked prompt (promptFeedback.blockReason) is read before candidates, mirroring VertexTransport.decode", async () => {
  const fetchImpl = async () =>
    new Response(JSON.stringify({ promptFeedback: { blockReason: "SAFETY" } }), { status: 200 });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "blocked");
});

test("a SAFETY finish reason on a candidate is a provider safety block", async () => {
  const fetchImpl = async () => new Response(JSON.stringify({ candidates: [{ finishReason: "SAFETY" }] }), { status: 200 });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "blocked");
});

test("a PROHIBITED_CONTENT finish reason is also a provider safety block", async () => {
  const fetchImpl = async () =>
    new Response(JSON.stringify({ candidates: [{ finishReason: "PROHIBITED_CONTENT" }] }), { status: 200 });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "blocked");
});

test("a RECITATION finish reason is a refusal, not a safety block", async () => {
  const fetchImpl = async () =>
    new Response(JSON.stringify({ candidates: [{ finishReason: "RECITATION" }] }), { status: 200 });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "refused");
});

test("no candidates at all is unavailable, not refused", async () => {
  const fetchImpl = async () => new Response(JSON.stringify({}), { status: 200 });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "unavailable");
});

test("HTTP 401/403 from Vertex means no usable credential", async () => {
  for (const status of [401, 403]) {
    const fetchImpl = async () => new Response("denied", { status });
    const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
    const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
    assert.equal(result.kind, "unauthorized");
  }
});

test("HTTP 429 from Vertex is rate limiting", async () => {
  const fetchImpl = async () => new Response("busy", { status: 429 });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "rateLimited");
});

test("any HTTP 5xx from Vertex is unavailable", async () => {
  for (const status of [500, 503]) {
    const fetchImpl = async () => new Response("oops", { status });
    const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
    const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
    assert.equal(result.kind, "unavailable");
  }
});

test("an unmapped HTTP status is a bad request, message preserved", async () => {
  const fetchImpl = async () => new Response("bad argument", { status: 400 });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "badRequest");
  assert.match(result.message, /bad argument/);
});

test("a fetch failure (no network) is unavailable, not a crash", async () => {
  const fetchImpl = async () => {
    throw new Error("ENOTFOUND");
  };
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "unavailable");
});

test("no usable credential (tokenProvider throws) is unauthorized without ever calling fetch", async () => {
  let called = false;
  const fetchImpl = async () => {
    called = true;
    return okResponse();
  };
  const tokenProvider = {
    getAccessToken: async () => {
      throw new Error("no metadata server, gcloud not found");
    }
  };
  const client = createVertexClient({ project: "p", model: "m", tokenProvider, fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "unauthorized");
  assert.equal(called, false);
});

test("a successful candidate's JSON text becomes the ok result's fields", async () => {
  const fetchImpl = async () => okResponse({ reply: "sure" });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "ok");
  assert.deepEqual(result.fields, { reply: "sure" });
});

test("a candidate whose text is not valid JSON is unavailable, not a crash", async () => {
  const fetchImpl = async () =>
    new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: "not json" }] } }] }), { status: 200 });
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  const result = await client.call({ instructions: "x", prompt: "y", fields: [], image: null });
  assert.equal(result.kind, "unavailable");
});

// Each endpoint has to send the generationConfig its own corpus was scored at,
// and the two corpora disagree. vertex_vision.py sets temperature 0; the ai-text
// harness sets no temperature at all. Sending 0 on both is the tidy-looking
// mistake this pins against.
test("a screen read sends temperature 0 and a text action sends none", async () => {
  const bodies = [];
  const client = createVertexClient({
    project: "p",
    model: "m",
    tokenProvider: tokenProviderStub(),
    fetchImpl: async (_url, init) => {
      bodies.push(JSON.parse(init.body));
      return okResponse();
    }
  });

  await client.call({
    instructions: "i", prompt: "p", fields: [{ name: "text", description: "d" }],
    image: { mimeType: "image/jpeg", data: "AAAA" }
  });
  await client.call({ instructions: "i", prompt: "p", fields: [{ name: "text", description: "d" }] });

  assert.equal(bodies[0].generationConfig.temperature, 0, "screen reads were scored at temperature 0");
  assert.ok(
    !("temperature" in bodies[1].generationConfig),
    "the ai-text corpus was scored with no temperature set; sending 0 ships an ungraded config"
  );
  // The knob that IS shared, so this test cannot pass by dropping both.
  assert.equal(bodies[0].generationConfig.thinkingConfig.thinkingBudget, 512);
  assert.equal(bodies[1].generationConfig.thinkingConfig.thinkingBudget, 512);
});

// MARK: - The audio path
//
// Dictation. Same inlineData shape as a frame, a different field and a
// different endpoint, for the reason `validateMedia` in `requestHandler.js`
// gives: a recording of somebody's voice should be able to have a different
// retention rule from a picture of their screen.

test("an audio part is added before the prompt text", async () => {
  let captured;
  const fetchImpl = async (url, init) => {
    captured = init;
    return okResponse();
  };
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  await client.call({
    instructions: "transcribe",
    prompt: "what was said",
    fields: [],
    audio: { mimeType: "audio/wav", data: "UklGRg==" }
  });
  const body = JSON.parse(captured.body);
  assert.deepEqual(body.contents[0].parts[0], { inlineData: { mimeType: "audio/wav", data: "UklGRg==" } });
  assert.deepEqual(body.contents[0].parts[1], { text: "what was said" });
});

// Not symmetry for its own sake. `Bar/dictation/` is deterministic *because* of
// this line — two full runs of the identical configuration came back byte for
// byte identical, which no other corpus in this repo manages — and every number
// on that bar was taken with it.
test("the audio path sends temperature 0", async () => {
  let captured;
  const fetchImpl = async (url, init) => {
    captured = init;
    return okResponse();
  };
  const client = createVertexClient({ project: "p", model: "m", tokenProvider: tokenProviderStub(), fetchImpl });
  await client.call({
    instructions: "transcribe",
    prompt: "what was said",
    fields: [],
    audio: { mimeType: "audio/wav", data: "UklGRg==" }
  });
  assert.equal(JSON.parse(captured.body).generationConfig.temperature, 0);
});
