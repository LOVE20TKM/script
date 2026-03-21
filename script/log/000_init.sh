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
source ../network/$network/address.extension.center.params
source ../network/$network/address.extension.group.params
source ../network/$network/address.extension.lp.params
source ../network/$network/address.group.params
source ../network/$network/address.else.params
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

    if [ -z "$address" ]; then
        return 0
    fi
    
    # 去掉 0x 前缀
    address=${address#0x}

    if [ ${#address} -lt 40 ]; then
        return 0
    fi
    
    # 取最后40个字符（20字节地址）
    address=${address: -40}
    
    # 重新添加 0x 前缀
    echo "0x$address"
}

is_nonzero_address() {
    local address=$1
    [ -n "$address" ] && [ "$address" != "0x0000000000000000000000000000000000000000" ]
}

cast_call() {
    local address=$1
    local function_signature=$2
    shift 2
    cast call "$address" "$function_signature" "$@" --rpc-url "$RPC_URL"
}

init_token_address_set() {
    local token_var_name=$1
    local token_address=$2
    local prefix=$3

    if ! is_nonzero_address "$token_address"; then
        return 0
    fi

    export "$token_var_name=$token_address"

    local st_var_name
    local sl_var_name
    if [ -n "$prefix" ]; then
        st_var_name="${prefix}StTokenAddress"
        sl_var_name="${prefix}SlTokenAddress"
    else
        st_var_name="stTokenAddress"
        sl_var_name="slTokenAddress"
    fi

    local st_address
    st_address=$(cast_call "$token_address" "stAddress()(address)" 2>/dev/null | normalize_address)
    if is_nonzero_address "$st_address"; then
        export "$st_var_name=$st_address"
    fi

    local sl_address
    sl_address=$(cast_call "$token_address" "slAddress()(address)" 2>/dev/null | normalize_address)
    if is_nonzero_address "$sl_address"; then
        export "$sl_var_name=$sl_address"
    fi
}

init_extension_addresses() {
    local token_address=$1
    local prefix=$2
    shift 2

    if ! is_nonzero_address "$token_address"; then
        return 0
    fi

    local actionId
    for actionId in "$@"; do
        local ext_var_name
        if [ -n "$prefix" ]; then
            ext_var_name="${prefix}Ext${actionId}Address"
        else
            ext_var_name="ext${actionId}Address"
        fi
        local ext_address
        ext_address=$(cast_call "$centerAddress" "extension(address,uint256)(address)" "$token_address" "$actionId" 2>/dev/null | normalize_address)
        if is_nonzero_address "$ext_address"; then
            export "$ext_var_name=$ext_address"
        fi
    done
}

init_pair_address() {
    local token0_address=$1
    local token1_address=$2
    local pair_var_name=$3

    if ! is_nonzero_address "$token0_address" || ! is_nonzero_address "$token1_address"; then
        return 0
    fi

    local pair_address
    pair_address=$(cast_call "$uniswapV2FactoryAddress" "getPair(address,address)(address)" "$token0_address" "$token1_address" 2>/dev/null | normalize_address)
    if is_nonzero_address "$pair_address"; then
        export "$pair_var_name=$pair_address"
    fi
}

export tokenAddress=$firstTokenAddress
init_token_address_set "tokenAddress" "$tokenAddress" ""
init_extension_addresses "$tokenAddress" "" 24 25 26 27 28 29
init_pair_address "$tokenAddress" "$rootParentTokenAddress" "love20Tkm20PairAddress"
init_pair_address "$tokenAddress" "$tusdtAddress" "love20TusdtPairAddress"

life20Address=$(cast_call "$launchAddress" "tokenAddressBySymbol(string)(address)" "LIFE20" 2>/dev/null | normalize_address)
if is_nonzero_address "$life20Address"; then
  init_token_address_set "life20Address" "$life20Address" "life20"
  init_extension_addresses "$life20Address" "life20" 0 1 2 3 4 5 6
  init_pair_address "$firstTokenAddress" "$life20Address" "love20Life20PairAddress"
fi

export maxBlocksPerRequest=50000  # Large chunks for Python processor
export maxRetries=5
export maxConcurrentJobs=10  # Reduced concurrency to avoid RPC rate limiting

# Script directory for Python processor
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHON_PROCESSOR="$SCRIPT_DIR/event_processor.py"
export BLOCK_PROCESSOR="$SCRIPT_DIR/block_processor.py"
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
