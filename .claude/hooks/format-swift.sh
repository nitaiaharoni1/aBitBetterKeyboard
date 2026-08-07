#!/usr/bin/env bash
# PostToolUse hook: run swift-format on .swift files after Edit/MultiEdit/Write.

input=$(cat)
[[ "$input" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] || exit 0
file_path="${BASH_REMATCH[1]}"

[[ "$file_path" == *.swift ]] || exit 0

# swift-format ships inside the Xcode toolchain rather than on PATH, so it is
# reached through xcrun. Style comes from the .swift-format file at the repo
# root; without it the default 2-space indent would rewrite every edited file.
if ! output=$(xcrun swift-format --in-place "$file_path" 2>&1); then
  echo "[format-swift] swift-format failed: $(echo "$output" | head -1)" >&2
fi
