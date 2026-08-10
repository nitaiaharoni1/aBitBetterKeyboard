// The ten checks Apple documents, in the order Apple documents them.
//
// **Everything here returns { ok: false, reason } rather than throwing, and the
// reason never leaves this process.** httpServer.js logs it and answers a single
// "attestation refused" to every one of the ten. A 401 that says which check
// failed is a tutorial for the person trying to get past it.
//
// The root is a parameter rather than an import so the tests can bring their own
// certificate authority. There is no other way to test the accepting path: a
// real attestation needs a real Secure Enclave, and a blob recorded off a device
// is frozen at one app id and one nonce.

// Must precede the @peculiar/x509 import; see test/helpers/fakeAttestation.js.
import "reflect-metadata";

import { createHash, webcrypto } from "node:crypto";
import * as x509 from "@peculiar/x509";
import {
  AAGUID_DEVELOPMENT,
  AAGUID_PRODUCTION,
  NONCE_OID,
  parseAttestation
} from "./attestation.js";

x509.cryptoProvider.set(webcrypto);

function refuse(reason) {
  return { ok: false, reason };
}

/// Apple's extension value is SEQUENCE { [1] { OCTET STRING nonce } }.
///
/// Parsed by shape rather than by "take the last 32 bytes", so a malformed
/// extension is refused instead of quietly yielding whatever happened to sit at
/// the end of it.
function nonceFromExtension(value) {
  const bytes = Buffer.from(value);
  if (bytes.length !== 38) return null;
  if (bytes[0] !== 0x30 || bytes[2] !== 0xa1 || bytes[4] !== 0x04 || bytes[5] !== 32) return null;
  return bytes.subarray(6, 38);
}

/// The 65-byte uncompressed point at the end of an EC SPKI.
///
/// Length-checked rather than assumed: a key on a curve that is not P-256 would
/// slice to the wrong bytes, and the hash of the wrong bytes is a key id that
/// never matches — a refusal for the wrong reason, which is the kind that costs
/// a day to read.
function uncompressedPoint(certificate) {
  const spki = Buffer.from(certificate.publicKey.rawData);
  const point = spki.subarray(-65);
  if (point.length !== 65 || point[0] !== 0x04) return null;
  return point;
}

export function createAttestationVerifier({ rootCertificatePem, appId, environment }) {
  if (!rootCertificatePem || !appId) {
    throw new Error("an attestation verifier needs a root certificate and an app id");
  }
  if (environment !== "development" && environment !== "production") {
    throw new Error(`unknown attestation environment: ${environment}`);
  }

  const root = new x509.X509Certificate(rootCertificatePem);
  const expectedAaguid = environment === "production" ? AAGUID_PRODUCTION : AAGUID_DEVELOPMENT;
  const expectedRpIdHash = createHash("sha256").update(appId).digest();

  return {
    async verify({ attestation, keyId, challenge }) {
      // 1. Decode.
      let parsed;
      try {
        parsed = parseAttestation(attestation);
      } catch (error) {
        return refuse(error.message);
      }

      if (typeof keyId !== "string" || typeof challenge !== "string") {
        return refuse("key id and challenge must both be strings");
      }
      const expectedKeyId = Buffer.from(keyId, "base64");
      if (expectedKeyId.length !== 32) return refuse("key id is not a 32 byte hash");

      // 2. The chain: leaf signed by the next certificate, and the chain ends at
      //    the root we trust. Compared by raw bytes, never by subject name — a
      //    name is something the attacker chooses.
      let chain;
      try {
        chain = parsed.x5c.map((der) => new x509.X509Certificate(new Uint8Array(der)));
      } catch {
        return refuse("certificate chain could not be parsed");
      }
      const leaf = chain[0];
      const intermediate = chain[1];

      if (!Buffer.from(intermediate.rawData).equals(Buffer.from(root.rawData))) {
        try {
          if (!(await intermediate.verify({ publicKey: root.publicKey }))) {
            return refuse("certificate chain does not reach the trusted root");
          }
        } catch {
          return refuse("certificate chain does not reach the trusted root");
        }
      }
      try {
        if (!(await leaf.verify({ publicKey: intermediate.publicKey }))) {
          return refuse("certificate chain is not signed as it claims");
        }
      } catch {
        return refuse("certificate chain is not signed as it claims");
      }

      const asOf = new Date();
      for (const certificate of chain) {
        if (asOf < certificate.notBefore || asOf > certificate.notAfter) {
          return refuse("certificate chain contains an expired certificate");
        }
      }

      // 3, 4. The nonce Apple bound into the leaf when it issued it.
      const clientDataHash = createHash("sha256").update(challenge).digest();
      const expectedNonce = createHash("sha256")
        .update(Buffer.concat([parsed.authData, clientDataHash]))
        .digest();

      // 5.
      const extension = leaf.getExtension(NONCE_OID);
      if (!extension) return refuse("attestation carries no nonce extension");
      const nonce = nonceFromExtension(extension.value);
      if (!nonce) return refuse("attestation nonce extension is malformed");
      if (!nonce.equals(expectedNonce)) {
        return refuse("attestation nonce does not match the challenge");
      }

      // 6.
      const point = uncompressedPoint(leaf);
      if (!point) return refuse("attested key is not an uncompressed P-256 point");
      if (!createHash("sha256").update(point).digest().equals(expectedKeyId)) {
        return refuse("key id is not the hash of the attested key");
      }

      // 7.
      if (!parsed.rpIdHash.equals(expectedRpIdHash)) {
        return refuse("attestation names a different app id");
      }

      // 8. A key that has been used before was not freshly generated for this
      //    attestation.
      if (parsed.signCount !== 0) return refuse("attested key has a non-zero counter");

      // 9. Production accepts only production. A development build must not be
      //    able to mint a token against the deployed service.
      if (parsed.aaguid !== expectedAaguid) {
        return refuse(`attestation is from the wrong environment: ${parsed.aaguid}`);
      }

      // 10.
      if (!parsed.credentialId.equals(expectedKeyId)) {
        return refuse("credential id does not match the key id");
      }

      return { ok: true, deviceId: keyId };
    }
  };
}
