import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createAttestationVerifier } from "../src/attestationVerifier.js";
import { buildFakeAttestation } from "./helpers/fakeAttestation.js";

const APP_ID = "9R8P28G4BJ.com.nitai.aikeyboard";

function verifierFor(fixture, overrides = {}) {
  return createAttestationVerifier({
    rootCertificatePem: fixture.rootPem,
    appId: APP_ID,
    environment: "development",
    ...overrides
  });
}

// ── The two that have to pass ──────────────────────────────────────────────
//
// Without these, every rejection below is worthless: a verifier whose `verify`
// is `return { ok: false, reason: "no" }` satisfies all nine of them. This repo
// has shipped three tests that passed against the bug they were named after, so
// the accepting case is written first and deliberately.

test("a valid attestation is accepted and names the device", async () => {
  const fixture = await buildFakeAttestation({ appId: APP_ID });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, true, `expected acceptance, got: ${result.reason}`);
  assert.equal(result.deviceId, fixture.keyId);
});

test("production accepts a production attestation", async () => {
  const fixture = await buildFakeAttestation({ aaguid: "appattest" });
  const result = await verifierFor(fixture, { environment: "production" }).verify(fixture);
  assert.equal(result.ok, true, `expected acceptance, got: ${result.reason}`);
});

// ── The nine rejections, one per check ─────────────────────────────────────

test("an attestation for another app is refused", async () => {
  const fixture = await buildFakeAttestation({ appId: "9R8P28G4BJ.com.someone.else" });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /app id/i);
});

test("an attestation raised for a different challenge is refused", async () => {
  const fixture = await buildFakeAttestation();
  const result = await verifierFor(fixture).verify({ ...fixture, challenge: "some other nonce" });
  assert.equal(result.ok, false);
  assert.match(result.reason, /nonce/i);
});

test("a key id that is not the hash of the attested key is refused", async () => {
  const fixture = await buildFakeAttestation();
  const result = await verifierFor(fixture).verify({
    ...fixture,
    keyId: createHash("sha256").update("something else").digest("base64")
  });
  assert.equal(result.ok, false);
  assert.match(result.reason, /key id/i);
});

test("a used key is refused: the counter must be zero at attestation", async () => {
  const fixture = await buildFakeAttestation({ signCount: 3 });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /counter/i);
});

test("production refuses a development attestation", async () => {
  const fixture = await buildFakeAttestation({ aaguid: "appattestdevelop" });
  const result = await verifierFor(fixture, { environment: "production" }).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /environment/i);
});

test("a chain that does not reach our root is refused", async () => {
  const fixture = await buildFakeAttestation();
  const other = await buildFakeAttestation();
  const result = await verifierFor(other).verify(fixture); // trusts a different root
  assert.equal(result.ok, false);
  assert.match(result.reason, /chain/i);
});

test("a leaf that signed itself is refused", async () => {
  const fixture = await buildFakeAttestation({ signLeafWithRoot: false });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /chain/i);
});

test("a credential id that disagrees with the key id is refused", async () => {
  const fixture = await buildFakeAttestation({ credentialIdOverride: Buffer.alloc(32, 9) });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /credential|key id/i);
});

test("a nonce extension that is the right length but the wrong shape is refused", async () => {
  const fixture = await buildFakeAttestation({ nonceOverride: Buffer.alloc(32, 1) });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /nonce/i);
});

// ── Malformed input is refused, never thrown ───────────────────────────────
//
// The verify path sits in front of an unauthenticated route. Anything that
// throws out of it is a 500 the caller can produce at will.

test("malformed bytes are refused rather than thrown", async () => {
  const fixture = await buildFakeAttestation();
  const result = await verifierFor(fixture).verify({
    ...fixture,
    attestation: Buffer.from("nonsense")
  });
  assert.equal(result.ok, false);
});

test("a missing key id or challenge is refused rather than thrown", async () => {
  const fixture = await buildFakeAttestation();
  const verifier = verifierFor(fixture);
  assert.equal((await verifier.verify({ ...fixture, keyId: undefined })).ok, false);
  assert.equal((await verifier.verify({ ...fixture, challenge: undefined })).ok, false);
  assert.equal((await verifier.verify({ ...fixture, keyId: "not base64 at all!!" })).ok, false);
});

test("an unknown environment is refused at construction, not at verify time", () => {
  assert.throws(
    () => createAttestationVerifier({ rootCertificatePem: "x", appId: "y", environment: "staging" }),
    /environment/
  );
});
