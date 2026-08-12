#!/bin/bash
# Do the Swift keyboard and the Python harness group and decode identically?
#
# The design was measured in Python and the keyboard implements it in Swift, and
# a port can be faithful in design while being wrong in a detail that is itself a
# different keyboard. This compiles the *real* `GroupedKeys.swift` and
# `GroupedDecoder.swift` against the simulator SDK — the same technique
# `Bar/typing/harness/run.sh` uses, and for the same reason — asks both sides the
# same questions, and diffs the answers.
#
#     Bar/grouped/harness/swift-check.sh
#
# Needs Xcode. Takes a few seconds. No simulator has to be booted: the binary is
# built for the simulator SDK but runs on the host.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../../../Packages/AIKeyboardCore/Sources/AIKeyboardCore"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# **The two files under check must stay Foundation-only**, and this says so
# before the compiler does. Importing UIKit into either one is easy, reasonable
# and fatal to this harness: it builds for the host so the grouping can be
# compared against the Python that measured it, and there is no UIKit there. It
# happened once, adding a `UITextContentType` gate; that gate now lives in
# `KeyboardController+Grouped.swift` where UIKit already is. Without this the
# failure reads as a broken toolchain.
if grep -lE '^import (UIKit|SwiftUI)' "$core/GroupedKeys.swift" "$core/GroupedDecoder.swift"; then
    echo "" >&2
    echo "The files listed above import a platform framework." >&2
    echo "GroupedKeys.swift and GroupedDecoder.swift are the port-checkable core" >&2
    echo "and must import Foundation only. Put UIKit-facing code in" >&2
    echo "KeyboardController+Grouped.swift instead." >&2
    exit 1
fi

cp "$core/GroupedKeys.swift" "$core/GroupedDecoder.swift" "$build/"
cp "$here/swift-check/shim.swift" "$here/swift-check/main.swift" "$build/"

# Built for the **host**, not the simulator, and that is the difference between
# this and `Bar/typing/harness/run.sh`. That one must target the simulator because
# `UITextChecker` is UIKit and macOS spell-checks with a different dictionary, so
# a macOS score would score an engine this repo does not ship. `GroupedKeys` and
# `GroupedDecoder` import Foundation and nothing else: there is no platform
# behaviour in a partition function, so there is no simulator to boot.
xcrun swiftc -O "$build"/*.swift -o "$build/check" 2>&1 | grep -v "^$" || true

if [ ! -x "$build/check" ]; then
    echo "swiftc produced no binary — see the errors above" >&2
    exit 1
fi

ROWS_JSON="$here/../data/rows.json" "$build/check" > "$build/swift.json"

# Compared structurally rather than as text: the two JSON writers disagree about
# key order, escaping and whitespace, and a `diff` over that reports formatting
# as a defect.
exec python3 "$here/swift-check/python_side.py" "$build/swift.json"
