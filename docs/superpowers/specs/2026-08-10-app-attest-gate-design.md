# The backend stops trusting a string and starts trusting the hardware

Date: 2026-08-10
Status: approved, not implemented

## The problem

`Backend/src/gate.js` is a shared secret, and its own header says so: "For a shipping
consumer build the right control is **App Attest** ... That needs a client change and an
Apple key, and it has not been done." `Backend/README.md` repeats it under Known gaps.

The consequences are not theoretical, and both halves are live right now:

- **Nothing can prove a request came from this app.** `deploy.sh` passes
  `--allow-unauthenticated` because the caller is a keyboard extension with no Google
  identity, so IAM cannot be the gate. That leaves a public URL in front of a paid
  model, held shut by one string that every user of the app has to be told.
- **Every install starts broken.** `BackendTransport.bundledDefaultURL` ships, so
  `configured()` is non-nil from first launch, but no token does, so `isReady()` is
  false and every cloud action 401s until somebody pastes a value into
  `Settings › AI › Cloud model`. On a simulator with no App Group token that is exactly
  what happens, and the router then reports the *on-device* failure instead — the
  "Model not ready" that started this design.

One change fixes both. If the device proves itself, the token stops being something a
human types and becomes something the app fetches, and there is nothing left to leak.

## What App Attest actually proves

Apple's Secure Enclave generates a key that cannot leave the chip and signs a statement
that the caller is a genuine, unmodified build of a *named* app, on genuine Apple
hardware. The server checks that signature against a certificate chain rooted at Apple.

It does not prove the *user* is honest. Someone who owns the device can still read
whatever the app stores. What it removes is the class of attack that matters here:
learning a string and calling the endpoint from anywhere, forever, with no device
involved at all.

## The shape

**The containing app attests. The extensions never do.** Three reasons, and the third
would be decisive alone:

1. The extensions are separate bundle IDs (`com.nitai.aikeyboard.keyboard`,
   `.broadcast`) from the app (`com.nitai.aikeyboard`), so an attestation raised there
   would name a different app.
2. Apple rate-limits attestation. A keyboard cannot do it per tap.
3. A keyboard extension has no network at all until Full Access is granted, and the
   broadcast extension is capped at ~50 MB and must never link `AIKeyboardCore`.

So the app raises the proof and hands down the result:

```
App (first launch)                  Backend                       Extensions
──────────────────                  ───────                       ──────────
POST /v1/challenge  ──────────────▶ signs a 5-minute nonce
                    ◀────────────── { challenge }
DCAppAttestService
  .generateKey()
  .attestKey(challenge)
POST /v1/attest     ──────────────▶ verifies against Apple's root
  { keyId, attestation,             checks app ID = 9R8P28G4BJ.com.nitai.aikeyboard
    challenge }                     signs a 90-day session token
                    ◀────────────── { token, expiresAt }
writes App Group
  cloudSessionToken  ─────────────────────────────────────────────▶ read as today
                                                                    via BackendTransport
                                                                    .configured()
```

**Step 4 is already built.** `BackendTransport.configured` is already read by three
processes through the App Group, and `SharedStore+CloudModel` already documents that
this is the one key the whole product turns on. This design changes who fills it, not
who reads it. `KeyboardController`, `ScreenReadService` and `ScreenContextSession` need
no change at all.

## Decisions

### No database, anywhere

Both server-side pieces of state are carried in signed tokens rather than stored:

- **The challenge** is a JWT the backend signs with a 5-minute expiry, handed out and
  handed back. Replaying one inside its window re-proves the same device and yields a
  second token for that same device, which is not an attack worth storage.
- **The session token** is a JWT the backend signs, carrying the device's key ID as
  `sub`. Verification is a signature check against the backend's own secret.

This keeps Cloud Run stateless and `--min-instances=0` viable. No Firestore, no Redis,
no cold-start dependency.

### Refresh is a full re-attestation, not an assertion

Apple's intended pattern is attest-once, assert-many: `generateAssertion` is the cheap
per-request proof. It is rejected here.

Verifying an assertion requires the server to hold that device's public key and its
signature counter, which is precisely the database this design does not want. The
workaround — embedding the public key inside the session token so the server can verify
an assertion statelessly — works, but it buys nothing: the counter check is what makes
assertions replay-proof, and the counter is the part that cannot be stateless.

So refresh generates a fresh key and attests again. At a 90-day lifetime refreshed at 30
days that is about twelve attestations per device per year, which is nothing against
Apple's limits, and it means **one code path on both sides** rather than two.

If attestation rate limits ever bite, assertions plus a Firestore-backed counter is the
upgrade, and the session token's shape does not have to change to get there.

### 90-day token, refreshed at 30 days, on app launch

The dial is reliability against exposure window, and for a keyboard reliability wins.

Only the containing app can refresh, because only the app can attest. A user who
installs the keyboard, enables it, and never opens the app again gets 90 days of working
AI. Refreshing whenever the stored token is older than 30 days means the realistic user —
who opens the app occasionally — is never anywhere near the edge.

A shorter lifetime buys less than it looks like it does. The exposure it bounds is a
token extracted from the App Group by the device's own owner, and that person can
re-extract the next one. **Lifetime is not the defence here; the per-device quota below
is.**

### The rate limiter counts per device, not per IP

`gate.js`'s `callerKey` currently returns the first `x-forwarded-for` entry. Behind
carrier NAT that is thousands of unrelated people sharing one bucket, and one abusive
caller starves them all.

A verified session token carries a stable device identity, so `callerKey` prefers the
token's `sub`. It falls back to the IP for `/v1/challenge` and `/v1/attest`, which by
definition run before a device has a token. A leaked token now buys the attacker exactly
one device's quota, which is the control that actually bounds the bill.

The known gap stays honest and stays in the README: the counter is per-instance and
`deploy.sh` sets `--max-instances=10`, so the real ceiling is up to ten times the
configured limit. Fixing that properly still means shared state.

### Dependencies: two on the backend, none in the app

The app stays dependency-free — that is in `AGENTS.md`'s first line and nothing here
changes it. `DeviceCheck` is an Apple framework.

The backend takes three, all popular and all replacing code that is easy to get subtly
wrong:

- a CBOR decoder, for the attestation object
- a JWT library, for signing and verifying the challenge and session tokens
- an X.509 library, for one specific reason: **Apple puts the attestation nonce in a
  certificate extension under OID `1.2.840.113635.100.8.2`, and Node cannot read it.**
  `crypto.X509Certificate` exposes `subject`, `issuer`, `keyUsage`, `infoAccess` and
  nothing that reaches an arbitrary OID — checked against the prototype on Node 25, not
  assumed from the documentation. The alternative is hand-rolled DER parsing in the
  auth path, which is worse than a dependency. The same library builds the test
  certificates, which have to carry that extension too.

`crypto.createHash` still does the four SHA-256s. Exact package names and versions are
chosen at implementation time, not pinned by this document.

### The typed-in token becomes a developer door

`cloudBackendToken` is removed from the shipping app. A user never sees it, never needs
it, and there is nothing for them to leak.

It survives in Debug builds only, so a simulator — which has no Secure Enclave and where
`DCAppAttestService.isSupported` is false — can still be pointed at the deployed backend
and exercised. `gate.js` keeps accepting `BACKEND_TOKEN` beside session tokens, which is
the same door, and is also what keeps a self-hosted backend usable.

The two live in **separate App Group keys** so their lifecycles cannot collide:
`cloudBackendToken` (typed, Debug only) and `cloudSessionToken` (written by attestation).
`BackendTransport.storedToken` prefers the first and falls back to the second, so a
developer's typed value overrides without the refresh path overwriting it.

## What changes

### Backend

| File | Change |
|---|---|
| `src/appAttest.js` | New. The ten verification steps below. Pure functions over bytes; no I/O. |
| `src/sessionToken.js` | New. Sign and verify the challenge and session JWTs. |
| `src/gate.js` | `authorize` accepts a valid session token **or** `BACKEND_TOKEN`. `callerKey` prefers the verified `sub`. |
| `src/httpServer.js` | Two new routes: `POST /v1/challenge`, `POST /v1/attest`. Both sit outside the bearer gate; both stay inside the rate limiter and the body cap. |
| `deploy.sh` | Requires `SESSION_SECRET` alongside `BACKEND_TOKEN`; sets `APP_ID` and `ATTEST_ENV`. |
| `package.json` | The two dependencies. |
| `test/` | `appAttest.test.js`, `sessionToken.test.js`, plus the `gate` and `httpServer` suites. |
| `README.md` | Known gaps rewritten: this one closes, the per-instance limiter one stays. |

The verification, in the order Apple documents it:

1. CBOR-decode the attestation to `{ fmt, attStmt: { x5c, receipt }, authData }`; `fmt`
   must be `apple-appattest`.
2. Build the chain from `x5c` and verify it to Apple's App Attest root CA. **The root
   PEM is fetched from Apple's certificate authority page and vendored at implementation
   time. It is not transcribed from memory into this document.**
3. `clientDataHash = SHA256(challenge)`.
4. `nonce = SHA256(authData || clientDataHash)`.
5. The leaf certificate's extension OID `1.2.840.113635.100.8.2` must contain that
   nonce.
6. `SHA256(leaf public key, uncompressed X9.63)` must equal `keyId`.
7. `authData[0..32]` must equal `SHA256(APP_ID)`, where `APP_ID` is
   `9R8P28G4BJ.com.nitai.aikeyboard`.
8. The signature counter, `authData[33..37]`, must be `0`.
9. The AAGUID, `authData[37..53]`, must be `appattestdevelop` when `ATTEST_ENV` is
   development and `appattest` right-padded with zeroes in production. **Production
   accepts only the production value** — a development build must not be able to mint a
   token against the deployed service.
10. The credential ID inside `authData` must equal `keyId`.

Any failure is one 401 with one message. The server never tells a caller which of the
ten steps rejected them.

### App

| File | Change |
|---|---|
| `AIKeyboard/AIKeyboard.entitlements` | Add `com.apple.developer.devicecheck.appattest-environment`, `development` in Debug and `production` in Release. |
| `AIKeyboard/Cloud/AppAttestation.swift` | New, app target only. Challenge, key, attest, store, and the age check that decides whether to refresh. |
| `AIKeyboard/Main/CloudModelFieldSection.swift` | Token row wrapped in `#if DEBUG`. Status line reports the attested connection instead. |
| `Packages/.../SharedStore+CloudModel.swift` | Add `cloudSessionToken`. `cloudBackendToken` stays, now Debug-written only. |
| `Packages/.../CloudTransport.swift` | `storedToken` prefers typed, falls back to session. `isReady()` becomes "there is an unexpired session token, or a typed one". |
| `Packages/.../AIOutput.swift` | `.cloudNotConfigured` copy stops naming a field to fill. |

Attestation is kicked off from the app's launch path, not from onboarding, because the
keyboard can be enabled and used without onboarding ever completing.

### Copy

`BackendTransport.setUpRecovery` and `.cloudNotConfigured`'s message both currently send
the user to a field to paste a token into. That field is gone in the shipping app, so
both must say the thing the user can now actually do:

> Open AI Keyboard once to reconnect.

`BackendTransport.settingsPath` survives for the Debug row and for the URL, which is
still user-editable.

## Failure behaviour

| State | What the user gets |
|---|---|
| First launch, attestation succeeds | Nothing. It is silent and takes one round trip. |
| First launch, offline | No token. Cloud actions report `.cloudNotConfigured` and say to reopen the app. The next launch retries. |
| Simulator, or `isSupported` false | No token, same as offline. A Debug build shows the typed-token row. |
| Token expired, app not opened in 90 days | Backend 401s, which already maps to `.cloudNotConfigured`. The banner says to open the app; opening it fixes it. |
| Jailbroken device | Attestation fails. Cloud actions never work. This is the intended outcome. |

Every one of these lands in `BannerState.blocked`, which the action-row work landed
today, so the keyboard says what happened without covering a single key.

## What this is not

- **Not protection from the device's owner.** They can read `cloudSessionToken` out of
  the App Group on their own hardware and use it until it expires. The per-device quota
  is what bounds that, not the attestation.
- **Not a fix for the per-instance rate limiter.** Ten instances still means up to ten
  times the configured ceiling. Unchanged, still in the README.
- **Not a reason to remove the budget cap.** A hard cap on the Google project is the
  only control that is true regardless of how wrong everything above turns out to be.

## Testing

Backend, under `node --test`, no network: a recorded attestation blob and its matching
challenge as fixtures, then one test per rejection — wrong app ID, wrong nonce, non-zero
counter, production service given a development AAGUID, expired challenge, key ID that
does not match the public key hash, broken chain. Each must be shown to fail *for its
own reason*, not to fail incidentally.

App: `AppAttestation`'s age arithmetic and the store round trip are testable without a
Secure Enclave and are what the unit tests cover. The attestation call itself is device
only, and `Scripts/prove-cloud-backend.sh` is where it gets proven end to end, exactly
as the current transport is.

The trap this repo keeps rediscovering applies here with full force: **write assertions
that reject the broken build.** A test that asserts an attestation verifier returns false
for garbage input passes against a verifier that returns false for everything. Every
rejection test needs a sibling that proves the same verifier accepts the valid fixture.
