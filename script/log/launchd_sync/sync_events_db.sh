#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${LOVE20_SYNC_RUNTIME_DIR:-$SCRIPT_DIR}"
DEFAULT_SCRIPT_LOG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_LOG_DIR="${LOVE20_SYNC_SCRIPT_LOG_DIR:-$DEFAULT_SCRIPT_LOG_DIR}"
SYNC_NETWORK="${LOVE20_SYNC_NETWORK:-thinkium70001_public}"
ENTRYPOINT_NAME="${LOVE20_SYNC_ENTRYPOINT_NAME:-one_click_process.sh}"
LOG_ROOT="${HOME}/Library/Logs/LOVE20"

PATH="${HOME}/.foundry/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

if ! SCRIPT_LOG_DIR="$(cd "${SCRIPT_LOG_DIR}" 2>/dev/null && pwd)"; then
  echo "sync script/log dir not found: ${SCRIPT_LOG_DIR}" >&2
  exit 1
fi

if ! RUNTIME_DIR="$(cd "${RUNTIME_DIR}" 2>/dev/null && pwd)"; then
  echo "sync runtime dir not found: ${RUNTIME_DIR}" >&2
  exit 1
fi

ENTRYPOINT_PATH="${RUNTIME_DIR}/${ENTRYPOINT_NAME}"
if [[ ! -f "${ENTRYPOINT_PATH}" ]]; then
  echo "sync entrypoint not found: ${ENTRYPOINT_PATH}" >&2
  exit 1
fi

mkdir -p "${LOG_ROOT}"

echo "Starting events db sync"
echo "Network: ${SYNC_NETWORK}"
echo "Working directory: ${SCRIPT_LOG_DIR}"
echo "Entrypoint: ${ENTRYPOINT_PATH}"

export LOVE20_LOG_REPO_DIR="${SCRIPT_LOG_DIR}"

# shellcheck disable=SC1090
source "${ENTRYPOINT_PATH}"
if ! declare -F main >/dev/null 2>&1; then
  echo "sync entrypoint does not define main(): ${ENTRYPOINT_PATH}" >&2
  exit 1
fi

main "${SYNC_NETWORK}"
