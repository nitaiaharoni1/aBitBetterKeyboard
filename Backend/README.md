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

Three endpoints, all POST, all JSON, matching `CloudTransport.swift` exactly:

- `POST /v1/text` — text actions (Fix, Rewrite, Tone, Reply)
- `POST /v1/audio` — one WAV of an utterance, for dictation (its own endpoint
  for the same reason the screen has one: a recording of somebody's voice earns
  its own retention rule)
- `POST /v1/screen` — one downscaled JPEG of the user's screen (its own
  endpoint so images can carry their own retention rule, separate from text)

All three take `{instructions, prompt, fields, image?, audio?}` and forward it to Vertex AI
Gemini as one `generateContent` call, built the way the scoring harnesses
build it (`Bar/ai-text/harness/VertexTransport.swift`,
`Bar/screen-context/harness/vertex_vision.py`) — **including where those two
disagree**: `vertex_vision.py` sets `temperature: 0` and `VertexTransport.swift`
sets no temperature at all, so `/v1/screen` and `/v1/audio` send it and
`/v1/text` does not (`src/vertexClient.js`: `if (image || audio)`).
That asymmetry is the point; sending 0 on all three would look tidier and would
mean every text action ran a configuration the ai-text corpus never graded.
Shared by all three: a `responseSchema` built from `fields` with `propertyOrdering` preserved
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
gate, because Cloud Run's own probes carry no bearer token. It answers that way
locally and 404s on the deployment, which is Google's frontend and not this
service — see "Known gaps".

A 200 response to any of the three is either `{"fields": {...}}` or `{"refused": true}`. The
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
BACKEND_TOKEN=... PROJECT=handi-project REGION=europe-west1 ./deploy.sh
```

**Live since 2026-08-10** at
`https://aikeyboard-backend-cq6zxsdx5a-ew.a.run.app`, in `handi-project`,
`europe-west1`. That address is the one the app ships pointing at
(`BackendTransport.bundledDefaultURL`); the token is not in the bundle and is
typed into `Settings › AI › Cloud model`. Deploying it took two grants this
README did not mention and `deploy.sh` does not make: `cloudbuild.googleapis.com`
had never been enabled on the project, and the Cloud Build default service
account (`<projectNumber>-compute@developer.gserviceaccount.com`) needed
`roles/cloudbuild.builds.builder` before `--source=.` could read its own upload.
Both are one-time and already done here. Allow a few minutes for an IAM grant to
propagate — two deploys failed with the same `PERMISSION_DENIED` after the role
was correctly bound, and the third succeeded with nothing else changed.

That deployment is also what retired this file's "the metadata-server token path
has never run against a real metadata server" gap: every answered call through
the Cloud Run service takes it, since there is no `gcloud` on that host.

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
- **`/healthz` answers locally and 404s in the deployment, and it is not this
  service that refuses it.** `curl localhost:8080/healthz` returns `ok`; the same
  path on Cloud Run comes back as Google's own HTML 404, without the
  `server: Google Frontend` header that this service's real 404s carry, so the
  request is being answered in front of the container rather than by it. Nothing
  in the app calls it — `BackendTransport` only ever posts to `/v1/text`,
  `/v1/screen` and `/v1/audio`, all three of which were checked against the
  deployment — so this is documentation drift rather than an outage. Do not "fix" it in `httpServer.js`: line 86 matches the path exactly and
  is provably reached, since `/nonsense` on the same deployment returns this
  service's own JSON 404.
- **`Bar/`'s harnesses are not wired to call this service.** They still talk
  to Vertex directly with a `gcloud` token on the scoring machine
  (`VertexTransport.swift`, `vertex_vision.py`) — that's deliberate, so a
  corpus run measures the model, not this service's own latency and error
  handling on top of it.
