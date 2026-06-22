#!/usr/bin/env bash
set -euo pipefail

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "${developer_dir}" != *"/Xcode.app/Contents/Developer" ]]; then
  echo "Full Xcode is required, but xcode-select points to: ${developer_dir:-<unset>}" >&2
  echo "Install Xcode, then run:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 2
fi

xcodebuild -version
xcrun simctl list devices available >/dev/null
echo "Xcode and Simulator tools are available."

