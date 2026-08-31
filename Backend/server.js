// Entrypoint. Wires the real token source and the real Vertex call together
// and starts listening — every seam used here (`fetch`, `execFile`) is the
// production implementation; `test/` wires fakes for the same modules
// instead of importing this file at all.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { APPLE_APP_ATTEST_ROOT_PEM } from "./src/appleRoot.js";
import { createAttestationVerifier } from "./src/attestationVerifier.js";
import { createAuthorizer, createRateLimiter, ServiceMode } from "./src/gate.js";
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

// The service has three deliberately separate modes. Production has one door:
// an App Attest session. A shared developer token can never become a hidden
// production fallback, and an open server can never start on Cloud Run.
const serviceMode = process.env.SERVICE_MODE;
const developerToken = process.env.BACKEND_TOKEN || null;
const sessionSecret = process.env.SESSION_SECRET || null;
const previousSessionSecret = process.env.SESSION_SECRET_PREVIOUS || null;
let sessionTokens = null;
let attestationVerifier = null;

if (serviceMode === ServiceMode.PRODUCTION) {
  if (!sessionSecret) {
    throw new Error("production-app-attest requires SESSION_SECRET");
  }
  sessionTokens = createTokens({
    secret: sessionSecret,
    previousSecrets: previousSessionSecret ? [previousSessionSecret] : []
  });
  attestationVerifier = createAttestationVerifier({
    rootCertificatePem: APPLE_APP_ATTEST_ROOT_PEM,
    appId: process.env.APP_ID || "9R8P28G4BJ.com.nitai.aikeyboard",
    environment: "production"
  });
} else if (sessionSecret || previousSessionSecret) {
  throw new Error("session secrets are only valid in production-app-attest mode");
}

if (serviceMode === ServiceMode.LOCAL_OPEN && process.env.K_SERVICE) {
  throw new Error("local-open is forbidden on Cloud Run");
}

const authorizeRequest = createAuthorizer({
  mode: serviceMode,
  verifySession: sessionTokens?.verifySession,
  developerToken
});

const server = createServer({
  vertexClient,
  authorizeRequest,
  tokens: sessionTokens,
  attestationVerifier,
  rateLimiter: createRateLimiter({
    maxPerWindow: Number(process.env.RATE_LIMIT_PER_MINUTE) || 60
  })
});
// An unauthenticated development server is reachable only from this machine.
// Testing from another device requires developer-token mode, so a laptop on a
// shared network can never expose an open model proxy by accident.
const bindHost = serviceMode === ServiceMode.LOCAL_OPEN ? "127.0.0.1" : undefined;
server.listen(port, bindHost, () => {
  console.log(
    `aikeyboard-backend listening on ${bindHost ?? "all interfaces"}:${port} (project=${project} model=${model} mode=${serviceMode})`
  );
});
