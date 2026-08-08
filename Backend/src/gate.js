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

/// 401 when a token is configured and the caller did not present it.
///
/// Configured-and-absent is the only rejection. A service with no
/// `BACKEND_TOKEN` set accepts everyone, which is what a local `npm start`
/// wants; `deploy.sh` refuses to deploy without one, so the open case cannot
/// reach Cloud Run by accident.
export function authorize({ expectedToken, headers }) {
  if (!expectedToken) return { ok: true };
  if (tokensMatch(expectedToken, bearerToken(headers))) return { ok: true };
  // 401 rather than 403: the client maps both to `cloudNotConfigured`, which is
  // the honest reading — from the app's side a backend it cannot authenticate
  // to is a backend it does not have.
  return { ok: false, status: 401, error: "missing or invalid bearer token" };
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
/// Cloud Run terminates TLS and proxies, so `socket.remoteAddress` is the load
/// balancer on every request and would rate-limit the whole world as one caller.
/// The real client is the first entry of `x-forwarded-for`. Trusting a header
/// the caller controls is normally wrong; here the alternative is a limiter that
/// does nothing at all, and the header is rewritten by Google's front end in the
/// deployment this ships to.
export function callerKey(req) {
  const forwarded = req.headers?.["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.length > 0) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket?.remoteAddress ?? "unknown";
}
