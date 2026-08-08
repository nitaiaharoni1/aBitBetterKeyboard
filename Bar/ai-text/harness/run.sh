#!/bin/bash
# HISTORICAL — this no longer runs. `MockAI` was deleted when the AI actions were
# made real, so there is nothing left for it to compile. mock_outputs.json stays
# as the frozen record of what the mock produced, which is what the real engine
# is measured against. Use run-real.sh for the engine that ships today.
#
# Rebuilds mock_outputs.json from the current MockIntelligence.swift.
# Copies the two source files it needs into a temp dir so the harness always runs
# against what is in the repo right now, never against a stale copy.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../../../Packages/AIKeyboardCore/Sources/AIKeyboardCore"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

cp "$core/Models.swift" "$core/MockIntelligence.swift" "$here/main.swift" "$build/"
swiftc -O "$build/Models.swift" "$build/MockIntelligence.swift" "$build/main.swift" -o "$build/harness"
"$build/harness" "$here/../corpus.json" "$here/../mock_outputs.json"
