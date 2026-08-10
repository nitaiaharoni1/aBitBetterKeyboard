import assert from "node:assert/strict";
import test from "node:test";
import { createServer } from "../src/httpServer.js";
import { createTokens } from "../src/sessionToken.js";
import { createAttestationVerifier } from "../src/attestationVerifier.js";
import { buildFakeAttestation, createTestCA } from "./helpers/fakeAttestation.js";

// These start a real `http.Server` on a loopback port and use the platform
// `fetch` against it — not a network call to any external service, and no
// `vertexClient` here ever does one either (each test supplies a fake).

function fakeVertexClient(call) {
  return { call };
}

async function withServer(vertexClient, run, opts = {}) {
  const server = createServer({ vertexClient, ...opts });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("POST /v1/text round-trips a valid request to a 200", async () => {
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: { corrections: "none", text: "hi" } })),
    async (base) => {
      const response = await fetch(`${base}/v1/text`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          instructions: "fix typos",
          prompt: "hii",
          fields: [{ name: "text", description: "corrected text" }]
        })
      });
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), { fields: { corrections: "none", text: "hi" } });
    }
  );
});

test("POST /v1/screen accepts an image field and forwards it to the vertex client", async () => {
  await withServer(
    fakeVertexClient(async (request) => {
      assert.ok(request.image);
      assert.equal(request.image.mimeType, "image/jpeg");
      return { kind: "ok", fields: { sender: "Dana" } };
    }),
    async (base) => {
      const response = await fetch(`${base}/v1/screen`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          instructions: "read the screen",
          prompt: "who sent the last message",
          fields: [{ name: "sender", description: "sender" }],
          image: { mimeType: "image/jpeg", data: "Zm9v" }
        })
      });
      assert.equal(response.status, 200);
    }
  );
});

test("an unknown route is 404", async () => {
  await withServer(fakeVertexClient(async () => ({ kind: "ok", fields: {} })), async (base) => {
    const response = await fetch(`${base}/v1/unknown`, { method: "POST", body: "{}" });
    assert.equal(response.status, 404);
  });
});

test("malformed JSON is 400", async () => {
  await withServer(fakeVertexClient(async () => ({ kind: "ok", fields: {} })), async (base) => {
    const response = await fetch(`${base}/v1/text`, { method: "POST", body: "not json" });
    assert.equal(response.status, 400);
  });
});

test("a body over the configured limit is 413 and never reaches the vertex client", async () => {
  let called = false;
  await withServer(
    fakeVertexClient(async () => {
      called = true;
      return { kind: "ok", fields: {} };
    }),
    async (base) => {
      const response = await fetch(`${base}/v1/text`, { method: "POST", body: "x".repeat(2000) });
      assert.equal(response.status, 413);
      assert.equal(called, false);
    },
    { maxBodyBytes: 1000 }
  );
});

test("GET /healthz answers without touching the vertex client", async () => {
  await withServer(
    fakeVertexClient(async () => {
      throw new Error("must not be called");
    }),
    async (base) => {
      const response = await fetch(`${base}/healthz`);
      assert.equal(response.status, 200);
    }
  );
});

test("an error status from the handler is passed through with its body", async () => {
  await withServer(
    fakeVertexClient(async () => ({ kind: "blocked", message: "unsafe content" })),
    async (base) => {
      const response = await fetch(`${base}/v1/text`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ instructions: "x", prompt: "y", fields: [] })
      });
      assert.equal(response.status, 422);
      assert.deepEqual(await response.json(), { error: "unsafe content" });
    }
  );
});

// The gate's own branches are covered in gate.test.js. These prove it is
// actually wired into the server, which unit tests of gate.js cannot: a
// perfectly correct `authorize` that nothing calls protects nothing.

test("a server with a token refuses an unauthenticated call before spending anything", async () => {
  let vertexCalls = 0;
  await withServer(
    fakeVertexClient(async () => {
      vertexCalls += 1;
      return { kind: "ok", fields: { text: "hi" } };
    }),
    async (base) => {
      const response = await fetch(`${base}/v1/text`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ instructions: "i", prompt: "p", fields: [{ name: "text", description: "d" }] })
      });
      assert.equal(response.status, 401);
      assert.equal(vertexCalls, 0, "an unauthorised request must not reach the paid model");
    },
    { expectedToken: "letmein" }
  );
});

test("…and accepts the same call with the bearer token", async () => {
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: { text: "hi" } })),
    async (base) => {
      const response = await fetch(`${base}/v1/text`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: "Bearer letmein" },
        body: JSON.stringify({ instructions: "i", prompt: "p", fields: [{ name: "text", description: "d" }] })
      });
      assert.equal(response.status, 200);
    },
    { expectedToken: "letmein" }
  );
});

test("health checks are exempt, or Cloud Run marks the revision unhealthy", async () => {
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: {} })),
    async (base) => {
      const response = await fetch(`${base}/healthz`);
      assert.equal(response.status, 200, "a health probe carries no bearer token");
    },
    { expectedToken: "letmein" }
  );
});

test("a rate-limited caller is refused with retry-after and costs nothing", async () => {
  let vertexCalls = 0;
  const { createRateLimiter } = await import("../src/gate.js");
  await withServer(
    fakeVertexClient(async () => {
      vertexCalls += 1;
      return { kind: "ok", fields: { text: "hi" } };
    }),
    async (base) => {
      const send = () =>
        fetch(`${base}/v1/text`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ instructions: "i", prompt: "p", fields: [{ name: "text", description: "d" }] })
        });

      assert.equal((await send()).status, 200);
      const refused = await send();
      assert.equal(refused.status, 429);
      assert.ok(refused.headers.get("retry-after"), "a 429 has to say when to come back");
      assert.equal(vertexCalls, 1, "the refused call must not reach the paid model");
    },
    { rateLimiter: createRateLimiter({ windowMs: 60_000, maxPerWindow: 1 }) }
  );
});

// A slow-POST probe, with a raw socket rather than `fetch`, because `fetch`
// cannot express "announce a huge body and then dribble it forever" — which is
// the whole attack. The gate refuses these callers instantly and for free; the
// question is whether refusing them also lets go of the connection. Before the
// fix it did not: node answered 401 and then held the socket open for as long
// as the caller cared to keep it, which is a connection-exhaustion route that
// costs the attacker no token and never reaches the paid model.
//
// Every test here carries its own timeout, because `node --test` runs with
// `--test-timeout=0` and a socket that never closes would otherwise hang the
// whole suite rather than failing it.

import net from "node:net";

const PROBE_TIMEOUT_MS = 3000;

/// Opens a connection, claims a 100 MB body, sends `bodyBytes` of it, and then
/// stops — never completing the request. Resolves with whatever the server said
/// and whether it hung up.
function slowPost(port, { authorization, bodyBytes = 1 } = {}) {
  return new Promise((resolve, reject) => {
    const socket = net.connect(port, "127.0.0.1", () => {
      socket.write(
        "POST /v1/text HTTP/1.1\r\n"
          + "Host: 127.0.0.1\r\n"
          + "Content-Type: application/json\r\n"
          + (authorization ? `Authorization: ${authorization}\r\n` : "")
          + "Content-Length: 100000000\r\n\r\n"
          + "x".repeat(bodyBytes)
      );
    });

    let received = "";
    const guard = setTimeout(() => {
      socket.destroy();
      reject(new Error(`server never hung up; it said: ${received.slice(0, 80) || "(nothing)"}`));
    }, PROBE_TIMEOUT_MS);

    socket.on("data", (chunk) => { received += chunk.toString("utf8"); });
    socket.on("close", () => { clearTimeout(guard); resolve(received); });
    socket.on("error", () => { clearTimeout(guard); resolve(received); });
  });
}

test("an unauthenticated slow POST is answered and hung up on", { timeout: 10_000 }, async () => {
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: { text: "hi" } })),
    async (base) => {
      // No Authorization header: refused before the body is ever read.
      const received = await slowPost(Number(new URL(base).port));
      assert.match(received, /^HTTP\/1\.1 401/, "expected a 401");
      assert.match(received, /connection: close/i);
    },
    { expectedToken: "letmein" }
  );
});

test("a rate-limited slow POST is answered and hung up on", { timeout: 10_000 }, async () => {
  const { createRateLimiter } = await import("../src/gate.js");
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: { text: "hi" } })),
    async (base) => {
      await fetch(`${base}/v1/text`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ instructions: "i", prompt: "p", fields: [{ name: "text", description: "d" }] })
      });

      const received = await slowPost(Number(new URL(base).port));
      assert.match(received, /^HTTP\/1\.1 429/, "expected a 429");
      assert.match(received, /connection: close/i);
    },
    { rateLimiter: createRateLimiter({ windowMs: 60_000, maxPerWindow: 1 }) }
  );
});

test("a body over the cap is answered and hung up on", { timeout: 10_000 }, async () => {
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: { text: "hi" } })),
    async (base) => {
      // No token configured, so this one passes auth and dies on the byte cap
      // instead — the other branch that answers before the body is consumed.
      const received = await slowPost(Number(new URL(base).port), { bodyBytes: 64 });
      assert.match(received, /^HTTP\/1\.1 413/, "expected a 413");
      assert.match(received, /connection: close/i);
    },
    { maxBodyBytes: 8 }
  );
});

test("an unknown route is hung up on too", { timeout: 10_000 }, async () => {
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: {} })),
    async (base) => {
      const response = await fetch(`${base}/v1/nope`, { method: "POST", body: "{}" });
      assert.equal(response.status, 404);
      assert.equal(response.headers.get("connection"), "close");
    }
  );
});

test("POST /v1/audio round-trips a transcription to a 200", async () => {
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: { speech: "yes", languages: "he,en", text: "היי" } })),
    async (base) => {
      const response = await fetch(`${base}/v1/audio`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          instructions: "transcribe",
          prompt: "what was said",
          fields: [{ name: "text", description: "the transcript" }],
          audio: { mimeType: "audio/wav", data: "UklGRg==" }
        })
      });
      assert.equal(response.status, 200);
      assert.equal((await response.json()).fields.text, "היי");
    }
  );
});

// ── The attestation routes ─────────────────────────────────────────────────
//
// These start the same real loopback server as the tests above, with a token
// signer and a verifier whose trust anchor is the test CA out of
// `helpers/fakeAttestation.js`. Nothing here reaches Apple, and nothing needs a
// Secure Enclave.

async function withAttestServer(run, { secret = "s".repeat(64), rootPem } = {}) {
  const tokens = createTokens({ secret });
  const attestationVerifier = createAttestationVerifier({
    rootCertificatePem: rootPem,
    appId: "9R8P28G4BJ.com.nitai.aikeyboard",
    environment: "development"
  });
  await withServer(
    fakeVertexClient(async () => ({ kind: "ok", fields: { corrections: "none", text: "hi" } })),
    (base) => run(base, tokens),
    { tokens, attestationVerifier, expectedToken: "shared-secret" }
  );
}

const TEXT_BODY = JSON.stringify({
  instructions: "fix typos",
  prompt: "hii",
  fields: [{ name: "text", description: "corrected text" }]
});

test("POST /v1/challenge hands out a challenge without a bearer", async () => {
  const ca = await createTestCA();
  await withAttestServer(
    async (base) => {
      const response = await fetch(`${base}/v1/challenge`, { method: "POST" });
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.ok(typeof body.challenge === "string" && body.challenge.length > 0);
    },
    { rootPem: ca.pem }
  );
});

test("a valid attestation is exchanged for a session token that opens /v1/text", async () => {
  // Built against a challenge this server actually issued, which is the whole
  // point of the round trip.
  const ca = await createTestCA();
  await withAttestServer(
    async (base) => {
      const challenge = (await (await fetch(`${base}/v1/challenge`, { method: "POST" })).json())
        .challenge;
      const fixture = await buildFakeAttestation({ challenge, ca });

      const attested = await fetch(`${base}/v1/attest`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          keyId: fixture.keyId,
          attestation: fixture.attestation.toString("base64"),
          challenge
        })
      });
      // Read once. `await attested.text()` as an assert message consumes the
      // body eagerly, and the `.json()` below then throws instead of reporting.
      const attestedBody = await attested.text();
      assert.equal(attested.status, 200, attestedBody);
      const { token, expiresAt } = JSON.parse(attestedBody);
      assert.ok(typeof token === "string" && token.length > 0);
      assert.ok(typeof expiresAt === "string");

      // The half that proves the token is worth anything.
      const used = await fetch(`${base}/v1/text`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
        body: TEXT_BODY
      });
      assert.equal(used.status, 200);

      // And the half that proves the gate is still a gate.
      const without = await fetch(`${base}/v1/text`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: TEXT_BODY
      });
      assert.equal(without.status, 401);
    },
    { rootPem: ca.pem }
  );
});

test("a challenge the service never issued is refused", async () => {
  const ca = await createTestCA();
  const fixture = await buildFakeAttestation({ challenge: "made up", ca });
  await withAttestServer(
    async (base) => {
      const response = await fetch(`${base}/v1/attest`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          keyId: fixture.keyId,
          attestation: fixture.attestation.toString("base64"),
          challenge: "made up"
        })
      });
      assert.equal(response.status, 401);
      assert.deepEqual(await response.json(), { error: "attestation refused" });
    },
    { rootPem: ca.pem }
  );
});

// **One message for every rejection.** A caller who can tell "wrong app" from
// "expired challenge" from "bad chain" is a caller being coached.
test("an attestation for another app is refused in exactly the same words", async () => {
  const ca = await createTestCA();
  await withAttestServer(
    async (base) => {
      const challenge = (await (await fetch(`${base}/v1/challenge`, { method: "POST" })).json())
        .challenge;
      const wrongApp = await buildFakeAttestation({
        challenge,
        ca,
        appId: "9R8P28G4BJ.com.someone.else"
      });
      const response = await fetch(`${base}/v1/attest`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          keyId: wrongApp.keyId,
          attestation: wrongApp.attestation.toString("base64"),
          challenge
        })
      });
      assert.equal(response.status, 401);
      assert.deepEqual(await response.json(), { error: "attestation refused" });
    },
    { rootPem: ca.pem }
  );
});

test("an attest body missing its fields is 400, not a crash", async () => {
  const ca = await createTestCA();
  await withAttestServer(
    async (base) => {
      const response = await fetch(`${base}/v1/attest`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ keyId: "only-this" })
      });
      assert.equal(response.status, 400);
    },
    { rootPem: ca.pem }
  );
});

test("an attest body over its own smaller cap is refused", async () => {
  const ca = await createTestCA();
  await withAttestServer(
    async (base) => {
      const response = await fetch(`${base}/v1/attest`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        // Well under the 8 MB the model routes allow, and well over this
        // route's own 64 KB.
        body: JSON.stringify({ keyId: "x", attestation: "A".repeat(200 * 1024), challenge: "y" })
      });
      assert.equal(response.status, 413);
    },
    { rootPem: ca.pem }
  );
});

test("with no attestation configured the routes do not exist", async () => {
  await withServer(fakeVertexClient(async () => ({ kind: "ok", fields: {} })), async (base) => {
    const response = await fetch(`${base}/v1/challenge`, { method: "POST" });
    assert.equal(response.status, 404);
  });
});

// **Regression: /v1/challenge answers a caller who has proved nothing, so it is
// the last route that should leave a socket open.** It never reads a body, and a
// POST can carry one, so it has to hang up the way every other pre-body branch
// does. Asserted through the header rather than the socket because that is what
// a client acts on.
test("/v1/challenge closes the connection it answers", async () => {
  const ca = await createTestCA();
  await withAttestServer(
    async (base) => {
      const response = await fetch(`${base}/v1/challenge`, { method: "POST" });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get("connection"), "close");
    },
    { rootPem: ca.pem }
  );
});
