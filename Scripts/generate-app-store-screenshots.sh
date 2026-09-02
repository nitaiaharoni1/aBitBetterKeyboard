#!/usr/bin/env bash
# THESIS: Warm editorial art direction frames real product pixels instead of asking image generation to imitate the app.
# OWN-WORLD: SF Pro, the shipped brand mark, ivory paper, peach pigment, burnt orange, and quiet studio depth.
# STORY: AI leads, language breadth follows, privacy earns trust, and real keyboard/settings captures prove every claim.
# FINISH: The generated set is unfinished until the visual review passes and Apple confirms all six files.
set -euo pipefail

release_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$release_root/AppStore/screenshots-source"
output_dir="$release_root/fastlane/screenshots/en-US"
brand_mark="$release_root/AIKeyboard/Assets.xcassets/BrandMark.imageset/BrandMark.png"
renderer_source="$release_root/Scripts/render-brand-text.swift"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/aikeyboard-store-shots.XXXXXX")"
renderer="$work_dir/render-brand-text"
staged_output_dir="$work_dir/screenshots"
publish_dir=''
backup_dir=''

dark='2C3031'
orange='D95728'
orange_label='A43A19'
orange_bright='#EE7442'
secondary='626766'
line='#DEDFDA'
card_fill='#FFFEFA'
pale_orange='#F7D5C4'
text_counter=0
product_shadow_inset_x=56

cleanup() {
    rm -rf "$work_dir"
    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ] && [ ! -e "$output_dir" ]; then
        mv "$backup_dir" "$output_dir"
    fi
    if [ -n "$publish_dir" ] && [ -d "$publish_dir" ]; then
        rm -rf "$publish_dir"
    fi
    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        rm -rf "$backup_dir"
    fi
}
trap cleanup EXIT

for required in \
    warm-editorial-bg-01.png \
    warm-editorial-bg-02.png \
    warm-editorial-bg-03.png \
    warm-editorial-bg-04.png \
    warm-editorial-bg-05.png \
    warm-editorial-bg-06.png \
    keyboard.png emoji.png palette.png privacy.png settings.png; do
    if [ ! -f "$source_dir/$required" ]; then
        echo "Missing screenshot source: $source_dir/$required" >&2
        exit 1
    fi
done
for required in "$brand_mark" "$renderer_source"; do
    if [ ! -f "$required" ]; then
        echo "Missing brand source: $required" >&2
        exit 1
    fi
done

xcrun swiftc "$renderer_source" -framework AppKit -o "$renderer"

mkdir -p "$staged_output_dir"

prepare_background() {
    local source="$1"
    local destination="$2"
    magick "$source" \
        -resize '1284x2778^' \
        -gravity center \
        -extent 1284x2778 \
        -alpha off \
        "$destination"
}

add_text() {
    local canvas="$1"
    local width="$2"
    local height="$3"
    local x="$4"
    local top="$5"
    local max_width="$6"
    local size="$7"
    local weight="$8"
    local tracking="$9"
    local color="${10}"
    local line_height="${11}"
    local copy="${12}"
    local layer="$work_dir/text-$text_counter.png"
    local next="$work_dir/text-composite-$text_counter.png"
    text_counter=$((text_counter + 1))

    "$renderer" "$layer" "$width" "$height" "$x" "$top" "$max_width" \
        "$size" "$weight" "$tracking" "$color" "$line_height" "$copy"
    magick "$canvas" "$layer" -compose over -composite "$next"
    mv "$next" "$canvas"
}

new_slide() {
    local destination="$1"
    local background="$2"
    local first_line="$3"
    local second_line="$4"
    local support="$5"

    prepare_background "$background" "$destination"
    magick "$destination" \
        \( "$brand_mark" -resize 72x72 \) \
        -geometry +70+60 \
        -composite \
        "$destination"
    add_text "$destination" 1284 2778 162 75 1050 50 semibold -0.9 "$dark" 58 'aBitBetterKeyboard'
    add_text "$destination" 1284 2778 70 238 1144 138 heavy -4.0 "$dark" 145 "$first_line"
    add_text "$destination" 1284 2778 70 390 1144 138 heavy -4.0 "$orange" 145 "$second_line"
    add_text "$destination" 1284 2778 74 594 1136 47 regular -0.4 "$secondary" 61 "$support"
}

new_card() {
    local width="$1"
    local height="$2"
    local radius="$3"
    local destination="$4"
    local right=$((width - 1))
    local bottom=$((height - 1))

    magick -size "${width}x${height}" xc:none \
        -fill "$card_fill" \
        -draw "roundrectangle 0,0,${right},${bottom},${radius},${radius}" \
        "$destination"
}

rounded_crop() {
    local source="$1"
    local crop="$2"
    local width="$3"
    local height="$4"
    local radius="$5"
    local destination="$6"
    local right=$((width - 1))
    local bottom=$((height - 1))

    magick "$source" \
        -crop "$crop" \
        +repage \
        -resize "${width}x${height}!" \
        \( -size "${width}x${height}" xc:none \
            -fill white \
            -draw "roundrectangle 0,0,${right},${bottom},${radius},${radius}" \) \
        -alpha off \
        -compose CopyOpacity \
        -composite \
        "$destination"
}

place_shadowed() {
    local slide="$1"
    local asset="$2"
    local x="$3"
    local y="$4"
    local angle="$5"
    local name="$6"
    local visual_x=$((x - product_shadow_inset_x))
    local rotated="$work_dir/$name-rotated.png"
    local lifted="$work_dir/$name-lifted.png"
    local next="$work_dir/$name-composite.png"

    magick "$asset" -background none -rotate "$angle" "$rotated"
    magick "$rotated" \
        \( +clone -background '#2C3031' -shadow 22x28+0+16 \) \
        +swap \
        -background none \
        -layers merge \
        +repage \
        "$lifted"
    magick "$slide" "$lifted" -geometry "+${visual_x}+${y}" -compose over -composite "$next"
    mv "$next" "$slide"
}

place_plain() {
    local slide="$1"
    local asset="$2"
    local x="$3"
    local y="$4"
    local name="$5"
    local next="$work_dir/$name-composite.png"
    magick "$slide" "$asset" -geometry "+${x}+${y}" -compose over -composite "$next"
    mv "$next" "$slide"
}

add_proof() {
    local slide="$1"
    local top="$2"
    local proof="$3"
    add_text "$slide" 1284 2778 80 "$top" 1124 38 regular -0.2 "$secondary" 48 "$proof"
}

compose_ai() {
    local slide="$staged_output_dir/01-ai.png"
    local keyboard="$work_dir/ai-keyboard.png"
    local card="$work_dir/ai-card.png"

    new_slide "$slide" "$source_dir/warm-editorial-bg-01.png" \
        'AI that helps you' \
        'say it better.' \
        $'Fix, rewrite, change tone, and reply from the keyboard.\nStart dictation in the app, then speak.'

    rounded_crop "$source_dir/keyboard.png" '1206x720+0+1580' 1070 638 38 "$keyboard"
    place_shadowed "$slide" "$keyboard" 95 900 -3 'ai-keyboard'

    new_card 1080 630 58 "$card"
    add_text "$card" 1080 630 58 45 960 24 semibold 3.0 "$secondary" 32 'AI WRITING TOOLS'
    magick "$card" \
        -stroke "$line" -strokewidth 2 \
        -draw 'line 58,134 1022,134 line 58,299 1022,299 line 58,464 1022,464' \
        -stroke none \
        -fill "$pale_orange" \
        -draw 'roundrectangle 60,166 154,260 22,22 roundrectangle 60,331 154,425 22,22 roundrectangle 60,496 154,590 22,22' \
        "$card"
    add_text "$card" 1080 630 82 197 60 18 semibold 0.2 "$orange_label" 24 'FIX'
    add_text "$card" 1080 630 75 362 72 16 semibold 0.1 "$orange_label" 22 'TONE'
    add_text "$card" 1080 630 71 527 78 14 semibold 0.0 "$orange_label" 20 'VOICE'
    add_text "$card" 1080 630 190 164 800 34 semibold -0.4 "$dark" 42 'Fix and rewrite'
    add_text "$card" 1080 630 190 211 800 25 regular -0.2 "$secondary" 34 'Clean up text or say it another way.'
    add_text "$card" 1080 630 190 329 800 34 semibold -0.4 "$dark" 42 'Tone and reply'
    add_text "$card" 1080 630 190 376 800 25 regular -0.2 "$secondary" 34 'Match the moment or answer what you copied.'
    add_text "$card" 1080 630 190 494 800 34 semibold -0.4 "$dark" 42 'Dictation'
    add_text "$card" 1080 630 190 541 800 25 regular -0.2 "$secondary" 34 'Speak when typing is slower.'
    place_shadowed "$slide" "$card" 98 1676 2 'ai-card'
    add_proof "$slide" 2426 'Every AI action starts with your tap.'
}

compose_languages() {
    local slide="$staged_output_dir/02-languages.png"
    local card="$work_dir/languages-card.png"
    local switcher="$work_dir/language-switcher.png"

    new_slide "$slide" "$source_dir/warm-editorial-bg-02.png" \
        '64 languages.' \
        'One keyboard.' \
        $'Choose the languages you use, then switch\nfrom one to the next with a swipe.'

    new_card 1080 900 58 "$card"
    add_text "$card" 1080 900 58 46 960 24 semibold 3.0 "$secondary" 32 'LANGUAGES'
    add_text "$card" 1080 900 62 135 310 190 heavy -4.0 "$orange" 205 '64'
    add_text "$card" 1080 900 378 172 630 35 semibold -0.4 "$dark" 43 $'languages you can\nchoose from.'
    add_text "$card" 1080 900 378 263 630 24 regular -0.1 "$secondary" 32 'Keep only the ones you use.'
    magick "$card" \
        -stroke "$line" -strokewidth 2 \
        -draw 'line 58,375 1022,375 line 58,542 1022,542 line 58,709 1022,709' \
        -stroke none \
        -fill "$pale_orange" \
        -draw 'roundrectangle 62,405 144,487 20,20 roundrectangle 562,405 644,487 20,20 roundrectangle 62,572 144,654 20,20 roundrectangle 562,572 644,654 20,20 roundrectangle 62,739 144,821 20,20 roundrectangle 562,739 644,821 20,20' \
        "$card"
    add_text "$card" 1080 900 88 431 45 20 semibold 0 "$orange_label" 26 'EN'
    add_text "$card" 1080 900 588 431 45 20 semibold 0 "$orange_label" 26 'ES'
    add_text "$card" 1080 900 90 598 45 20 semibold 0 "$orange_label" 26 'FR'
    add_text "$card" 1080 900 586 598 45 20 semibold 0 "$orange_label" 26 'DE'
    add_text "$card" 1080 900 94 765 45 20 semibold 0 "$orange_label" 26 'IT'
    add_text "$card" 1080 900 586 765 45 20 semibold 0 "$orange_label" 26 'PT'
    add_text "$card" 1080 900 174 424 330 32 semibold -0.3 "$dark" 40 'English'
    add_text "$card" 1080 900 674 424 330 32 semibold -0.3 "$dark" 40 'Español'
    add_text "$card" 1080 900 174 591 330 32 semibold -0.3 "$dark" 40 'Français'
    add_text "$card" 1080 900 674 591 330 32 semibold -0.3 "$dark" 40 'Deutsch'
    add_text "$card" 1080 900 174 758 330 32 semibold -0.3 "$dark" 40 'Italiano'
    add_text "$card" 1080 900 674 758 330 32 semibold -0.3 "$dark" 40 'Português'
    place_shadowed "$slide" "$card" 102 900 0 'languages-card'

    rounded_crop "$source_dir/keyboard.png" '1206x330+0+2190' 1000 274 34 "$switcher"
    place_shadowed "$slide" "$switcher" 142 1880 0 'language-switcher'
    add_proof "$slide" 2234 'Your language list stays under your control.'
}

compose_privacy() {
    local slide="$staged_output_dir/03-privacy.png"
    local card="$work_dir/privacy-card.png"

    new_slide "$slide" "$source_dir/warm-editorial-bg-03.png" \
        'Cloud AI, only' \
        'when you ask.' \
        $'Typing stays local. Cloud text and audio are off\nuntil an adult allows them, and every send\nstarts with a tap.'

    rounded_crop "$source_dir/privacy.png" '1156x1020+64+1000' 1080 953 58 "$card"
    place_shadowed "$slide" "$card" 102 920 0 'privacy-card'
    add_proof "$slide" 2070 'Cloud permission can be turned off again at any time in Settings.'
}

compose_control() {
    local slide="$staged_output_dir/04-control.png"
    local settings="$work_dir/control-settings.png"

    new_slide "$slide" "$source_dir/warm-editorial-bg-04.png" \
        'Every detail.' \
        'Yours to control.' \
        $'Autocorrect, predictions, tone, haptics, sounds,\nand layout stay in your hands.'

    rounded_crop "$source_dir/settings.png" '1206x1880+0+160' 980 1528 54 "$settings"
    place_shadowed "$slide" "$settings" 152 890 0 'control-settings'
}

compose_emoji() {
    local slide="$staged_output_dir/05-emoji.png"
    local emoji="$work_dir/emoji-keyboard.png"
    local card="$work_dir/emoji-card.png"

    new_slide "$slide" "$source_dir/warm-editorial-bg-05.png" \
        'Emoji, right' \
        'where you type.' \
        $'Browse favorites and categories without\nleaving the keyboard.'

    rounded_crop "$source_dir/emoji.png" '1206x1012+0+1610' 1050 881 42 "$emoji"
    place_shadowed "$slide" "$emoji" 117 930 0 'emoji-keyboard'

    new_card 1010 320 54 "$card"
    magick "$card" \
        -fill "$pale_orange" \
        -draw 'roundrectangle 58,82 172,196 30,30' \
        -fill "$orange_bright" \
        -draw 'circle 115,139 115,107' \
        "$card"
    add_text "$card" 1010 320 210 78 730 34 semibold -0.4 "$dark" 42 'Favorites stay first'
    add_text "$card" 1010 320 210 132 730 25 regular -0.2 "$secondary" 34 'Categories are always one tap away.'
    add_text "$card" 1010 320 78 238 840 20 semibold 2.5 "$secondary" 28 'RECENT'
    place_shadowed "$slide" "$card" 137 1891 0 'emoji-card'
}

compose_customize() {
    local slide="$staged_output_dir/06-customize.png"
    local keyboard="$work_dir/customize-keyboard.png"
    local palette="$work_dir/customize-palette.png"
    local card="$work_dir/customize-card.png"

    new_slide "$slide" "$source_dir/warm-editorial-bg-06.png" \
        'A keyboard that' \
        'feels like yours.' \
        $'Choose the accent, key size, and layout\nthat feel right to you.'

    rounded_crop "$source_dir/keyboard.png" '1206x620+0+2002' 1110 571 38 "$keyboard"
    place_shadowed "$slide" "$keyboard" 87 1880 0 'customize-keyboard'

    new_card 1080 900 58 "$card"
    add_text "$card" 1080 900 58 44 960 24 semibold 3.0 "$secondary" 32 'MAKE IT YOURS'
    rounded_crop "$source_dir/palette.png" '1100x500+53+1180' 960 436 34 "$palette"
    place_plain "$card" "$palette" 60 105 'customize-palette'
    magick "$card" \
        -stroke "$line" -strokewidth 2 \
        -draw 'line 58,590 1022,590 line 58,748 1022,748' \
        -stroke none \
        -fill "$pale_orange" \
        -draw 'roundrectangle 62,619 150,707 22,22 roundrectangle 62,777 150,865 22,22' \
        "$card"
    add_text "$card" 1080 900 76 650 60 15 semibold 0 "$orange_label" 20 'SIZE'
    add_text "$card" 1080 900 68 808 75 13 semibold 0 "$orange_label" 18 'LAYOUT'
    add_text "$card" 1080 900 182 615 690 32 semibold -0.3 "$dark" 40 'Key size'
    add_text "$card" 1080 900 182 657 690 24 regular -0.1 "$secondary" 32 'Choose how much room each key gets.'
    add_text "$card" 1080 900 182 773 690 32 semibold -0.3 "$dark" 40 'Keyboard layout'
    add_text "$card" 1080 900 182 815 690 24 regular -0.1 "$secondary" 32 'Change rows, spacing, and key actions.'
    place_shadowed "$slide" "$card" 102 900 0 'customize-card'
}

compose_ai
compose_languages
compose_privacy
compose_control
compose_emoji
compose_customize

screenshot_count=0
for screenshot in "$staged_output_dir"/*.png; do
    screenshot_count=$((screenshot_count + 1))
    opaque="$work_dir/opaque-${screenshot_count}.png"
    magick "$screenshot" -alpha off "$opaque"
    mv "$opaque" "$screenshot"

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

# Publish the complete set with one directory swap. A missing source, rendering
# failure, interrupted copy, or failed rename leaves the last good assets in
# place (or restores them from the temporary backup in `cleanup`).
output_parent="$(dirname "$output_dir")"
mkdir -p "$output_parent"
publish_dir="$(mktemp -d "$output_parent/.en-US.new.XXXXXX")"
cp "$staged_output_dir"/*.png "$publish_dir/"
if [ -e "$output_dir" ]; then
    backup_dir="$(mktemp -d "$output_parent/.en-US.old.XXXXXX")"
    rmdir "$backup_dir"
    mv "$output_dir" "$backup_dir"
fi
mv "$publish_dir" "$output_dir"
publish_dir=''
if [ -n "$backup_dir" ]; then
    rm -rf "$backup_dir"
    backup_dir=''
fi

echo "Generated six warm-editorial screenshots with SF Pro and real product captures in $output_dir."
