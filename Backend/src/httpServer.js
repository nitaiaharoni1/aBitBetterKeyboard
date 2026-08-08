// The one file that touches `node:http`. Everything it does is either read a
// request into a JS object or write one back out — the actual work is
// `requestHandler.js`, which never sees a socket.

import { createServer as createHttpServer } from "node:http";
import { authorize, callerKey, createRateLimiter } from "./gate.js";
import { handleRequest } from "./requestHandler.js";

// Generous headroom over anything this service should ever see: the
// screen-context bar's own numbers put a q0.70 JPEG at this quality at a
// median of 66 KB and a max of 250 KB unscaled
// (`Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudScreenReader.swift`),
// base64 included. 8 MB rejects abuse without rejecting anything real.
const DEFAULT_MAX_BODY_BYTES = 8 * 1024 * 1024;

function sendJSON(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

// Answers, then hangs up.
//
// Every branch that replies *before* the request body has been consumed has to
// tear the connection down, and none of them did. Sending a 401 to a caller who
// announced `Content-Length: 100000000` and then trickles a byte every few
// hundred milliseconds leaves that socket open and counted for as long as they
// care to hold it: node has answered, but nothing told the client to go away and
// nothing stopped listening. Repeat it in parallel and every instance's
// connection budget is gone, which starves real traffic or forces `deploy.sh`'s
// `--max-instances` worth of autoscaling.
//
// The important part is *which* branches: 401, 429, 404 and 413 all fire before
// or during the body read, so this costs the attacker no token, no successful
// auth and no model call. It is the one exhaustion route that sidesteps the gate
// entirely, which is exactly what the gate exists to prevent.
//
// `Connection: close` tells a well-behaved client; destroying the socket handles
// the rest. Destroyed on `finish` rather than immediately, because destroying a
// socket with bytes still buffered truncates the response the client came for.
function sendJSONAndClose(req, res, status, body, headers = {}) {
  res.writeHead(status, { "content-type": "application/json", connection: "close", ...headers });
  res.end(JSON.stringify(body), () => {
    req.destroy();
    res.socket?.destroy();
  });
}

// Rejects early rather than buffering an oversized body to completion first —
// the whole point of a byte cap is to stop reading, not to read everything
// and then complain.
function readBody(req, maxBytes) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    let rejected = false;
    req.on("data", (chunk) => {
      if (rejected) return;
      total += chunk.length;
      if (total > maxBytes) {
        rejected = true;
        reject(Object.assign(new Error("request body too large"), { tooLarge: true }));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      if (!rejected) resolve(Buffer.concat(chunks));
    });
    req.on("error", reject);
  });
}

export function createServer({
  vertexClient,
  maxBodyBytes = DEFAULT_MAX_BODY_BYTES,
  expectedToken = null,
  rateLimiter = createRateLimiter()
} = {}) {
  return createHttpServer(async (req, res) => {
    // Deliberately before the gate: Cloud Run's own health checks carry no
    // bearer token and must not be rate-limited into failing the revision.
    if (req.method === "GET" && req.url === "/healthz") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("ok");
      return;
    }

    const route = req.method === "POST" ? req.url : null;
    if (route !== "/v1/text" && route !== "/v1/screen") {
      sendJSONAndClose(req, res, 404, { error: "not found" });
      return;
    }

    // Both gates run before the body is read, so an unauthorised or
    // rate-limited caller cannot make this service buffer 8 MB on their behalf,
    // let alone pay for a model call.
    const auth = authorize({ expectedToken, headers: req.headers });
    if (!auth.ok) {
      sendJSONAndClose(req, res, auth.status, { error: auth.error });
      return;
    }

    const allowance = rateLimiter.check(callerKey(req));
    if (!allowance.ok) {
      sendJSONAndClose(
        req, res, allowance.status, { error: allowance.error },
        { "retry-after": String(allowance.retryAfterSeconds) }
      );
      return;
    }

    let raw;
    try {
      raw = await readBody(req, maxBodyBytes);
    } catch (error) {
      // Both of these happen mid-body, so the connection goes with the answer:
      // a client that has already overrun the cap has no second request coming
      // that we want to keep a socket warm for.
      if (error.tooLarge) sendJSONAndClose(req, res, 413, { error: "request body too large" });
      else sendJSONAndClose(req, res, 400, { error: "could not read request body" });
      return;
    }

    let body;
    try {
      body = raw.length > 0 ? JSON.parse(raw.toString("utf8")) : {};
    } catch {
      sendJSON(res, 400, { error: "request body must be valid JSON" });
      return;
    }

    try {
      const { status, body: responseBody } = await handleRequest(body, { vertexClient });
      sendJSON(res, status, responseBody);
    } catch (error) {
      // A bug in this service, not the request — still answer inside the
      // "5xx = unavailable" bucket rather than let the socket hang.
      sendJSON(res, 500, { error: `internal error: ${error.message}` });
    }
  });
}
