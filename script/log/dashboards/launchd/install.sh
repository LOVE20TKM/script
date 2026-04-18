#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DASHBOARD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLIST_DST="${HOME}/Library/LaunchAgents/com.love20.dashboards.plist"
STAGED_DIR="${HOME}/Library/Application Support/LOVE20/dashboards"
STAGED_SCRIPT="${STAGED_DIR}/start_dashboard.sh"
LOG_DIR="${HOME}/Library/Logs/LOVE20"
LABEL="com.love20.dashboards"
PYTHON_BIN="$(command -v python3 || true)"

mkdir -p "${HOME}/Library/LaunchAgents" "${LOG_DIR}" "${STAGED_DIR}"
cp "${SCRIPT_DIR}/start_dashboard.sh" "${STAGED_SCRIPT}"
chmod +x "${STAGED_SCRIPT}"

if [[ -z "${PYTHON_BIN}" ]]; then
  echo "python3 not found" >&2
  exit 1
fi

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
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>DASHBOARD_NETWORK</key>
    <string>thinkium70001_public</string>
    <key>DASHBOARD_HOST</key>
    <string>127.0.0.1</string>
    <key>DASHBOARD_PORT</key>
    <string>8000</string>
    <key>DASHBOARD_REPO_DIR</key>
    <string>${REPO_DASHBOARD_DIR}</string>
    <key>PYTHON_BIN</key>
    <string>${PYTHON_BIN}</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/dashboards.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/dashboards.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "${PLIST_DST}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST_DST}"
launchctl enable "gui/$(id -u)/${LABEL}"
launchctl kickstart -k "gui/$(id -u)/${LABEL}"

echo "installed: ${PLIST_DST}"
echo "dashboard: http://127.0.0.1:8000/dashboards/"
