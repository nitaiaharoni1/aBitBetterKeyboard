#!/usr/bin/env bash
set -euo pipefail

# Fails a release or backend deployment when a secret, credential file, or
# known unsafe production pattern is present. It scans both Git history and the
# exact current files, including untracked files that would be easy to publish.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "gitleaks is required. Install it with: brew install gitleaks" >&2
  exit 1
fi

audit_tmp="$(mktemp -d "${TMPDIR:-/tmp}/aikeyboard-security.XXXXXX")"
audit_tmp="$(cd "$audit_tmp" && pwd -P)"
trap 'rm -rf "$audit_tmp"' EXIT

echo "==> Scanning Git history for secrets"
gitleaks git . \
  --redact=100 \
  --no-banner \
  --report-format=json \
  --report-path="$audit_tmp/history.json"

echo "==> Scanning the exact Git index for secrets"
mkdir -p "$audit_tmp/index"
git checkout-index --all --prefix="$audit_tmp/index/"
gitleaks dir "$audit_tmp/index" \
  --redact=100 \
  --no-banner \
  --max-target-megabytes=20 \
  --report-format=json \
  --report-path="$audit_tmp/index.json"

echo "==> Scanning current tracked and untracked files for secrets"
mkdir -p "$audit_tmp/current"
git ls-files -z --cached --others --exclude-standard \
  | cpio -0 -pdm "$audit_tmp/current" >/dev/null 2>&1
gitleaks dir "$audit_tmp/current" \
  --redact=100 \
  --no-banner \
  --max-target-megabytes=20 \
  --report-format=json \
  --report-path="$audit_tmp/current.json"

credential_name_pattern='(^|/)(\.env($|\.)|.*\.(key|p8|p12|pfx|jks|keystore|mobileprovision)|GoogleService-Info\.plist|service[-_]?account.*\.json|credentials.*\.json)$'
current_credential_files="$(git ls-files --cached --others --exclude-standard \
  | rg -i "$credential_name_pattern" \
  | rg -v '(^|/)\.env\.example$' || true)"
history_credential_files="$(git log --all --name-only --pretty=format: \
  | sort -u \
  | rg -i "$credential_name_pattern" \
  | rg -v '(^|/)\.env\.example$' || true)"
if [ -n "$current_credential_files" ] || [ -n "$history_credential_files" ]; then
  echo "Credential-like file names were found in the current tree or history:" >&2
  printf '%s\n%s\n' "$current_credential_files" "$history_credential_files" \
    | sed '/^$/d' \
    | sort -u >&2
  exit 1
fi

if rg -n -- '--set-env-vars=.*(BACKEND_TOKEN|SESSION_SECRET)' Backend/deploy.sh; then
  echo "Backend secrets must use Cloud Run Secret Manager references." >&2
  exit 1
fi

if rg -n 'hasPrefix\("http"\)' \
  Packages/AIKeyboardCore/Sources/AIKeyboardShared AIKeyboard; then
  echo "A cloud URL uses prefix validation instead of exact HTTPS validation." >&2
  exit 1
fi

if rg -n 'partialTranscript\.prefix|transcript\.prefix|reading=\\\((sender|record\?\.sender)|firstApp=\\\(bundleID[[:space:]]*\?\?' \
  Packages/AIKeyboardCore/Sources AIKeyboard AIKeyboardBroadcast --glob '*.swift'; then
  echo "A public log may contain dictated text, a sender name, or an app identifier." >&2
  exit 1
fi

if [ "$#" -gt 1 ]; then
  echo "Usage: Scripts/audit-release-security.sh [path-to-built-app]" >&2
  exit 1
fi
if [ "$#" -eq 1 ]; then
  if [ ! -d "$1" ]; then
    echo "Built app was not found: $1" >&2
    exit 1
  fi
  echo "==> Scanning built app for embedded secrets"
  gitleaks dir "$1" \
    --redact=100 \
    --no-banner \
    --max-target-megabytes=100 \
    --report-format=json \
    --report-path="$audit_tmp/app.json"
fi

echo "Security scan passed."
