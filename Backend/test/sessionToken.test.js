import { test } from "node:test";
import assert from "node:assert/strict";
import {
  createTokens,
  SESSION_TTL_MS,
  CHALLENGE_TTL_MS,
  SessionRejectReason
} from "../src/sessionToken.js";

const SECRET = "a".repeat(64);

function at(ms) {
  return createTokens({ secret: SECRET, now: () => ms });
}

test("a freshly signed challenge verifies", async () => {
  const tokens = at(1_000_000);
  assert.equal(await tokens.verifyChallenge(await tokens.signChallenge()), true);
});

test("a challenge stops verifying once its window has passed", async () => {
  const challenge = await at(1_000_000).signChallenge();
  assert.equal(await at(1_000_000 + CHALLENGE_TTL_MS + 60_000).verifyChallenge(challenge), false);
});

test("a session token carries the device it was issued to", async () => {
  const tokens = at(1_000_000);
  const { token } = await tokens.signSession("device-abc");
  assert.deepEqual(await tokens.verifySession(token), { ok: true, deviceId: "device-abc" });
});

test("a session token reports when it expires", async () => {
  const { expiresAt } = await at(1_000_000).signSession("device-abc");
  assert.equal(expiresAt, new Date(1_000_000 + SESSION_TTL_MS).toISOString());
});

test("a session token stops verifying after ninety days", async () => {
  const { token } = await at(1_000_000).signSession("device-abc");
  const later = at(1_000_000 + SESSION_TTL_MS + 60_000);
  assert.equal((await later.verifySession(token)).ok, false);
});

test("a session token signed with another secret is refused", async () => {
  const { token } = await at(1_000_000).signSession("device-abc");
  const other = createTokens({ secret: "b".repeat(64), now: () => 1_000_000 });
  assert.equal((await other.verifySession(token)).ok, false);
});

// **The pair that stops the gate being an open door.** Both tokens are signed
// with one secret, so without the audience claim a caller could take the free
// 5-minute challenge and present it as a 90-day session token. A verifier that
// checks only the signature passes every other test in this file.
test("a challenge is not accepted as a session token", async () => {
  const tokens = at(1_000_000);
  const challenge = await tokens.signChallenge();
  assert.equal((await tokens.verifySession(challenge)).ok, false);
});

test("a session token is not accepted as a challenge", async () => {
  const tokens = at(1_000_000);
  const { token } = await tokens.signSession("device-abc");
  assert.equal(await tokens.verifyChallenge(token), false);
});

test("garbage verifies as nothing", async () => {
  const tokens = at(1_000_000);
  assert.equal((await tokens.verifySession("not.a.jwt")).ok, false);
  assert.equal((await tokens.verifySession("")).ok, false);
  assert.equal(await tokens.verifyChallenge(""), false);
  assert.equal(await tokens.verifyChallenge(null), false);
});

test("a secret too short to be one is refused at construction", () => {
  assert.throws(() => createTokens({ secret: "short" }), /at least 32/);
  assert.throws(() => createTokens({ secret: undefined }), /at least 32/);
});

// ── Rejection reasons ───────────────────────────────────────────────────────
//
// The closed set `httpServer.js` logs a session refusal with (NIT-87): the
// service used to say nothing when a bearer failed, which left "Full Access
// is off" and "SESSION_SECRET rotated" indistinguishable from the logs alone.

test("an expired session token is refused as expired", async () => {
  const { token } = await at(1_000_000).signSession("device-abc");
  const later = at(1_000_000 + SESSION_TTL_MS + 60_000);
  assert.deepEqual(await later.verifySession(token), {
    ok: false,
    reason: SessionRejectReason.EXPIRED
  });
});

test("garbage is refused as malformed, not as a bad signature", async () => {
  const tokens = at(1_000_000);
  assert.deepEqual(await tokens.verifySession("not.a.jwt"), {
    ok: false,
    reason: SessionRejectReason.MALFORMED
  });
  assert.deepEqual(await tokens.verifySession(""), {
    ok: false,
    reason: SessionRejectReason.MALFORMED
  });
});

test("a session token signed with another secret is refused as a bad signature", async () => {
  const { token } = await at(1_000_000).signSession("device-abc");
  const other = createTokens({ secret: "b".repeat(64), now: () => 1_000_000 });
  assert.deepEqual(await other.verifySession(token), {
    ok: false,
    reason: SessionRejectReason.BAD_SIGNATURE
  });
});

test("a challenge presented as a session token is refused as a bad signature", async () => {
  const tokens = at(1_000_000);
  const challenge = await tokens.signChallenge();
  assert.deepEqual(await tokens.verifySession(challenge), {
    ok: false,
    reason: SessionRejectReason.BAD_SIGNATURE
  });
});

// ── Rotating SESSION_SECRET without logging every device out ───────────────
//
// Nothing persists `SESSION_SECRET` across a `deploy.sh` run — it is read
// fresh from the shell environment on every invocation and handed to Cloud
// Run with `--set-env-vars`. A second deploy that does not reuse the exact
// same value invalidates every outstanding session token the instant the new
// revision starts serving, which is one of the two mechanisms NIT-87 could
// not rule out from the traffic logs alone. `previousSecrets` is the grace
// window: a redeploy can rotate the secret and still honour tokens signed
// under the one before it.

test("a token signed under the previous secret still verifies during the grace window", async () => {
  const oldSecret = "a".repeat(64);
  const newSecret = "b".repeat(64);
  const { token } = await createTokens({ secret: oldSecret, now: () => 1_000_000 })
    .signSession("device-abc");

  const rotated = createTokens({
    secret: newSecret,
    previousSecrets: [oldSecret],
    now: () => 1_000_000
  });
  assert.deepEqual(await rotated.verifySession(token), { ok: true, deviceId: "device-abc" });
});

test("a fresh token is signed with the current secret, not a previous one", async () => {
  const oldSecret = "a".repeat(64);
  const newSecret = "b".repeat(64);
  const rotated = createTokens({
    secret: newSecret,
    previousSecrets: [oldSecret],
    now: () => 1_000_000
  });
  const { token } = await rotated.signSession("device-abc");

  // Verifies under the new secret alone, with no previous secret in play —
  // proves `sign` never reaches for anything but `key`.
  const newOnly = createTokens({ secret: newSecret, now: () => 1_000_000 });
  assert.deepEqual(await newOnly.verifySession(token), { ok: true, deviceId: "device-abc" });
});

test("a secret that is neither current nor previous is still refused", async () => {
  const { token } = await createTokens({ secret: "a".repeat(64), now: () => 1_000_000 })
    .signSession("device-abc");

  const rotated = createTokens({
    secret: "b".repeat(64),
    previousSecrets: ["c".repeat(64)],
    now: () => 1_000_000
  });
  assert.deepEqual(await rotated.verifySession(token), {
    ok: false,
    reason: SessionRejectReason.BAD_SIGNATURE
  });
});

test("the grace window does not extend an already-expired token", async () => {
  const oldSecret = "a".repeat(64);
  const { token } = await createTokens({ secret: oldSecret, now: () => 1_000_000 })
    .signSession("device-abc");

  const rotated = createTokens({
    secret: "b".repeat(64),
    previousSecrets: [oldSecret],
    now: () => 1_000_000 + SESSION_TTL_MS + 60_000
  });
  assert.deepEqual(await rotated.verifySession(token), {
    ok: false,
    reason: SessionRejectReason.EXPIRED
  });
});

test("a previous secret too short to be one is refused at construction", () => {
  assert.throws(
    () => createTokens({ secret: "a".repeat(64), previousSecrets: ["short"] }),
    /at least 32/
  );
});
