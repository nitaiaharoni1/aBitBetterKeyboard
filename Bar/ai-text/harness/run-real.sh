#!/bin/bash
# Runs the real engine over corpus.json and writes real_outputs.json.
#
# Runs against macOS, not the simulator: every simulator runtime reports the
# on-device model as available and then fails on the first generation call
# because no model assets ship with it. macOS 26 runs the same model for real.
#
# Requires macOS 26+ with Apple Intelligence enabled, and a gcloud login for the
# Vertex half. Takes several minutes — every entry is a real model call.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../../../Packages/AIKeyboardCore/Sources/AIKeyboardCore"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

for source in Models.swift LanguageDetector.swift TextIntelligence.swift AIPrompts.swift \
    OutputGuard.swift EditScope.swift FoundationModelsEngine.swift CloudIntelligence.swift; do
    cp "$core/$source" "$build/"
done
cp "$here/VertexTransport.swift" "$build/"
cp "$here/real.swift" "$build/main.swift"

# Vertex is the cloud half for scoring only. The token belongs to this machine,
# never to the app. Passed inline so the active gcloud config is left alone.
VERTEX_PROJECT="${VERTEX_PROJECT:-handi-project}"
VERTEX_ACCESS_TOKEN="${VERTEX_ACCESS_TOKEN:-$(gcloud auth print-access-token --account=nitai@handi.co.il 2>/dev/null)}"
export VERTEX_PROJECT VERTEX_ACCESS_TOKEN

xcrun -sdk macosx swiftc -O "$build"/*.swift -o "$build/harness"
"$build/harness" "$here/../corpus.json" "$here/../real_outputs.json" "$here/../real_outputs.meta.json"
