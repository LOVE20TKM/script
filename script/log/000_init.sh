network=$1
if [ -z "$network" ]; then
  echo "Network parameter is required."
  return 1
fi


source ../network/$network/address.params 
source ../network/$network/network.params

from_block=3939811
to_block=$(cast block-number --rpc-url $RPC_URL)

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

tokenAddress=$firstTokenAddress
stTokenAddress=$(cast call $tokenAddress "stAddress()" --rpc-url $RPC_URL | normalize_address)
slTokenAddress=$(cast call $tokenAddress "slAddress()" --rpc-url $RPC_URL | normalize_address)

maxBlocksPerRequest=4000
maxRetries=3
maxConcurrentJobs=10




output_dir="./output/$network"

# Create output directory if it doesn't exist
if [ ! -d "$output_dir" ]; then
  echo "📁 Creating output directory..."
  mkdir -p "$output_dir"
  echo "✅ Output directory created: $output_dir"
fi


contract_address(){
  local contract_name=${1}

  case "$contract_name" in
    "launch")
      echo $launchAddress
      ;;
    "submit")
      echo $submitAddress
      ;;
    "vote")
      echo $voteAddress
      ;;
    "verify")
      echo $verifyAddress
      ;;
    "stake")
      echo $stakeAddress
      ;;
    "mint")
      echo $mintAddress
      ;;
    "join")
      echo $joinAddress
      ;;
    "token")
      echo $tokenAddress
      ;;
    "tokenFactory")
      echo $tokenFactoryAddress
      ;;
    "slToken")
      echo $slTokenAddress
      ;;
    "stToken")
      echo $stTokenAddress
      ;;
    "random")
      echo $randomAddress
      ;;
    "erc20")
      echo $tokenAddress
      ;;
    "uniswapV2Factory")
      echo $uniswapV2FactoryAddress
      ;;
    *)
      echo "❌ Error: Unknown contract name: $contract_name"
      return 1
      ;;
  esac
}

abi_file_path() {
  local contract_name=${1}

  local abi_dir="../../abi"

  case "$contract_name" in
    "launch")
      echo "$abi_dir/ILOVE20Launch.sol/ILOVE20Launch.json"
      ;;
    "submit")
      echo "$abi_dir/ILOVE20Submit.sol/ILOVE20Submit.json"
      ;;
    "vote")
      echo "$abi_dir/ILOVE20Vote.sol/ILOVE20Vote.json"
      ;;
    "verify")
      echo "$abi_dir/ILOVE20Verify.sol/ILOVE20Verify.json"
      ;;
    "stake")
      echo "$abi_dir/ILOVE20Stake.sol/ILOVE20Stake.json"
      ;;
    "mint")
      echo "$abi_dir/ILOVE20Mint.sol/ILOVE20Mint.json"
      ;;
    "join")
      echo "$abi_dir/ILOVE20Join.sol/ILOVE20Join.json"
      ;;
    "token")
      echo "$abi_dir/ILOVE20Token.sol/ILOVE20Token.json"
      ;;
    "tokenFactory")
      echo "$abi_dir/ILOVE20TokenFactory.sol/ILOVE20TokenFactory.json"
      ;;
    "slToken")
      echo "$abi_dir/ILOVE20SLToken.sol/ILOVE20SLToken.json"
      ;;
    "stToken")
      echo "$abi_dir/ILOVE20STToken.sol/ILOVE20STToken.json"
      ;;
    "random")
      echo "$abi_dir/ILOVE20Random.sol/ILOVE20Random.json"
      ;;
    "erc20")
      echo "$abi_dir/IERC20.sol/IERC20.json"
      ;;
    "uniswapV2Factory")
      echo "$abi_dir/ILOVE20UniswapV2Factory.sol/ILOVE20UniswapV2Factory.json"
      ;;
    "uniswapV2Pair")
      echo "$abi_dir/ILOVE20UniswapV2Pair.sol/ILOVE20UniswapV2Pair.json"
      ;;
    *)
      echo "❌ Error: Unknown contract name: $contract_name"
      return 1
      ;;
  esac

}

event_def_from_abi() {
  local abi_file=${1}
  local event_name=${2}
  
  if [ ! -f "$abi_file" ]; then
    echo "❌ ABI file not found: $abi_file"
    return 1
  fi
  
  # 修正的jq查询 - 正确处理indexed字段
  local signature=$(jq -r --arg name "$event_name" '
    .abi[] | 
    select(.type == "event" and .name == $name) | 
    .name + "(" + 
    (.inputs | map(.type + (if .indexed then " indexed" else "" end)) | join(", ")) + 
    ")"
  ' "$abi_file")
  
  if [ "$signature" != "null" ] && [ -n "$signature" ]; then
    echo "$signature"
  else
    echo "❌ Event '$event_name' not found in ABI"
    return 1
  fi
}

event_def_from_contract_name(){
  local contract_name=${1}
  local event_name=${2} 

  local abi_file=$(abi_file_path $contract_name)
  local event_def=$(event_def_from_abi $abi_file $event_name)

  echo "$event_def"
}

fetch_and_convert(){
  # Save current shell options and disable debug output completely
  local original_shell_opts="$-"
  set +x  # Disable debug output to prevent pollution
  
  local contract_name=${1}
  local event_name=${2}

  local output_file_name="$(get_output_file_name $contract_name $event_name)"
  local abi_file_path=$(abi_file_path $contract_name)

  fetch_events $contract_name $event_name $output_file_name
  convert_event_file_to_csv $output_file_name $abi_file_path $event_name
  
  # Restore original shell options only after all conversions complete
  case $original_shell_opts in
    *x*) set -x ;;
  esac
}

get_output_file_name(){
  local contract_name=${1}
  local event_name=${2}
  echo "${contract_name}.${event_name}"
}

fetch_events(){
  local contract_name=${1}
  local event_name=${2}

  local contract_address=$(contract_address $contract_name)
  local event_def=$(event_def_from_contract_name $contract_name $event_name)
  local output_file_name="$(get_output_file_name $contract_name $event_name)"

  # echo "contract_address: $contract_address"
  # echo "event_def: $event_def"
  # echo "from_block: $from_block"
  # echo "to_block: $to_block"
  # echo "output_file_name: $output_file_name"

  cast_logs $contract_address "$event_def" $from_block $to_block $output_file_name
}

# 用event_def来解析event log，并转换为csv格式
# 生产级实现：完整错误处理、性能优化、类型安全
convert_event_file_to_csv(){
  # Save original shell options and disable debug output for entire function
  local original_opts="$-"
  set +x  # Explicitly disable debug output at function start
  
  # Set flag to prevent debug output restoration in sub-functions
  export CSV_CONVERSION_IN_PROGRESS=1
  
  local output_file_name=${1}
  local abi_file_path=${2}
  local event_name=${3}

  local input_file="$output_dir/$output_file_name.event"
  local csv_file="$output_dir/$output_file_name.csv"
  local temp_dir=$(mktemp -d)
  local log_file="$temp_dir/conversion.log"

  # Initialize logging
  exec 3>"$log_file"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting conversion for $event_name" >&3

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Converting to CSV: $event_name"
  echo "📁 Input: $input_file"
  echo "💾 Output: $csv_file"
  echo "🔧 Log: $log_file"

  # Validation checks
  if ! validate_inputs "$input_file" "$abi_file_path" "$csv_file" "$event_name"; then
    cleanup_and_exit "$temp_dir" 1
    return 1
  fi

  # Extract and validate event ABI
  local event_abi
  if ! event_abi=$(extract_event_abi "$abi_file_path" "$event_name"); then
    echo "❌ Failed to extract event ABI" >&3
    cleanup_and_exit "$temp_dir" 1
    return 1
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') - Event ABI extracted successfully" >&3

  # Generate CSV structure
  local csv_header
  if ! csv_header=$(generate_csv_header "$event_abi"); then
    echo "❌ Failed to generate CSV header" >&3
    cleanup_and_exit "$temp_dir" 1
    return 1
  fi

  echo "$csv_header" > "$csv_file"
  echo "📝 CSV header: $csv_header"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - CSV header generated: $csv_header" >&3

  # Extract parameter metadata
  if ! extract_parameter_metadata "$event_abi" "$temp_dir"; then
    echo "❌ Failed to extract parameter metadata" >&3
    cleanup_and_exit "$temp_dir" 1
    return 1
  fi

  # Convert and process events
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting event processing" >&3
  local success_count=0 error_count=0
  if ! process_all_events "$input_file" "$temp_dir" "$csv_file" success_count error_count; then
    echo "❌ Failed to process events" >&3
    cleanup_and_exit "$temp_dir" 1
    return 1
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Event processing completed" >&3

  # Generate final report
  generate_final_report "$csv_file" "$success_count" "$error_count" "$log_file"
  
  # Cleanup
  cleanup_and_exit "$temp_dir" 0
  
  # Clear CSV conversion flag and restore original shell options
  unset CSV_CONVERSION_IN_PROGRESS
  case $original_opts in
    *x*) set -x ;;
  esac
  
  return 0
}

# Comprehensive input validation
validate_inputs() {
  local input_file=$1
  local abi_file_path=$2
  local csv_file=$3
  local event_name=$4

  # Check if input file exists and is readable
  if [ ! -f "$input_file" ]; then
    echo "❌ Input file not found: $input_file"
    return 1
  fi

  if [ ! -r "$input_file" ]; then
    echo "❌ Input file not readable: $input_file"
    return 1
  fi

  # Check if input file is not empty
  if [ ! -s "$input_file" ]; then
    echo "⚠️  Input file is empty: $input_file"
    return 1
  fi

  # Check if ABI file exists and is valid JSON
  if [ ! -f "$abi_file_path" ]; then
    echo "❌ ABI file not found: $abi_file_path"
    return 1
  fi

  if ! jq empty "$abi_file_path" 2>/dev/null; then
    echo "❌ ABI file is not valid JSON: $abi_file_path"
    return 1
  fi

  # Check if CSV file already exists
  if [ -f "$csv_file" ]; then
    echo "❌ CSV file already exists: $csv_file"
    return 1
  fi

  # Check if output directory is writable
  local output_dir=$(dirname "$csv_file")
  if [ ! -w "$output_dir" ]; then
    echo "❌ Output directory not writable: $output_dir"
    return 1
  fi

  # Validate event name
  if [ -z "$event_name" ]; then
    echo "❌ Event name cannot be empty"
    return 1
  fi

  # Check available disk space (require at least 100MB)
  local available_space=$(df "$output_dir" | awk 'NR==2 {print $4}')
  if [ "$available_space" -lt 102400 ]; then
    echo "❌ Insufficient disk space (need at least 100MB)"
    return 1
  fi

  return 0
}

# Extract event ABI with error handling
extract_event_abi() {
  local abi_file_path=$1
  local event_name=$2

  local event_abi
  event_abi=$(jq -r --arg name "$event_name" '
    .abi[] | select(.type == "event" and .name == $name) | @json
  ' "$abi_file_path" 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo "❌ jq failed to process ABI file" >&2
    return 1
  fi

  if [ "$event_abi" = "null" ] || [ -z "$event_abi" ]; then
    echo "❌ Event '$event_name' not found in ABI" >&2
    return 1
  fi

  # Validate event ABI structure
  if ! echo "$event_abi" | jq -e '.inputs | type == "array"' >/dev/null 2>&1; then
    echo "❌ Invalid event ABI structure: missing inputs array" >&2
    return 1
  fi

  echo "$event_abi"
  return 0
}

# Generate CSV header with proper escaping
generate_csv_header() {
  local event_abi=$1

  local header
  header=$(echo "$event_abi" | jq -r '
    "blockNumber,transactionHash,transactionIndex,logIndex,address," +
    (.inputs | map(.name // ("param" + (. | keys | length | tostring))) | join(","))
  ' 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$header" ]; then
    echo "❌ Failed to generate CSV header" >&2
    return 1
  fi

  echo "$header"
  return 0
}

# Extract parameter metadata for processing
extract_parameter_metadata() {
  local event_abi=$1
  local temp_dir=$2

  # Extract parameter details
  echo "$event_abi" | jq -r '.inputs[] | @json' > "$temp_dir/params.json"
  
  if [ $? -ne 0 ]; then
    echo "❌ Failed to extract parameter metadata" >&2
    return 1
  fi

  # Generate type information for cast abi-decode
  local non_indexed_types
  non_indexed_types=$(echo "$event_abi" | jq -r '
    [.inputs[] | select(.indexed != true) | .type] | join(",")
  ' 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo "❌ Failed to generate type information" >&2
    return 1
  fi

  echo "$non_indexed_types" > "$temp_dir/non_indexed_types.txt"

  # Count parameters
  local param_count
  param_count=$(echo "$event_abi" | jq -r '.inputs | length' 2>/dev/null)
  echo "$param_count" > "$temp_dir/param_count.txt"

  return 0
}

# Convert YAML to JSON with robust error handling
convert_yaml_to_json() {
  local yaml_file=$1
  local json_file=$2

  echo "🔄 Converting YAML to JSON..."

  # Try yq first if available
  if command -v yq >/dev/null 2>&1; then
    echo "📝 Using yq for YAML conversion"
    if yq eval -o json "$yaml_file" > "$json_file" 2>/dev/null; then
      # Validate the JSON output
      if jq empty "$json_file" 2>/dev/null; then
        return 0
      else
        echo "⚠️  yq produced invalid JSON, falling back to Python conversion"
        rm -f "$json_file"
      fi
    else
      echo "⚠️  yq conversion failed, falling back to Python conversion"
    fi
  fi

  # Python-based conversion (more reliable)
  echo "📝 Using Python for YAML to JSON conversion"
  
  python3 -c "
import sys
import json

events = []
current_event = None
in_topics = False
topics = []

with open('$yaml_file', 'r') as f:
    for line in f:
        line = line.strip()
        
        if line.startswith('- address:'):
            # Save previous event
            if current_event:
                if in_topics and topics:
                    current_event['topics'] = topics
                events.append(current_event)
            
            # Start new event
            current_event = {'address': line.split(':', 1)[1].strip()}
            in_topics = False
            topics = []
            
        elif line.startswith('topics:'):
            in_topics = True
            topics = []
            
        elif in_topics and line == ']':
            # End of topics array
            current_event['topics'] = topics
            in_topics = False
            topics = []
            
        elif in_topics and line.startswith('0x'):
            # Add topic (hex value)
            topics.append(line)
            
        elif current_event and ':' in line and not in_topics:
            # Regular field
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip()
            
            # Convert numeric fields
            if key in ['blockNumber', 'transactionIndex', 'logIndex']:
                try:
                    value = int(value)
                except:
                    pass
                    
            current_event[key] = value

# Add the last event
if current_event:
    if in_topics and topics:
        current_event['topics'] = topics
    events.append(current_event)

with open('$json_file', 'w') as f:
    json.dump(events, f, indent=2)
" 2>/dev/null

  # Validate the JSON output
  if ! jq empty "$json_file" 2>/dev/null; then
    echo "❌ Python YAML conversion produced invalid JSON" >&2
    return 1
  fi

  return 0
}

# Process all events with progress tracking and error handling
process_all_events() {
  local input_file=$1
  local temp_dir=$2
  local csv_file=$3
  local success_var_name=$4
  local error_var_name=$5

  eval "${success_var_name}=0"
  eval "${error_var_name}=0"

  # Convert YAML to JSON
  if ! convert_yaml_to_json "$input_file" "$temp_dir/events.json"; then
    echo "❌ Failed to convert YAML to JSON" >&2
    return 1
  fi

  # Validate JSON structure
  local event_count
  event_count=$(jq '. | length' "$temp_dir/events.json" 2>/dev/null)
  
  if [ $? -ne 0 ] || [ "$event_count" = "null" ]; then
    echo "❌ Invalid JSON structure" >&2
    return 1
  fi

  echo "📊 Processing $event_count events..."
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Processing $event_count events" >&3

  # Load parameter metadata
  local non_indexed_types
  non_indexed_types=$(cat "$temp_dir/non_indexed_types.txt" 2>/dev/null || echo "")

  # Process events in batches for better performance
  local batch_size=100
  local processed=0

  for ((start=0; start<event_count; start+=batch_size)); do
    local end=$((start + batch_size - 1))
    if [ $end -ge $event_count ]; then
      end=$((event_count - 1))
    fi

    # Process batch
    for ((i=start; i<=end; i++)); do
      if process_single_event_safe "$temp_dir/events.json" $i "$temp_dir" "$csv_file" "$non_indexed_types"; then
        eval "${success_var_name}=\$((\$${success_var_name} + 1))"
      else
        eval "${error_var_name}=\$((\$${error_var_name} + 1))"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to process event $i" >&3
      fi
      
      processed=$((processed + 1))
    done

    # Progress update
    local progress=$((processed * 100 / event_count))
    echo "🔄 Progress: $progress% ($processed/$event_count)"
  done

  return 0
}

# Process single event with comprehensive error handling
process_single_event_safe() {
  local events_file=$1
  local event_index=$2
  local temp_dir=$3
  local csv_file=$4
  local non_indexed_types=$5

  # Extract event data using jq with error handling
  local event_data
  event_data=$(jq -c ".[$event_index] // empty" "$events_file" 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$event_data" ] || [ "$event_data" = "null" ]; then
    echo "⚠️  Failed to extract event data for index $event_index" >&2
    return 1
  fi

  # Extract transaction information
  local tx_info
  tx_info=$(echo "$event_data" | jq -r '
    [
      (.blockNumber // ""),
      (.transactionHash // ""),
      (.transactionIndex // ""),
      (.logIndex // ""),
      (.address // "")
    ] | @csv
  ' 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo "⚠️  Failed to extract transaction info for event $event_index" >&2
    return 1
  fi

  # Extract and process parameter values
  local param_values
  if ! param_values=$(process_event_parameters "$event_data" "$temp_dir" "$non_indexed_types"); then
    echo "⚠️  Failed to process parameters for event $event_index" >&2
    return 1
  fi

  # Write complete row to CSV
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Writing event $event_index to CSV" >&3
  echo "$tx_info$param_values" >> "$csv_file"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Event $event_index written successfully" >&3
  return 0
}

# Process event parameters with type-aware handling
process_event_parameters() {
  # Completely suppress all output except the final result
  # Save current shell options
  local old_opts="$-"
  set +x  # Disable debug output
  
  {
    local event_data=$1
    local temp_dir=$2
    local non_indexed_types=$3

    local param_values=""
    local topic_index=1  # Skip event signature hash
    local non_indexed_index=0

    # Extract topics and data
    local topics_json
    topics_json=$(echo "$event_data" | jq -c '.topics // []' 2>/dev/null)
    local data
    data=$(echo "$event_data" | jq -r '.data // "0x"' 2>/dev/null)

    # Decode non-indexed data if present
    local decoded_values=""
    if [ "$data" != "0x" ] && [ -n "$non_indexed_types" ] && [ "$non_indexed_types" != "" ]; then
      decoded_values=$(decode_non_indexed_data "$data" "$non_indexed_types" 2>/dev/null)
    fi

    # Process each parameter
    while IFS= read -r param_json; do
      if [ -n "$param_json" ] && [ "$param_json" != "null" ]; then
        local value=""
        
        # Process parameter directly without intermediate variables to avoid debug output
        if [ "$(echo "$param_json" | jq -r '.indexed // false' 2>/dev/null)" = "true" ]; then
          # Process indexed parameter
          value=$(process_indexed_parameter "$topics_json" $topic_index "$(echo "$param_json" | jq -r '.type // ""' 2>/dev/null)" 2>/dev/null)
          topic_index=$((topic_index + 1))
        else
          # Process non-indexed parameter
          value=$(get_decoded_value "$decoded_values" $non_indexed_index "$(echo "$param_json" | jq -r '.type // ""' 2>/dev/null)" 2>/dev/null)
          non_indexed_index=$((non_indexed_index + 1))
        fi

        # Escape and format value for CSV
        value=$(escape_csv_value "$value" 2>/dev/null)
        param_values="$param_values,$value"
      fi
    done < "$temp_dir/params.json"

    # Only output the final result
    echo "$param_values"
  } 2>/dev/null 1>&3
  
  # Only restore debug mode if not in CSV conversion process
  if [ -z "$CSV_CONVERSION_IN_PROGRESS" ]; then
    case $old_opts in
      *x*) set -x ;;
    esac
  fi
  
  return 0
} 3>&1

# Process indexed parameters with type-specific handling
process_indexed_parameter() {
  # Save current shell options and disable debug output
  local old_opts="$-"
  set +x  # Disable debug output
  
  {
    local topics_json=$1
    local topic_index=$2
    local param_type=$3

    local raw_value
    raw_value=$(echo "$topics_json" | jq -r ".[$topic_index] // \"\"" 2>/dev/null)

    if [ -z "$raw_value" ] || [ "$raw_value" = "null" ]; then
      echo ""
      return 0
    fi

    # Type-specific processing using cast
    case "$param_type" in
          "address")
      # Extract address from 32-byte topic (last 20 bytes) and normalize
      local addr_part="${raw_value: -40}"  # Get last 40 hex chars (20 bytes)
      if [ -n "$addr_part" ]; then
        addr_part="0x$addr_part"
        cast --to-checksum-address "$addr_part" 2>/dev/null || echo "$addr_part"
      else
        echo "$raw_value"
      fi
      ;;
      uint*)
        # Convert to decimal using cast
        cast --to-dec "$raw_value" 2>/dev/null || echo "$raw_value"
        ;;
      int*)
        # Handle signed integers
        cast --to-dec "$raw_value" 2>/dev/null || echo "$raw_value"
        ;;
      bool)
        # Convert boolean
        if [ "$raw_value" = "0x0000000000000000000000000000000000000000000000000000000000000000" ]; then
          echo "false"
        else
          echo "true"
        fi
        ;;
      bytes*)
        # Keep as hex
        echo "$raw_value"
        ;;
      *)
        # Default: keep as-is
        echo "$raw_value"
        ;;
    esac
  } 2>/dev/null
  
  # Only restore debug mode if not in CSV conversion process
  if [ -z "$CSV_CONVERSION_IN_PROGRESS" ]; then
    case $old_opts in
      *x*) set -x ;;
    esac
  fi
}

# Decode non-indexed data using cast abi-decode
decode_non_indexed_data() {
  # Save current shell options and disable debug output
  local old_opts="$-"
  set +x  # Disable debug output
  
  {
    local data=$1
    local types=$2

    if [ -z "$types" ] || [ "$types" = "" ]; then
      echo ""
      return 0
    fi

    # Use cast abi-decode with correct function output format
    local decoded
    decoded=$(cast abi-decode "decode()($types)" "$data" 2>/dev/null)

    if [ $? -ne 0 ]; then
      # Silent failure - don't output error messages to avoid CSV pollution
      echo ""
      return 1
    fi

    echo "$decoded"
  } 2>/dev/null
  
  # Only restore debug mode if not in CSV conversion process
  if [ -z "$CSV_CONVERSION_IN_PROGRESS" ]; then
    case $old_opts in
      *x*) set -x ;;
    esac
  fi
  
  return 0
}

# Extract decoded value by index
get_decoded_value() {
  # Save current shell options and disable debug output
  local old_opts="$-"
  set +x  # Disable debug output
  
  {
    local decoded_values=$1
    local index=$2
    local param_type=$3

    if [ -z "$decoded_values" ]; then
      echo ""
      return 0
    fi

    # Extract value by line number (simple approach)
    local value
    value=$(echo "$decoded_values" | sed -n "$((index + 1))p" 2>/dev/null)

    # Type-specific cleanup
    case "$param_type" in
      *"[]")
        # Array type - format properly for CSV (check this first!)
        # Remove leading/trailing whitespace and format as JSON-like array
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Remove scientific notation annotations like "[1.23e21]" 
        value=$(echo "$value" | sed 's/ \[[^]]*\]//g')
        # Convert "1, 2, 3" format to "[1,2,3]" format  
        if [ -n "$value" ] && [ "$value" != "null" ]; then
          # Check if it's already in bracket format
          if ! echo "$value" | grep -q '^\[.*\]$'; then
            # Convert comma-separated values to bracketed format
            value="[$value]"
          fi
          # Clean up spaces around commas for consistent formatting
          value=$(echo "$value" | sed 's/, */,/g' | sed 's/ *,/,/g')
        else
          value="[]"
        fi
        ;;
          uint*|int*)
      # Remove scientific notation annotations and cleanup
      value=$(echo "$value" | sed 's/ \[.*\]$//' | awk '{print $1}' | tr -d '\n\r\t')
      ;;
      bytes*)
        # Bytes types - keep as hex, ensure proper format
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$value" ] && ! echo "$value" | grep -q '^0x'; then
          value="0x$value"
        fi
        ;;
      bool)
        # Boolean type - normalize values
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$value" in
          "true"|"True"|"TRUE"|"1")
            value="true"
            ;;
          "false"|"False"|"FALSE"|"0")
            value="false"
            ;;
        esac
        ;;
      address)
        # Address type - normalize using cast if available
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$value" ] && command -v cast >/dev/null 2>&1; then
          normalized=$(cast --to-checksum-address "$value" 2>/dev/null)
          if [ $? -eq 0 ] && [ -n "$normalized" ]; then
            value="$normalized"
          fi
        fi
        ;;
      string)
        # Keep as-is but trim
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        ;;
    esac

    echo "$value"
  } 2>/dev/null
  
  # Only restore debug mode if not in CSV conversion process
  if [ -z "$CSV_CONVERSION_IN_PROGRESS" ]; then
    case $old_opts in
      *x*) set -x ;;
    esac
  fi
  
  return 0
}

# Escape values for CSV with proper quoting
escape_csv_value() {
  # Save current shell options and disable debug output
  local old_opts="$-"
  set +x  # Disable debug output
  
  {
    local value=$1

    if [ -z "$value" ]; then
      echo ""
      return 0
    fi

    # Escape quotes
    value=$(echo "$value" | sed 's/"/\\"/g')
    
    # Remove control characters
    value=$(echo "$value" | tr -d '\r\n\t')
    
    # For arrays and values containing commas, spaces, or quotes - always quote
    if echo "$value" | grep -q '[,"]' || echo "$value" | grep -q '[[:space:]]'; then
      echo "\"$value\""
    else
      echo "$value"
    fi
  } 2>/dev/null
  
  # Only restore debug mode if not in CSV conversion process
  if [ -z "$CSV_CONVERSION_IN_PROGRESS" ]; then
    case $old_opts in
      *x*) set -x ;;
    esac
  fi
}

# Generate comprehensive final report
generate_final_report() {
  local csv_file=$1
  local success_count=$2
  local error_count=$3
  local log_file=$4

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Conversion Complete"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [ -f "$csv_file" ]; then
    local csv_lines
    csv_lines=$(wc -l < "$csv_file" | tr -d ' ')
    local csv_size
    csv_size=$(wc -c < "$csv_file" | tr -d ' ')
    local csv_size_kb=$((csv_size / 1024))
    
    echo "✅ Successfully processed: $success_count events"
    if [ $error_count -gt 0 ]; then
      echo "⚠️  Failed to process: $error_count events"
    fi
    echo "💾 Output file: $csv_file"
    echo "📏 File size: ${csv_size_kb}KB"
    echo "📄 Total rows: $((csv_lines - 1)) (excluding header)"
    
    # Validate CSV structure
    if validate_csv_output "$csv_file"; then
      echo "✅ CSV structure validation: PASSED"
    else
      echo "⚠️  CSV structure validation: FAILED"
    fi
  else
    echo "❌ No output file generated"
  fi

  if [ -f "$log_file" ]; then
    echo "📋 Detailed log: $log_file"
    local log_size
    log_size=$(wc -c < "$log_file" | tr -d ' ')
    if [ $log_size -gt 1024 ]; then
      echo "📝 Log size: $((log_size / 1024))KB"
    fi
  fi

  local total_processed=$((success_count + error_count))
  if [ $total_processed -gt 0 ]; then
    local success_rate=$((success_count * 100 / total_processed))
    echo "📈 Success rate: ${success_rate}%"
  fi

  echo "$(date '+%Y-%m-%d %H:%M:%S') - Conversion completed: $success_count success, $error_count errors" >&3
}

# Validate CSV output structure
validate_csv_output() {
  local csv_file=$1

  # Check if file exists and is not empty
  if [ ! -s "$csv_file" ]; then
    return 1
  fi

  # Check if all lines have the same number of fields
  local header_fields
  header_fields=$(head -1 "$csv_file" | tr ',' '\n' | wc -l)
  
  local inconsistent_lines
  inconsistent_lines=$(awk -F',' -v expected="$header_fields" 'NF != expected {print NR}' "$csv_file" | wc -l)

  if [ "$inconsistent_lines" -gt 0 ]; then
    echo "⚠️  Found $inconsistent_lines lines with inconsistent field count" >&2
    return 1
  fi

  return 0
}

# Clean up temporary files and exit
cleanup_and_exit() {
  local temp_dir=$1
  local exit_code=$2

  if [ -d "$temp_dir" ]; then
    # Copy log file to output directory if it exists
    if [ -f "$temp_dir/conversion.log" ] && [ -d "$output_dir" ]; then
      cp "$temp_dir/conversion.log" "$output_dir/" 2>/dev/null || true
    fi
    
    rm -rf "$temp_dir"
  fi

  # Close log file descriptor
  exec 3>&-

  return $exit_code
}

cast_logs(){
  local contract_address=${1}
  local event_def=${2}
  local from_block=${3}
  local to_block=${4}
  local output_file_name=${5}

  local output_file="$output_dir/$output_file_name.event"
  local current_from_block=$from_block
  local pids=()
  local temp_dir=$(mktemp -d)
  local success_count=0
  local failure_count=0
  local retry_count=0
  local total_ranges=0

  # Extract event name from event signature for display
  local display_event_def=$(echo "$event_def" | cut -d'(' -f1)

  # make sure output_file not exists
  if [ -f "$output_file" ]; then
    echo "Output file $output_file already exists"
    return 1
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Fetching event logs: $display_event_def"
  echo "📍 Contract: $contract_address"
  echo "📦 Block range: $from_block → $to_block"

  # Calculate total ranges
  local temp_from=$from_block
  while [ $temp_from -le $to_block ]; do
    total_ranges=$((total_ranges + 1))
    temp_from=$((temp_from + maxBlocksPerRequest))
  done
  echo "⚙️  Processing $total_ranges ranges..."
  echo ""

  # Function to fetch logs for a specific block range with retry mechanism
  fetch_logs_range() {
    local start_block=$1
    local end_block=$2
    local temp_output_file=$3
    local range_id=$4
    local retry_attempt=${5:-0}

    # Silent execution, only log status to files
    local logs=$(cast logs --from-block $start_block --to-block $end_block --address $contract_address "$event_def" --rpc-url $RPC_URL 2>/dev/null)
    local cast_exit_code=$?
    
    if [ $cast_exit_code -eq 0 ] && [ -n "$logs" ]; then
      echo "$logs" > "$temp_output_file"
      local log_count=$(echo "$logs" | grep -c "^- address:" 2>/dev/null || echo "0")
      echo "SUCCESS:$range_id:$start_block:$end_block:$log_count" >> "$temp_dir/status.log"
    elif [ $cast_exit_code -eq 0 ]; then
      # No logs found, but request was successful
      echo "SUCCESS:$range_id:$start_block:$end_block:0" >> "$temp_dir/status.log"
    else
      # Request failed
      if [ $retry_attempt -lt $maxRetries ]; then
        sleep 2
        fetch_logs_range $start_block $end_block "$temp_output_file" $range_id $((retry_attempt + 1))
      else
        echo "FAILURE:$range_id:$start_block:$end_block:$((retry_attempt + 1))" >> "$temp_dir/status.log"
      fi
    fi
  }

  # Progress monitoring function
  monitor_progress() {
    local last_completed=0
    while [ $last_completed -lt $total_ranges ]; do
      sleep 2
      if [ -f "$temp_dir/status.log" ]; then
        local completed=$(wc -l < "$temp_dir/status.log" 2>/dev/null | tr -d '\n' || echo "0")
        if [ "$completed" != "$last_completed" ]; then
          local progress=$((completed * 100 / total_ranges))
          local running_jobs=$((total_ranges - completed))
          if [ $running_jobs -gt $maxConcurrentJobs ]; then
            running_jobs=$maxConcurrentJobs
          fi
          
          echo "🔄 Processing: ${progress}% ($completed/$total_ranges) | Jobs: $running_jobs"
          
          last_completed=$completed
        fi
      fi
    done
    echo ""
  }

  # Disable job control messages to avoid spam
  set +m

  # Start progress monitor in background
  monitor_progress &
  local monitor_pid=$!

  # Start parallel processes with concurrency control
  local range_id=1
  while [ $current_from_block -le $to_block ]; do
    local current_to_block=$((current_from_block + maxBlocksPerRequest - 1))
    if [ $current_to_block -gt $to_block ]; then
      current_to_block=$to_block
    fi
    
    local temp_output_file="$temp_dir/logs_${current_from_block}_${current_to_block}"
    
    # Control concurrency - wait if too many jobs are running
    while [ ${#pids[@]} -ge $maxConcurrentJobs ]; do
      local new_pids=()
      for pid in "${pids[@]}"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
          new_pids+=("$pid")
        fi
      done
      pids=("${new_pids[@]}")
      if [ ${#pids[@]} -ge $maxConcurrentJobs ]; then
        sleep 0.1
      fi
    done
    
    fetch_logs_range $current_from_block $current_to_block "$temp_output_file" $range_id &
    pids+=($!)
    
    current_from_block=$((current_to_block + 1))
    range_id=$((range_id + 1))
  done

  # Wait for all processes to complete
  for pid in "${pids[@]}"; do
    if [ -n "$pid" ]; then
      wait $pid
    fi
  done

  # Kill progress monitor
  kill $monitor_pid 2>/dev/null
  wait $monitor_pid 2>/dev/null

  # Re-enable job control messages
  set -m

  # Final progress update
  echo "🔄 Processing: 100% ($total_ranges/$total_ranges) | Completed!"

  # Analyze results
  if [ -f "$temp_dir/status.log" ]; then
    success_count=$(grep -c "^SUCCESS:" "$temp_dir/status.log" 2>/dev/null | tr -d '\n' || echo "0")
    failure_count=$(grep -c "^FAILURE:" "$temp_dir/status.log" 2>/dev/null | tr -d '\n' || echo "0")
    
    # Calculate actual total logs found
    local total_logs=0
    local temp_from=$from_block
    while [ $temp_from -le $to_block ]; do
      local temp_to=$((temp_from + maxBlocksPerRequest - 1))
      if [ $temp_to -gt $to_block ]; then
        temp_to=$to_block
      fi
      local temp_output_file="$temp_dir/logs_${temp_from}_${temp_to}"
      if [ -f "$temp_output_file" ] && [ -s "$temp_output_file" ]; then
        local log_count=$(grep -c "^- address:" "$temp_output_file" 2>/dev/null | tr -d '\n' || echo "0")
        total_logs=$((total_logs + log_count))
      fi
      temp_from=$((temp_to + 1))
    done
    
    # Only show failure details if there are failures
    if [ $failure_count -gt 0 ]; then
      echo ""
      echo "⚠️  Warning: $failure_count of $total_ranges ranges failed"
      echo "Failed ranges details:"
      grep "^FAILURE:" "$temp_dir/status.log" | while IFS=':' read -r log_status range_id start_block end_block attempts; do
        echo "  Range $range_id: blocks $start_block-$end_block (failed after $attempts attempts)"
      done
      echo ""
    fi
  else
    success_count=$total_ranges
    failure_count=0
  fi

  # Create output file if specified, even if no logs found
  if [ -n "$output_file" ]; then
    # Create output directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    touch "$output_file"
  fi

  # Output results in order to file if specified, otherwise to stdout
  local total_log_count=0
  current_from_block=$from_block
  while [ $current_from_block -le $to_block ]; do
    local current_to_block=$((current_from_block + maxBlocksPerRequest - 1))
    if [ $current_to_block -gt $to_block ]; then
      current_to_block=$to_block
    fi
    
    local temp_output_file="$temp_dir/logs_${current_from_block}_${current_to_block}"
    if [ -f "$temp_output_file" ] && [ -s "$temp_output_file" ]; then
      # Count actual event logs (lines starting with "- address:")
      local log_count=$(grep -c "^- address:" "$temp_output_file" 2>/dev/null | tr -d '\n' || echo "0")
      total_log_count=$((total_log_count + log_count))
      if [ -n "$output_file" ]; then
        cat "$temp_output_file" >> "$output_file"
      else
        cat "$temp_output_file"
      fi
    fi
    
    current_from_block=$((current_to_block + 1))
  done

  # Final summary
  echo ""
  echo "✅ Found $total_log_count event logs"
  
  if [ -n "$output_file" ]; then
    if [ -f "$output_file" ]; then
      local file_size=$(wc -c < "$output_file" | tr -d '\n')
      local file_size_kb=$((file_size / 1024))
      echo "💾 Saved to: $output_file (${file_size_kb}KB)"
    else
      echo "💾 Saved to: $output_file (empty)"
    fi
  fi
  
  if [ $failure_count -gt 0 ]; then
    echo "⚠️  Note: Some ranges failed - check network connectivity"
  fi

  # Cleanup
  rm -rf "$temp_dir"
  
  # Return non-zero exit code if there were failures
  if [ $failure_count -gt 0 ]; then
    return 1
  fi
  return 0
}