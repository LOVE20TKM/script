#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NETWORK="${1:-thinkium70001_public}"
SOURCE_DB="${2:-$SCRIPT_DIR/../../db/$NETWORK/events.db}"
OUTPUT_DIR="$SCRIPT_DIR/data"
OUTPUT_DB="$OUTPUT_DIR/$NETWORK.db"
TMP_DB="$OUTPUT_DB.tmp"
TMP_SQL="$(mktemp)"

if [ ! -f "$SOURCE_DB" ]; then
  echo "Error: source db not found: $SOURCE_DB" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

{
  printf "ATTACH DATABASE '%s' AS dash;\n" "$TMP_DB"
  printf "PRAGMA dash.journal_mode = DELETE;\n"
  printf "PRAGMA dash.synchronous = OFF;\n"
  printf "DROP TABLE IF EXISTS dash.round_stats;\n"
  printf "DROP TABLE IF EXISTS dash.history_summary;\n"
  printf "DROP TABLE IF EXISTS dash.metadata;\n"
  printf "CREATE TABLE dash.round_stats AS\n"
  cat "$SCRIPT_DIR/source_query.sql"
  printf ";\n"
  printf "CREATE INDEX dash.idx_round_stats_round ON round_stats(log_round);\n"
  printf "CREATE TABLE dash.history_summary AS\n"
  cat "$SCRIPT_DIR/source_summary.sql"
  printf ";\n"
  printf "CREATE TABLE dash.metadata (\n"
  printf "  network TEXT NOT NULL,\n"
  printf "  source_db TEXT NOT NULL,\n"
  printf "  generated_at TEXT NOT NULL,\n"
  printf "  source_query_file TEXT NOT NULL,\n"
  printf "  summary_query_file TEXT NOT NULL\n"
  printf ");\n"
  printf "INSERT INTO dash.metadata VALUES (\n"
  printf "  '%s',\n" "$NETWORK"
  printf "  '%s',\n" "$SOURCE_DB"
  printf "  datetime('now'),\n"
  printf "  'source_query.sql',\n"
  printf "  'source_summary.sql'\n"
  printf ");\n"
  printf "DETACH DATABASE dash;\n"
} > "$TMP_SQL"

rm -f "$TMP_DB"
sqlite3 "$SOURCE_DB" < "$TMP_SQL"
mv "$TMP_DB" "$OUTPUT_DB"
rm -f "$TMP_SQL"

echo "Wrote dashboard db: $OUTPUT_DB"
