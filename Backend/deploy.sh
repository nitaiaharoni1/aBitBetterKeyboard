#!/usr/bin/env bash
set -euo pipefail

# Deploys the backend that `BackendTransport`
# (Packages/AIKeyboardCore/Sources/AIKeyboardShared/CloudTransport.swift)
# posts to. Nothing in the repo runs this automatically — whoever is
# deploying runs it by hand, from this directory or anywhere:
#   PROJECT=handi-project REGION=us-central1 ./deploy.sh

PROJECT="${PROJECT:-handi-project}"
REGION="${REGION:-us-central1}"
SERVICE="${SERVICE:-aikeyboard-backend}"
MODEL="${MODEL:-gemini-2.5-flash}"

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
# cannot be the gate. That leaves an endpoint where every request costs money,
# which is why the service refuses to come up on a public URL without a bearer
# token of its own. `BackendTransport` sends it from the app's
# `cloudBackendToken` setting — a value you type in beside the URL, never
# something compiled into the bundle, because anything in a bundle is
# extractable. See src/gate.js.
if [ -z "${BACKEND_TOKEN:-}" ]; then
  echo "BACKEND_TOKEN is not set." >&2
  echo >&2
  echo "This service proxies a paid model on a URL anyone can reach. Generate one," >&2
  echo "deploy with it, and put the same value in the app's cloudBackendToken setting:" >&2
  echo >&2
  echo "  BACKEND_TOKEN=\$(openssl rand -hex 32) ./deploy.sh" >&2
  exit 1
fi

gcloud run deploy "$SERVICE" \
  --project="$PROJECT" \
  --region="$REGION" \
  --source=. \
  --allow-unauthenticated \
  --set-env-vars="PROJECT=${PROJECT},MODEL=${MODEL}" \
  --set-env-vars="BACKEND_TOKEN=${BACKEND_TOKEN}" \
  --memory=256Mi \
  --min-instances=0 \
  --max-instances=10

echo
echo "Deployed. Point the app's cloudBackendURL setting at:"
gcloud run services describe "$SERVICE" --project="$PROJECT" --region="$REGION" --format='value(status.url)'
