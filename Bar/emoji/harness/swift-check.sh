#!/bin/bash
# Does the Python in this directory rank exactly as the shipping keyboard does?
#
# `Bar/emoji/` scores a ranker written in Swift by re-implementing it in Python,
# so every number it produces is a number about the port. This is what makes
# them numbers about the keyboard: it compiles the *real* `EmojiSearch.swift`,
# `EmojiCatalog.swift` and `EmojiSkinTone.swift` against the *real*
# `Resources/EmojiCatalog.json`, asks both sides the same 146 queries, and
# diffs the answers rank by rank.
#
#     Bar/emoji/harness/swift-check.sh
#
# Needs Xcode. Takes a few seconds. No simulator: both files import Foundation
# and nothing else, so this builds for the host.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../../../Packages/AIKeyboardCore/Sources/AIKeyboardCore"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# **The three files under check must stay Foundation-only**, and this says so
# before the compiler does. `Bar/grouped/harness/swift-check.sh` carries the
# same guard because the equivalent import landed there once and the failure
# read as a broken toolchain rather than as a rule being broken. Search and
# catalogue loading have no platform behaviour in them; anything UIKit-facing
# belongs in `EmojiPanel.swift` or `EmojiSearchViews.swift`, where UIKit and
# SwiftUI already are.
if grep -lE '^import (UIKit|SwiftUI)' \
    "$core/EmojiSearch.swift" "$core/EmojiCatalog.swift" "$core/EmojiSkinTone.swift"; then
    echo "" >&2
    echo "The files listed above import a platform framework." >&2
    echo "EmojiSearch.swift, EmojiCatalog.swift and EmojiSkinTone.swift are the" >&2
    echo "port-checkable core and must import Foundation only. Put view code" >&2
    echo "in EmojiPanel.swift or EmojiSearchViews.swift instead." >&2
    exit 1
fi

# `EmojiSkinTone.swift` comes too: `EmojiCatalog`'s tone accessors name the
# enum, so without it the catalogue does not compile on its own. It is
# Foundation-only for the same reason the other two are, and the guard above
# holds it there.
cp "$core/EmojiSearch.swift" "$core/EmojiCatalog.swift" "$core/EmojiSkinTone.swift" "$build/"
cp "$here/swift-check/shim.swift" "$here/swift-check/main.swift" "$build/"

# The shipping catalogue, in a bundle `Bundle.module` can find. Written into
# both layouts because a `.bundle` directory on macOS is read through
# `Contents/Resources` and on iOS through its own root, and this harness should
# not care which one Foundation picks today.
bundle="$build/AIKeyboardCore_AIKeyboardCore.bundle"
mkdir -p "$bundle/Contents/Resources"
cp "$core/Resources/EmojiCatalog.json" "$bundle/"
cp "$core/Resources/EmojiCatalog.json" "$bundle/Contents/Resources/"

xcrun swiftc -O "$build"/*.swift -o "$build/check" 2>&1 | grep -v "^$" || true

if [ ! -x "$build/check" ]; then
    echo "swiftc produced no binary — see the errors above" >&2
    exit 1
fi

python3 "$here/swift-check/python_side.py" queries > "$build/queries.json"
EMOJI_QUERIES="$build/queries.json" EMOJI_RESOURCE_BUNDLE="$bundle" \
    "$build/check" > "$build/swift.json"

exec python3 "$here/swift-check/python_side.py" compare "$build/queries.json" "$build/swift.json"
