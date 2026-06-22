#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
"$(dirname "$0")/check-xcode.sh"

echo "Mac companion source exists under App/AIAgentHubMac."
echo "A full macOS target must be generated in Xcode before this script can build it."
exit 3

