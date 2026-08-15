// Entrypoint. Wires the real token source and the real Vertex call together
// and starts listening — every seam used here (`fetch`, `execFile`) is the
// production implementation; `test/` wires fakes for the same modules
// instead of importing this file at all.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { APPLE_APP_ATTEST_ROOT_PEM } from "./src/appleRoot.js";
import { createAttestationVerifier } from "./src/attestationVerifier.js";
import { createRateLimiter } from "./src/gate.js";
import { createServer } from "./src/httpServer.js";
import { createTokens } from "./src/sessionToken.js";
import { createTokenProvider } from "./src/token.js";
import { createVertexClient } from "./src/vertexClient.js";

const execFileAsync = promisify(execFile);

const project = process.env.PROJECT || "handi-project";
const model = process.env.MODEL || "gemini-3.5-flash-lite";
const port = Number(process.env.PORT) || 8080;

const tokenProvider = createTokenProvider({
  execFileImpl: (file, args) => execFileAsync(file, args)
});
const vertexClient = createVertexClient({ project, model, tokenProvider });

// Absent locally is fine and open; absent in the deployment is not, and
// `deploy.sh` refuses to deploy without one rather than relying on this warning
// being read. See `src/gate.js` for why a shared string is the ceiling of what
// this can be, and what a shipping consumer build would use instead.
const expectedToken = process.env.BACKEND_TOKEN || null;
if (!expectedToken) {
  console.warn(
    "BACKEND_TOKEN is not set: every caller is accepted, and every call spends "
      + "this project's Vertex budget. Fine on localhost, never on a public URL."
  );
}

// App Attest, the gate a shipping install actually passes.
//
// **Absent `SESSION_SECRET` switches the two attestation routes off rather than
// refusing to start**, and that is the same bargain `BACKEND_TOKEN` already
// strikes: a bare `npm start` on a laptop keeps working with no environment at
// all, and `deploy.sh` is what refuses to put either gap on a public URL.
// `createTokens` throws on a secret too short to be one, so the failure mode
// this leaves open is "no attestation locally", never "tokens signed with
// undefined".
//
// `createTokens` is the session signer and has nothing to do with
// `createTokenProvider` above it, which fetches Google access tokens for Vertex.
// Two different tokens, two different jobs, named apart here because they were
// briefly not.
// `SESSION_SECRET_PREVIOUS` is the grace window across a rotation, and it exists
// because rotating without one is silent. `deploy.sh` reads the secret from the
// caller's shell on every run and its own printed example generates one inline
// with `openssl rand -hex 32`, so a redeploy that does not reuse the old value
// invalidates every session token already on every device at that instant. The
// devices cannot tell that from a forged token: they get a flat 401 on the AI
// action they just pressed. That is the shape of the 2026-08-14 bursts in
// NIT-87, both of which follow revision 00004 by minutes.
//
// Set it to the outgoing secret for one deploy and outstanding tokens keep
// verifying until they expire on their own schedule. Signing always uses the
// current secret, so nothing is issued under the old one and the window closes
// by itself. Unset is the ordinary state and means no grace at all.
const sessionSecret = process.env.SESSION_SECRET || null;
const previousSessionSecret = process.env.SESSION_SECRET_PREVIOUS || null;
let sessionTokens = null;
let attestationVerifier = null;
if (sessionSecret) {
  sessionTokens = createTokens({
    secret: sessionSecret,
    previousSecrets: previousSessionSecret ? [previousSessionSecret] : []
  });
  attestationVerifier = createAttestationVerifier({
    rootCertificatePem: APPLE_APP_ATTEST_ROOT_PEM,
    appId: process.env.APP_ID || "9R8P28G4BJ.com.nitai.aikeyboard",
    environment: process.env.ATTEST_ENV || "production"
  });
} else {
  console.warn(
    "SESSION_SECRET is not set: /v1/challenge and /v1/attest are switched off, so "
      + "no device can attest and the shared BACKEND_TOKEN is the only way in."
  );
}

const server = createServer({
  vertexClient,
  expectedToken,
  tokens: sessionTokens,
  attestationVerifier,
  rateLimiter: createRateLimiter({
    maxPerWindow: Number(process.env.RATE_LIMIT_PER_MINUTE) || 60
  })
});
server.listen(port, () => {
  console.log(`aikeyboard-backend listening on :${port} (project=${project} model=${model})`);
});
