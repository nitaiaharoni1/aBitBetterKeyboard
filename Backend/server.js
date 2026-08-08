// Entrypoint. Wires the real token source and the real Vertex call together
// and starts listening — every seam used here (`fetch`, `execFile`) is the
// production implementation; `test/` wires fakes for the same modules
// instead of importing this file at all.

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { createRateLimiter } from "./src/gate.js";
import { createServer } from "./src/httpServer.js";
import { createTokenProvider } from "./src/token.js";
import { createVertexClient } from "./src/vertexClient.js";

const execFileAsync = promisify(execFile);

const project = process.env.PROJECT || "handi-project";
const model = process.env.MODEL || "gemini-2.5-flash";
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

const server = createServer({
  vertexClient,
  expectedToken,
  rateLimiter: createRateLimiter({
    maxPerWindow: Number(process.env.RATE_LIMIT_PER_MINUTE) || 60
  })
});
server.listen(port, () => {
  console.log(`aikeyboard-backend listening on :${port} (project=${project} model=${model})`);
});
