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
echo "🚀 Processing contracts using unified configuration in BATCH mode..."
echo "====================================================================="

$PYTHON_CMD "$PYTHON_PROCESSOR" \
  --config "$CONFIG_FILE" \
  --rpc "$RPC_URL" \
  --to-block "$to_block" \
  --max-blocks "$maxBlocksPerRequest" \
  --concurrency "$maxConcurrentJobs" \
  --retries "$maxRetries" \
  --db-path "$db_dir/events.db" \
  --origin-blocks "$originBlocks" \
  --phase-blocks "$PHASE_BLOCKS"

exit_code=$?
if [ $exit_code -ne 0 ]; then
  echo ""
  echo "❌ Error during event log processing."
  script_return_or_exit $exit_code
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
