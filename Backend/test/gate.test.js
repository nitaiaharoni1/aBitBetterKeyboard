// The gate is the only thing between a public URL and this project's Vertex
// bill, so every branch of it is pinned here. An auth check nobody tests is
// worse than no auth check, because it looks like protection.

import assert from "node:assert/strict";
import test from "node:test";
import {
  authorize,
  bearerToken,
  callerKey,
  createAuthorizer,
  createRateLimiter,
  ServiceMode
} from "../src/gate.js";

test("a service with no token configured accepts everyone", async () => {
  // The lower-level primitive used only by the explicit local-open policy.
  assert.deepEqual(await authorize({ expectedToken: null, headers: {} }), {
    ok: true,
    deviceId: null
  });
});

test("production refuses to exist without a session verifier", () => {
  assert.throws(
    () => createAuthorizer({ mode: ServiceMode.PRODUCTION }),
    /requires session verification/
  );
});

test("production refuses a shared developer-token fallback", () => {
  assert.throws(
    () =>
      createAuthorizer({
        mode: ServiceMode.PRODUCTION,
        verifySession: acceptsOnly("good"),
        developerToken: "shared"
      }),
    /forbids BACKEND_TOKEN/
  );
});

test("production rejects a session verifier refusal instead of failing open", async () => {
  const authorizeRequest = createAuthorizer({
    mode: ServiceMode.PRODUCTION,
    verifySession: acceptsOnly("good")
  });
  const result = await authorizeRequest({ authorization: "Bearer wrong" });
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
});

test("a configured token accepts the matching bearer and nothing else", async () => {
  const expectedToken = "s3cret-value";

  assert.equal(
    (await authorize({ expectedToken, headers: { authorization: "Bearer s3cret-value" } })).ok,
    true
  );
  assert.equal(
    (await authorize({ expectedToken, headers: { authorization: "bearer s3cret-value" } })).ok,
    true
  );

  for (const headers of [
    {},
    { authorization: "" },
    { authorization: "Bearer" },
    { authorization: "Bearer wrong" },
    { authorization: "Bearer s3cret-valu" }, // one character short
    { authorization: "Bearer s3cret-values" }, // one character long
    { authorization: "s3cret-value" }, // right value, no scheme
    { authorization: "Basic s3cret-value" }
  ]) {
    const result = await authorize({ expectedToken, headers });
    assert.equal(result.ok, false, `accepted ${JSON.stringify(headers)}`);
    // 401, because the client maps it to "cloud not configured" — from the
    // app's side a backend it cannot authenticate to is one it does not have.
    assert.equal(result.status, 401);
  }
});

// ── The attested path ──────────────────────────────────────────────────────

/// Stands in for `sessionToken.verifySession`. The real one is pinned by its own
/// suite; what is being tested here is which of the two doors `authorize` tries
/// and what it reports back, not JWT verification a second time.
const acceptsOnly = (good) => async (token) =>
  token === good ? { ok: true, deviceId: "device-1" } : { ok: false };

test("a valid session token is accepted and names its device", async () => {
  const result = await authorize({
    expectedToken: "shared",
    headers: { authorization: "Bearer good" },
    verifySession: acceptsOnly("good")
  });
  assert.deepEqual(result, { ok: true, deviceId: "device-1" });
});

test("the shared token still works beside session tokens", async () => {
  const result = await authorize({
    expectedToken: "shared",
    headers: { authorization: "Bearer shared" },
    verifySession: acceptsOnly("good")
  });
  // No device: this token is shared by definition, so its callers stay counted
  // by address.
  assert.deepEqual(result, { ok: true, deviceId: null });
});

test("a bearer that is neither is refused", async () => {
  const result = await authorize({
    expectedToken: "shared",
    headers: { authorization: "Bearer neither" },
    verifySession: acceptsOnly("good")
  });
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
});

test("a session token is not accepted when no verifier was wired in", async () => {
  // Guards the wiring: a `createServer` that forgot to pass `verifySession`
  // would otherwise fail open on whatever the shared token happens to be.
  const result = await authorize({
    expectedToken: "shared",
    headers: { authorization: "Bearer good" }
  });
  assert.equal(result.ok, false);
});

test("the caller key is the device when there is one", () => {
  const req = { headers: { "x-forwarded-for": "1.2.3.4" }, socket: {} };
  assert.equal(callerKey(req, "device-1"), "device:device-1");
});

test("the caller key falls back to the address when there is not", () => {
  const req = { headers: { "x-forwarded-for": "1.2.3.4" }, socket: {} };
  assert.equal(callerKey(req, null), "1.2.3.4");
});

// **The reason for the `device:` prefix.** `x-forwarded-for` is a header the
// caller writes, so without a namespace anyone could set it to a device id and
// share, or drain, that device's allowance.
test("a device and an address can never collide in the limiter", () => {
  const req = { headers: { "x-forwarded-for": "device-1" }, socket: {} };
  assert.notEqual(callerKey(req, "device-1"), callerKey(req, null));
});

test("bearerToken tolerates the whitespace a real header carries", () => {
  assert.equal(bearerToken({ authorization: "  Bearer   abc  " }), "abc");
  assert.equal(bearerToken({ Authorization: "Bearer abc" }), "abc");
  assert.equal(bearerToken({}), null);
  assert.equal(bearerToken(undefined), null);
});

test("the rate limiter allows a burst up to the cap and then refuses", () => {
  let now = 1_000;
  const limiter = createRateLimiter({ windowMs: 60_000, maxPerWindow: 3, now: () => now });

  assert.equal(limiter.check("a").ok, true);
  assert.equal(limiter.check("a").ok, true);
  assert.equal(limiter.check("a").ok, true);

  const refused = limiter.check("a");
  assert.equal(refused.ok, false);
  assert.equal(refused.status, 429);
  assert.ok(refused.retryAfterSeconds >= 1, "a 429 has to say when to come back");
});

test("callers are counted separately", () => {
  let now = 1_000;
  const limiter = createRateLimiter({ windowMs: 60_000, maxPerWindow: 1, now: () => now });

  assert.equal(limiter.check("a").ok, true);
  assert.equal(limiter.check("a").ok, false);
  assert.equal(limiter.check("b").ok, true, "one caller's burst must not lock out another");
});

test("the window reopens", () => {
  let now = 1_000;
  const limiter = createRateLimiter({ windowMs: 60_000, maxPerWindow: 1, now: () => now });

  assert.equal(limiter.check("a").ok, true);
  assert.equal(limiter.check("a").ok, false);

  now += 60_001;
  assert.equal(limiter.check("a").ok, true);
});

test("expired counters are swept, so the map is not a memory leak", () => {
  // A Map keyed by remote address that never forgets is an unbounded
  // allocation on a service that sees many IPs — the exact shape of leak a
  // rate limiter is supposed to prevent, in the rate limiter.
  let now = 1_000;
  const limiter = createRateLimiter({ windowMs: 1_000, maxPerWindow: 10, now: () => now });

  for (let i = 0; i < 500; i += 1) limiter.check(`caller-${i}`);
  assert.equal(limiter.size, 500);

  now += 5_000;
  limiter.check("someone-else");
  assert.equal(limiter.size, 1, "every expired counter should be gone, not just the one checked");
});

test("the caller key prefers x-forwarded-for, because Cloud Run proxies", () => {
  // Without this every request arrives from the load balancer and the limiter
  // rate-limits the entire world as a single caller.
  assert.equal(
    callerKey({ headers: { "x-forwarded-for": "203.0.113.7, 130.211.0.1" }, socket: { remoteAddress: "10.0.0.1" } }),
    "203.0.113.7"
  );
  assert.equal(callerKey({ headers: {}, socket: { remoteAddress: "10.0.0.1" } }), "10.0.0.1");
  assert.equal(callerKey({ headers: {} }), "unknown");
});
