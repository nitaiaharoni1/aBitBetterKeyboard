#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
command -v swiftlint >/dev/null || { echo 'error: Install SwiftLint with brew install swiftlint.' >&2; exit 1; }

files=()
while IFS= read -r -d '' file; do
    [[ -f "$file" ]] && files+=("$file")
done < <(git ls-files --cached --others --exclude-standard -z -- \
    'AIKeyboard/*.swift' 'AIKeyboardExtension/*.swift' 'AIKeyboardBroadcast/*.swift' \
    'AIKeyboardCoreTests/*.swift' 'AIKeyboardUITests/*.swift' \
    'Packages/*.swift' 'Scripts/*.swift' 'Bar/*.swift')
[[ ${#files[@]} -gt 0 ]] || { echo 'error: No Swift source files found.' >&2; exit 1; }

status=0
swiftlint lint --config .swiftlint.yml --strict --no-cache --quiet "${files[@]}" || status=1

swift_bin="$(xcrun --find swift)"
host_lib="$(dirname "$swift_bin")/../lib/swift/host"
max_nesting_depth=4
"$swift_bin" -I "$host_lib" -L "$host_lib" -lSwiftParser -lSwiftSyntax \
    Scripts/lint-nesting.swift "$max_nesting_depth" "${files[@]}" || status=1
exit "$status"
