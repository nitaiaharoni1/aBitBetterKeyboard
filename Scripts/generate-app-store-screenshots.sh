#!/usr/bin/env bash
set -euo pipefail

release_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$release_root/AppStore/screenshots-source"
output_dir="$release_root/fastlane/screenshots/en-US"
font="/System/Library/Fonts/SFNS.ttf"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aikeyboard-store-shots.XXXXXX")"

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

for required in background.png home.png keyboard.png emoji.png settings.png palette.png privacy.png; do
    if [ ! -f "$source_dir/$required" ]; then
        echo "Missing screenshot source: $source_dir/$required" >&2
        exit 1
    fi
done
if [ ! -f "$font" ]; then
    echo "Required system font is missing: $font" >&2
    exit 1
fi

mkdir -p "$output_dir"
find "$output_dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -delete

magick "$source_dir/background.png" \
    -resize '1284x2778^' \
    -gravity center \
    -extent 1284x2778 \
    -alpha off \
    "$work_dir/canvas.png"

brand_canvas() {
    local destination="$1"
    magick "$work_dir/canvas.png" \
        \( "$release_root/Landing/public/mark.png" -resize 48x48 \) \
        -geometry +76+64 \
        -composite \
        -font "$font" \
        -fill '#242728' \
        -pointsize 38 \
        -weight 700 \
        -annotate +142+103 'aBitBetterKeyboard' \
        "$destination"
}

compose_full_screen() {
    local source="$1"
    local destination="$2"
    local title="$3"
    local subtitle="$4"
    local canvas="$work_dir/$(basename "$destination" .png)-canvas.png"
    local screen="$work_dir/$(basename "$destination" .png)-screen.png"

    brand_canvas "$canvas"
    magick "$source" \
        -resize '1020x2217!' \
        -bordercolor white \
        -border 4 \
        "$screen"

    magick "$canvas" \
        -font "$font" \
        -fill '#242728' \
        -pointsize 82 \
        -weight 800 \
        -annotate +76+285 "$title" \
        -fill '#646968' \
        -pointsize 33 \
        -weight 400 \
        -annotate +78+382 "$subtitle" \
        \( "$screen" -background '#242728' -shadow 45x12+0+16 \) \
        -geometry +128+520 \
        -composite \
        "$screen" \
        -geometry +128+520 \
        -composite \
        -alpha off \
        "$destination"
}

compose_keyboard() {
    local source="$1"
    local destination="$2"
    local title="$3"
    local subtitle="$4"
    local canvas="$work_dir/$(basename "$destination" .png)-canvas.png"
    local keyboard="$work_dir/$(basename "$destination" .png)-keyboard.png"

    brand_canvas "$canvas"
    magick "$source" \
        -crop '1206x1052+0+1570' \
        +repage \
        -resize '1150x1003!' \
        -bordercolor white \
        -border 4 \
        "$keyboard"

    magick "$canvas" \
        -font "$font" \
        -fill '#242728' \
        -pointsize 104 \
        -weight 800 \
        -annotate +76+340 "$title" \
        -fill '#646968' \
        -pointsize 42 \
        -weight 400 \
        -annotate +80+520 "$subtitle" \
        \( "$keyboard" -background '#242728' -shadow 50x14+0+18 \) \
        -geometry +63+1670 \
        -composite \
        "$keyboard" \
        -geometry +63+1670 \
        -composite \
        -alpha off \
        "$destination"
}

compose_full_screen \
    "$source_dir/home.png" \
    "$output_dir/01-home.png" \
    'Set up in minutes.' \
    $'Clear steps, dictation, and a built-in place\nto try the keyboard.'

compose_keyboard \
    "$source_dir/keyboard.png" \
    "$output_dir/02-keyboard.png" \
    $'Your keyboard.\nYour way.' \
    $'Real keys, suggestions, and quick actions\nin one place.'

compose_keyboard \
    "$source_dir/emoji.png" \
    "$output_dir/03-emoji.png" \
    $'Emoji without\nthe detour.' \
    $'Pick one without leaving the keyboard\nor losing your place.'

compose_full_screen \
    "$source_dir/settings.png" \
    "$output_dir/04-settings.png" \
    'Control every detail.' \
    $'Typing, AI, and keyboard feel stay\nin your hands.'

compose_full_screen \
    "$source_dir/palette.png" \
    "$output_dir/05-customize.png" \
    'Make it feel like yours.' \
    $'Pick the accent you want and change it\nwhenever you like.'

magick "$source_dir/privacy.png" \
    -resize '1284x2778!' \
    -alpha off \
    "$output_dir/06-privacy.png"

screenshot_count=0
for screenshot in "$output_dir"/*.png; do
    screenshot_count=$((screenshot_count + 1))
    image_info="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$screenshot")"
    width="$(printf '%s\n' "$image_info" | awk '/pixelWidth:/ {print $2}')"
    height="$(printf '%s\n' "$image_info" | awk '/pixelHeight:/ {print $2}')"
    alpha="$(printf '%s\n' "$image_info" | awk '/hasAlpha:/ {print $2}')"
    if [ "$width" != '1284' ] || [ "$height" != '2778' ] || [ "$alpha" != 'no' ]; then
        echo "$(basename "$screenshot") must be an opaque 1284x2778 image; found ${width}x${height}, alpha=$alpha" >&2
        exit 1
    fi
done

if [ "$screenshot_count" -ne 6 ]; then
    echo "Expected six screenshots; found $screenshot_count" >&2
    exit 1
fi

echo "Generated six opaque 1284x2778 App Store screenshots in $output_dir."
