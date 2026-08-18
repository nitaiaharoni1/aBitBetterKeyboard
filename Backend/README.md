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
(`src/schema.js`), and `thinkingConfig.thinkingBudget: 0` on
`gemini-3.5-flash-lite` — measured 2026-08-14, thinking off kept Latin
loanwords and cut Fix to ~1.2s. On `gemini-2.5-flash`, 0 transliterated
`sync` into `סִינְק`; that is a different model. `src/vertexClient.js`
and `VertexTransport.swift` match.

Vertex's response comes back as one JSON object. Every value in it is either
already a string or gets `JSON.stringify`'d into one before it reaches the
client (`src/fields.js`), because the client does
`fields.compactMapValues { $0 as? String }` and silently drops anything that
isn't. That silent drop is the failure this guards: the screen reader's
`messages` list comes back from Vertex as an array, and an array simply
disappears on the way into Swift with no error anywhere. (An earlier version of
this paragraph priced it at "7 points". That number was retired — see
`CloudField.items` — the drop is silent either way, which is reason enough.)

## The analytics endpoint

`POST /v1/event` is the fourth endpoint and the odd one out: its client is
`AIKeyboard/Analytics/Analytics.swift` rather than `CloudTransport.swift`, it
never touches Vertex, and it is **unauthenticated on purpose**. App Attest gates
the three routes above because each of them spends money per call; a counter has
no cost and no abuse profile worth a Secure Enclave round trip, and gating it
would make the app's own setup funnel unmeasurable on exactly the installs where
attestation is what failed. It still runs inside the per-caller rate limiter and
takes a 4 KB body cap, three orders of magnitude below the model routes'.

The body is flat JSON: the envelope `Analytics.envelope` builds — `event`,
`install_id`, `app_version`, `os_version`, `sent_at` — plus that event's own
properties.

| | |
|---|---|
| 200 | `{"recorded": true}` |
| 400 | `{"error": "<what was expected>"}`, never quoting what the caller sent |
| 413 | body over 4 KB |
| 429 | the same per-caller limiter the other routes use, with `retry-after` |

**`src/eventHandler.js` is the never-list made checkable.** The policy
(`.claude/docs/analytics-policy.md`, sections 2 and 3) promises that no event
carries anything typed, corrected, dictated or read off a screen. The client keeps
that promise with a closed enum; this service keeps it with two tables — the six
event names with their exact property keys, and the envelope, whose four values
are matched against *patterns* rather than merely typed as strings, because "it is
a string" is the check that lets a sentence through. An install id that is not a
UUID, an app version that is not `0.1 (46)`, a timestamp that is not an instant:
all 400. Unknown event names and unknown property keys are 400. What is stored is
rebuilt key by key from those tables rather than being the body that arrived.

**The sink is the log, and its limits are real.** This service has no datastore
and adding one would be the first runtime dependency of a project whose stated
property is that it has none, so an accepted event is one structured line on
stdout (`{"analytics": {...}}`), which Cloud Run delivers to Cloud Logging as a
queryable `jsonPayload`. That means: retention is whatever the log bucket keeps
(30 days by default), counting means a log-based metric or a BigQuery sink rather
than a query, there is no dedupe (`Analytics.send` never retries, which is now
load-bearing on this side too), and a dropped log line is a lost event with
nothing to reconcile against. Good enough for a setup funnel; anything needing
joins over months needs a real sink, which is a new decision.

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

`GET /healthz` is outside this table: 200 `text/plain`, no
gate, because Cloud Run's own probes carry no bearer token. It answers that way
locally and 404s on the deployment, which is Google's frontend and not this
service — see "Known gaps". `POST /v1/event` is outside it too, and has its own
table above.

A 200 response to any of the three is either `{"fields": {...}}` or `{"refused": true}`. The
second is for a decline that isn't a safety verdict — Vertex's `RECITATION`
and `OTHER` finish reasons — so a log reader can tell "unsafe" apart from
"declined for some other reason" even though the client reads both the same
way: both decode to the identical `AIEngineError.refused`.

## Running it locally

```bash
cd Backend
gcloud auth login                      # once — the token this borrows is yours
PROJECT=handi-project node server.js   # PROJECT defaults to handi-project, MODEL to gemini-3.5-flash-lite
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
(`BackendTransport.bundledDefaultURL`); the token is not in the bundle.
`AppAttestation` fills it. Deploying it took two grants this
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
run without both of this service's own gates:

```bash
SESSION_SECRET=$(openssl rand -hex 32) BACKEND_TOKEN=$(openssl rand -hex 32) \
  PROJECT=handi-project ./deploy.sh
```

`SESSION_SECRET` is the gate a shipping install passes. The app proves itself
with App Attest at `/v1/attest`, the service signs it a ninety-day token, and
nothing is ever typed in by anybody.

`BACKEND_TOKEN` is the door behind it, and it is required too: a simulator has no
Secure Enclave and cannot attest at all, so without it no cloud action can be
exercised anywhere but on a device. Anyone running this backend themselves uses
the same door. Put its value in the app's `cloudBackendToken` setting, which
exists in Debug builds only.

See "Known gaps" for what these are and are not.

## Known gaps

- **The gate is App Attest now, and what it does not cover is a session token
  sitting on the device it was issued to.** `IAM` cannot be the gate here: the
  caller is a keyboard extension making a plain `URLSession` request with no
  Google identity, so the service has to be `--allow-unauthenticated`, which
  leaves a URL where every request costs money. That URL also ships in the app
  (`BackendTransport.bundledDefaultURL`), so it is public by construction.

  `src/attestationVerifier.js` closes it properly: the containing app raises an
  App Attest statement, this service checks it against Apple's vendored root and
  against `9R8P28G4BJ.com.nitai.aikeyboard`, and signs back a ninety-day session
  token. Nothing is typed in and there is nothing to leak. The gate and the rate
  limit still run before the request body is read, so a refused caller cannot make
  this service buffer 8 MB on their behalf, and the connection is closed rather
  than left open — answering a slow POST without hanging up is a
  connection-exhaustion route that costs the attacker nothing and never reaches
  the model.

  **What survives.** A session token is a bearer in the App Group, so the owner
  of a device can read their own and use it off-device until it expires. That is
  bounded by the ninety days and by the per-device rate limit, which is now the
  real control — `callerKey` counts on the attested device rather than on
  `x-forwarded-for`, so a leaked token buys one device's quota instead of a whole
  carrier NAT's. There is no revocation list: this service stores nothing, so the
  only way to kill a token early is rotating `SESSION_SECRET`, which kills every
  token at once and makes every app re-attest on its next launch.

  **`BACKEND_TOKEN` is still here and still a shared secret**, because a
  simulator has no Secure Enclave and cannot attest. It is a Debug-only field in
  the app now, so no shipping install has one, but on the service it is exactly as
  strong as whoever holds it keeps it.

  The rate limiter still counts **in one process**, and `deploy.sh` still sets
  `--max-instances=10`, so the real ceiling is up to ten times the per-instance
  limit and a caller spread across instances sees a looser bound than the number
  suggests. Per-device keying makes each bucket the right size without making the
  count shared. Bounding it properly still means shared state (Cloud Armor, or
  Redis).

  **Receipt validation is not done.** The attestation carries a receipt that can
  be exchanged with Apple for fraud metrics and a risk score. It is a separate
  server-to-server flow with its own key, and nothing here depends on it.
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
