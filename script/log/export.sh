#!/bin/bash

# Export SQL query results to CSV and XLSX
# Usage: ./export.sh <network> <sql_file>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <network> <sql_file>"
  echo "Example: $0 thinkium70001_public sql/stat/event_stat.sql"
  exit 1
fi

network=$1
sql_file=$2

source ./000_init.sh "$network" 2>/dev/null || {
  echo "Error: failed to load init (check network: $network)"
  exit 1
}

if [ ! -f "$sql_file" ]; then
  echo "Error: SQL file not found: $sql_file"
  exit 1
fi

if [[ "$sql_file" == /* ]]; then
  sql_path="$sql_file"
else
  sql_path="$SCRIPT_DIR/$sql_file"
fi

if [ ! -f "$sql_path" ]; then
  echo "Error: SQL file not found: $sql_path"
  exit 1
fi

export PYTHON_EXPORT="$SCRIPT_DIR/export_query.py"

echo "Exporting: $sql_path"
echo "Database:  $db_dir/events.db"
echo "Output:    $output_dir"
echo ""

$PYTHON_CMD "$PYTHON_EXPORT" \
  --db "$db_dir/events.db" \
  --sql "$sql_path" \
  --out-dir "$output_dir"
