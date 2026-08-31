#!/usr/bin/env bash
set -euo pipefail

release_root="$(cd "$(dirname "$0")/.." && pwd)"
site_port=48731
site_origin="http://127.0.0.1:${site_port}"
chrome_path="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
output_dir="$release_root/fastlane/screenshots/en-US"
server_log_path="${TMPDIR:-/tmp}/aikeyboard-store-site.log"

if lsof -nP -iTCP:"$site_port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $site_port is already in use; no process was stopped." >&2
    exit 1
fi
if [ ! -x "$chrome_path" ]; then
    echo "Google Chrome is required at $chrome_path" >&2
    exit 1
fi

cd "$release_root/Landing"
npm run build

ruby -run -e httpd out -p "$site_port" >"$server_log_path" 2>&1 &
server_pid=$!
cleanup() {
    pkill -TERM -P "$server_pid" 2>/dev/null || true
    kill -TERM "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

for _ in {1..40}; do
    curl --silent --fail "$site_origin/store/hebrew/" >/dev/null && break
    sleep 0.25
done
curl --silent --fail "$site_origin/store/hebrew/" >/dev/null

mkdir -p "$output_dir"
for shot_spec in \
    "hebrew:01-hebrew.png" \
    "bilingual:02-bilingual.png" \
    "privacy:03-privacy.png"; do
    shot="${shot_spec%%:*}"
    filename="${shot_spec#*:}"
    "$chrome_path" \
        --headless=new \
        --disable-gpu \
        --force-device-scale-factor=3 \
        --hide-scrollbars \
        --window-size=428,926 \
        --screenshot="$output_dir/$filename" \
        "$site_origin/store/$shot/" >/dev/null 2>&1
    magick "$output_dir/$filename" -alpha off "$output_dir/$filename"

    image_info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$output_dir/$filename")"
    width="$(printf '%s\n' "$image_info" | awk '/pixelWidth:/ {print $2}')"
    height="$(printf '%s\n' "$image_info" | awk '/pixelHeight:/ {print $2}')"
    alpha="$(printf '%s\n' "$image_info" | awk '/hasAlpha:/ {print $2}')"
    if [ "$width" != "1284" ] || [ "$height" != "2778" ] || [ "$alpha" != "no" ]; then
        echo "$filename must be an opaque 1284x2778 image; found ${width}x${height}, alpha=$alpha" >&2
        exit 1
    fi
done

echo "Generated three opaque 1284x2778 App Store screenshots in $output_dir."
