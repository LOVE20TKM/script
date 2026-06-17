#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SCRIPT_LOG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_LOG_DIR="${LOVE20_SYNC_SCRIPT_LOG_DIR:-$DEFAULT_SCRIPT_LOG_DIR}"
RUNTIME_DIR="${LOVE20_SYNC_RUNTIME_DIR:-$SCRIPT_LOG_DIR}"
SOURCE_LOG_DIR="${LOVE20_SYNC_SOURCE_LOG_DIR:-}"
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

refresh_runtime_from_source() {
  if [[ -z "${SOURCE_LOG_DIR}" ]]; then
    return 0
  fi

  local source_log_dir
  if ! source_log_dir="$(cd "${SOURCE_LOG_DIR}" 2>/dev/null && pwd)"; then
    echo "warning: sync source log dir not found, using staged runtime: ${SOURCE_LOG_DIR}" >&2
    return 0
  fi

  local source_network_root="${LOVE20_SYNC_SOURCE_NETWORK_ROOT:-${source_log_dir}/../network}"
  local runtime_network_root="${LOVE20_LOG_NETWORK_ROOT:-${RUNTIME_DIR}/network}"
  local source_network_dir="${source_network_root}/${SYNC_NETWORK}"
  local runtime_network_dir="${runtime_network_root}/${SYNC_NETWORK}"
  local temp_network_dir="${runtime_network_root}/${SYNC_NETWORK}.tmp.$$"

  if [[ ! -f "${source_log_dir}/one_click_process.sh" || ! -f "${source_log_dir}/000_init.sh" || ! -d "${source_network_dir}" ]]; then
    echo "warning: sync source runtime incomplete, using existing staged runtime" >&2
    return 0
  fi

  mkdir -p "${RUNTIME_DIR}" "${runtime_network_root}" || {
    echo "warning: failed to prepare staged runtime dirs, using existing staged runtime" >&2
    return 0
  }

  cp "${source_log_dir}/one_click_process.sh" "${RUNTIME_DIR}/one_click_process.sh" &&
    cp "${source_log_dir}/000_init.sh" "${RUNTIME_DIR}/000_init.sh" &&
    rm -rf "${temp_network_dir}" &&
    mkdir -p "${temp_network_dir}" &&
    cp -R "${source_network_dir}/." "${temp_network_dir}/" &&
    rm -rf "${runtime_network_dir}" &&
    mv "${temp_network_dir}" "${runtime_network_dir}" || {
      rm -rf "${temp_network_dir}"
      echo "warning: failed to refresh staged runtime from source, using existing staged runtime" >&2
      return 0
    }
}

refresh_runtime_from_source

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
