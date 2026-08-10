# App Attest Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the backend's shared-secret gate with Apple App Attest, so a cloud call is accepted because the hardware proved it came from this app, not because the caller knew a string.

**Architecture:** The containing app attests once, the backend verifies against Apple's root CA and returns a signed 90-day session token, and the app writes that token into the App Group slot the keyboard and broadcast extensions already read. No server-side storage: the challenge and the session token are both JWTs the backend signs and re-verifies. Refresh re-attests rather than using assertions, because assertion replay protection needs a stored counter.

**Tech Stack:** Node 22 (backend, `node --test`), Swift 6 / SwiftUI (app), Apple `DeviceCheck` framework, Cloud Run.

**Spec:** `docs/superpowers/specs/2026-08-10-app-attest-gate-design.md`

## Global Constraints

- **The app takes no third-party dependencies.** `AGENTS.md` line 1. `DeviceCheck` is an Apple framework. The three new dependencies are backend-only.
- **`AIKeyboardBroadcast` links `AIKeyboardShared` alone** and must never link `AIKeyboardCore`. Nothing in this plan puts code in its path.
- **All five target directories are `PBXFileSystemSynchronizedRootGroup`s.** A new `.swift` file dropped in compiles automatically. No `.pbxproj` edit, ever.
- **Never run the full test suite.** The user's standing instruction. Backend tests (`cd Backend && npm test`) are seconds long and ARE run in this plan; the Xcode suite is not. Swift work is verified with `xcodebuild build-for-testing`.
- **Trunk only.** Commit on `main`. No feature branches, no worktrees.
- **Commit subjects carry no em dashes or en dashes.** Bodies may.
- **Verification must reject the broken build.** Every rejection test needs a sibling proving the same code path accepts the valid input. A verifier that returns `false` for everything passes a suite made only of rejection tests.
- Exact app identity, used verbatim in code: Team ID `9R8P28G4BJ`, app bundle ID `com.nitai.aikeyboard`, so `APP_ID` is `9R8P28G4BJ.com.nitai.aikeyboard`.
- App Group: `group.com.nitai.aikeyboard`.

---

## File Structure

**Backend — new**

| File | Responsibility |
|---|---|
| `Backend/src/appleRoot.js` | The vendored Apple App Attest root CA, and nothing else. |
| `Backend/src/sessionToken.js` | Sign and verify the challenge JWT and the session JWT. Knows nothing about attestation. |
| `Backend/src/attestation.js` | Parse an attestation object into plain fields. Pure bytes in, object out, no I/O and no crypto policy. |
| `Backend/src/attestationVerifier.js` | The ten checks. Consumes `attestation.js`, holds all the policy (app ID, environment, root). |
| `Backend/test/helpers/fakeAttestation.js` | Mints a test CA and a valid attestation so the verifier can be shown to accept as well as reject. |

**Backend — modified**

| File | Change |
|---|---|
| `Backend/src/gate.js` | `authorize` becomes async and accepts a session token or `BACKEND_TOKEN`; `callerKey` prefers the device. |
| `Backend/src/httpServer.js` | Two unauthenticated routes, a smaller body cap for them, and the async `authorize`. |
| `Backend/server.js` | Wire the new modules from env. |
| `Backend/deploy.sh` | Require `SESSION_SECRET`; set `APP_ID` and `ATTEST_ENV`. |
| `Backend/package.json` | Three dependencies. |
| `Backend/README.md` | Known gaps: this one closes, the per-instance limiter one stays. |

**App — new**

| File | Responsibility |
|---|---|
| `AIKeyboard/Cloud/AppAttestation.swift` | The whole client flow: decide, challenge, attest, store. App target only. |
| `AIKeyboardCoreTests/SessionTokenTests.swift` | Expiry reading and the token-preference rule. |

**App — modified**

| File | Change |
|---|---|
| `AIKeyboard/AIKeyboard.entitlements` | `com.apple.developer.devicecheck.appattest-environment`. |
| `Packages/.../AIKeyboardShared/CloudTransport.swift` | `storedToken` prefers typed then session; `isReady` asks about expiry; `setUpRecovery` copy. |
| `Packages/.../AIKeyboardShared/SessionTokenExpiry.swift` | New. Read `exp` out of a JWT without verifying it. |
| `Packages/.../AIKeyboardShared/AIOutput.swift` | `.cloudNotConfigured` copy. |
| `Packages/.../AIKeyboardCore/SharedStore+CloudModel.swift` | `cloudSessionToken`. |
| `AIKeyboard/Main/CloudModelFieldSection.swift` | Token row becomes `#if DEBUG`; status line reports the attested connection. |
| `AIKeyboard/AIKeyboardApp.swift` | Kick off `AppAttestation.refreshIfNeeded` at launch. |

---

## Task 1: Pin the dependencies and vendor Apple's root certificate

Nothing else can be written until the root CA is on disk and provably the right one. It is fetched from Apple, not transcribed.

**Files:**
- Modify: `Backend/package.json`
- Create: `Backend/src/appleRoot.js`
- Test: `Backend/test/appleRoot.test.js`

**Interfaces:**
- Produces: `APPLE_APP_ATTEST_ROOT_PEM` (string) from `src/appleRoot.js`.

- [ ] **Step 1: Install the three dependencies**

```bash
cd Backend
npm install cbor-x jose @peculiar/x509
```

Why three, and why each one is not avoidable:
- `cbor-x` — the attestation object is CBOR. Node has no CBOR.
- `jose` — the challenge and session tokens are JWTs. Hand-rolled HMAC token formats are where algorithm-confusion bugs live.
- `@peculiar/x509` — Apple puts the attestation nonce in a certificate extension under OID `1.2.840.113635.100.8.2`. Node's `crypto.X509Certificate` exposes `subject`, `issuer`, `keyUsage`, `infoAccess` and no way to read an arbitrary OID (verified: its prototype has no extension accessor). This library reads it and also builds the test certificates in Task 3.

- [ ] **Step 2: Fetch the root certificate from Apple**

```bash
cd Backend
curl -fsSL https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem \
  -o /tmp/apple-appattest-root.pem
openssl x509 -in /tmp/apple-appattest-root.pem -noout -subject -issuer -fingerprint -sha256
```

Expected: subject and issuer are identical (it is self-signed) and both name Apple's App Attestation Root CA. **Record the printed SHA-256 fingerprint** — Step 4's test pins it. If the download fails or the subject is not Apple's App Attestation root, stop and raise it rather than substituting any other certificate.

- [ ] **Step 3: Vendor it**

Create `Backend/src/appleRoot.js`:

```js
// Apple's App Attest root CA, the trust anchor for every attestation this
// service accepts.
//
// Vendored rather than fetched at runtime on purpose: a network dependency in
// the auth path is an outage waiting to happen, and a root that could be
// swapped by whoever answers a DNS query is not a trust anchor. Downloaded from
// https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
// and pinned by fingerprint in test/appleRoot.test.js.
export const APPLE_APP_ATTEST_ROOT_PEM = `-----BEGIN CERTIFICATE-----
<paste the exact contents of /tmp/apple-appattest-root.pem here>
-----END CERTIFICATE-----`;
```

- [ ] **Step 4: Write the test that pins it**

Create `Backend/test/appleRoot.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { X509Certificate } from "node:crypto";
import { APPLE_APP_ATTEST_ROOT_PEM } from "../src/appleRoot.js";

test("the vendored root parses and is self-signed", () => {
  const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM);
  assert.equal(root.subject, root.issuer);
  assert.ok(root.ca, "the vendored certificate is not a CA certificate");
});

test("the vendored root is the exact certificate Apple publishes", () => {
  const root = new X509Certificate(APPLE_APP_ATTEST_ROOT_PEM);
  // Replace with the fingerprint printed in Step 2. A test that only checks
  // "it parses" would pass against any certificate at all, including one an
  // attacker substituted in a pull request.
  assert.equal(root.fingerprint256, "<SHA-256 FINGERPRINT FROM STEP 2>");
});
```

- [ ] **Step 5: Run it**

```bash
cd Backend && npm test
```
Expected: PASS. If the fingerprint assertion fails, the pasted PEM is not the file that was downloaded.

- [ ] **Step 6: Commit**

```bash
git add Backend/package.json Backend/package-lock.json Backend/src/appleRoot.js Backend/test/appleRoot.test.js
git commit -m "Vendor Apple's App Attest root and pin it by fingerprint"
```

---

## Task 2: Session and challenge tokens

**Files:**
- Create: `Backend/src/sessionToken.js`
- Test: `Backend/test/sessionToken.test.js`

**Interfaces:**
- Produces: `createTokens({ secret, now })` returning `{ signChallenge, verifyChallenge, signSession, verifySession }`.
  - `signChallenge(): Promise<string>`
  - `verifyChallenge(jwt: string): Promise<boolean>`
  - `signSession(deviceId: string): Promise<{ token: string, expiresAt: string }>`
  - `verifySession(jwt: string): Promise<{ ok: boolean, deviceId?: string }>`
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write the failing tests**

Create `Backend/test/sessionToken.test.js`:

```js
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
  assert.equal(await at(1_000_000 + CHALLENGE_TTL_MS + 1_000).verifyChallenge(challenge), false);
});

test("a session token carries the device it was issued to", async () => {
  const tokens = at(1_000_000);
  const { token } = await tokens.signSession("device-abc");
  assert.deepEqual(await tokens.verifySession(token), { ok: true, deviceId: "device-abc" });
});

test("a session token stops verifying after ninety days", async () => {
  const { token } = await at(1_000_000).signSession("device-abc");
  const later = at(1_000_000 + SESSION_TTL_MS + 1_000);
  assert.equal((await later.verifySession(token)).ok, false);
});

test("a session token signed with another secret is refused", async () => {
  const { token } = await at(1_000_000).signSession("device-abc");
  const other = createTokens({ secret: "b".repeat(64), now: () => 1_000_000 });
  assert.equal((await other.verifySession(token)).ok, false);
});

test("a challenge is not accepted as a session token, or the reverse", async () => {
  const tokens = at(1_000_000);
  const challenge = await tokens.signChallenge();
  const { token } = await tokens.signSession("device-abc");
  assert.equal((await tokens.verifySession(challenge)).ok, false);
  assert.equal(await tokens.verifyChallenge(token), false);
});

test("garbage verifies as nothing", async () => {
  const tokens = at(1_000_000);
  assert.equal((await tokens.verifySession("not.a.jwt")).ok, false);
  assert.equal(await tokens.verifyChallenge(""), false);
});
```

The last two matter more than they look. Both tokens are signed with the same secret, so without a distinguishing claim a 5-minute challenge would be accepted as a 90-day session token by any caller who asked for one.

- [ ] **Step 2: Run them and watch them fail**

```bash
cd Backend && node --test test/sessionToken.test.js
```
Expected: FAIL, `Cannot find module '../src/sessionToken.js'`.

- [ ] **Step 3: Implement**

Create `Backend/src/sessionToken.js`:

```js
// The two signed slips this service hands out, and the reason it needs no
// database. A challenge proves "this service issued this nonce, recently"; a
// session token proves "this service saw this device pass App Attest". Both are
// verified against the same secret they were signed with, so Cloud Run holds no
// state between requests and --min-instances=0 stays viable.

import { SignJWT, jwtVerify } from "jose";

export const CHALLENGE_TTL_MS = 5 * 60 * 1000;
export const SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;

// Both tokens are signed with the same secret, so something has to tell them
// apart. Without this a caller could take the 5-minute challenge they are
// handed for free and present it as a 90-day session token.
const CHALLENGE_AUDIENCE = "aikeyboard/challenge";
const SESSION_AUDIENCE = "aikeyboard/session";

export function createTokens({ secret, now = Date.now }) {
  if (typeof secret !== "string" || secret.length < 32) {
    throw new Error("SESSION_SECRET must be at least 32 characters");
  }
  const key = new TextEncoder().encode(secret);

  // Seconds, because that is what `exp` and `iat` are. Injected rather than
  // read from the clock so the tests can move time instead of sleeping for
  // ninety days.
  const seconds = () => Math.floor(now() / 1000);

  async function sign(audience, ttlMs, claims = {}) {
    const issuedAt = seconds();
    return new SignJWT(claims)
      .setProtectedHeader({ alg: "HS256" })
      .setAudience(audience)
      .setIssuedAt(issuedAt)
      .setExpirationTime(issuedAt + Math.floor(ttlMs / 1000))
      .sign(key);
  }

  async function verify(token, audience) {
    if (typeof token !== "string" || token.length === 0) return null;
    try {
      const { payload } = await jwtVerify(token, key, {
        audience,
        algorithms: ["HS256"],
        currentDate: new Date(now())
      });
      return payload;
    } catch {
      return null;
    }
  }

  return {
    signChallenge: () => sign(CHALLENGE_AUDIENCE, CHALLENGE_TTL_MS),

    async verifyChallenge(token) {
      return (await verify(token, CHALLENGE_AUDIENCE)) !== null;
    },

    async signSession(deviceId) {
      const token = await sign(SESSION_AUDIENCE, SESSION_TTL_MS, { sub: deviceId });
      return { token, expiresAt: new Date(now() + SESSION_TTL_MS).toISOString() };
    },

    async verifySession(token) {
      const payload = await verify(token, SESSION_AUDIENCE);
      if (!payload?.sub) return { ok: false };
      return { ok: true, deviceId: payload.sub };
    }
  };
}
```

`algorithms: ["HS256"]` is not decoration. Without it a token whose header says `alg: none` is a token this service would verify.

- [ ] **Step 4: Run the tests**

```bash
cd Backend && node --test test/sessionToken.test.js
```
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Backend/src/sessionToken.js Backend/test/sessionToken.test.js
git commit -m "Sign the two tokens that let the gate hold no state"
```

---

## Task 3: Parse an attestation, and mint a fake one to parse

The fixture builder and the parser ship together because neither is testable without the other: a parser with no valid input can only be shown to reject.

**Files:**
- Create: `Backend/src/attestation.js`
- Create: `Backend/test/helpers/fakeAttestation.js`
- Test: `Backend/test/attestation.test.js`

**Interfaces:**
- Produces: `parseAttestation(bytes)` → `{ fmt, x5c, receipt, authData, rpIdHash, flags, signCount, aaguid, credentialId }`, throwing `Error` on anything malformed.
- Produces: `buildFakeAttestation(options)` → `{ attestation, keyId, challenge, rootPem, leafPem }` for Tasks 3 and 4.
- Produces: `AAGUID_DEVELOPMENT`, `AAGUID_PRODUCTION`, `NONCE_OID` constants.

- [ ] **Step 1: Write the fixture builder**

Create `Backend/test/helpers/fakeAttestation.js`:

```js
// A valid attestation, minted locally, so the verifier can be shown to *accept*
// as well as reject.
//
// There is no other way to get one. A real attestation needs a real Secure
// Enclave, which no CI machine and no simulator has, and a blob recorded from a
// device is frozen at one app ID, one environment and one nonce — useless for
// testing the checks that are supposed to reject. So the tests bring their own
// certificate authority and the verifier takes its root as a parameter.

import { createHash, generateKeyPairSync, randomBytes } from "node:crypto";
import { encode } from "cbor-x";
import * as x509 from "@peculiar/x509";
import { webcrypto } from "node:crypto";

x509.cryptoProvider.set(webcrypto);

export const NONCE_OID = "1.2.840.113635.100.8.2";

// Apple's extension value is SEQUENCE { [1] { OCTET STRING nonce } }. Every
// length here is under 128, so single-byte DER lengths are correct and a
// long-form encoder would be wrong.
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

/// The 65-byte uncompressed point, which is what Apple hashes to make the key ID.
async function uncompressedPoint(publicKey) {
  const raw = Buffer.from(await webcrypto.subtle.exportKey("raw", publicKey));
  if (raw.length !== 65 || raw[0] !== 0x04) {
    throw new Error(`expected a 65-byte uncompressed point, got ${raw.length}`);
  }
  return raw;
}

export async function buildFakeAttestation({
  appId = "9R8P28G4BJ.com.nitai.aikeyboard",
  challenge = "test-challenge",
  aaguid = "appattestdevelop",
  signCount = 0,
  // Seams for the rejection tests: each one breaks exactly one check.
  rpIdHashOverride = null,
  credentialIdOverride = null,
  nonceOverride = null,
  signLeafWithRoot = true
} = {}) {
  const rootKeys = await generateP256();
  const leafKeys = await generateP256();

  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: "CN=Test App Attest Root",
    notBefore: new Date("2020-01-01"),
    notAfter: new Date("2040-01-01"),
    keys: rootKeys,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-256" },
    extensions: [new x509.BasicConstraintsExtension(true, 1, true)]
  });

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
    credentialId,
    // A COSE public key would follow on a real device. The verifier takes the
    // key from the leaf certificate and never reads this, so the fixture leaves
    // it out rather than pretending to encode one.
    Buffer.alloc(0)
  ]);

  const clientDataHash = createHash("sha256").update(challenge).digest();
  const nonce =
    nonceOverride ?? createHash("sha256").update(Buffer.concat([authData, clientDataHash])).digest();

  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test Attestation Leaf",
    issuer: root.subject,
    notBefore: new Date("2020-01-01"),
    notAfter: new Date("2040-01-01"),
    publicKey: leafKeys.publicKey,
    signingKey: signLeafWithRoot ? rootKeys.privateKey : leafKeys.privateKey,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-256" },
    extensions: [new x509.Extension(NONCE_OID, false, nonceExtensionValue(nonce))]
  });

  const attestation = encode({
    fmt: "apple-appattest",
    attStmt: {
      x5c: [Buffer.from(leaf.rawData), Buffer.from(root.rawData)],
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
```

- [ ] **Step 2: Write the failing parser tests**

Create `Backend/test/attestation.test.js`:

```js
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

test("the app ID hash is the one the app ID produces", async () => {
  const appId = "9R8P28G4BJ.com.nitai.aikeyboard";
  const { attestation } = await buildFakeAttestation({ appId });
  const parsed = parseAttestation(attestation);
  assert.deepEqual(parsed.rpIdHash, createHash("sha256").update(appId).digest());
});

test("a non-zero counter survives parsing rather than being normalised away", async () => {
  const { attestation } = await buildFakeAttestation({ signCount: 7 });
  assert.equal(parseAttestation(attestation).signCount, 7);
});

test("a production AAGUID reads as production", async () => {
  const { attestation } = await buildFakeAttestation({ aaguid: "appattest" });
  assert.equal(parseAttestation(attestation).aaguid, "appattest");
});

test("bytes that are not CBOR are rejected", () => {
  assert.throws(() => parseAttestation(Buffer.from("nonsense")), /could not be decoded/);
});

test("a CBOR object that is not an attestation is rejected", () => {
  assert.throws(() => parseAttestation(Buffer.from(encode({ hello: "world" }))), /fmt/);
});

test("authData too short to hold its own fields is rejected", () => {
  const truncated = encode({
    fmt: "apple-appattest",
    attStmt: { x5c: [Buffer.alloc(4)], receipt: Buffer.alloc(0) },
    authData: Buffer.alloc(40)
  });
  assert.throws(() => parseAttestation(Buffer.from(truncated)), /authData/);
});
```

- [ ] **Step 3: Run them and watch them fail**

```bash
cd Backend && node --test test/attestation.test.js
```
Expected: FAIL, `Cannot find module '../src/attestation.js'`.

- [ ] **Step 4: Implement the parser**

Create `Backend/src/attestation.js`:

```js
// Bytes in, fields out. No policy lives here: this file will happily parse an
// attestation for the wrong app in the wrong environment with a counter of 900,
// and attestationVerifier.js is what refuses it. Splitting them that way is what
// lets the rejection tests state which check fired.

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
    // Trailing NULs are padding, not part of the name. Apple pads "appattest"
    // to sixteen bytes; the development value fills them exactly.
    aaguid: auth.subarray(37, 53).toString("binary").replace(/\0+$/, ""),
    credentialId: auth.subarray(CREDENTIAL_ID_OFFSET, credentialIdEnd)
  };
}
```

- [ ] **Step 5: Run the tests**

```bash
cd Backend && node --test test/attestation.test.js
```
Expected: PASS, 7 tests.

- [ ] **Step 6: Commit**

```bash
git add Backend/src/attestation.js Backend/test/attestation.test.js Backend/test/helpers/fakeAttestation.js
git commit -m "Read an attestation into its parts, and mint one to read"
```

---

## Task 4: The ten checks

**Files:**
- Create: `Backend/src/attestationVerifier.js`
- Test: `Backend/test/attestationVerifier.test.js`

**Interfaces:**
- Consumes: `parseAttestation`, `AAGUID_DEVELOPMENT`, `AAGUID_PRODUCTION`, `NONCE_OID` from `src/attestation.js`; `buildFakeAttestation` from the test helper.
- Produces: `createAttestationVerifier({ rootCertificatePem, appId, environment })` returning `{ verify({ attestation, keyId, challenge }): Promise<{ ok: true, deviceId } | { ok: false, reason }> }`.

`reason` exists for tests and logs. The HTTP layer never returns it: a caller learning *which* of ten checks rejected them is a caller being helped to pass.

- [ ] **Step 1: Write the failing tests**

Create `Backend/test/attestationVerifier.test.js`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { createAttestationVerifier } from "../src/attestationVerifier.js";
import { buildFakeAttestation } from "./helpers/fakeAttestation.js";

const APP_ID = "9R8P28G4BJ.com.nitai.aikeyboard";

async function verifierFor(fixture, overrides = {}) {
  return createAttestationVerifier({
    rootCertificatePem: fixture.rootPem,
    appId: APP_ID,
    environment: "development",
    ...overrides
  });
}

// The one that has to pass, or every rejection below is worthless: a verifier
// that returns false unconditionally satisfies all of them.
test("a valid attestation is accepted and names the device", async () => {
  const fixture = await buildFakeAttestation({ appId: APP_ID });
  const result = await (await verifierFor(fixture)).verify(fixture);
  assert.equal(result.ok, true, `expected acceptance, got ${result.reason}`);
  assert.equal(result.deviceId, fixture.keyId);
});

test("an attestation for another app is refused", async () => {
  const fixture = await buildFakeAttestation({ appId: "9R8P28G4BJ.com.someone.else" });
  const result = await (await verifierFor(fixture)).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /app id/i);
});

test("an attestation raised for a different challenge is refused", async () => {
  const fixture = await buildFakeAttestation();
  const result = await (await verifierFor(fixture)).verify({ ...fixture, challenge: "other" });
  assert.equal(result.ok, false);
  assert.match(result.reason, /nonce/i);
});

test("a key id that is not the hash of the attested key is refused", async () => {
  const fixture = await buildFakeAttestation();
  const result = await (await verifierFor(fixture)).verify({
    ...fixture,
    keyId: createHash("sha256").update("something else").digest("base64")
  });
  assert.equal(result.ok, false);
  assert.match(result.reason, /key id/i);
});

test("a used key is refused: the counter must be zero at attestation", async () => {
  const fixture = await buildFakeAttestation({ signCount: 3 });
  const result = await (await verifierFor(fixture)).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /counter/i);
});

test("production refuses a development attestation", async () => {
  const fixture = await buildFakeAttestation({ aaguid: "appattestdevelop" });
  const verifier = await verifierFor(fixture, { environment: "production" });
  const result = await verifier.verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /environment/i);
});

test("production accepts a production attestation", async () => {
  const fixture = await buildFakeAttestation({ aaguid: "appattest" });
  const verifier = await verifierFor(fixture, { environment: "production" });
  const result = await verifier.verify(fixture);
  assert.equal(result.ok, true, `expected acceptance, got ${result.reason}`);
});

test("a chain that does not reach our root is refused", async () => {
  const fixture = await buildFakeAttestation();
  const other = await buildFakeAttestation();
  const verifier = await verifierFor(other); // trusts a different root
  const result = await verifier.verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /chain/i);
});

test("a leaf that signed itself is refused", async () => {
  const fixture = await buildFakeAttestation({ signLeafWithRoot: false });
  const result = await (await verifierFor(fixture)).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /chain/i);
});

test("a credential id that disagrees with the key id is refused", async () => {
  const fixture = await buildFakeAttestation({ credentialIdOverride: Buffer.alloc(32, 9) });
  const result = await (await verifierFor(fixture)).verify(fixture);
  assert.equal(result.ok, false);
  assert.match(result.reason, /credential/i);
});

test("malformed bytes are refused rather than thrown", async () => {
  const fixture = await buildFakeAttestation();
  const result = await (await verifierFor(fixture)).verify({
    ...fixture,
    attestation: Buffer.from("nonsense")
  });
  assert.equal(result.ok, false);
});
```

- [ ] **Step 2: Run them and watch them fail**

```bash
cd Backend && node --test test/attestationVerifier.test.js
```
Expected: FAIL, `Cannot find module '../src/attestationVerifier.js'`.

- [ ] **Step 3: Implement**

Create `Backend/src/attestationVerifier.js`:

```js
// The ten checks Apple documents, in the order Apple documents them.
//
// Everything here returns { ok: false, reason } rather than throwing, and the
// reason never leaves this process. A 401 that says which check failed is a
// tutorial for the person trying to get past it.

import { createHash, webcrypto } from "node:crypto";
import * as x509 from "@peculiar/x509";
import { AAGUID_DEVELOPMENT, AAGUID_PRODUCTION, NONCE_OID, parseAttestation } from "./attestation.js";

x509.cryptoProvider.set(webcrypto);

function refuse(reason) {
  return { ok: false, reason };
}

/// Apple's extension value is SEQUENCE { [1] { OCTET STRING nonce } }. Parsed by
/// shape rather than by "take the last 32 bytes", so a malformed extension is
/// refused instead of silently yielding whatever happened to be at the end.
function nonceFromExtension(value) {
  const bytes = Buffer.from(value);
  if (bytes.length !== 38) return null;
  if (bytes[0] !== 0x30 || bytes[2] !== 0xa1 || bytes[4] !== 0x04 || bytes[5] !== 32) return null;
  return bytes.subarray(6, 38);
}

/// The 65-byte uncompressed point lives at the end of an EC SPKI. Length-checked
/// rather than assumed, because a curve that is not P-256 would slice wrong.
async function uncompressedPoint(certificate) {
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

      let expectedKeyId;
      try {
        expectedKeyId = Buffer.from(keyId, "base64");
      } catch {
        return refuse("key id is not base64");
      }

      // 2. Chain: leaf signed by the next certificate, and the chain ends at the
      //    root we trust. Compared by raw bytes, not by subject name, because a
      //    name is something an attacker chooses.
      const chain = parsed.x5c.map((der) => new x509.X509Certificate(new Uint8Array(der)));
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

      // 3, 4. The nonce Apple bound into the certificate.
      const clientDataHash = createHash("sha256").update(challenge).digest();
      const expectedNonce = createHash("sha256")
        .update(Buffer.concat([parsed.authData, clientDataHash]))
        .digest();

      // 5.
      const extension = leaf.getExtension(NONCE_OID);
      if (!extension) return refuse("attestation carries no nonce extension");
      const nonce = nonceFromExtension(extension.value);
      if (!nonce) return refuse("attestation nonce extension is malformed");
      if (!nonce.equals(expectedNonce)) return refuse("attestation nonce does not match the challenge");

      // 6.
      const point = await uncompressedPoint(leaf);
      if (!point) return refuse("attested key is not an uncompressed P-256 point");
      const publicKeyHash = createHash("sha256").update(point).digest();
      if (!publicKeyHash.equals(expectedKeyId)) {
        return refuse("key id is not the hash of the attested key");
      }

      // 7.
      if (!parsed.rpIdHash.equals(expectedRpIdHash)) {
        return refuse("attestation names a different app id");
      }

      // 8.
      if (parsed.signCount !== 0) return refuse("attested key has a non-zero counter");

      // 9.
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
```

- [ ] **Step 4: Run the tests**

```bash
cd Backend && node --test test/attestationVerifier.test.js
```
Expected: PASS, 11 tests. **If the two acceptance tests fail while the nine rejections pass, the verifier is refusing everything and the suite is worthless — fix that before going on.**

- [ ] **Step 5: Commit**

```bash
git add Backend/src/attestationVerifier.js Backend/test/attestationVerifier.test.js
git commit -m "Verify an attestation against Apple's root and this app's identity"
```

---

## Task 5: The gate accepts a device, and counts per device

**Files:**
- Modify: `Backend/src/gate.js`
- Test: `Backend/test/gate.test.js`

**Interfaces:**
- Produces: `authorize({ expectedToken, headers, verifySession })` → `Promise<{ ok: true, deviceId: string | null } | { ok: false, status, error }>`. **Now async.**
- Produces: `callerKey(req, deviceId)` → string.

- [ ] **Step 1: Add the failing tests**

Append to `Backend/test/gate.test.js`:

```js
test("a valid session token is accepted and names its device", async () => {
  const verifySession = async (token) =>
    token === "good" ? { ok: true, deviceId: "device-1" } : { ok: false };
  const result = await authorize({
    expectedToken: "shared",
    headers: { authorization: "Bearer good" },
    verifySession
  });
  assert.deepEqual(result, { ok: true, deviceId: "device-1" });
});

test("the shared token still works beside session tokens", async () => {
  const verifySession = async () => ({ ok: false });
  const result = await authorize({
    expectedToken: "shared",
    headers: { authorization: "Bearer shared" },
    verifySession
  });
  assert.deepEqual(result, { ok: true, deviceId: null });
});

test("a bearer that is neither is refused", async () => {
  const verifySession = async () => ({ ok: false });
  const result = await authorize({
    expectedToken: "shared",
    headers: { authorization: "Bearer neither" },
    verifySession
  });
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
});

test("the caller key is the device when there is one", () => {
  const req = { headers: { "x-forwarded-for": "1.2.3.4" }, socket: {} };
  assert.equal(callerKey(req, "device-1"), "device:device-1");
});

test("the caller key falls back to the address when there is not", () => {
  const req = { headers: { "x-forwarded-for": "1.2.3.4" }, socket: {} };
  assert.equal(callerKey(req, null), "1.2.3.4");
});

test("a device and an address can never collide in the limiter", () => {
  const req = { headers: { "x-forwarded-for": "device-1" }, socket: {} };
  assert.notEqual(callerKey(req, "device-1"), callerKey(req, null));
});
```

That last test is the reason for the `device:` prefix. Without it a caller who sets `X-Forwarded-For: <somebody's device id>` shares, and can exhaust, that device's bucket.

- [ ] **Step 2: Run and watch them fail**

```bash
cd Backend && node --test test/gate.test.js
```
Expected: FAIL. The existing synchronous `authorize` returns `{ ok: true }` with no `deviceId`, and `callerKey` takes one argument.

- [ ] **Step 3: Change `authorize` and `callerKey`**

In `Backend/src/gate.js`, replace `authorize` with:

```js
/// 401 unless the caller proved something. Two things count, and the order is
/// deliberate: a session token is the shipping path and is tried first, and
/// `BACKEND_TOKEN` is the developer and self-hosting door behind it.
///
/// Returns the device when there is one, because the rate limiter is keyed on
/// it. A `BACKEND_TOKEN` caller has no device and falls back to its address,
/// which is the old behaviour and is right: that token is shared by definition.
export async function authorize({ expectedToken, headers, verifySession }) {
  const presented = bearerToken(headers);

  if (presented && verifySession) {
    const session = await verifySession(presented);
    if (session.ok) return { ok: true, deviceId: session.deviceId };
  }

  if (!expectedToken) return { ok: true, deviceId: null };
  if (tokensMatch(expectedToken, presented)) return { ok: true, deviceId: null };

  // 401 rather than 403: the client maps both to `cloudNotConfigured`, which is
  // the honest reading — from the app's side a backend it cannot authenticate
  // to is a backend it does not have.
  return { ok: false, status: 401, error: "missing or invalid bearer token" };
}
```

And replace `callerKey` with:

```js
/// The caller's identity for rate-limiting purposes.
///
/// **A device, when the gate proved one.** The address was the only key
/// available before attestation, and behind carrier NAT that is thousands of
/// unrelated people sharing one bucket — one abusive caller starved all of them,
/// and a leaked token cost as much as its holder's IP allowance rather than one
/// device's. Keying on the attested device is the control that actually bounds
/// the bill.
///
/// Namespaced, so a caller cannot set `X-Forwarded-For` to somebody's device id
/// and drain their allowance.
///
/// Cloud Run terminates TLS and proxies, so `socket.remoteAddress` is the load
/// balancer on every request. The real client is the first entry of
/// `x-forwarded-for`. Trusting a header the caller controls is normally wrong;
/// here the alternative is a limiter that does nothing at all, and it only
/// applies to the two unauthenticated routes now.
export function callerKey(req, deviceId = null) {
  if (deviceId) return `device:${deviceId}`;
  const forwarded = req.headers?.["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket?.remoteAddress ?? "unknown";
}
```

- [ ] **Step 4: Run the whole backend suite**

```bash
cd Backend && npm test
```
Expected: the new gate tests PASS. Any pre-existing `gate` or `httpServer` test that called `authorize` synchronously now fails on a Promise; update those call sites with `await` in the same step. Nothing else should move.

- [ ] **Step 5: Commit**

```bash
git add Backend/src/gate.js Backend/test/gate.test.js
git commit -m "Let the gate take a device, and rate limit by it"
```

---

## Task 6: The two new routes

**Files:**
- Modify: `Backend/src/httpServer.js`, `Backend/server.js`
- Test: `Backend/test/httpServer.test.js`

**Interfaces:**
- Consumes: `createTokens` (Task 2), `createAttestationVerifier` (Task 4), the async `authorize` (Task 5).
- Produces: `createServer({ vertexClient, maxBodyBytes, expectedToken, rateLimiter, tokens, attestationVerifier })`.

- [ ] **Step 1: Write the failing route tests**

Add to `Backend/test/httpServer.test.js`, following the request helper the existing tests already use:

```js
test("POST /v1/challenge hands out a challenge without a bearer", async () => {
  const { status, body } = await post("/v1/challenge", {}, {});
  assert.equal(status, 200);
  assert.ok(typeof body.challenge === "string" && body.challenge.length > 0);
});

test("a valid attestation is exchanged for a session token", async () => {
  const { body: challengeBody } = await post("/v1/challenge", {}, {});
  const fixture = await buildFakeAttestation({ challenge: challengeBody.challenge });
  const { status, body } = await post(
    "/v1/attest",
    {
      keyId: fixture.keyId,
      attestation: fixture.attestation.toString("base64"),
      challenge: challengeBody.challenge
    },
    {}
  );
  assert.equal(status, 200);
  assert.ok(typeof body.token === "string");
  assert.ok(typeof body.expiresAt === "string");
});

test("that session token then opens /v1/text", async () => {
  // ... obtain `token` exactly as above ...
  const { status } = await post("/v1/text", VALID_TEXT_BODY, { authorization: `Bearer ${token}` });
  assert.notEqual(status, 401);
});

test("a challenge the service never issued is refused", async () => {
  const fixture = await buildFakeAttestation({ challenge: "made up" });
  const { status, body } = await post(
    "/v1/attest",
    {
      keyId: fixture.keyId,
      attestation: fixture.attestation.toString("base64"),
      challenge: "made up"
    },
    {}
  );
  assert.equal(status, 401);
  // The response must not name which check fired.
  assert.equal(body.error, "attestation refused");
});

test("an attest body over its own cap is refused before it is read", async () => {
  const { status } = await postRaw("/v1/attest", Buffer.alloc(200 * 1024), {});
  assert.equal(status, 413);
});
```

- [ ] **Step 2: Run and watch them fail**

```bash
cd Backend && node --test test/httpServer.test.js
```
Expected: FAIL with 404 on both new paths.

- [ ] **Step 3: Add the routes**

In `Backend/src/httpServer.js`:

```js
// An attestation is about 5 KB. The 8 MB cap exists for dictation audio and
// screen JPEGs, and applying it to an unauthenticated route would let anyone
// make this service buffer 8 MB before it has proved anything at all.
const ATTEST_MAX_BODY_BYTES = 64 * 1024;
```

Inside the request handler, after the `/healthz` branch and before the existing
route check:

```js
    // Both of these run before any bearer exists, by definition: they are how a
    // device gets one. They stay inside the rate limiter and inside a much
    // smaller body cap, and neither one costs a model call.
    if (req.method === "POST" && (req.url === "/v1/challenge" || req.url === "/v1/attest")) {
      const allowance = rateLimiter.check(callerKey(req, null));
      if (!allowance.ok) {
        sendJSONAndClose(
          req, res, allowance.status, { error: allowance.error },
          { "retry-after": String(allowance.retryAfterSeconds) }
        );
        return;
      }

      if (req.url === "/v1/challenge") {
        sendJSON(res, 200, { challenge: await tokens.signChallenge() });
        return;
      }

      let attestBody;
      try {
        const raw = await readBody(req, ATTEST_MAX_BODY_BYTES);
        attestBody = JSON.parse(raw.toString("utf8"));
      } catch (error) {
        if (error.tooLarge) sendJSONAndClose(req, res, 413, { error: "request body too large" });
        else sendJSONAndClose(req, res, 400, { error: "could not read request body" });
        return;
      }

      const { keyId, attestation, challenge } = attestBody ?? {};
      if (typeof keyId !== "string" || typeof attestation !== "string" || typeof challenge !== "string") {
        sendJSON(res, 400, { error: "keyId, attestation and challenge are required" });
        return;
      }

      // The challenge is checked first and separately: an attestation raised
      // against a nonce this service never issued is replay, and there is no
      // reason to spend certificate parsing on it.
      if (!(await tokens.verifyChallenge(challenge))) {
        sendJSONAndClose(req, res, 401, { error: "attestation refused" });
        return;
      }

      const verdict = await attestationVerifier.verify({
        attestation: Buffer.from(attestation, "base64"),
        keyId,
        challenge
      });
      if (!verdict.ok) {
        // One message for all ten checks. `verdict.reason` is for the log, and
        // stops at this line.
        console.warn(`attestation refused: ${verdict.reason}`);
        sendJSONAndClose(req, res, 401, { error: "attestation refused" });
        return;
      }

      sendJSON(res, 200, await tokens.signSession(verdict.deviceId));
      return;
    }
```

Then change the existing gate to the async form and thread the device through:

```js
    const auth = await authorize({ expectedToken, headers: req.headers, verifySession: tokens.verifySession });
    if (!auth.ok) {
      sendJSONAndClose(req, res, auth.status, { error: auth.error });
      return;
    }

    const allowance = rateLimiter.check(callerKey(req, auth.deviceId));
```

- [ ] **Step 4: Wire it in `Backend/server.js`**

```js
import { createTokens } from "./src/sessionToken.js";
import { createAttestationVerifier } from "./src/attestationVerifier.js";
import { APPLE_APP_ATTEST_ROOT_PEM } from "./src/appleRoot.js";

const tokens = createTokens({ secret: process.env.SESSION_SECRET });
const attestationVerifier = createAttestationVerifier({
  rootCertificatePem: APPLE_APP_ATTEST_ROOT_PEM,
  appId: process.env.APP_ID ?? "9R8P28G4BJ.com.nitai.aikeyboard",
  environment: process.env.ATTEST_ENV ?? "production"
});
```

and pass both into `createServer`. `createTokens` throws on a missing or short
`SESSION_SECRET`, which is deliberate: the service should refuse to start rather
than come up signing tokens with `undefined`.

- [ ] **Step 5: Run the whole suite**

```bash
cd Backend && npm test
```
Expected: PASS throughout.

- [ ] **Step 6: Commit**

```bash
git add Backend/src/httpServer.js Backend/server.js Backend/test/httpServer.test.js
git commit -m "Trade a challenge and an attestation for a session token"
```

---

## Task 7: Deploy and document

**Files:**
- Modify: `Backend/deploy.sh`, `Backend/README.md`

- [ ] **Step 1: Require the new secret in `deploy.sh`**

After the existing `BACKEND_TOKEN` block:

```bash
if [ -z "${SESSION_SECRET:-}" ]; then
  echo "SESSION_SECRET is not set." >&2
  echo >&2
  echo "This signs the session tokens attested devices are issued. Losing it logs" >&2
  echo "every device out; leaking it lets anyone mint one. Generate and deploy with:" >&2
  echo >&2
  echo "  SESSION_SECRET=\$(openssl rand -hex 32) BACKEND_TOKEN=\$(openssl rand -hex 32) ./deploy.sh" >&2
  exit 1
fi
```

And add to the `gcloud run deploy` invocation:

```bash
  --set-env-vars="SESSION_SECRET=${SESSION_SECRET}" \
  --set-env-vars="APP_ID=${APP_ID:-9R8P28G4BJ.com.nitai.aikeyboard}" \
  --set-env-vars="ATTEST_ENV=${ATTEST_ENV:-production}" \
```

Also update the `--allow-unauthenticated` comment: the reason it is unavoidable
is unchanged, but the sentence claiming a typed-in bearer is the only gate is now
wrong.

- [ ] **Step 2: Rewrite the Known gaps section of `Backend/README.md`**

The first bullet currently ends "For a shipping consumer build the right control
is **App Attest** ... and it has not been done." Replace that bullet with what is
now true: attestation is the gate, `BACKEND_TOKEN` survives as the developer and
self-hosting door, and the honest residue is that a session token can be read out
of the App Group by the owner of the device it was issued to and used until it
expires, bounded by that device's own quota.

**Keep the second half of the old bullet.** The rate limiter still counts in one
process and `--max-instances=10` still means up to ten times the configured
ceiling. That gap did not close, and per-device keying makes each bucket smaller
without making the count shared.

- [ ] **Step 3: Commit**

```bash
git add Backend/deploy.sh Backend/README.md
git commit -m "Deploy with a session secret, and close the gap the README named"
```

---

## Task 8: The app knows what a session token is

**Files:**
- Create: `Packages/AIKeyboardCore/Sources/AIKeyboardShared/SessionTokenExpiry.swift`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardCore/SharedStore+CloudModel.swift`
- Test: `AIKeyboardCoreTests/SessionTokenTests.swift`

**Interfaces:**
- Produces: `SessionToken.expiry(of: String) -> Date?`
- Produces: `SharedStore.cloudSessionToken: String`
- Changes: `BackendTransport.storedToken`, `BackendTransport.isReady`

- [ ] **Step 1: Write the failing tests**

Create `AIKeyboardCoreTests/SessionTokenTests.swift`:

```swift
import XCTest

@testable import AIKeyboardCore

final class SessionTokenTests: XCTestCase {

    /// A JWT this test builds itself. Unsigned on purpose: the app cannot verify
    /// a signature it has no secret for, and must never behave as though it can.
    private func token(expiringAt seconds: Int) -> String {
        let payload = #"{"sub":"device-1","exp":\#(seconds)}"#
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    func testTheExpiryIsReadOutOfTheToken() {
        let expiry = SessionToken.expiry(of: token(expiringAt: 1_800_000_000))
        XCTAssertEqual(expiry, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testSomethingThatIsNotAJWTHasNoExpiry() {
        XCTAssertNil(SessionToken.expiry(of: "not-a-token"))
        XCTAssertNil(SessionToken.expiry(of: ""))
        XCTAssertNil(SessionToken.expiry(of: "a.b.c"))
    }

    func testAnExpiredSessionTokenIsNotAReadyBackend() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(token(expiringAt: 1), forKey: "cloudSessionToken")
        XCTAssertFalse(BackendTransport.isReady(defaults: defaults))
    }

    func testAnUnexpiredSessionTokenIsAReadyBackend() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let future = Int(Date().addingTimeInterval(60 * 60 * 24).timeIntervalSince1970)
        defaults.set(token(expiringAt: future), forKey: "cloudSessionToken")
        XCTAssertTrue(BackendTransport.isReady(defaults: defaults))
    }

    func testATypedTokenWinsOverAnAttestedOne() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set("typed-by-a-developer", forKey: "cloudBackendToken")
        defaults.set(token(expiringAt: 1), forKey: "cloudSessionToken")
        // The expired session token must not be what goes on the wire, and the
        // expired session token must not make `isReady` false either: a typed
        // token is a complete setup on its own.
        XCTAssertTrue(BackendTransport.isReady(defaults: defaults))
    }
}
```

The last two are the pair that rejects the broken build. A `storedToken` that
always returns the session token, and an `isReady` that only looks at expiry,
both pass the first three tests.

- [ ] **Step 2: Implement the expiry reader**

Create `Packages/AIKeyboardCore/Sources/AIKeyboardShared/SessionTokenExpiry.swift`:

```swift
import Foundation

/// Reads the expiry out of a session token **without verifying it**, and that
/// distinction is the whole of this file.
///
/// The app holds no signing secret — that is the point of the design — so it
/// cannot tell a real token from one somebody wrote. It does not need to: the
/// backend checks the signature on every call, and the only question here is
/// "is there any point sending this one", which decides whether a screen says
/// the cloud is set up and whether the app bothers re-attesting. A forged token
/// gets a 401 from the service exactly as an absent one does.
public enum SessionToken {

    public static func expiry(of token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let payload = decodeBase64URL(String(parts[1])),
            let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let expiry = object["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: expiry)
    }

    /// Base64URL, which is not what `Data(base64Encoded:)` reads: JWTs swap
    /// `+/` for `-_` and drop the padding, and a decoder that ignores both
    /// returns nil for most real tokens.
    private static func decodeBase64URL(_ value: String) -> Data? {
        var text = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text.append("=") }
        return Data(base64Encoded: text)
    }
}
```

- [ ] **Step 3: Change `storedToken` and `isReady`**

In `CloudTransport.swift`, replace `storedToken` and `isReady`:

```swift
    /// The bearer to send, or nil when there is nothing to send.
    ///
    /// **Two sources, and the order is the design.** `cloudSessionToken` is what
    /// `AppAttestation` writes after the hardware proved this is a genuine build
    /// of this app, and it is the only one a shipping install ever has.
    /// `cloudBackendToken` is typed by hand, exists in Debug builds only, and
    /// wins — a simulator has no Secure Enclave, so without it there is no way
    /// to exercise a cloud action anywhere but on a device.
    ///
    /// Separate keys rather than one, so the two lifecycles cannot collide: a
    /// refresh writing the session slot must never overwrite what a developer
    /// typed.
    private static func storedToken(_ defaults: UserDefaults) -> String? {
        nonBlank(defaults.string(forKey: "cloudBackendToken"))
            ?? nonBlank(defaults.string(forKey: "cloudSessionToken"))
    }

    /// Whether a cloud call would be **accepted**, not merely addressed.
    ///
    /// (Keep the existing doc comment above this line; it is still true.)
    ///
    /// **Expiry is asked about here, and only of an attested token.** A session
    /// token has a ninety-day life and only the containing app can renew it, so
    /// an install whose owner has not opened the app in three months has a token
    /// the service will refuse. Saying "set up" about it would put a green tick
    /// in front of a keyboard that 401s on every action, which is exactly the
    /// class of claim `isReady` exists to prevent. A typed token carries no
    /// expiry to read and is taken at face value.
    public static func isReady(defaults: UserDefaults = SharedContainer.userDefaults) -> Bool {
        guard configured(defaults: defaults) != nil else { return false }
        guard usesBundledBackend(defaults: defaults) else { return true }
        if nonBlank(defaults.string(forKey: "cloudBackendToken")) != nil { return true }
        guard let session = nonBlank(defaults.string(forKey: "cloudSessionToken")),
            let expiry = SessionToken.expiry(of: session)
        else { return false }
        return expiry > Date()
    }
```

- [ ] **Step 4: Add the store property**

In `SharedStore+CloudModel.swift`, beside `cloudBackendToken`:

```swift
    /// The bearer `AppAttestation` writes once the hardware has proved this app.
    /// Never typed, never shown, and the only one a shipping install has. See
    /// `BackendTransport.storedToken` for why it is a second key rather than
    /// reusing `cloudBackendToken`.
    public var cloudSessionToken: String {
        get { defaults.string(forKey: Key.cloudSessionToken) ?? "" }
        set { write(newValue, forKey: Key.cloudSessionToken) }
    }
```

Add `static let cloudSessionToken = "cloudSessionToken"` to the `Key` enum,
beside the existing `cloudBackendToken` entry.

- [ ] **Step 5: Build**

```bash
xcodebuild build-for-testing -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Packages/AIKeyboardCore/Sources/AIKeyboardShared/SessionTokenExpiry.swift \
        Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift \
        Packages/AIKeyboardCore/Sources/AIKeyboardCore/SharedStore+CloudModel.swift \
        AIKeyboardCoreTests/SessionTokenTests.swift
git commit -m "Store an attested token beside the typed one, and read its expiry"
```

---

## Task 9: The app attests

**Files:**
- Create: `AIKeyboard/Cloud/AppAttestation.swift`
- Modify: `AIKeyboard/AIKeyboard.entitlements`
- Modify: `AIKeyboard/AIKeyboardApp.swift`

**Interfaces:**
- Consumes: `SharedStore.cloudSessionToken`, `BackendTransport.effectiveURL`, `SessionToken.expiry`.
- Produces: `AppAttestation.refreshIfNeeded(store:)`.

- [ ] **Step 1: Add the entitlement**

`AIKeyboard/AIKeyboard.entitlements` gains, beside the App Group:

```xml
	<key>com.apple.developer.devicecheck.appattest-environment</key>
	<string>development</string>
```

Only the app's entitlements file. **Not the keyboard's and not the broadcast
extension's** — neither attests, and granting a capability to a process that does
not use it is how a keyboard ends up asking for something it cannot explain.

`development` is the Debug value. Release builds need `production`, which is set
by adding the key to the Release configuration through Xcode's capability editor
rather than by editing this file twice. **Verify after the first Release archive
that the shipped entitlement says `production`** — a Release build carrying the
development value attests against Apple's development environment and is refused
by the deployed service, which is check 9 doing its job and would read as "the
cloud is broken".

- [ ] **Step 2: Write the client**

Create `AIKeyboard/Cloud/AppAttestation.swift`:

```swift
import AIKeyboardCore
import DeviceCheck
import Foundation

/// Proves to the backend that this is a genuine, unmodified build of this app on
/// real Apple hardware, and stores the token that proof buys.
///
/// **This lives in the containing app and nowhere else.** The keyboard and the
/// broadcast extension are separate bundle IDs, so an attestation raised there
/// would name a different app; Apple rate-limits attestation, so a keyboard
/// cannot do it per tap; and a keyboard extension has no network at all until
/// Full Access is granted. They read the token this writes, through the App
/// Group, exactly as they read the one that used to be typed in.
///
/// Everything here fails quietly. There is no screen to put an error on and
/// nothing the user could do about it: an install with no token reports
/// `.cloudNotConfigured` at the moment an AI action is tapped, which is where
/// the sentence belongs.
public enum AppAttestation {

    /// Renew once the token is a third of the way through its life.
    ///
    /// The backend issues ninety days. Refreshing at thirty means a user who
    /// opens the app even occasionally is never near the edge, and the sixty-day
    /// margin is for the user who does not: they keep working until they do.
    static let refreshAfter: TimeInterval = 30 * 24 * 60 * 60

    /// Called at launch. Does nothing at all in the common case.
    public static func refreshIfNeeded(store: SharedStore) async {
        guard needsRefresh(store: store) else { return }
        guard DCAppAttestService.shared.isSupported else { return }
        try? await attest(store: store)
    }

    static func needsRefresh(store: SharedStore) -> Bool {
        let existing = store.cloudSessionToken
        guard !existing.isEmpty, let expiry = SessionToken.expiry(of: existing) else { return true }
        return expiry.timeIntervalSinceNow < (90 * 24 * 60 * 60) - refreshAfter
    }

    static func attest(store: SharedStore) async throws {
        let base = URL(string: BackendTransport.effectiveURL())!
        let service = DCAppAttestService.shared

        let challenge = try await fetchChallenge(base: base)

        // A fresh key every time, rather than reusing one and sending an
        // assertion. Assertions are Apple's cheap path, and they are declined
        // here on purpose: verifying one requires the server to remember that
        // device's public key and signature counter, and the counter is what
        // makes an assertion replay-proof. That is a database, and the whole
        // design turns on not having one. Twelve attestations a device a year
        // is nothing against Apple's limits.
        let keyId = try await service.generateKey()
        let attestation = try await service.attestKey(
            keyId, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))

        var request = URLRequest(url: base.appendingPathComponent("v1/attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyId": keyId,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = body["token"] as? String
        else { return }

        store.cloudSessionToken = token
    }

    private static func fetchChallenge(base: URL) async throws -> String {
        var request = URLRequest(url: base.appendingPathComponent("v1/challenge"))
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let challenge = body["challenge"] as? String
        else { throw URLError(.cannotParseResponse) }
        return challenge
    }
}
```

Add `import CryptoKit` for `SHA256`. `generateKey()` returns the key ID as a
base64 string, which is what the backend hashes against; send it unchanged.

- [ ] **Step 3: Call it at launch**

In `AIKeyboard/AIKeyboardApp.swift`, on the root view:

```swift
                .task { await AppAttestation.refreshIfNeeded(store: store) }
```

**At launch, not in onboarding.** The keyboard can be enabled from Settings and
used without onboarding ever finishing, and an install whose AI depends on a flow
the user skipped is the failure this whole design exists to remove.

- [ ] **Step 4: Build**

```bash
xcodebuild build-for-testing -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add AIKeyboard/Cloud/AppAttestation.swift AIKeyboard/AIKeyboard.entitlements AIKeyboard/AIKeyboardApp.swift
git commit -m "Attest at launch and store what the hardware buys"
```

---

## Task 10: The typed token leaves the shipping app, and the copy stops naming it

**Files:**
- Modify: `AIKeyboard/Main/CloudModelFieldSection.swift`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardShared/AIOutput.swift`
- Modify: `Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift`

- [ ] **Step 1: Make the token row Debug-only**

In `CloudModelFieldSection.swift`, wrap the access-token field and everything that
describes it in `#if DEBUG` / `#endif`. The URL field stays in every build: it is
still user-editable and self-hosting still depends on it.

Replace the released status line, which currently reasons about a typed token,
with one that reports the attested connection: `store.hasCloudModel` is still the
question, and the subtitle wording changes from "the token is missing" to
whether this install has connected.

- [ ] **Step 2: Fix the two copy sites**

`BackendTransport.setUpRecovery` and `AIEngineError.cloudNotConfigured`'s message
both currently send the user to a field that no longer exists for them. Both must
say the only thing a user can now do:

> Open AI Keyboard once to reconnect.

Keep `BackendTransport.settingsPath` — the URL row is still real, and the Debug
token row still lives there.

Update the doc comment above `.cloudNotConfigured` too. It currently reasons at
length about a token that is "missing, mistyped or revoked", which stops being
the likely cause the moment nobody types one. The likely causes are now: the app
has never had network since install, or it has not been opened in ninety days.

- [ ] **Step 3: Build**

```bash
xcodebuild build-for-testing -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** TEST BUILD SUCCEEDED **`.

Then confirm the row really is gone from a Release build rather than assuming the
`#if` landed where it was meant to:

```bash
xcodebuild build -project AIKeyboard.xcodeproj -scheme AIKeyboard -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add AIKeyboard/Main/CloudModelFieldSection.swift \
        Packages/AIKeyboardCore/Sources/AIKeyboardShared/AIOutput.swift \
        Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift
git commit -m "Take the pasted token out of the shipping app"
```

---

## Task 11: Prove it against the deployed service

**Files:**
- Modify: `Scripts/prove-cloud-backend.sh`
- Modify: `README.md`

- [ ] **Step 1: Extend the prove script**

`Scripts/prove-cloud-backend.sh` runs the shipping client against the live
service. Add two checks it can make without a Secure Enclave:

1. `POST /v1/challenge` returns a challenge.
2. `POST /v1/attest` with a syntactically valid but unattested body returns 401
   and a body of exactly `{"error":"attestation refused"}` — proving the service
   is not leaking which check fired.

Read the script first and follow whatever pass/fail convention it already uses.

- [ ] **Step 2: Update the table in `README.md`**

`README.md` carries the table of what is measured and what is only compiled. The
attestation path is **measured on the backend** (Tasks 1-6 are all real tests
against real crypto) and **only compiled on the device side** until somebody runs
it on real hardware. Say exactly that. Do not let this land claiming the
end-to-end flow has been proven on a phone when it has not.

- [ ] **Step 3: Commit**

```bash
git add Scripts/prove-cloud-backend.sh README.md
git commit -m "Prove the new routes answer, and say what is still unmeasured"
```

---

## Rollout order

The backend must be deployed **before** an app carrying Task 9 reaches anybody,
and it is safe to deploy early: `authorize` accepts `BACKEND_TOKEN` exactly as it
does today, so every existing install keeps working through the whole change.
There is no flag day and no version pinning.

Deploy with:

```bash
cd Backend
SESSION_SECRET=$(openssl rand -hex 32) BACKEND_TOKEN=$(openssl rand -hex 32) \
  PROJECT=handi-project ./deploy.sh
```

Rotating `SESSION_SECRET` later invalidates every issued token at once. Every app
re-attests on its next launch, so the blast radius is "AI is unavailable in the
keyboard until each user opens the app once", not a permanent break. Worth
knowing before rotating it casually.

## Self-review notes

Three things this plan deliberately does not do, so a reviewer does not read them
as omissions:

- **No receipt validation.** The attestation carries a receipt that can be
  exchanged with Apple for fraud metrics and a risk score. It is a separate
  server-to-server flow with its own key, and it is worth having later. Nothing
  in this design depends on it.
- **No revocation list.** A stolen session token cannot be individually killed;
  the controls are its ninety-day life and its per-device quota. Adding
  revocation means storage, which is the thing this design is shaped to avoid.
- **The per-instance rate limiter is unchanged.** Ten instances still means up to
  ten times the configured ceiling. Per-device keying makes each bucket the right
  size without making the count shared, and the README keeps saying so.
