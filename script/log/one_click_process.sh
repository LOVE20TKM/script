#!/bin/bash

# ============================================================================
# LOVE20 Event Log Processor (Batch version with unified JSON config)
# 
# Fetches all events for ALL contracts in a SINGLE parallelized RPC call.
# ============================================================================

# 引入初始化逻辑 (网络参数、ABI 路径、地址解析等)
source ./000_init.sh $1

echo ""
echo "🎯 Starting incremental event log processing..."
echo "📊 This will fetch new logs since last sync and store them in SQLite."
echo ""

# Check Python dependencies
if ! check_python_deps; then
  echo "❌ Please install Python dependencies first: pip install -r requirements.txt"
  return 1
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

if [ $exit_code -eq 0 ]; then
  echo ""
  echo "🎉 All event log processing completed!"
  echo "📊 Data is available in SQLite database: $db_dir/events.db"
else
  echo ""
  echo "❌ Error during event log processing."
fi
