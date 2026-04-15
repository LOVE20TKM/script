#!/bin/bash

# ============================================================================
# LOVE20 Event Log Processor (Batch version with unified JSON config)
# 
# Fetches all events for ALL contracts in a SINGLE parallelized RPC call.
# ============================================================================

script_return_or_exit() {
  local code=$1
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return "$code"
  fi
  exit "$code"
}

# 引入初始化逻辑 (网络参数、ABI 路径、地址解析等)
if ! source ./000_init.sh "$1"; then
  echo "❌ Initialization failed."
  script_return_or_exit 1
fi

echo ""
echo "🎯 Starting incremental event log processing..."
echo "📊 This will fetch new logs since last sync and store them in SQLite."
echo ""

# Check Python dependencies
if ! check_python_deps; then
  echo "❌ Please install Python dependencies first: pip install -r requirements.txt"
  script_return_or_exit 1
fi

echo "====================================================================="
echo "🚀 Processing contracts using current configuration in BATCH mode..."
echo "====================================================================="

run_event_processor() {
  "$PYTHON_CMD" "$PYTHON_PROCESSOR" \
    --config "$CONFIG_FILE" \
    --rpc "$RPC_URL" \
    --to-block "$to_block" \
    --max-blocks "$maxBlocksPerRequest" \
    --concurrency "$maxConcurrentJobs" \
    --retries "$maxRetries" \
    --db-path "$db_dir/events.db" \
    --origin-blocks "$originBlocks" \
    --phase-blocks "$PHASE_BLOCKS"
}

run_event_processor

exit_code=$?
if [ $exit_code -ne 0 ]; then
  echo ""
  echo "❌ Error during first event log processing pass."
  script_return_or_exit $exit_code
fi

echo ""
echo "🔎 Rebuilding auto-discovered extension configuration from events.db..."
echo ""

discover_status_file=$(mktemp)

"$PYTHON_CMD" "$DISCOVER_PROCESSOR" \
  --config "$CONFIG_FILE" \
  --db-path "$db_dir/events.db" \
  --status-file "$discover_status_file"

discover_exit=$?
if [ $discover_exit -ne 0 ]; then
  rm -f "$discover_status_file"
  echo ""
  echo "❌ Error while rebuilding extension configuration."
  script_return_or_exit $discover_exit
fi

if [ -f "$discover_status_file" ]; then
  # shellcheck disable=SC1090
  source "$discover_status_file"
fi
rm -f "$discover_status_file"

DISCOVER_SYNC_NEEDED=${DISCOVER_SYNC_NEEDED:-1}
DISCOVER_CONFIG_CHANGED=${DISCOVER_CONFIG_CHANGED:-0}
DISCOVER_GENERATED_COUNT=${DISCOVER_GENERATED_COUNT:-0}
DISCOVER_RESET_CONTRACTS=${DISCOVER_RESET_CONTRACTS:-}

if [ "$DISCOVER_SYNC_NEEDED" = "1" ]; then
  echo ""
  echo "🚀 Processing contracts again with refreshed extension configuration..."
  echo ""

  run_event_processor

  second_pass_exit=$?
  if [ $second_pass_exit -ne 0 ]; then
    echo ""
    echo "❌ Error during second event log processing pass."
    script_return_or_exit $second_pass_exit
  fi
else
  echo ""
  echo "⏭️ No new tracked contract events detected after discovery."
  echo "   Skipping second event log processing pass."
fi

echo ""
echo "🎉 Event log processing completed!"
echo ""
echo "====================================================================="
echo "📦 Supplementing block metadata (blocks table)..."
echo "====================================================================="

$PYTHON_CMD "$BLOCK_PROCESSOR" \
  --rpc "$RPC_URL" \
  --to-block "$to_block" \
  --db-path "$db_dir/events.db" \
  --origin-blocks "$originBlocks" \
  --batch-size 500 \
  --concurrency 20 \
  --retries "$maxRetries"

block_exit=$?

if [ $block_exit -eq 0 ]; then
  echo ""
  echo "🎉 All processing completed!"
  echo "📊 Data is available in SQLite database: $db_dir/events.db"
else
  echo ""
  echo "⚠️ Block processor returned error (events were saved successfully)."
fi
script_return_or_exit $block_exit
