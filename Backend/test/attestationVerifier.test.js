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

// ── The nonce locator ──────────────────────────────────────────────────────
//
// Nothing here has yet seen a blob from a real Secure Enclave, so the exact DER
// nesting Apple sends is the one assumption in this file that has not been
// measured. The locator is therefore tolerant about *where* it finds the nonce,
// and the verifier stays strict about *what* it equals. These two pin both
// halves: an unusual nesting still verifies, and a wrong nonce still fails
// however deeply it is wrapped.
//
// Only the wrapping varies. The nonce itself stays correct by construction,
// because a nonce computed for one attestation can never match another's.

/// One more SEQUENCE than Apple is believed to send.
function wrappedOneLayerDeeper(nonce) {
  const octetString = Buffer.concat([Buffer.from([0x04, nonce.length]), nonce]);
  const inner = Buffer.concat([Buffer.from([0x30, octetString.length]), octetString]);
  return Buffer.concat([Buffer.from([0x30, inner.length]), inner]);
}

test("a nonce nested one layer deeper than expected is still found", async () => {
  const fixture = await buildFakeAttestation({ nonceWrapper: wrappedOneLayerDeeper });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, true, `expected acceptance, got: ${result.reason}`);
});

test("a wrong nonce is still refused however deeply it is wrapped", async () => {
  const fixture = await buildFakeAttestation({
    nonceOverride: Buffer.alloc(32, 7),
    nonceWrapper: wrappedOneLayerDeeper
  });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /nonce/i);
});

// ── The chain shape a real device actually sends ───────────────────────────
//
// Apple's x5c is always [leaf, intermediate], with the root kept out of it. The
// fixtures above use the flatter two-certificate form, which makes x5c[1]
// byte-identical to the trusted root — and the verifier short-circuits that
// case, so none of them ever exercise the intermediate-to-root link that every
// real attestation depends on. These do.

test("a real-shaped chain, leaf under a distinct intermediate under the root, is accepted", async () => {
  const fixture = await buildFakeAttestation({ withIntermediate: true });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, true, `expected acceptance, got: ${result.reason}`);
  assert.equal(result.deviceId, fixture.keyId);
});

test("a real-shaped chain whose intermediate is not signed by our root is refused", async () => {
  const fixture = await buildFakeAttestation({ withIntermediate: true });
  const other = await buildFakeAttestation({ withIntermediate: true });
  const result = await verifierFor(other).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /trusted root/i);
});

// **Signed by the root is not the same as allowed to sign.** This intermediate
// is genuinely signed by the trusted root and still must be refused, because it
// is marked CA:false. Nobody can reach this from outside without Apple's private
// key; it matters the day the hierarchy changes.
test("an intermediate that is not marked as a CA is refused even though the root signed it", async () => {
  const fixture = await buildFakeAttestation({ withIntermediate: true, intermediateIsCA: false });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /not a CA/i);
});

// The expiry branch, which had no coverage at all while it sat below the
// signature checks and was therefore unreachable: `@peculiar/x509` rejects an
// expired certificate inside `verify()` unless `signatureOnly` is passed, so an
// expired leaf used to come back as "not signed as it claims" — a false
// statement about a perfectly good signature.
test("an expired leaf is refused, and refused for being expired", async () => {
  const fixture = await buildFakeAttestation({ leafNotAfter: new Date("2021-01-01") });
  const result = await verifierFor(fixture).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /expired/i);
});
