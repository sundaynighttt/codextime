#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ios_dir="$(cd "$script_dir/.." && pwd)"

simulator_id="$({
  xcrun simctl list devices available
} | awk -F '[()]' '/iPhone/ && /(Booted|Shutdown)/ { print $2; exit }')"

if [[ -z "$simulator_id" ]]; then
  echo "No available iPhone Simulator was found." >&2
  exit 1
fi

xcodebuild \
  -project "$ios_dir/CodexTime.xcodeproj" \
  -scheme CodexTime \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  CODE_SIGNING_ALLOWED=NO \
  test
