import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { encode } from "cbor-x";
import { parseAttestation } from "../src/attestation.js";
import { buildFakeAttestation } from "./helpers/fakeAttestation.js";

test("a valid attestation parses into its parts", async () => {
  const { attestation, keyId } = await buildFakeAttestation();
  const parsed = parseAttestation(attestation);

  assert.equal(parsed.fmt, "apple-appattest");
  assert.equal(parsed.x5c.length, 2);
  assert.equal(parsed.signCount, 0);
  assert.equal(parsed.aaguid, "appattestdevelop");
  assert.equal(parsed.credentialId.toString("base64"), keyId);
  assert.equal(parsed.rpIdHash.length, 32);
});

test("the app id hash is the one the app id produces", async () => {
  const appId = "9R8P28G4BJ.com.nitai.aikeyboard";
  const { attestation } = await buildFakeAttestation({ appId });
  const parsed = parseAttestation(attestation);
  assert.deepEqual(parsed.rpIdHash, createHash("sha256").update(appId).digest());
});

// The parser must hand the verifier what is actually there. A parser that
// normalised a used key's counter to zero would make the verifier's counter
// check unreachable, and the check would pass its own test forever.
test("a non-zero counter survives parsing rather than being normalised away", async () => {
  const { attestation } = await buildFakeAttestation({ signCount: 7 });
  assert.equal(parseAttestation(attestation).signCount, 7);
});

test("a production AAGUID reads as production, without its padding", async () => {
  const { attestation } = await buildFakeAttestation({ aaguid: "appattest" });
  assert.equal(parseAttestation(attestation).aaguid, "appattest");
});

test("bytes that are not CBOR are rejected", () => {
  assert.throws(() => parseAttestation(Buffer.from("nonsense")), /could not be decoded/);
});

test("a CBOR object that is not an attestation is rejected", () => {
  assert.throws(() => parseAttestation(Buffer.from(encode({ hello: "world" }))), /fmt/);
});

test("an attestation with no chain is rejected", () => {
  const noChain = encode({
    fmt: "apple-appattest",
    attStmt: { x5c: [Buffer.alloc(4)], receipt: Buffer.alloc(0) },
    authData: Buffer.alloc(87)
  });
  assert.throws(() => parseAttestation(Buffer.from(noChain)), /certificate chain/);
});

test("authData too short to hold its own fields is rejected", () => {
  const truncated = encode({
    fmt: "apple-appattest",
    attStmt: { x5c: [Buffer.alloc(4), Buffer.alloc(4)], receipt: Buffer.alloc(0) },
    authData: Buffer.alloc(40)
  });
  assert.throws(() => parseAttestation(Buffer.from(truncated)), /authData is too short/);
});

test("authData that declares a credential longer than itself is rejected", () => {
  const authData = Buffer.alloc(87);
  authData.writeUInt16BE(9999, 53);
  const lying = encode({
    fmt: "apple-appattest",
    attStmt: { x5c: [Buffer.alloc(4), Buffer.alloc(4)], receipt: Buffer.alloc(0) },
    authData
  });
  assert.throws(() => parseAttestation(Buffer.from(lying)), /too short for the credential/);
});
