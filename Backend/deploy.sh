#!/usr/bin/env bash
set -euo pipefail

# Deploys the public Cloud Run endpoint used by the app. Production accepts
# only App Attest sessions. Secret values stay in Secret Manager and are never
# passed on this command line or stored in Cloud Run's plain environment.

PROJECT="${PROJECT:-${HANDI_PROJECT:-}}"
GCLOUD_ACCOUNT="${GCLOUD_ACCOUNT:-nitai@handi.co.il}"
REGION="${REGION:-europe-west1}"
SERVICE="${SERVICE:-aikeyboard-backend}"
MODEL="${MODEL:-gemini-3.5-flash-lite}"
APP_ID="${APP_ID:-9R8P28G4BJ.com.nitai.aikeyboard}"
SESSION_SECRET_NAME="${SESSION_SECRET_NAME:-aikeyboard-session-secret}"
SESSION_SECRET_VERSION="${SESSION_SECRET_VERSION:-}"
SESSION_SECRET_PREVIOUS_VERSION="${SESSION_SECRET_PREVIOUS_VERSION:-}"
LOG_EXCLUSION_NAME="${LOG_EXCLUSION_NAME:-aikeyboard-cloud-run-requests}"
RUNTIME_SERVICE_ACCOUNT="aikeyboard-backend-runtime@${PROJECT}.iam.gserviceaccount.com"

if [ -z "$PROJECT" ]; then
  echo "PROJECT or HANDI_PROJECT must name the Google Cloud project." >&2
  exit 1
fi
if ! [[ "$SESSION_SECRET_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "SESSION_SECRET_VERSION must be a numeric Secret Manager version." >&2
  echo "Example: SESSION_SECRET_VERSION=3 ./deploy.sh" >&2
  exit 1
fi
if [ -n "$SESSION_SECRET_PREVIOUS_VERSION" ] \
  && ! [[ "$SESSION_SECRET_PREVIOUS_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "SESSION_SECRET_PREVIOUS_VERSION must be empty or numeric." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
Scripts/audit-release-security.sh

# Resolve every required secret reference before changing project settings.
# Describing a version checks existence and state without reading its value.
if ! current_secret_state="$(gcloud secrets versions describe "$SESSION_SECRET_VERSION" \
  --secret="$SESSION_SECRET_NAME" \
  --project="$PROJECT" \
  --account="$GCLOUD_ACCOUNT" \
  --format='value(state)' 2>/dev/null)" \
  || [ "$current_secret_state" != "ENABLED" ]; then
  echo "Secret Manager version is missing or not enabled: ${SESSION_SECRET_NAME}:${SESSION_SECRET_VERSION}" >&2
  exit 1
fi
if [ -n "$SESSION_SECRET_PREVIOUS_VERSION" ]; then
  if ! previous_secret_state="$(gcloud secrets versions describe "$SESSION_SECRET_PREVIOUS_VERSION" \
    --secret="$SESSION_SECRET_NAME" \
    --project="$PROJECT" \
    --account="$GCLOUD_ACCOUNT" \
    --format='value(state)' 2>/dev/null)" \
    || [ "$previous_secret_state" != "ENABLED" ]; then
    echo "Previous Secret Manager version is missing or not enabled: ${SESSION_SECRET_NAME}:${SESSION_SECRET_PREVIOUS_VERSION}" >&2
    exit 1
  fi
fi

# Google's published Gemini models cache inputs and outputs in memory for up to
# 24 hours by default. This project needs request-time processing only, so make
# that project-wide privacy setting explicit before deploying any revision. The
# header file keeps the short-lived access token out of the curl process list.
cache_headers="$(mktemp "${TMPDIR:-/tmp}/aikeyboard-vertex-headers.XXXXXX")"
trap 'rm -f "$cache_headers"' EXIT
access_token="$(gcloud auth print-access-token --account="$GCLOUD_ACCOUNT")"
chmod 600 "$cache_headers"
printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' \
  "$access_token" > "$cache_headers"
unset access_token

cache_endpoint="https://us-central1-aiplatform.googleapis.com/v1/projects/${PROJECT}/cacheConfig"
curl --silent --show-error --fail-with-body \
  --config "$cache_headers" \
  --request PATCH \
  --data "{\"name\":\"projects/${PROJECT}/cacheConfig\",\"disableCache\":true}" \
  "$cache_endpoint" >/dev/null
cache_status="$(curl --silent --show-error --fail-with-body \
  --config "$cache_headers" \
  "$cache_endpoint")"
if ! printf '%s' "$cache_status" | tr -d '[:space:]' | grep -Fq '"disableCache":true'; then
  echo "Vertex AI in-memory data caching is still enabled." >&2
  exit 1
fi

# Cloud Run writes a request log automatically for every call. Those entries
# can include the caller's IP address, user agent, URL, response size, and
# latency. Keep the app's deliberately small analytics events, but prevent
# automatic request metadata for this service from entering the _Default sink.
# Create and patch use the same payload so rerunning this script repairs drift.
logging_exclusion_filter="resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE}\" AND logName=\"projects/${PROJECT}/logs/run.googleapis.com%2Frequests\""
logging_exclusion_description="Exclude automatic Cloud Run request metadata for ${SERVICE}; application analytics logs remain enabled."
logging_exclusion_payload="$(jq -cn \
  --arg name "$LOG_EXCLUSION_NAME" \
  --arg description "$logging_exclusion_description" \
  --arg filter "$logging_exclusion_filter" \
  '{name: $name, description: $description, filter: $filter, disabled: false}')"
logging_exclusions_endpoint="https://logging.googleapis.com/v2/projects/${PROJECT}/exclusions"
logging_exclusion_endpoint="${logging_exclusions_endpoint}/${LOG_EXCLUSION_NAME}"
logging_exclusion_http_status="$(curl --silent --show-error \
  --config "$cache_headers" \
  --output /dev/null \
  --write-out '%{http_code}' \
  "$logging_exclusion_endpoint")"

case "$logging_exclusion_http_status" in
  200)
    curl --silent --show-error --fail-with-body \
      --config "$cache_headers" \
      --request PATCH \
      --data "$logging_exclusion_payload" \
      "${logging_exclusion_endpoint}?updateMask=description%2Cfilter%2Cdisabled" >/dev/null
    ;;
  404)
    curl --silent --show-error --fail-with-body \
      --config "$cache_headers" \
      --request POST \
      --data "$logging_exclusion_payload" \
      "$logging_exclusions_endpoint" >/dev/null
    ;;
  *)
    echo "Could not inspect the Cloud Logging exclusion (HTTP ${logging_exclusion_http_status})." >&2
    exit 1
    ;;
esac

logging_exclusion_status="$(curl --silent --show-error --fail-with-body \
  --config "$cache_headers" \
  "$logging_exclusion_endpoint")"
if ! printf '%s' "$logging_exclusion_status" | jq -e \
  --arg description "$logging_exclusion_description" \
  --arg filter "$logging_exclusion_filter" \
  '.description == $description and .filter == $filter and .disabled != true' >/dev/null; then
  echo "Cloud Run automatic request logging is not excluded as requested." >&2
  exit 1
fi

if ! gcloud iam service-accounts describe "$RUNTIME_SERVICE_ACCOUNT" \
  --project="$PROJECT" \
  --account="$GCLOUD_ACCOUNT" >/dev/null 2>&1; then
  gcloud iam service-accounts create aikeyboard-backend-runtime \
    --project="$PROJECT" \
    --account="$GCLOUD_ACCOUNT" \
    --display-name="aBitBetterKeyboard backend runtime"
fi

# Refuse a reused identity that already has a direct project role broader than
# this service needs. Inherited organization and group grants still need an IAM
# review outside this script; this check makes the project's own bindings exact.
direct_project_roles="$(gcloud projects get-iam-policy "$PROJECT" \
  --project="$PROJECT" \
  --account="$GCLOUD_ACCOUNT" \
  --flatten='bindings[].members' \
  --filter="bindings.members=serviceAccount:${RUNTIME_SERVICE_ACCOUNT}" \
  --format='value(bindings.role)')"
unexpected_roles="$(printf '%s\n' "$direct_project_roles" \
  | awk 'NF && $0 != "roles/aiplatform.user" { print }')"
if [ -n "$unexpected_roles" ]; then
  echo "The backend runtime identity has unexpected direct project roles:" >&2
  printf '%s\n' "$unexpected_roles" >&2
  echo "Remove them after reviewing their users, then deploy again." >&2
  exit 1
fi

# This script grants one project role and one secret-specific role. It never
# creates or downloads a service-account key.
gcloud projects add-iam-policy-binding "$PROJECT" \
  --project="$PROJECT" \
  --account="$GCLOUD_ACCOUNT" \
  --member="serviceAccount:${RUNTIME_SERVICE_ACCOUNT}" \
  --role="roles/aiplatform.user" \
  --condition=None \
  --quiet

gcloud secrets add-iam-policy-binding "$SESSION_SECRET_NAME" \
  --project="$PROJECT" \
  --account="$GCLOUD_ACCOUNT" \
  --member="serviceAccount:${RUNTIME_SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor" \
  --condition=None \
  --quiet

secret_bindings="SESSION_SECRET=${SESSION_SECRET_NAME}:${SESSION_SECRET_VERSION}"
if [ -n "$SESSION_SECRET_PREVIOUS_VERSION" ]; then
  secret_bindings+=",SESSION_SECRET_PREVIOUS=${SESSION_SECRET_NAME}:${SESSION_SECRET_PREVIOUS_VERSION}"
fi

cd "$repo_root/Backend"
gcloud run deploy "$SERVICE" \
  --project="$PROJECT" \
  --account="$GCLOUD_ACCOUNT" \
  --region="$REGION" \
  --source=. \
  --allow-unauthenticated \
  --service-account="$RUNTIME_SERVICE_ACCOUNT" \
  --set-env-vars="PROJECT=${PROJECT},MODEL=${MODEL},SERVICE_MODE=production-app-attest,APP_ID=${APP_ID}" \
  --set-secrets="$secret_bindings" \
  --memory=256Mi \
  --min-instances=0 \
  --max-instances=10

service_description="$(gcloud run services describe "$SERVICE" \
  --project="$PROJECT" \
  --account="$GCLOUD_ACCOUNT" \
  --region="$REGION" \
  --format=json)"
actual_service_account="$(jq -r '.spec.template.spec.serviceAccountName // empty' \
  <<<"$service_description")"
if [ "$actual_service_account" != "$RUNTIME_SERVICE_ACCOUNT" ]; then
  echo "Deployment used the wrong runtime service account: $actual_service_account" >&2
  exit 1
fi

env_names="$(jq -r '.spec.template.spec.containers[0].env[]?.name' \
  <<<"$service_description")"
if printf '%s\n' "$env_names" | grep -Fxq BACKEND_TOKEN; then
  echo "Deployment still contains the retired BACKEND_TOKEN environment variable." >&2
  exit 1
fi

service_mode="$(jq -r \
  '[.spec.template.spec.containers[0].env[]? | select(.name == "SERVICE_MODE") | .value][0] // empty' \
  <<<"$service_description")"
if [ "$service_mode" != "production-app-attest" ]; then
  echo "Deployment is not in production-app-attest mode." >&2
  exit 1
fi

secret_refs="$(jq -r \
  '.spec.template.spec.containers[0].env[]? | [.name, (.valueFrom.secretKeyRef.name // ""), (.valueFrom.secretKeyRef.key // "")] | join(",")' \
  <<<"$service_description")"
expected_current="SESSION_SECRET,${SESSION_SECRET_NAME},${SESSION_SECRET_VERSION}"
if ! printf '%s\n' "$secret_refs" | grep -Fxq "$expected_current"; then
  echo "SESSION_SECRET is not pinned to the requested Secret Manager version." >&2
  exit 1
fi
if [ -n "$SESSION_SECRET_PREVIOUS_VERSION" ]; then
  expected_previous="SESSION_SECRET_PREVIOUS,${SESSION_SECRET_NAME},${SESSION_SECRET_PREVIOUS_VERSION}"
  if ! printf '%s\n' "$secret_refs" | grep -Fxq "$expected_previous"; then
    echo "SESSION_SECRET_PREVIOUS is not pinned to the requested version." >&2
    exit 1
  fi
elif printf '%s\n' "$env_names" | grep -Fxq SESSION_SECRET_PREVIOUS; then
  echo "Deployment kept SESSION_SECRET_PREVIOUS even though no grace version was requested." >&2
  exit 1
fi

echo
echo "Deployed with App Attest-only access, Secret Manager signing, Vertex caching disabled, and request-log storage excluded."
gcloud run services describe "$SERVICE" \
  --project="$PROJECT" \
  --account="$GCLOUD_ACCOUNT" \
  --region="$REGION" \
  --format='value(status.url)'
