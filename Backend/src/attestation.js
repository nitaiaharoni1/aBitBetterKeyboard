// Bytes in, fields out.
//
// **No policy lives here.** This file will happily parse an attestation for the
// wrong app, in the wrong environment, with a counter of 900 — and
// attestationVerifier.js is what refuses it. Splitting them that way is what
// lets each rejection test name the check that fired instead of asserting
// "something went wrong somewhere".

import { decode } from "cbor-x";

export const AAGUID_DEVELOPMENT = "appattestdevelop";
export const AAGUID_PRODUCTION = "appattest";
export const NONCE_OID = "1.2.840.113635.100.8.2";

// rpIdHash(32) + flags(1) + signCount(4) + aaguid(16) + credentialIdLength(2)
const CREDENTIAL_ID_OFFSET = 55;

export function parseAttestation(bytes) {
  let decoded;
  try {
    decoded = decode(bytes);
  } catch {
    throw new Error("attestation could not be decoded");
  }

  if (decoded?.fmt !== "apple-appattest") {
    throw new Error("attestation fmt is not apple-appattest");
  }

  const x5c = decoded?.attStmt?.x5c;
  if (!Array.isArray(x5c) || x5c.length < 2) {
    throw new Error("attestation carries no certificate chain");
  }

  const authData = decoded.authData;
  if (!Buffer.isBuffer(authData) && !(authData instanceof Uint8Array)) {
    throw new Error("attestation authData is missing");
  }
  const auth = Buffer.from(authData);
  if (auth.length < CREDENTIAL_ID_OFFSET) {
    throw new Error("attestation authData is too short");
  }

  const credentialIdLength = auth.readUInt16BE(53);
  const credentialIdEnd = CREDENTIAL_ID_OFFSET + credentialIdLength;
  if (auth.length < credentialIdEnd) {
    throw new Error("attestation authData is too short for the credential it declares");
  }

  return {
    fmt: decoded.fmt,
    x5c: x5c.map((certificate) => Buffer.from(certificate)),
    receipt: decoded.attStmt.receipt ? Buffer.from(decoded.attStmt.receipt) : null,
    authData: auth,
    rpIdHash: auth.subarray(0, 32),
    flags: auth[32],
    signCount: auth.readUInt32BE(33),
    // Trailing NULs are padding, not part of the name: Apple pads "appattest"
    // out to sixteen bytes, and "appattestdevelop" fills them exactly.
    aaguid: auth.subarray(37, 53).toString("binary").replace(/\0+$/, ""),
    credentialId: auth.subarray(CREDENTIAL_ID_OFFSET, credentialIdEnd)
  };
}
