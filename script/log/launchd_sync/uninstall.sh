#!/usr/bin/env bash
set -euo pipefail

PLIST_DST="${HOME}/Library/LaunchAgents/com.love20.events-sync.plist"
STAGED_SCRIPT="${HOME}/Library/Application Support/LOVE20/events-sync/sync_events_db.sh"
STAGED_ONE_CLICK="${HOME}/Library/Application Support/LOVE20/events-sync/one_click_process.sh"
STAGED_INIT="${HOME}/Library/Application Support/LOVE20/events-sync/000_init.sh"
STAGED_NETWORK_ROOT="${HOME}/Library/Application Support/LOVE20/events-sync/network"
LABEL="com.love20.events-sync"

launchctl bootout "gui/$(id -u)" "${PLIST_DST}" 2>/dev/null || true
rm -f "${PLIST_DST}"
rm -f "${STAGED_SCRIPT}"
rm -f "${STAGED_ONE_CLICK}"
rm -f "${STAGED_INIT}"
rm -rf "${STAGED_NETWORK_ROOT}"

echo "removed: ${LABEL}"
