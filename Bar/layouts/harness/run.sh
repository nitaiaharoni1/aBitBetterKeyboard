#!/bin/bash
# Regenerates Bar/layouts/apple-layouts.json from Apple's own data on this Mac.
#
# NEEDS macOS. `TISCreateInputSourceList` only exists there, and it only returns
# a layout the machine actually has installed — the tool names anything it could
# not find rather than writing a short file quietly. It also reads
# `InputMode_<tag>.plist` out of the installed iOS Simulator runtime; set
# IOS_RUNTIME_ROOT to point at a different one.
#
# The output is committed. `LayoutProvenanceTests` diffs every shipped layout
# against it positionally, so regenerating it and re-running the suite are one
# action: if a row moves, the test is what says so.
set -euo pipefail

cd "$(dirname "$0")"
OUT="${1:-../apple-layouts.json}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

xcrun -sdk macosx swiftc -O extract-layouts.swift -o "$BUILD/extract-layouts"
"$BUILD/extract-layouts" "$OUT"
echo "==> $OUT"
