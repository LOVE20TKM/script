#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_LOG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_NETWORK_DIR="${REPO_LOG_DIR}/../network"
PLIST_DST="${HOME}/Library/LaunchAgents/com.love20.events-sync.plist"
STAGED_DIR="${HOME}/Library/Application Support/LOVE20/events-sync"
STAGED_SCRIPT="${STAGED_DIR}/sync_events_db.sh"
STAGED_ONE_CLICK="${STAGED_DIR}/one_click_process.sh"
STAGED_INIT="${STAGED_DIR}/000_init.sh"
LOG_DIR="${HOME}/Library/Logs/LOVE20"
LABEL="com.love20.events-sync"
SYNC_NETWORK="${LOVE20_SYNC_NETWORK:-thinkium70001_public}"
STAGED_NETWORK_ROOT="${STAGED_DIR}/network"
STAGED_NETWORK_DIR="${STAGED_NETWORK_ROOT}/${SYNC_NETWORK}"

mkdir -p "${HOME}/Library/LaunchAgents" "${LOG_DIR}" "${STAGED_DIR}" "${STAGED_NETWORK_ROOT}"
cp "${SCRIPT_DIR}/sync_events_db.sh" "${STAGED_SCRIPT}"
cp "${SCRIPT_DIR}/../one_click_process.sh" "${STAGED_ONE_CLICK}"
cp "${SCRIPT_DIR}/../000_init.sh" "${STAGED_INIT}"
rm -rf "${STAGED_NETWORK_DIR}"
mkdir -p "${STAGED_NETWORK_DIR}"
cp -R "${REPO_NETWORK_DIR}/${SYNC_NETWORK}/." "${STAGED_NETWORK_DIR}/"
chmod +x "${STAGED_SCRIPT}"
chmod +x "${STAGED_ONE_CLICK}"

cat > "${PLIST_DST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${STAGED_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>3600</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>LOVE20_SYNC_NETWORK</key>
    <string>${SYNC_NETWORK}</string>
    <key>LOVE20_SYNC_SCRIPT_LOG_DIR</key>
    <string>${REPO_LOG_DIR}</string>
    <key>LOVE20_LOG_NETWORK_ROOT</key>
    <string>${STAGED_NETWORK_ROOT}</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/events-sync.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/events-sync.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "${PLIST_DST}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_DST}"
launchctl enable "gui/$(id -u)/${LABEL}"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "installed: ${PLIST_DST}"
echo "label: ${LABEL}"
echo "schedule: every 3600 seconds"
echo "network: ${SYNC_NETWORK}"
