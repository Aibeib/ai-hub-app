#!/usr/bin/env bash
set -euo pipefail

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "${developer_dir}" != *".app/Contents/Developer" ]]; then
  echo "Full Xcode is required, but xcode-select points to: ${developer_dir:-<unset>}" >&2
  echo "macOS: $(sw_vers -productVersion 2>/dev/null || echo unknown)" >&2
  echo "Install a compatible Xcode version, then run one of:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  echo "  sudo xcode-select -s /Applications/Xcode-16.4.app/Contents/Developer" >&2
  exit 2
fi

xcodebuild -version
xcrun simctl list devices available >/dev/null
echo "Xcode and Simulator tools are available."
