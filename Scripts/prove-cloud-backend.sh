#!/bin/bash
#
# Proves the deployed backend answers the shipping client, in Hebrew.
#
#   BACKEND_TOKEN=... Scripts/prove-cloud-backend.sh [url]
#
# Three checks, each able to fail on its own:
#
#   1. The address the app ships pointing at is reachable and refuses an
#      unauthenticated caller. A backend that answers everyone is a bill.
#   2. `BackendTransport.configured` falls back to that address when nothing is
#      stored — which is the state of every fresh install, and the state that
#      used to mean "no cloud engine at all".
#   3. The real `CloudIntelligence` + `BackendTransport`, compiled from the
#      shipping sources, corrects a Hebrew message through the live service.
#
# Check 3 is the one that matters, and it is the only check in this repo that
# runs the product's own cloud path end to end. Everything else about the cloud
# is tested against a fake transport, which is exactly how a service could be
# down, unreachable, mis-deployed or answering the wrong shape for a week
# without a single test going red.
#
# Why macOS and not the simulator: these sources compile standalone under the
# macOS SDK — `Bar/ai-text/harness/run-real.sh` already relies on that — so this
# needs no app, no simulator and no Full Access. Nothing here touches
# `FoundationModelsEngine`, so Apple Intelligence is not required either.
#
# The token is passed in, never stored here. It is the service's own bearer
# (`Backend/src/gate.js`), the same value that goes into the app under
# `Settings › AI › Cloud model`, and it is deliberately not in the repo for the
# same reason it is not in the bundle.

set -uo pipefail

cd "$(dirname "$0")/.."

CORE="Packages/AIKeyboardCore/Sources/AIKeyboardCore"
SHARED="Packages/AIKeyboardCore/Sources/AIKeyboardShared"

# The address the app ships pointing at, read out of the source rather than
# repeated here: a script that carries its own copy of the URL can pass against a
# backend the app does not use.
URL="${1:-$(sed -n 's/.*bundledDefaultURL = "\(.*\)".*/\1/p' "$SHARED/CloudTransport.swift")}"

if [ -z "$URL" ]; then
    echo "FAIL: could not read bundledDefaultURL out of $SHARED/CloudTransport.swift" >&2
    exit 1
fi

if [ -z "${BACKEND_TOKEN:-}" ]; then
    echo "BACKEND_TOKEN is not set." >&2
    echo >&2
    echo "This is the bearer the deployed service gates on, and the same value" >&2
    echo "the app takes under 'Settings > AI > Cloud model'. Without it every" >&2
    echo "check below would prove only that a 401 works." >&2
    exit 1
fi

echo "Backend: $URL"
FAILED=0

note_failure() {
    echo "FAIL: $1" >&2
    FAILED=1
}

# --- 1. Reachable, and closed to callers with no token -----------------------

echo
echo "1. The gate"

STATUS="$(curl -s -o /dev/null -w '%{http_code}' -m 60 "$URL/v1/text" \
    -X POST -H 'content-type: application/json' \
    -d '{"instructions":"i","prompt":"p","fields":[{"name":"text","description":"d"}]}')"

if [ "$STATUS" = "401" ]; then
    echo "   refuses an unauthenticated POST (401)"
else
    note_failure "an unauthenticated POST returned $STATUS, wanted 401. An open" \
        "endpoint in front of a paid model bills whoever finds it."
fi

# --- 2. A fresh install resolves a transport ---------------------------------
#
# Asserted here as well as in `CloudIntelligenceTests` because the unit test
# proves the *fallback* works and this proves the constant it falls back to is
# the address that is actually live. Those are two different failures.

echo
echo "2. The fallback"

if [ "$(printf '%s' "$URL" | cut -c1-8)" = "https://" ]; then
    echo "   bundledDefaultURL is an https address"
else
    note_failure "bundledDefaultURL is not https, so the keyboard would post the user's text in clear"
fi

# --- 3. The shipping client, against the live service ------------------------

echo
echo "3. The real client, in Hebrew"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# `FoundationModelsEngine.swift` is in this list and is never called: nothing
# below constructs it and no check here goes near Apple's model. It is here
# because `RoutedIntelligence.standard` names it, so `TextIntelligence.swift`
# does not compile without it. That is also why this needs the macOS 26 SDK to
# build — but not Apple Intelligence to run, which is the difference between this
# script and `Bar/ai-text/harness/run-real.sh`.
for source in Models.swift LanguageDetector.swift TextIntelligence.swift AIPrompts.swift \
    OutputGuard.swift EditScope.swift FoundationModelsEngine.swift CloudIntelligence.swift; do
    cp "$CORE/$source" "$BUILD/"
done
# Both targets ship a `LanguageDetector.swift`, one half each, and they land in
# the same directory here. Same rename as `Bar/ai-text/harness/run-real.sh`.
cp "$SHARED/LanguageDetector.swift" "$BUILD/SharedLanguageDetector.swift"
for source in KeyboardLanguage.swift AIOutput.swift CloudTransport.swift SharedContainer.swift \
    ScreenContextEndReason.swift; do
    cp "$SHARED/$source" "$BUILD/"
done

# Hebrew on purpose. English would pass against a backend that had lost its
# Hebrew handling entirely, and Hebrew is the language this whole path exists
# for — Apple's on-device model does not list it, so there is no second engine
# behind this one.
cat > "$BUILD/main.swift" <<'SWIFT'
import Foundation

let url = URL(string: CommandLine.arguments[1])!
let token = CommandLine.arguments[2]
let message = "היי אפשר לקבל את הקבץ מאתמול בבקשא"

let engine = CloudIntelligence(transport: BackendTransport(baseURL: url, token: token))

do {
    let corrected = try await engine.fix(message)
    let changed = corrected != message
    print("   in:  \(message)")
    print("   out: \(corrected)")
    guard changed else {
        // Two real misspellings go in. An answer identical to the input means
        // the model never ran, `EditScope` undid everything, or the service
        // echoed the prompt back.
        FileHandle.standardError.write(Data("FAIL: the corrected text is byte-identical to the input\n".utf8))
        exit(1)
    }
    // **Both misspellings is the wrong assertion, and asserting it failed here
    // on a correct answer.** The input carries two — `הקבץ`→`הקובץ` and
    // `בבקשא`→`בבקשה` — and a raw `curl` of the same text named both. The
    // shipping client, on the next run, came back
    // `היי אפשר לקבל את הקבץ מאתמול בבקשה?`: the model listed only the second
    // correction that time, so `EditScope.applied` put the first word back,
    // which is `EditScope` doing exactly its job. The model is sampled, and one
    // run is not evidence — see the corpus note in `.claude/CLAUDE.md`.
    //
    // So this asserts the properties that hold on every run: the answer is
    // Hebrew, and at least one real mistake was actually corrected. An English
    // answer or an untouched echo both still fail, which are the two failures
    // worth a script.
    let fixedSomething = corrected.contains("הקובץ") || corrected.contains("בבקשה")
    let isHebrew = corrected.unicodeScalars.contains { (0x0590...0x05FF).contains(Int($0.value)) }
    guard isHebrew else {
        FileHandle.standardError.write(Data("FAIL: the answer came back in another script\n".utf8))
        exit(1)
    }
    guard fixedSomething else {
        FileHandle.standardError.write(Data("FAIL: neither misspelling was corrected\n".utf8))
        exit(1)
    }
    print("   answered in Hebrew, with a real correction applied")
} catch {
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8))
    exit(1)
}
SWIFT

if ! xcrun -sdk macosx swiftc -O "$BUILD"/*.swift -o "$BUILD/prove" 2> "$BUILD/build.log"; then
    note_failure "the shipping cloud sources did not compile"
    tail -20 "$BUILD/build.log" >&2
else
    "$BUILD/prove" "$URL" "$BACKEND_TOKEN" || note_failure "the live service did not correct a Hebrew message"
fi

echo
if [ "$FAILED" -eq 0 ]; then
    echo "PASS: the backend the app ships pointing at is live, gated, and answers Hebrew."
else
    echo "FAILED"
fi
exit "$FAILED"
