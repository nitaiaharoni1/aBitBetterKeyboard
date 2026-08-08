// Gets a Vertex-usable access token without ever writing a credential to
// disk. On Cloud Run, the metadata server hands out a token scoped to the
// service's runtime identity; locally, there is no metadata server, so this
// falls back to whatever `gcloud auth login` already put on the developer's
// machine. Neither path sets `GOOGLE_APPLICATION_CREDENTIALS` or reads a
// service-account key file — the whole point of a backend owning the
// credential is that nothing in the process needs to hold one as a file.

const METADATA_TOKEN_URL =
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token";

// A minute of slack: a token that expires mid-call is worse than one
// refreshed a little early, and a Vertex call here can legitimately run a few
// seconds on its own (the 512-token thinking budget alone costs up to ~4.4s,
// see `vertexClient.js`).
const REFRESH_MARGIN_MS = 60_000;

// GCP access tokens are minted for exactly one hour. `gcloud auth
// print-access-token` returns only the token, not its expiry, so a
// locally-obtained token is cached for less than that hour rather than
// derived from a value gcloud never reports.
const GCLOUD_TOKEN_TTL_MS = 55 * 60 * 1000;

async function fromMetadataServer(fetchImpl) {
  let response;
  try {
    // Cloud Run's metadata server answers in well under a second when it
    // exists at all; a short timeout is what makes this fall through to the
    // gcloud path on a developer's laptop instead of hanging on a host that
    // will never answer.
    response = await fetchImpl(METADATA_TOKEN_URL, {
      headers: { "Metadata-Flavor": "Google" },
      signal: AbortSignal.timeout(2000)
    });
  } catch {
    return null;
  }
  if (!response.ok) return null;
  const payload = await response.json().catch(() => null);
  if (!payload?.access_token) return null;
  const ttlMs = typeof payload.expires_in === "number" ? payload.expires_in * 1000 : GCLOUD_TOKEN_TTL_MS;
  return { token: payload.access_token, ttlMs };
}

async function fromGcloud(execFileImpl) {
  const { stdout } = await execFileImpl("gcloud", ["auth", "print-access-token"]);
  const token = stdout.trim();
  if (!token) throw new Error("gcloud printed no access token");
  return { token, ttlMs: GCLOUD_TOKEN_TTL_MS };
}

/// Caches the token until shortly before it expires, so a busy backend is not
/// hitting the metadata server or shelling out to gcloud on every request.
///
/// `fetchImpl`, `execFileImpl` and `now` are seams: `server.js` wires the real
/// `fetch`, a promisified `child_process.execFile`, and `Date.now`; tests wire
/// fakes and never touch a network or a subprocess.
export function createTokenProvider({ fetchImpl = fetch, execFileImpl, now = Date.now } = {}) {
  let cached = null; // { token, expiresAt }

  return {
    async getAccessToken() {
      const currentTime = now();
      if (cached && currentTime < cached.expiresAt) return cached.token;

      const fromMetadata = await fromMetadataServer(fetchImpl);
      const result = fromMetadata ?? (await fromGcloud(execFileImpl));

      cached = { token: result.token, expiresAt: currentTime + result.ttlMs - REFRESH_MARGIN_MS };
      return result.token;
    }
  };
}
