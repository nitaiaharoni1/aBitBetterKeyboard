// Who is allowed to spend this project's Vertex budget, and how fast.
//
// The service has to be reachable without Google's own IAM, because
// `BackendTransport` is a plain `URLSession` call from a keyboard extension and
// carries no Google identity. So `deploy.sh` passes `--allow-unauthenticated`,
// and that leaves an endpoint where every request costs real money and anyone
// who learns the URL can make one. A model proxy with no gate is a bill with no
// ceiling.
//
// Two layers, both deliberately modest about what they are:
//
// **A bearer token.** Set `BACKEND_TOKEN` on the service and the same value in
// the app's `cloudBackendToken` setting. This is *not* a bundled secret — nothing
// ships one, for exactly the reason the app holds no provider credential:
// anything in an app bundle is extractable. It is a value whoever runs the
// backend types in beside its URL, so it is as private as they keep it. It stops
// a URL that leaks from becoming an open model endpoint. It does not stop a
// determined user of the app itself, and it is not meant to.
//
// **A per-IP rate limit.** Bounds the damage when a token does leak, and bounds
// an honest bug looping on retry, which is the more likely of the two. A fixed
// window rather than a sliding one because the failure being prevented is
// "thousands of calls", not "eleven calls in a second", and a fixed window needs
// one integer per caller instead of a list of timestamps.
//
// **What neither of these is.** For a shipping consumer app the right control is
// App Attest: it proves the caller is a genuine, unmodified copy of this app on
// real Apple hardware, which a shared string can never do. That needs a client
// change and an Apple key, and it is listed under known gaps in the README
// rather than pretended away here.

const DEFAULT_WINDOW_MS = 60_000;
const DEFAULT_MAX_PER_WINDOW = 60;

/// Constant-time-ish comparison. Not because a timing attack on a self-hosted
/// proxy is a realistic threat, but because writing `a === b` here is the habit
/// that matters somewhere it is.
function tokensMatch(expected, provided) {
  if (typeof provided !== "string" || provided.length !== expected.length) return false;
  let difference = 0;
  for (let i = 0; i < expected.length; i += 1) {
    difference |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
  }
  return difference === 0;
}

export function bearerToken(headers) {
  const raw = headers?.authorization ?? headers?.Authorization;
  if (typeof raw !== "string") return null;
  const match = /^Bearer\s+(.+)$/i.exec(raw.trim());
  return match ? match[1] : null;
}

/// 401 unless the caller proved something. Two things count.
///
/// **A session token, first, because it is the shipping path.** It is what
/// `/v1/attest` hands back once App Attest proved the caller is a genuine,
/// unmodified build of this app on real Apple hardware, and it is the only
/// bearer an installed copy ever has. It carries the device it was issued to,
/// which is what `callerKey` rate-limits on.
///
/// **`BACKEND_TOKEN` behind it**, unchanged, as the developer and self-hosting
/// door. A simulator has no Secure Enclave, so without this there is no way to
/// exercise a cloud action anywhere but on a device; and a backend somebody runs
/// themselves is their business. It carries no device, because it is shared by
/// definition, so its callers fall back to being counted by address exactly as
/// they were before.
///
/// Configured-and-absent is still the only rejection. A service with no
/// `BACKEND_TOKEN` and no session token accepts everyone, which is what a local
/// `npm start` wants; `deploy.sh` refuses to deploy without one, so the open
/// case cannot reach Cloud Run by accident.
export async function authorize({ expectedToken, headers, verifySession }) {
  const presented = bearerToken(headers);
  let sessionRejectReason;

  if (presented && verifySession) {
    const session = await verifySession(presented);
    if (session.ok) return { ok: true, deviceId: session.deviceId };
    // Kept rather than discarded: `session.reason` is one of the closed set
    // `SessionRejectReason` names in sessionToken.js (expired, bad signature,
    // malformed), and it is the only place that distinction still exists once
    // this function has decided to refuse the call.
    sessionRejectReason = session.reason;
  }

  if (!expectedToken) return { ok: true, deviceId: null };
  if (tokensMatch(expectedToken, presented)) return { ok: true, deviceId: null };
  // 401 rather than 403: the client maps both to `cloudNotConfigured`, which is
  // the honest reading — from the app's side a backend it cannot authenticate
  // to is a backend it does not have.
  return {
    ok: false,
    status: 401,
    error: "missing or invalid bearer token",
    // A session-shaped bearer that `verifySession` itself rejected names why.
    // Otherwise, the only other reason this project's own devices ever hit
    // this branch is that no bearer was presented at all — NIT-87's "no token
    // yet" state, distinct from a real refusal.
    reason: sessionRejectReason ?? (presented ? undefined : "absent")
  };
}

/// A fixed-window counter keyed by caller.
///
/// `now` is injected so the tests can move time instead of sleeping through a
/// window, which is the difference between a 3 ms test and a 60 s one.
export function createRateLimiter({
  windowMs = DEFAULT_WINDOW_MS,
  maxPerWindow = DEFAULT_MAX_PER_WINDOW,
  now = () => Date.now()
} = {}) {
  const counters = new Map();

  return {
    /// True when the caller may proceed. Sweeps expired entries on the way past
    /// so the map cannot grow without bound on a service that sees many IPs —
    /// an unbounded Map keyed by remote address is a memory leak wearing a rate
    /// limiter's clothes.
    check(key) {
      const current = now();
      for (const [existing, entry] of counters) {
        if (entry.resetAt <= current) counters.delete(existing);
      }

      const entry = counters.get(key);
      if (!entry || entry.resetAt <= current) {
        counters.set(key, { count: 1, resetAt: current + windowMs });
        return { ok: true, remaining: maxPerWindow - 1 };
      }
      if (entry.count >= maxPerWindow) {
        return {
          ok: false,
          status: 429,
          error: "too many requests",
          retryAfterSeconds: Math.max(1, Math.ceil((entry.resetAt - current) / 1000))
        };
      }
      entry.count += 1;
      return { ok: true, remaining: maxPerWindow - entry.count };
    },
    get size() {
      return counters.size;
    }
  };
}

/// The caller's identity for rate-limiting purposes.
///
/// **The attested device, whenever the gate proved one.** The address was the
/// only key available before attestation, and behind carrier NAT that is
/// thousands of unrelated people sharing one bucket: one abusive caller starved
/// all of them, and a leaked token cost as much as its holder's whole IP
/// allowance rather than one device's. Counting per device is what actually
/// bounds the bill now, and it is why the ninety-day token life is not the
/// control it looks like.
///
/// **Namespaced with a prefix, and that is not cosmetic.** `x-forwarded-for` is
/// a header the caller writes. Without the prefix, setting it to somebody's
/// device id would share, and could drain, that device's allowance.
///
/// Cloud Run terminates TLS and proxies, so `socket.remoteAddress` is the load
/// balancer on every request and would rate-limit the whole world as one caller.
/// The real client is the first entry of `x-forwarded-for`. Trusting a header
/// the caller controls is normally wrong; here the alternative is a limiter that
/// does nothing at all, the header is rewritten by Google's front end in the
/// deployment this ships to, and it now only decides the two unauthenticated
/// routes and the shared-token callers.
export function callerKey(req, deviceId = null) {
  if (deviceId) return `device:${deviceId}`;
  const forwarded = req.headers?.["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket?.remoteAddress ?? "unknown";
}
