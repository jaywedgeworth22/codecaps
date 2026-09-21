#!/usr/bin/env bash
# Thin wrapper: ship CodeCaps Companion to TestFlight (no Xcode UI).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IN_REPO="${ROOT}/scripts/ios-fleet/ship-testflight.sh"
MAC="/Users/jay/apps/ios-fleet/ship-testflight.sh"
if [[ -f "$IN_REPO" ]]; then
  exec bash "$IN_REPO" codecaps --repo-root "$ROOT" "$@"
fi
if [[ -f "$MAC" ]]; then
  exec bash "$MAC" codecaps --repo-root "$ROOT" "$@"
fi
echo "error: ios-fleet ship-testflight.sh not found at ${IN_REPO} or ${MAC}" >&2
exit 1
