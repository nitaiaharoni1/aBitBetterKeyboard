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

export function createTokens({ secret, now = Date.now }) {
  // Thrown rather than defaulted: a service that comes up signing tokens with
  // `undefined` accepts tokens anybody can mint, and it would come up looking
  // perfectly healthy. server.js calls this at startup so the failure is a
  // deployment that never serves, not a gate that silently is not one.
  if (typeof secret !== "string" || secret.length < 32) {
    throw new Error("SESSION_SECRET must be at least 32 characters");
  }
  const key = new TextEncoder().encode(secret);

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

  async function verify(token, audience) {
    if (typeof token !== "string" || token.length === 0) return null;
    try {
      const { payload } = await jwtVerify(token, key, {
        audience,
        // **Not decoration.** Without it, a token whose header says `alg: none`
        // is a token this service verifies, and every caller can mint one.
        algorithms: ["HS256"],
        currentDate: new Date(now())
      });
      return payload;
    } catch {
      // Every failure is the same failure to a caller: wrong signature, wrong
      // audience, expired, malformed. Telling them which would be telling them
      // what to fix.
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
