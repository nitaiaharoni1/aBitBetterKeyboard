// A valid attestation, minted locally, so the verifier can be shown to *accept*
// as well as reject.
//
// **There is no other way to get one.** A real attestation needs a real Secure
// Enclave, which no CI machine and no simulator has, and a blob recorded off a
// device is frozen at one app id, one environment and one nonce — useless for
// testing the checks that are supposed to reject. So the tests bring their own
// certificate authority and the verifier takes its root as a parameter.
//
// Every `...Override` below breaks exactly one of the verifier's ten checks, so
// a rejection test can say which one it is exercising rather than feeding in
// noise and asserting that something failed.

// `reflect-metadata` must be imported before `@peculiar/x509`, not beside it.
// That library resolves its own internals through tsyringe, which throws on
// load without the polyfill — so an import sorter that moves this line below
// the one under it breaks the whole suite with an error that names neither
// file.
import "reflect-metadata";

import { createHash, randomBytes, webcrypto } from "node:crypto";
import { encode } from "cbor-x";
import * as x509 from "@peculiar/x509";

x509.cryptoProvider.set(webcrypto);

export const NONCE_OID = "1.2.840.113635.100.8.2";

/// Apple's extension value is SEQUENCE { [1] { OCTET STRING nonce } }.
///
/// Every length here is under 128, so single-byte DER lengths are correct and a
/// long-form encoder would produce something Apple never sends.
export function nonceExtensionValue(nonce) {
  const octetString = Buffer.concat([Buffer.from([0x04, nonce.length]), nonce]);
  const tagged = Buffer.concat([Buffer.from([0xa1, octetString.length]), octetString]);
  return Buffer.concat([Buffer.from([0x30, tagged.length]), tagged]);
}

async function generateP256() {
  return webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
    "sign",
    "verify"
  ]);
}

/// The 65-byte uncompressed point, which is what Apple hashes to make the key id.
async function uncompressedPoint(publicKey) {
  const raw = Buffer.from(await webcrypto.subtle.exportKey("raw", publicKey));
  if (raw.length !== 65 || raw[0] !== 0x04) {
    throw new Error(`expected a 65-byte uncompressed point, got ${raw.length}`);
  }
  return raw;
}

/// A certificate authority the tests own.
///
/// **Separable from `buildFakeAttestation` because a round-trip test needs two
/// attestations under one root.** The server is constructed trusting a PEM, and
/// only then can it issue the challenge that the real attestation has to be
/// built against — so the CA has to outlive the fixture. Every call to
/// `buildFakeAttestation` without one mints a fresh CA, which is what the
/// "chain does not reach our root" rejection relies on.
export async function createTestCA() {
  const keys = await generateP256();
  const certificate = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: "CN=Test App Attest Root",
    notBefore: new Date("2020-01-01"),
    notAfter: new Date("2040-01-01"),
    keys,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-256" },
    extensions: [new x509.BasicConstraintsExtension(true, 1, true)]
  });
  return { keys, certificate, pem: certificate.toString("pem") };
}

export async function buildFakeAttestation({
  appId = "9R8P28G4BJ.com.nitai.aikeyboard",
  challenge = "test-challenge",
  aaguid = "appattestdevelop",
  signCount = 0,
  ca = null,
  rpIdHashOverride = null,
  credentialIdOverride = null,
  nonceOverride = null,
  // How the (correct) nonce gets wrapped into the certificate extension.
  // Varying the *wrapping* while the nonce stays right by construction is the
  // only honest way to test the locator: computing a nonce for one attestation
  // and injecting it into another can never match, because authData differs.
  nonceWrapper = nonceExtensionValue,
  // **The shape a real device sends.** Apple's `x5c` is always
  // [leaf, intermediate] with the root kept out of it, so the leaf is signed by
  // an intermediate and the intermediate by the root. The default here is the
  // flatter two-certificate chain, which is easier to build and which every
  // rejection test uses — but it makes `x5c[1]` byte-identical to the trusted
  // root, and the verifier short-circuits that case, so it never exercises the
  // one link every real attestation depends on.
  withIntermediate = false,
  // Separate from the above so the CA-flag rejection can be built at all: a
  // signer that is genuinely signed by the root but is not marked as a
  // certificate authority.
  intermediateIsCA = true,
  // So the expiry branch can be reached at all. It used to sit below the
  // signature checks, where `@peculiar/x509` had already rejected an expired
  // certificate inside `verify()` and it was unreachable dead code.
  leafNotAfter = new Date("2040-01-01"),
  signLeafWithRoot = true
} = {}) {
  const authority = ca ?? (await createTestCA());
  const rootKeys = authority.keys;
  const root = authority.certificate;
  const leafKeys = await generateP256();

  let issuerCertificate = root;
  let issuerKeys = rootKeys;
  if (withIntermediate) {
    const intermediateKeys = await generateP256();
    issuerCertificate = await x509.X509CertificateGenerator.create({
      serialNumber: "03",
      subject: "CN=Test Attestation Intermediate",
      issuer: root.subject,
      notBefore: new Date("2020-01-01"),
      notAfter: new Date("2040-01-01"),
      publicKey: intermediateKeys.publicKey,
      signingKey: rootKeys.privateKey,
      signingAlgorithm: { name: "ECDSA", hash: "SHA-256" },
      extensions: [
        intermediateIsCA
          ? new x509.BasicConstraintsExtension(true, 0, true)
          : new x509.BasicConstraintsExtension(false, undefined, true)
      ]
    });
    issuerKeys = intermediateKeys;
  }

  const point = await uncompressedPoint(leafKeys.publicKey);
  const keyId = createHash("sha256").update(point).digest();

  const rpIdHash = rpIdHashOverride ?? createHash("sha256").update(appId).digest();
  const credentialId = credentialIdOverride ?? keyId;

  const signCountBytes = Buffer.alloc(4);
  signCountBytes.writeUInt32BE(signCount);
  const credentialIdLength = Buffer.alloc(2);
  credentialIdLength.writeUInt16BE(credentialId.length);

  const authData = Buffer.concat([
    rpIdHash,
    Buffer.from([0x40]), // AT flag: attested credential data present
    signCountBytes,
    Buffer.from(aaguid.padEnd(16, "\0"), "binary"),
    credentialIdLength,
    credentialId
    // A COSE public key follows on a real device. The verifier takes the key
    // from the leaf certificate and never reads this, so the fixture leaves it
    // out rather than pretending to encode one it would never be checked
    // against.
  ]);

  const clientDataHash = createHash("sha256").update(challenge).digest();
  const nonce =
    nonceOverride ??
    createHash("sha256").update(Buffer.concat([authData, clientDataHash])).digest();

  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test Attestation Leaf",
    issuer: issuerCertificate.subject,
    notBefore: new Date("2020-01-01"),
    notAfter: leafNotAfter,
    publicKey: leafKeys.publicKey,
    signingKey: signLeafWithRoot ? issuerKeys.privateKey : leafKeys.privateKey,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-256" },
    extensions: [new x509.Extension(NONCE_OID, false, nonceWrapper(nonce))]
  });

  const attestation = encode({
    fmt: "apple-appattest",
    attStmt: {
      x5c: [Buffer.from(leaf.rawData), Buffer.from(issuerCertificate.rawData)],
      receipt: randomBytes(32)
    },
    authData
  });

  return {
    attestation: Buffer.from(attestation),
    keyId: keyId.toString("base64"),
    challenge,
    rootPem: root.toString("pem"),
    leafPem: leaf.toString("pem")
  };
}
