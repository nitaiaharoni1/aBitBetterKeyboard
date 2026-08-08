# Backend

The service `BackendTransport`
(`Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift`)
posts to. The app and its two extensions hold no cloud credential — anything
in an app bundle is extractable — so this is the only thing in the whole
product that ever sees a Vertex AI token, and it never sees it as a file: no
service-account key is written to disk, `GOOGLE_APPLICATION_CREDENTIALS` is
never set, and locally it borrows whatever `gcloud auth login` already put in
your shell.

Node.js, zero runtime dependencies.

## What it does

Two endpoints, both POST, both JSON, matching `CloudTransport.swift` exactly:

- `POST /v1/text` — text actions (Fix, Rewrite, Tone, Reply)
- `POST /v1/screen` — one downscaled JPEG of the user's screen (its own
  endpoint so images can carry their own retention rule, separate from text)

Both take `{instructions, prompt, fields, image?}` and forward it to Vertex AI
Gemini as one `generateContent` call, built the way the scoring harnesses
build it (`Bar/ai-text/harness/VertexTransport.swift`,
`Bar/screen-context/harness/vertex_vision.py`): `temperature: 0`, a
`responseSchema` built from `fields` with `propertyOrdering` preserved
(`src/schema.js`), and `thinkingConfig.thinkingBudget: 512` — capped, not off:
0 breaks the Hebrew/English code-switching this product exists for, and
unbounded pushes the tail to 17–18s (see `VertexTransport.swift`'s comment on
`thinkingBudget` for the numbers that measurement produced; `src/vertexClient.js`
matches it).

Vertex's response comes back as one JSON object. Every value in it is either
already a string or gets `JSON.stringify`'d into one before it reaches the
client (`src/fields.js`), because the client does
`fields.compactMapValues { $0 as? String }` and silently drops anything that
isn't — the exact failure mode that would otherwise cost the screen reader 7
points with no error anywhere.

## Error mapping

The client (`BackendTransport.mapped`) already knows how to read exactly
these statuses, so this service produces exactly these and nothing else for a
failure:

| Status | Meaning |
|---|---|
| 401 / 403 | no usable credential — ours (can't reach Vertex at all) or Vertex's (it rejected the one we sent) |
| 413 | request body too large |
| 422 | Vertex declined the content on safety grounds |
| 429 | Vertex is rate-limiting this project |
| 5xx | Vertex, or this service, is unavailable |
| anything else | `{"error": "<message>"}`, surfaced to the user verbatim |

A 200 response is either `{"fields": {...}}` or `{"refused": true}`. The
second is for a decline that isn't a safety verdict — Vertex's `RECITATION`
and `OTHER` finish reasons — so a log reader can tell "unsafe" apart from
"declined for some other reason" even though the client reads both the same
way: both decode to the identical `AIEngineError.refused`.

## Running it locally

```bash
cd Backend
gcloud auth login                      # once — the token this borrows is yours
PROJECT=handi-project node server.js   # PROJECT defaults to handi-project, MODEL to gemini-2.5-flash
```

Whichever account `gcloud auth print-access-token` resolves to needs
`roles/aiplatform.user` (or broader) on that project. Then, from another
terminal:

```bash
curl localhost:8080/v1/text -X POST -H 'content-type: application/json' -d '{
  "instructions": "Fix spelling and grammar only.",
  "prompt": "fields.corrections = what changed, fields.text = corrected text\n\nText: helo there",
  "fields": [
    {"name": "corrections", "description": "What changed, or \"none\"."},
    {"name": "text", "description": "The corrected text."}
  ]
}'
```

## Tests

```bash
npm test   # node --test — no network calls anywhere in the suite
```

The Vertex HTTP call is the one seam every test replaces
(`src/vertexClient.js`'s `fetchImpl`), and `src/token.js`'s `fetchImpl` /
`execFileImpl` are the seams for the credential lookup, so nothing under
`test/` touches a real socket or spawns `gcloud` — including the
`httpServer.test.js` cases, which start a real `http.Server` on a loopback
port but always hand it a fake `vertexClient`.

## Deploying

```bash
PROJECT=handi-project REGION=us-central1 ./deploy.sh
```

Not run automatically by anything — deploy by hand. The script grants the
Cloud Run default runtime identity `roles/aiplatform.user` (idempotent, safe
to re-run) and deploys with `--allow-unauthenticated`, because
`BackendTransport.send` sends no auth header of its own; requiring one here
would 401 every real request from the app. See "Known gaps" below for what
that trade-off costs.

## Known gaps

- **The gate is a shared secret, and a shared secret has a ceiling.** `IAM`
  cannot be the gate here: the caller is a keyboard extension making a plain
  `URLSession` request with no Google identity, so the service has to be
  `--allow-unauthenticated`, which leaves a URL where every request costs
  money. `src/gate.js` closes the obvious half of that — set `BACKEND_TOKEN`
  and `BackendTransport` sends it as a bearer from the app's
  `cloudBackendToken` setting, and a per-IP rate limit bounds the damage if it
  leaks or a client loops on retry. `deploy.sh` refuses to deploy without one.

  What this is *not*: protection from a determined user of the app itself.
  Nothing ships the token in the bundle — for the same reason no provider
  credential ships there, anything in a bundle is extractable — but a token
  typed into settings is still only as private as the person holding it. For a
  shipping consumer build the right control is **App Attest**, which proves the
  caller is a genuine unmodified copy of this app on real Apple hardware rather
  than proving it knows a string. That needs a client change and an Apple key,
  and it has not been done.
- **The metadata-server token path has never run against a real metadata
  server.** It matches the documented shape and is covered by
  `test/token.test.js` with a fake `fetch`, but there is no Cloud Run
  instance deployed yet to exercise it against the real one — `deploy.sh` was
  written and not run, per the task that produced this service.
- **`Bar/`'s harnesses are not wired to call this service.** They still talk
  to Vertex directly with a `gcloud` token on the scoring machine
  (`VertexTransport.swift`, `vertex_vision.py`) — that's deliberate, so a
  corpus run measures the model, not this service's own latency and error
  handling on top of it.
