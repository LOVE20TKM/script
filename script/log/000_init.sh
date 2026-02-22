network=$1
if [ -z "$network" ]; then
  echo "Network parameter is required."
  return 1
fi

# Export all variables from parameter files so Python can access them
set -a
source ../network/$network/address.params
source ../network/$network/network.params
source ../network/$network/LOVE20.params
for f in address.extension.center.params address.extension.group.params address.extension.lp.params address.group.params; do
  [ -f "../network/$network/$f" ] && source "../network/$network/$f"
done
set +a

export from_block=$originBlocks
export to_block=$(cast block-number --rpc-url $RPC_URL)

normalize_address() {
    # 如果有参数，使用参数；否则从标准输入读取
    local address
    if [ $# -gt 0 ]; then
        address=$1
    else
        read address
    fi
    
    # 去掉 0x 前缀
    address=${address#0x}
    
    # 取最后40个字符（20字节地址）
    address=${address: -40}
    
    # 重新添加 0x 前缀
    echo "0x$address"
}

cast_call() {
    local address=$1
    local function_signature=$2
    shift 2
    cast call "$address" "$function_signature" "$@" --rpc-url "$RPC_URL"
}

export tokenAddress=$firstTokenAddress
export stTokenAddress=$(cast_call $tokenAddress "stAddress()(address)" 2>/dev/null | normalize_address)
export slTokenAddress=$(cast_call $tokenAddress "slAddress()(address)" 2>/dev/null | normalize_address)

# Extension actions 24-28 (24: lpFactory, 25-27: groupActionFactory, 28: groupServiceFactory)
for actionId in 24 25 26 27 28; do
  addr=$(cast_call $centerAddress "extension(address,uint256)(address)" $firstTokenAddress $actionId 2>/dev/null | normalize_address)
  if [ -n "$addr" ] && [ "$addr" != "0x0000000000000000000000000000000000000000" ]; then
    export ext${actionId}Address=$addr
  fi
done

# Uniswap V2 pairs: LOVE20-TKM20, LOVE20-TUSDT
love20Tkm20Pair=$(cast_call $uniswapV2FactoryAddress "getPair(address,address)(address)" $firstTokenAddress $rootParentTokenAddress 2>/dev/null | normalize_address)
if [ -n "$love20Tkm20Pair" ] && [ "$love20Tkm20Pair" != "0x0000000000000000000000000000000000000000" ]; then
  export love20Tkm20PairAddress=$love20Tkm20Pair
fi
love20TusdtPair=$(cast_call $uniswapV2FactoryAddress "getPair(address,address)(address)" $firstTokenAddress $tusdtAddress 2>/dev/null | normalize_address)
if [ -n "$love20TusdtPair" ] && [ "$love20TusdtPair" != "0x0000000000000000000000000000000000000000" ]; then
  export love20TusdtPairAddress=$love20TusdtPair
fi

export maxBlocksPerRequest=50000  # Large chunks for Python processor
export maxRetries=5
export maxConcurrentJobs=10  # Reduced concurrency to avoid RPC rate limiting

# Script directory for Python processor
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHON_PROCESSOR="$SCRIPT_DIR/event_processor.py"
export CONFIG_FILE="$SCRIPT_DIR/../network/$network/contracts.json"

export output_dir="./output/$network"
export db_dir="./db/$network"

# Create output directory if it doesn't exist
if [ ! -d "$output_dir" ]; then
  echo "📁 Creating output directory..."
  mkdir -p "$output_dir"
  echo "✅ Output directory created: $output_dir"
fi

# Create db directory if it doesn't exist
if [ ! -d "$db_dir" ]; then
  echo "📁 Creating db directory..."
  mkdir -p "$db_dir"
  echo "✅ DB directory created: $db_dir"
fi

# ============================================================================
# Check Python dependencies
# ============================================================================
# Prefer python3.11 if available (has dependencies installed)
if command -v python3.11 >/dev/null 2>&1 && python3.11 -c "import eth_abi, httpx" 2>/dev/null; then
  export PYTHON_CMD="python3.11"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import eth_abi, httpx" 2>/dev/null; then
  export PYTHON_CMD="python3"
else
  export PYTHON_CMD=""
fi

check_python_deps() {
  if [ -z "$PYTHON_CMD" ]; then
    echo "❌ Python dependencies not installed"
    echo "💡 Install with: pip install -r requirements.txt"
    return 1
  fi
  return 0
}
