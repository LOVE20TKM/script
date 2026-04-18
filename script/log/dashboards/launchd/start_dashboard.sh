#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_ROOT="${HOME}/Library/Logs/LOVE20"
NETWORK="${DASHBOARD_NETWORK:-thinkium70001_public}"
HOST="${DASHBOARD_HOST:-127.0.0.1}"
PORT="${DASHBOARD_PORT:-8000}"
PYTHON_BIN="${PYTHON_BIN:-}"

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

if [[ -n "${DASHBOARD_REPO_DIR:-}" ]]; then
  DASHBOARD_DIR="$(cd "${DASHBOARD_REPO_DIR}" && pwd)"
else
  DASHBOARD_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

if [[ ! -d "${DASHBOARD_DIR}" ]]; then
  echo "dashboard dir not found: ${DASHBOARD_DIR}" >&2
  exit 1
fi

DB_PATH="$(cd "${DASHBOARD_DIR}/.." && pwd)/db/${NETWORK}/events.db"
if [[ ! -f "${DB_PATH}" ]]; then
  echo "dashboard db not found: ${DB_PATH}" >&2
  exit 1
fi

if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="$(command -v python3 || true)"
fi

if [[ -z "${PYTHON_BIN}" || ! -x "${PYTHON_BIN}" ]]; then
  echo "python3 not found for dashboard service" >&2
  exit 1
fi

mkdir -p "${LOG_ROOT}"
exec "${PYTHON_BIN}" "${DASHBOARD_DIR}/dashboard_server.py" --host "${HOST}" --port "${PORT}" --network "${NETWORK}"
