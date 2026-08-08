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
`Bar/screen-context/harness/vertex_vision.py`) — **including where those two
disagree**: `vertex_vision.py` sets `temperature: 0` and `VertexTransport.swift`
sets no temperature at all, so `/v1/screen` sends it and `/v1/text` does not.
That asymmetry is the point; sending 0 on both would look tidier and would mean
every text action ran a configuration the ai-text corpus never graded. Shared by
both: a `responseSchema` built from `fields` with `propertyOrdering` preserved
(`src/schema.js`), and `thinkingConfig.thinkingBudget: 512` — capped, not off:
0 breaks the Hebrew/English code-switching this product exists for, and
unbounded pushes the tail to 17–18s (see `VertexTransport.swift`'s comment on
`thinkingBudget` for the numbers that measurement produced; `src/vertexClient.js`
matches it).

Vertex's response comes back as one JSON object. Every value in it is either
already a string or gets `JSON.stringify`'d into one before it reaches the
client (`src/fields.js`), because the client does
`fields.compactMapValues { $0 as? String }` and silently drops anything that
isn't. That silent drop is the failure this guards: the screen reader's
`messages` list comes back from Vertex as an array, and an array simply
disappears on the way into Swift with no error anywhere. (An earlier version of
this paragraph priced it at "7 points". That number was retired — see
`CloudField.items` — the drop is silent either way, which is reason enough.)

## Error mapping

The client (`BackendTransport.mapped`) already knows how to read exactly
these statuses, so this service produces exactly these and nothing else for a
failure:

| Status | Meaning |
|---|---|
| 401 | either this service's bearer token was missing or wrong (`src/gate.js`), or Vertex rejected ours. The client reads both as "cloud not configured", which is the honest reading from the app's side |
| 403 | Vertex rejected our credential with a forbidden. Never produced by the gate |
| 413 | request body too large |
| 422 | Vertex declined the content on safety grounds |
| 429 | either this service's own per-caller rate limit (`src/gate.js`, sent with `retry-after`) or Vertex rate-limiting the project |
| 5xx | Vertex, or this service, is unavailable |
| anything else | `{"error": "<message>"}`, surfaced to the user verbatim |

`GET /healthz` is the one endpoint outside this table: 200 `text/plain`, no
gate, because Cloud Run's own probes carry no bearer token.

A 200 response to either POST is either `{"fields": {...}}` or `{"refused": true}`. The
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
to re-run) and deploys with `--allow-unauthenticated`, because the caller is a
keyboard extension with no Google identity and IAM cannot gate it. It refuses to
run without `BACKEND_TOKEN`, which is this service's own gate:

```bash
BACKEND_TOKEN=$(openssl rand -hex 32) PROJECT=handi-project ./deploy.sh
```

Put the same value in the app's `cloudBackendToken` setting beside its URL. See
"Known gaps" for what that gate is and is not.

## Known gaps

- **The gate is a shared secret, and a shared secret has a ceiling.** `IAM`
  cannot be the gate here: the caller is a keyboard extension making a plain
  `URLSession` request with no Google identity, so the service has to be
  `--allow-unauthenticated`, which leaves a URL where every request costs
  money. `src/gate.js` closes the obvious half of that — set `BACKEND_TOKEN`
  and `BackendTransport` sends it as a bearer from the app's
  `cloudBackendToken` setting, and a rate limit per caller bounds the damage if it
  leaks or a client loops on retry. `deploy.sh` refuses to deploy without one.
  Both run before the request body is read, so a refused caller cannot make this
  service buffer 8 MB on their behalf, and the connection is closed rather than
  left open — answering a slow POST without hanging up is a connection-exhaustion
  route that costs the attacker nothing and never reaches the model.

  The rate limiter counts **in one process**, and `deploy.sh` sets
  `--max-instances=10`, so the real ceiling is up to ten times the per-instance
  limit and a caller spread across instances sees a looser bound than the number
  suggests. Bounding it properly means shared state (Cloud Armor, or Redis).

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
