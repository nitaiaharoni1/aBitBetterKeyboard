#!/usr/bin/env bash
set -euo pipefail

# Deploys the backend that `BackendTransport`
# (Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift)
# posts to. Nothing in the repo runs this automatically — whoever is
# deploying runs it by hand, from this directory or anywhere:
#   SESSION_SECRET=... BACKEND_TOKEN=... ./deploy.sh

PROJECT="${PROJECT:-handi-project}"
# **This has to match the region in `BackendTransport.bundledDefaultURL`, and
# it did not.** The default used to be us-central1 while the only service that
# has ever existed runs in europe-west1, which is the region baked into the
# address every install posts to. Deploying with the default therefore did not
# update the service the app talks to: it stood up a second, identical service
# in another region that nothing pointed at, left the real one serving whatever
# it was already serving, and reported success. Changing the address in the app
# is a release; changing it here is a flag. Keep them equal.
REGION="${REGION:-europe-west1}"
SERVICE="${SERVICE:-aikeyboard-backend}"
MODEL="${MODEL:-gemini-3.5-flash-lite}"

cd "$(dirname "$0")"

# Cloud Run's default runtime identity needs permission to call Vertex before
# the service can do anything useful. Idempotent: re-running this against a
# project that already has the binding is a no-op, not an error. If the
# service is deployed with a custom `--service-account`, grant that account
# the role instead and skip this block.
RUNTIME_SA="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${RUNTIME_SA}" \
  --role="roles/aiplatform.user" \
  --condition=None \
  --quiet

# `--allow-unauthenticated` is unavoidable: the caller is a keyboard extension
# making a plain URLSession request and it carries no Google identity, so IAM
# cannot be the gate. That leaves an endpoint where every request costs money.
#
# Two gates close it, and they are not alternatives. SESSION_SECRET is the one a
# shipping install passes: the app proves itself with App Attest, the service
# signs it a ninety-day token, and nothing is ever typed in. BACKEND_TOKEN is the
# door behind it, for a simulator (which has no Secure Enclave, so it cannot
# attest at all) and for anyone running this backend themselves. Both are
# required here because deploying with only one leaves either real users or every
# developer locked out. See src/gate.js.
if [ -z "${BACKEND_TOKEN:-}" ]; then
  echo "BACKEND_TOKEN is not set." >&2
  echo >&2
  echo "This service proxies a paid model on a URL anyone can reach. It is the" >&2
  echo "developer and self-hosting door; App Attest is what real installs use." >&2
  echo >&2
  echo "  SESSION_SECRET=\$(openssl rand -hex 32) BACKEND_TOKEN=\$(openssl rand -hex 32) ./deploy.sh" >&2
  exit 1
fi

# Signs the session tokens attested devices are issued. Rotating it logs every
# device out at once — they re-attest on their next app launch, so the blast
# radius is "AI is unavailable in the keyboard until each user opens the app",
# not a permanent break. It is also the only revocation there is: a session token
# carries its own expiry and this service stores nothing, so there is no list to
# remove one from.
#
# **Generate it once and keep it. Do not generate it per deploy.** The secret
# signs every session token already sitting on every device, so a redeploy under
# a fresh one invalidates all of them at that instant, and a device cannot tell
# that from a forged token: it gets a flat 401 on the AI action the user just
# pressed, then retries into the same wall. That is what the 2026-08-14 bursts in
# NIT-87 look like, both of which follow revision 00004 by minutes. An earlier
# version of this message printed `openssl rand -hex 32` as the example for every
# run, which is how the habit started.
#
# Rotating on purpose is fine, but hand the old value over for one deploy:
#
#   SESSION_SECRET=<new> SESSION_SECRET_PREVIOUS=<old> ./deploy.sh
#
# Tokens signed under the old secret keep verifying until they expire on their
# own, and nothing new is ever signed with it. Drop the variable on the deploy
# after that.
if [ -z "${SESSION_SECRET:-}" ]; then
  echo "SESSION_SECRET is not set." >&2
  echo >&2
  echo "Without it /v1/challenge and /v1/attest are switched off, no device can" >&2
  echo "attest, and every install falls back to a token nobody has typed in." >&2
  echo >&2
  echo "Generate it ONCE, keep it somewhere you can read back, and reuse it on" >&2
  echo "every deploy. A fresh secret 401s every device that has already attested." >&2
  echo >&2
  echo "  SESSION_SECRET=\"\$(cat ~/.aikeyboard-session-secret)\" BACKEND_TOKEN=... ./deploy.sh" >&2
  echo >&2
  echo "First time only:" >&2
  echo "  openssl rand -hex 32 > ~/.aikeyboard-session-secret" >&2
  echo >&2
  echo "Rotating on purpose? Pass the outgoing value as SESSION_SECRET_PREVIOUS" >&2
  echo "for one deploy so live tokens keep working until they expire." >&2
  exit 1
fi

gcloud run deploy "$SERVICE" \
  --project="$PROJECT" \
  --region="$REGION" \
  --source=. \
  --allow-unauthenticated \
  --set-env-vars="PROJECT=${PROJECT},MODEL=${MODEL}" \
  --set-env-vars="BACKEND_TOKEN=${BACKEND_TOKEN}" \
  --set-env-vars="SESSION_SECRET=${SESSION_SECRET}" \
  --set-env-vars="SESSION_SECRET_PREVIOUS=${SESSION_SECRET_PREVIOUS:-}" \
  --set-env-vars="APP_ID=${APP_ID:-9R8P28G4BJ.com.nitai.aikeyboard}" \
  --set-env-vars="ATTEST_ENV=${ATTEST_ENV:-production}" \
  --memory=256Mi \
  --min-instances=0 \
  --max-instances=10

echo
echo "Deployed. Point the app's cloudBackendURL setting at:"
gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(status.url)'
