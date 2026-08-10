import { test } from "node:test";
import assert from "node:assert/strict";
import { createTokens, SESSION_TTL_MS, CHALLENGE_TTL_MS } from "../src/sessionToken.js";

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
