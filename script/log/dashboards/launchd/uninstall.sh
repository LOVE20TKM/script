#!/usr/bin/env bash
set -euo pipefail

PLIST_DST="${HOME}/Library/LaunchAgents/com.love20.dashboards.plist"
STAGED_SCRIPT="${HOME}/Library/Application Support/LOVE20/dashboards/start_dashboard.sh"
LABEL="com.love20.dashboards"

launchctl bootout "gui/$(id -u)" "${PLIST_DST}" 2>/dev/null || true
rm -f "${PLIST_DST}"
rm -f "${STAGED_SCRIPT}"

echo "removed: ${LABEL}"
