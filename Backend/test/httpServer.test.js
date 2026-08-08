import assert from "node:assert/strict";
import test from "node:test";
import { createServer } from "../src/httpServer.js";

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
