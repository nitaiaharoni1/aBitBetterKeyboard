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
if [ -z "${SESSION_SECRET:-}" ]; then
  echo "SESSION_SECRET is not set." >&2
  echo >&2
  echo "Without it /v1/challenge and /v1/attest are switched off, no device can" >&2
  echo "attest, and every install falls back to a token nobody has typed in." >&2
  echo >&2
  echo "  SESSION_SECRET=\$(openssl rand -hex 32) BACKEND_TOKEN=\$(openssl rand -hex 32) ./deploy.sh" >&2
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
  --set-env-vars="APP_ID=${APP_ID:-9R8P28G4BJ.com.nitai.aikeyboard}" \
  --set-env-vars="ATTEST_ENV=${ATTEST_ENV:-production}" \
  --memory=256Mi \
  --min-instances=0 \
  --max-instances=10

echo
echo "Deployed. Point the app's cloudBackendURL setting at:"
gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(status.url)'
