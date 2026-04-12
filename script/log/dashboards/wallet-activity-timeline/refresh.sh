#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK="${1:-thinkium70001_public}"
SOURCE_DB="${2:-$SCRIPT_DIR/../../db/$NETWORK/events.db}"
OUTPUT_DIR="$SCRIPT_DIR/data"
OUTPUT_DB="$OUTPUT_DIR/$NETWORK.db"
TMP_DB="$OUTPUT_DB.tmp"

if [ ! -f "$SOURCE_DB" ]; then
  echo "Error: source db not found: $SOURCE_DB" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$TMP_DB"

python3 "$SCRIPT_DIR/build_dashboard_db.py" \
  --source-db "$SOURCE_DB" \
  --output-db "$TMP_DB" \
  --network "$NETWORK"

mv "$TMP_DB" "$OUTPUT_DB"
echo "Wrote dashboard db: $OUTPUT_DB"
