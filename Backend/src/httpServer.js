// The one file that touches `node:http`. Everything it does is either read a
// request into a JS object or write one back out — the actual work is
// `requestHandler.js`, which never sees a socket.

import { createServer as createHttpServer } from "node:http";
import { handleEvent } from "./eventHandler.js";
import { authorize, callerKey, createRateLimiter } from "./gate.js";
import { handleRequest } from "./requestHandler.js";

// Generous headroom over anything this service should ever see: the
// screen-context bar's own numbers put a q0.70 JPEG at this quality at a
// median of 66 KB and a max of 250 KB unscaled
// (`Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudScreenReader.swift`),
// base64 included. 8 MB rejects abuse without rejecting anything real.
// Dictation is what sets this now, not screen reading. `SpeechGate.maximumSeconds`
// caps an utterance at 60s, and 16 kHz mono LEI16 is 32 KB a second, so the
// worst honest body is ~1.9 MB of PCM and ~2.6 MB once base64 puts it in JSON.
// 8 MB still rejects abuse without rejecting anything real.
const DEFAULT_MAX_BODY_BYTES = 8 * 1024 * 1024;

// An attestation is about 5 KB. The 8 MB cap above exists for dictation audio
// and screen JPEGs, and applying it to `/v1/attest` would let anybody make this
// service buffer 8 MB before it has proved anything at all — which is exactly
// the exhaustion route `sendJSONAndClose` was written to close.
const ATTEST_MAX_BODY_BYTES = 64 * 1024;

// An event is an envelope and at most three small properties: the largest one
// `AnalyticsEvent` can build is about 250 bytes. 4 KB leaves room for a longer
// version number without leaving room for anything interesting, and the same
// reasoning as the line above applies twice over here, because `/v1/event` is
// unauthenticated by design.
const EVENT_MAX_BODY_BYTES = 4 * 1024;

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
  rateLimiter = createRateLimiter(),
  // Both absent means no attestation route exists at all, which is what the
  // suites that only exercise the model path get. `server.js` always supplies
  // them, and refuses to start if it cannot.
  tokens = null,
  attestationVerifier = null
} = {}) {
  return createHttpServer(async (req, res) => {
    // Deliberately before the gate: Cloud Run's own health checks carry no
    // bearer token and must not be rate-limited into failing the revision.
    if (req.method === "GET" && req.url === "/healthz") {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end("ok");
      return;
    }

    // **How a device gets a bearer, so necessarily reached without one.**
    //
    // Neither route costs a model call, both stay inside the rate limiter, and
    // both use a body cap two orders of magnitude smaller than the model
    // routes' — an unauthenticated endpoint that will buffer 8 MB is a denial
    // of service with a polite name.
    const route = req.method === "POST" ? req.url : null;
    if (tokens && attestationVerifier && (route === "/v1/challenge" || route === "/v1/attest")) {
      const allowance = rateLimiter.check(callerKey(req, null));
      if (!allowance.ok) {
        sendJSONAndClose(
          req, res, allowance.status, { error: allowance.error },
          { "retry-after": String(allowance.retryAfterSeconds) }
        );
        return;
      }

      if (route === "/v1/challenge") {
        // **Closed, not merely answered, because this branch never reads a
        // body.** It is a POST, so a caller can announce `Content-Length:
        // 100000000` and trickle it; answering without hanging up leaves that
        // socket open and counted for as long as they care to hold it. That is
        // the exhaustion route `sendJSONAndClose` exists for, and it applies
        // here more than anywhere: this is the one route that answers 200 to a
        // caller who has proved nothing at all.
        sendJSONAndClose(req, res, 200, { challenge: await tokens.signChallenge() });
        return;
      }

      let attestBody;
      try {
        const raw = await readBody(req, ATTEST_MAX_BODY_BYTES);
        attestBody = raw.length > 0 ? JSON.parse(raw.toString("utf8")) : {};
      } catch (error) {
        if (error.tooLarge) sendJSONAndClose(req, res, 413, { error: "request body too large" });
        else sendJSONAndClose(req, res, 400, { error: "could not read request body" });
        return;
      }

      const { keyId, attestation, challenge } = attestBody ?? {};
      if (
        typeof keyId !== "string" ||
        typeof attestation !== "string" ||
        typeof challenge !== "string"
      ) {
        sendJSON(res, 400, { error: "keyId, attestation and challenge are required" });
        return;
      }

      // Checked first and separately: an attestation raised against a nonce this
      // service never issued is a replay, and there is no reason to spend
      // certificate parsing on one.
      if (!(await tokens.verifyChallenge(challenge))) {
        sendJSONAndClose(req, res, 401, { error: "attestation refused" });
        return;
      }

      const verdict = await attestationVerifier.verify({
        attestation: Buffer.from(attestation, "base64"),
        keyId,
        challenge
      });
      if (!verdict.ok) {
        // One message for all ten checks. `verdict.reason` is for whoever reads
        // the logs and stops at this line: a 401 that says which check fired is
        // a tutorial for the person trying to get past it.
        console.warn(`attestation refused: ${verdict.reason}`);
        sendJSONAndClose(req, res, 401, { error: "attestation refused" });
        return;
      }

      sendJSON(res, 200, await tokens.signSession(verdict.deviceId));
      return;
    }

    // **Unauthenticated deliberately, and the reasoning is not "it is only
    // analytics".** App Attest gates the three routes below because each of them
    // spends this project's Vertex budget on every call; a counter costs nothing
    // per request and has no abuse profile worth a Secure Enclave round trip.
    // Gating it would also make the app's own setup funnel unmeasurable on
    // exactly the installs where attestation is what failed — the population the
    // funnel most needs to see. See `.claude/docs/analytics-policy.md` section 5,
    // and `eventHandler.js` for what an unauthenticated endpoint is allowed to
    // store, which is only what its own two tables name.
    //
    // It stays inside the rate limiter and takes a body cap three orders of
    // magnitude below the model routes', for the same reason `/v1/challenge`
    // does: an unauthenticated endpoint that will buffer 8 MB is a denial of
    // service with a polite name.
    if (route === "/v1/event") {
      const allowance = rateLimiter.check(callerKey(req, null));
      if (!allowance.ok) {
        sendJSONAndClose(
          req, res, allowance.status, { error: allowance.error },
          { "retry-after": String(allowance.retryAfterSeconds) }
        );
        return;
      }

      let eventBody;
      try {
        const raw = await readBody(req, EVENT_MAX_BODY_BYTES);
        eventBody = raw.length > 0 ? JSON.parse(raw.toString("utf8")) : {};
      } catch (error) {
        if (error.tooLarge) sendJSONAndClose(req, res, 413, { error: "request body too large" });
        else sendJSONAndClose(req, res, 400, { error: "could not read request body" });
        return;
      }

      const { status, body } = handleEvent(eventBody);
      sendJSON(res, status, body);
      return;
    }

    if (route !== "/v1/text" && route !== "/v1/screen" && route !== "/v1/audio") {
      sendJSONAndClose(req, res, 404, { error: "not found" });
      return;
    }

    // Both gates run before the body is read, so an unauthorised or
    // rate-limited caller cannot make this service buffer 8 MB on their behalf,
    // let alone pay for a model call.
    const auth = await authorize({
      expectedToken,
      headers: req.headers,
      verifySession: tokens?.verifySession
    });
    if (!auth.ok) {
      // Mirrors the attestation log above: the reason stays server-side and
      // the caller gets one message regardless of which of the four it was.
      // `auth.reason` is only ever set on the paths gate.js documents — never
      // free text, never the token, never anything a caller sent.
      if (auth.reason) console.warn(`session token rejected: ${auth.reason}`);
      sendJSONAndClose(req, res, auth.status, { error: auth.error });
      return;
    }

    const allowance = rateLimiter.check(callerKey(req, auth.deviceId));
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
