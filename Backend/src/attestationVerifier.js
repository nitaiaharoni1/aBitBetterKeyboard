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

/// Every 32-byte octet string in Apple's nonce extension, most likely first.
///
/// **Deliberately tolerant about *locating* the nonce, and that is not a
/// weakness.** Apple documents this extension as a DER sequence containing "the
/// single octet string", and the shape everything in the wild sends is
/// `SEQUENCE { [1] { OCTET STRING } }` — 38 bytes, which is what the exact
/// branch below matches. But nothing here has yet seen a blob from a real Secure
/// Enclave, so a parser that insisted on those exact offsets would reject every
/// real device if Apple nests it one layer differently, and it would do it with
/// a message about a malformed extension rather than about the guess that was
/// wrong.
///
/// Leniency costs nothing because the caller does not *trust* what this
/// returns — it compares each candidate against a nonce it computed itself from
/// `authData` and the challenge. Handing back the wrong 32 bytes fails that
/// comparison. An attacker cannot gain by having their nonce found somewhere
/// unusual; it still has to equal SHA-256 of their own authData and a challenge
/// this service issued.
function noncesFromExtension(value) {
  const bytes = Buffer.from(value);
  const candidates = [];

  // The documented shape, first, so the ordinary case is an exact match rather
  // than a scan.
  if (
    bytes.length === 38 &&
    bytes[0] === 0x30 &&
    bytes[2] === 0xa1 &&
    bytes[4] === 0x04 &&
    bytes[5] === 32
  ) {
    candidates.push(bytes.subarray(6, 38));
  }

  // Then any other 32-byte octet string in the value, for the shapes this has
  // not been shown a real example of.
  for (let i = 0; i + 34 <= bytes.length; i += 1) {
    if (bytes[i] === 0x04 && bytes[i + 1] === 32) {
      candidates.push(bytes.subarray(i + 2, i + 34));
    }
  }
  return candidates;
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

      // **Validity first, so an expired certificate says so.** `verify()` in
      // `@peculiar/x509` already checks the subject certificate's own dates
      // unless `signatureOnly` is passed, so leaving this below the signature
      // checks made it unreachable in practice: an expired leaf came back as
      // "not signed as it claims", which is a false statement about a
      // perfectly good signature and a full day of debugging for whoever reads
      // it. Asked here, it is both accurate and the first thing tried.
      const asOf = new Date();
      for (const certificate of chain) {
        if (asOf < certificate.notBefore || asOf > certificate.notAfter) {
          return refuse("certificate chain contains an expired certificate");
        }
      }

      if (!Buffer.from(intermediate.rawData).equals(Buffer.from(root.rawData))) {
        // **Signed by the root is not the same as allowed to sign, and only the
        // second one is what "verify the chain" means.** Without this, any
        // certificate the root ever issued — including a leaf, which is not a
        // certificate authority and carries no `keyCertSign` — could occupy the
        // intermediate slot and vouch for an attestation. Nobody can exploit it
        // today, because both links still need Apple's private key and nobody
        // outside Apple has one. It becomes load-bearing the moment Apple's
        // hierarchy changes or this verifier is pointed at a second root, which
        // is exactly when nobody will be looking at it.
        const constraints = intermediate.getExtension(x509.BasicConstraintsExtension);
        if (constraints?.ca !== true) {
          return refuse("certificate chain is signed by a certificate that is not a CA");
        }
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

      // 3, 4. The nonce Apple bound into the leaf when it issued it.
      const clientDataHash = createHash("sha256").update(challenge).digest();
      const expectedNonce = createHash("sha256")
        .update(Buffer.concat([parsed.authData, clientDataHash]))
        .digest();

      // 5.
      const extension = leaf.getExtension(NONCE_OID);
      if (!extension) return refuse("attestation carries no nonce extension");
      const candidates = noncesFromExtension(extension.value);
      if (candidates.length === 0) return refuse("attestation nonce extension is malformed");
      if (!candidates.some((candidate) => candidate.equals(expectedNonce))) {
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
