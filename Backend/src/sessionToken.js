// The two signed slips this service hands out, and the reason it needs no
// database.
//
// A challenge proves "this service issued this nonce, recently". A session token
// proves "this service watched this device pass App Attest". Both are verified
// against the same secret they were signed with, so Cloud Run holds no state
// between requests, `--min-instances=0` stays viable, and there is no store to
// go down in the auth path.
//
// What that costs, said plainly: a session token cannot be individually revoked.
// The controls on a stolen one are its ninety-day life and the per-device rate
// limit in gate.js. Rotating SESSION_SECRET invalidates every token at once,
// which is the only revocation there is.

import { SignJWT, jwtVerify } from "jose";

export const CHALLENGE_TTL_MS = 5 * 60 * 1000;
export const SESSION_TTL_MS = 90 * 24 * 60 * 60 * 1000;

// **Both tokens are signed with the same secret, so something has to tell them
// apart.** Without a distinguishing claim, the 5-minute challenge this service
// hands to anyone who asks would verify as a 90-day session token, and the whole
// gate would be an open door with extra steps.
const CHALLENGE_AUDIENCE = "aikeyboard/challenge";
const SESSION_AUDIENCE = "aikeyboard/session";

// **The closed set of reasons a session token is refused, for the log line
// `authorize` (gate.js) writes and `httpServer.js` prints.** A constant set
// rather than free text on purpose: the reason reaches the log unfiltered, so
// it must never be able to carry a token fragment or anything else worth not
// printing — it can only ever be one of these four words.
export const SessionRejectReason = Object.freeze({
  EXPIRED: "expired",
  BAD_SIGNATURE: "bad_signature",
  MALFORMED: "malformed"
});

/// jose's own error `code` distinguishes the shapes that matter here. Anything
/// that is not "expired" or "not even a JWT" is treated as a bad signature —
/// which is also where a wrong audience lands (a challenge presented as a
/// session token, or a token from a secret this deployment no longer holds):
/// the payload parsed, so it is not malformed, and it has not aged out, so it
/// is not expired; it simply does not check out as ours.
function reasonForError(error) {
  if (error?.code === "ERR_JWT_EXPIRED") return SessionRejectReason.EXPIRED;
  if (error?.code === "ERR_JWS_INVALID" || error?.code === "ERR_JWT_INVALID") {
    return SessionRejectReason.MALFORMED;
  }
  return SessionRejectReason.BAD_SIGNATURE;
}

export function createTokens({ secret, previousSecrets = [], now = Date.now }) {
  // Thrown rather than defaulted: a service that comes up signing tokens with
  // `undefined` accepts tokens anybody can mint, and it would come up looking
  // perfectly healthy. server.js calls this at startup so the failure is a
  // deployment that never serves, not a gate that silently is not one.
  if (typeof secret !== "string" || secret.length < 32) {
    throw new Error("SESSION_SECRET must be at least 32 characters");
  }
  for (const candidate of previousSecrets) {
    if (typeof candidate !== "string" || candidate.length < 32) {
      throw new Error("SESSION_SECRET must be at least 32 characters");
    }
  }
  const key = new TextEncoder().encode(secret);
  // **Signing only ever uses `key`.** These exist so a token signed under a
  // secret this deployment has since rotated away from still verifies during
  // the grace window — the fix for the redeploy on 2026-08-14 that is one
  // candidate explanation for NIT-87's 36 refusals: nothing here persists
  // `SESSION_SECRET` across a `deploy.sh` run, so a second invocation that
  // does not reuse the same value invalidates every outstanding token the
  // instant the new revision serves.
  const previousKeys = previousSecrets.map((value) => new TextEncoder().encode(value));

  // Seconds, because that is what `exp` and `iat` are. Injected rather than read
  // from the clock so the tests can move time instead of sleeping for ninety
  // days.
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

  async function verifyWith(candidateKey, token, audience) {
    const { payload } = await jwtVerify(token, candidateKey, {
      audience,
      // **Not decoration.** Without it, a token whose header says `alg: none`
      // is a token this service verifies, and every caller can mint one.
      algorithms: ["HS256"],
      currentDate: new Date(now())
    });
    return payload;
  }

  /// Tries the current secret, then each previous one in order, but only
  /// keeps trying while the failure is specifically a signature mismatch —
  /// expired or malformed is true of the token regardless of which key
  /// verifies it, so a second key cannot change that verdict and is not
  /// worth the extra check.
  async function verify(token, audience) {
    if (typeof token !== "string" || token.length === 0) {
      return { payload: null, reason: SessionRejectReason.MALFORMED };
    }
    let reason = SessionRejectReason.MALFORMED;
    for (const candidateKey of [key, ...previousKeys]) {
      try {
        return { payload: await verifyWith(candidateKey, token, audience) };
      } catch (error) {
        reason = reasonForError(error);
        if (reason !== SessionRejectReason.BAD_SIGNATURE) break;
      }
    }
    return { payload: null, reason };
  }

  return {
    signChallenge: () => sign(CHALLENGE_AUDIENCE, CHALLENGE_TTL_MS),

    async verifyChallenge(token) {
      return (await verify(token, CHALLENGE_AUDIENCE)).payload !== null;
    },

    async signSession(deviceId) {
      const token = await sign(SESSION_AUDIENCE, SESSION_TTL_MS, { sub: deviceId });
      return { token, expiresAt: new Date(now() + SESSION_TTL_MS).toISOString() };
    },

    async verifySession(token) {
      const { payload, reason } = await verify(token, SESSION_AUDIENCE);
      if (!payload?.sub) return { ok: false, reason: reason ?? SessionRejectReason.MALFORMED };
      return { ok: true, deviceId: payload.sub };
    }
  };
}
