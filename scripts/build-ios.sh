#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
"$(dirname "$0")/check-xcode.sh"

scheme="${SCHEME:-AIAgentHub}"
destination="${DESTINATION:-platform=iOS Simulator,name=iPhone 16}"

xcodebuild \
  -project AI-Agent-Hub.xcodeproj \
  -scheme "${scheme}" \
  -destination "${destination}" \
  -configuration Debug \
  build

