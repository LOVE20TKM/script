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

fetch_events(){
  local contract_name=${1}
  local event_name=${2}

  local abi_file=$(abi_file_path $contract_name)
  local event_def=$(event_def_from_abi $abi_file $event_name)
  local output_file_name="${contract_name}.${event_name}"

  echo "abi_file: $abi_file"
  echo "event_def: $event_def"
  echo "output_file_name: $output_file_name"

  cast_logs $contract_name "$event_def" $from_block $to_block $output_file_name
}

# 用event_def来解析event log，并转换为csv格式
convert_event_file_to_csv(){
  local output_file_name=${1}
  local abi_file_path=${2}
  local event_name=${3}

  local event_def=$(event_def_from_abi $abi_file_path $event_name)

  echo "event_def: $event_def"
  echo "output_file_name: $output_file_name"
  
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


# # Parse decoded output from cast abi-decode to handle dynamic arrays properly
# # Parameters: decoded_file, params_file, output_file
# parse_decoded_output() {
#   local decoded_file="$1"
#   local params_file="$2" 
#   local output_file="$3"
  
#   # Create output file
#   : > "$output_file"
  
#   # Check if decoded file exists and has content
#   if [ ! -f "$decoded_file" ] || [ ! -s "$decoded_file" ]; then
#     echo "Empty or missing decoded file: $decoded_file" >&2
#     return 1
#   fi
  
#   # Count parameters to know how many non-indexed values to expect
#   local param_count=$(wc -l < "$params_file" | tr -d ' ')
#   local non_indexed_count=0
#   local i=1
#   while [ $i -le $param_count ]; do
#     local param=$(sed -n "${i}p" "$params_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
#     if ! echo "$param" | grep -q "indexed"; then
#       non_indexed_count=$((non_indexed_count + 1))
#     fi
#     i=$((i + 1))
#   done
  
#   # Read all content and parse it properly
#   local temp_parsed=$(mktemp)
#   local in_array=false
#   local array_content=""
#   local brace_count=0
  
#   # First pass: parse arrays correctly
#   while IFS= read -r line; do
#     # Trim whitespace
#     line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
#     if [ -z "$line" ]; then
#       continue
#     fi
    
#     # Check if line starts with [
#     if echo "$line" | grep -q "^\["; then
#       in_array=true
#       array_content="$line"
#       brace_count=$(echo "$line" | tr -cd '[' | wc -c)
#       brace_count=$((brace_count - $(echo "$line" | tr -cd ']' | wc -c)))
      
#       # If array is complete in one line
#       if [ $brace_count -eq 0 ]; then
#         in_array=false
#         echo "$array_content" >> "$temp_parsed"
#         array_content=""
#       fi
#     elif [ "$in_array" = true ]; then
#       # Continue building array
#       if [ -n "$array_content" ]; then
#         array_content="$array_content $line"
#       else
#         array_content="$line"
#       fi
      
#       # Update brace count
#       brace_count=$((brace_count + $(echo "$line" | tr -cd '[' | wc -c)))
#       brace_count=$((brace_count - $(echo "$line" | tr -cd ']' | wc -c)))
      
#       # If array is complete
#       if [ $brace_count -eq 0 ]; then
#         in_array=false
#         # Clean up array content
#         array_content=$(echo "$array_content" | sed 's/  */ /g' | sed 's/ *\] */]/g' | sed 's/\[ */[/g')
#         echo "$array_content" >> "$temp_parsed"
#         array_content=""
#       fi
#     else
#       # Regular value
#       echo "$line" >> "$temp_parsed"
#     fi
#   done < "$decoded_file"
  
#   # Now map values to parameters
#   local param_index=1
#   local value_index=1
#   while [ $param_index -le $param_count ]; do
#     local param=$(sed -n "${param_index}p" "$params_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
#     local param_type=$(echo "$param" | awk '{print $1}' | sed 's/indexed[[:space:]]*//')
    
#     # Skip indexed parameters
#     if echo "$param" | grep -q "indexed"; then
#       param_index=$((param_index + 1))
#       continue
#     fi
    
#     # Get value
#     local value=$(sed -n "${value_index}p" "$temp_parsed" 2>/dev/null || echo "")
    
#     # Clean up value based on type
#     if echo "$param_type" | grep -q "\[\]"; then
#       # Dynamic array
#       if [ -z "$value" ]; then
#         value="[]"
#       fi
#     elif echo "$param_type" | grep -q "^uint"; then
#       # Handle uint types
#       if [ -n "$value" ] && echo "$value" | grep -q " \[.*\]"; then
#         value=$(echo "$value" | sed 's/ \[.*\]$//')
#       elif [ -n "$value" ] && echo "$value" | grep -q " "; then
#         value=$(echo "$value" | cut -d' ' -f1)
#       fi
#       # Convert hex to decimal if needed
#       if [ -n "$value" ] && echo "$value" | grep -q "^0x"; then
#         value=$(echo $((value)) 2>/dev/null || echo "$value")
#       fi
#     fi
    

    
#     # Write value to output
#     echo "$value" >> "$output_file"
    
#     value_index=$((value_index + 1))
#     param_index=$((param_index + 1))
#   done
  
#   # Cleanup
#   rm -f "$temp_parsed"
# }

# # Convert event logs to CSV format using cast abi-decode
# convert_to_csv(){
#   local input_file=${1}
#   local event_signature=${2}
#   local output_file_name=${3}
#   local output_file="$output_dir/$output_file_name"
#   local csv_file="$output_dir/$output_file_name.csv"

#   # Check if input file exists
#   if [ ! -f "$input_file" ]; then
#     echo "❌ Input file not found: $input_file"
#     return 1
#   fi

#   # Check if CSV file already exists
#   if [ -f "$csv_file" ]; then
#     echo "❌ CSV file already exists: $csv_file"
#     return 1
#   fi

#   # Parse event signature to get event name
#   local event_def=$(echo "$event_signature" | cut -d'(' -f1)

#   echo ""
#   echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#   echo "📊 Converting to CSV: $event_def"
#   echo "📁 Input: $input_file"
#   echo "💾 Output: $csv_file"

#   # Parse event signature
#   local params_part=$(echo "$event_signature" | sed 's/.*(\(.*\)).*/\1/')
  
#   # Create temporary directory
#   local temp_dir=$(mktemp -d)
  
#   # Parse parameters manually to avoid array issues
#   echo "$params_part" | sed 's/,/\n/g' > "$temp_dir/params.txt"
  
#   # Count parameters
#   local param_count=$(wc -l < "$temp_dir/params.txt" | tr -d ' ')
#   echo "📋 Processing $param_count parameters..."
  
#   # Create CSV header
#   local csv_header="blockNumber,transactionHash,transactionIndex,logIndex,address"
  
#   # Process each parameter for header
#   local line_num=1
#   while [ $line_num -le $param_count ]; do
#     local param=$(sed -n "${line_num}p" "$temp_dir/params.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
#     if [ -n "$param" ]; then
#       # Remove indexed keyword
#       param=$(echo "$param" | sed 's/indexed[[:space:]]*//')
#       # Extract parameter name (second word)
#       local param_name=$(echo "$param" | awk '{print $2}')
#       csv_header="$csv_header,$param_name"
#     fi
#     line_num=$((line_num + 1))
#   done
  
#   echo "$csv_header" > "$csv_file"

#   # Split input file into individual log entries
#   grep -n "^- address:" "$input_file" | cut -d: -f1 > "$temp_dir/log_starts.tmp"
#   local line_count=$(wc -l < "$input_file" | tr -d ' ')
#   echo $((line_count + 1)) >> "$temp_dir/log_starts.tmp"
  
#   local entry_count=0
#   local prev_start=0
  
#   while IFS= read -r start_line; do
#     if [ $prev_start -gt 0 ]; then
#       local end_line=$((start_line - 1))
#       sed -n "${prev_start},${end_line}p" "$input_file" > "$temp_dir/log_$entry_count.yaml"
#       entry_count=$((entry_count + 1))
#     fi
#     prev_start=$start_line
#   done < "$temp_dir/log_starts.tmp"

#   # Process each log entry
#   local success_count=0
#   local error_count=0
  
#   # Check if entry_count is 0 to avoid division by zero
#   if [ $entry_count -eq 0 ]; then
#     echo ""
#     echo "⚠️  No event logs found in the input file"
#     echo "✅ Converted 0 logs to CSV"
    
#     if [ -f "$csv_file" ]; then
#       local csv_lines=$(wc -l < "$csv_file" | tr -d ' ')
#       local csv_size=$(wc -c < "$csv_file" | tr -d ' ')
#       local csv_size_kb=$((csv_size / 1024))
#       echo "💾 File: $csv_file (${csv_size_kb}KB, $((csv_lines - 1)) rows)"
#     fi

#     # Cleanup
#     rm -rf "$temp_dir"
#     return 0
#   fi
  
#   for i in $(seq 0 $((entry_count - 1))); do
#     local log_file="$temp_dir/log_$i.yaml"
    
#     if [ -f "$log_file" ]; then
#       # Extract basic fields
#       local address=$(grep "address:" "$log_file" | head -1 | sed 's/.*address: *//' | tr -d ' ')
#       local block_number=$(grep "blockNumber:" "$log_file" | sed 's/.*blockNumber: *//' | tr -d ' ')
#       local tx_hash=$(grep "transactionHash:" "$log_file" | sed 's/.*transactionHash: *//' | tr -d ' ')
#       local tx_index=$(grep "transactionIndex:" "$log_file" | sed 's/.*transactionIndex: *//' | tr -d ' ')
#       local log_index=$(grep "logIndex:" "$log_file" | sed 's/.*logIndex: *//' | tr -d ' ')
#       local data=$(grep "data:" "$log_file" | sed 's/.*data: *//' | tr -d ' ')
      
#       # Extract topics (skip first one which is event signature)
#       grep "0x" "$log_file" | grep -v "address\|data\|Hash" | sed 's/^[[:space:]]*//' | tail -n +2 > "$temp_dir/topics_$i.tmp"
      
#       # Build CSV row
#       local csv_row="$block_number,$tx_hash,$tx_index,$log_index,$address"
      
#       # Process parameters in order
#       local topic_index=1
#       local non_indexed_data=""
#       local non_indexed_types=""
      
#       # First pass: collect non-indexed types for decoding
#       local line_num=1
#       while [ $line_num -le $param_count ]; do
#         local param=$(sed -n "${line_num}p" "$temp_dir/params.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
#         if [ -n "$param" ]; then
#           if ! echo "$param" | grep -q "indexed"; then
#             # Non-indexed parameter
#             local param_type=$(echo "$param" | awk '{print $1}')
#             if [ -n "$non_indexed_types" ]; then
#               non_indexed_types="$non_indexed_types,$param_type"
#             else
#               non_indexed_types="$param_type"
#             fi
#           fi
#         fi
#         line_num=$((line_num + 1))
#       done
      
#               # Decode non-indexed data if exists
#         if [ -n "$data" ] && [ "$data" != "0x" ] && [ -n "$non_indexed_types" ]; then
#           # Special handling for ActionCreate event with complex tuple
#           if echo "$event_signature" | grep -q "ActionCreate.*minStake.*maxRandomAccounts"; then
#             # For ActionCreate, manually extract actionId from data
#             local actionId=$(echo "$data" | cut -c3-66 | sed 's/^0*//' | sed 's/^$/0/')  # Extract first 32 bytes and remove leading zeros
#             if [ -z "$actionId" ] || [ "$actionId" = "0" ]; then
#               actionId="0"
#             else
#               actionId=$((0x$actionId))  # Convert hex to decimal
#             fi
#             echo "$actionId" > "$temp_dir/decoded_$i.tmp"
#             # Add placeholder values for struct fields (since complex decode is failing)
#             echo "未解析" >> "$temp_dir/decoded_$i.tmp"  # minStake
#             echo "未解析" >> "$temp_dir/decoded_$i.tmp"  # maxRandomAccounts  
#             echo "未解析" >> "$temp_dir/decoded_$i.tmp"  # whiteList
#             echo "未解析" >> "$temp_dir/decoded_$i.tmp"  # action
#             echo "未解析" >> "$temp_dir/decoded_$i.tmp"  # consensus
#             echo "未解析" >> "$temp_dir/decoded_$i.tmp"  # verificationRule
#             echo "未解析" >> "$temp_dir/decoded_$i.tmp"  # verificationKeys
#             echo "未解析" >> "$temp_dir/decoded_$i.tmp"  # verificationInfoGuides
#           else
#             # Use improved ABI decode with proper dynamic array handling
#             cast abi-decode --input "decode($non_indexed_types)" "$data" 2>/dev/null > "$temp_dir/decoded_raw_$i.tmp"
#             # Parse the decoded output and create structured parameter file
#             parse_decoded_output "$temp_dir/decoded_raw_$i.tmp" "$temp_dir/params.txt" "$temp_dir/decoded_$i.tmp"
#           fi
#         fi
      
#       # Second pass: build CSV row with values
#       local line_num=1
#       local non_indexed_index=1
#       while [ $line_num -le $param_count ]; do
#         local param=$(sed -n "${line_num}p" "$temp_dir/params.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
#         local value=""
        
#         if [ -n "$param" ]; then
#           # Extract parameter type for both indexed and non-indexed parameters
#           local param_type=""
#           if echo "$param" | grep -q "indexed"; then
#             param_type=$(echo "$param" | sed 's/indexed[[:space:]]*//' | awk '{print $1}')
#           else
#             param_type=$(echo "$param" | awk '{print $1}')
#           fi
          
#           if echo "$param" | grep -q "indexed"; then
#             # Indexed parameter - get from topics
#             if [ -f "$temp_dir/topics_$i.tmp" ]; then
#               local topic=$(sed -n "${topic_index}p" "$temp_dir/topics_$i.tmp")
#               if [ -n "$topic" ]; then
#                 if [ "$param_type" = "address" ]; then
#                   value="0x${topic:26}"  # Remove padding
#                 else
#                   value="$topic"
#                 fi
#               fi
#               topic_index=$((topic_index + 1))
#             fi
#           else
#             # Non-indexed parameter - get from decoded data
#             if [ -f "$temp_dir/decoded_$i.tmp" ]; then
#               # Special handling for ActionCreate event
#               if echo "$event_signature" | grep -q "ActionCreate.*minStake.*maxRandomAccounts"; then
#                 # For ActionCreate, simply read the pre-generated values line by line
#                 value=$(sed -n "${non_indexed_index}p" "$temp_dir/decoded_$i.tmp" | sed 's/^"//;s/"$//')
#               else
#                 # Use improved parsing that handles dynamic arrays properly
#                 value=$(sed -n "${non_indexed_index}p" "$temp_dir/decoded_$i.tmp" | sed 's/^"//;s/"$//')
                

                
#                                   # Clean up scientific notation in arrays first
#                 if echo "$param_type" | grep -q "\[\]"; then
#                   # Remove scientific notation annotations like " [3.043e21]"
#                   value=$(echo "$value" | sed 's/ \[[0-9]*\.[0-9]*e[0-9]*\]//g')
#                   # Clean up array formatting for CSV
#                   value=$(echo "$value" | sed 's/\[/[/g' | sed 's/\]/]/g' | sed 's/, */, /g')
#                   # Escape any remaining commas for CSV
#                   value=$(echo "$value" | sed 's/,/，/g')
#                 fi
#               fi
#               non_indexed_index=$((non_indexed_index + 1))
#             fi
#           fi
          
#           # Remove scientific notation suffix for uint types - extract first value only
#           if [ -n "$value" ] && echo "$param_type" | grep -q "^uint"; then
#             # Handle format like "6250000000000000000000000 [6.25e24]" - take first value only
#             if echo "$value" | grep -q " \[.*\]"; then
#               value=$(echo "$value" | sed 's/ \[.*\]$//')
#             fi
#             # Handle format with scientific notation suffix like "6250000000000000000000000 6.25e24"
#             if echo "$value" | grep -q " [0-9]*\.[0-9]*e[0-9]*"; then
#               value=$(echo "$value" | cut -d' ' -f1)
#             fi
#             # Handle any space-separated format - take first value
#             if echo "$value" | grep -q " "; then
#               value=$(echo "$value" | cut -d' ' -f1)
#             fi
#           fi
          
#           # Convert hexadecimal to decimal for uint types
#           if [ -n "$value" ] && echo "$param_type" | grep -q "^uint" && echo "$value" | grep -q "^0x"; then
#             # Convert hex to decimal using bash arithmetic expansion
#             value=$(echo $((value)))
#           fi
#         fi
        

        
#         # Escape CSV value
#         local escaped_value=$(echo "$value" | sed 's/"/\\"/g' | tr '\n\r' '  ' | sed 's/  */ /g' | sed 's/,/，/g')
#         if echo "$escaped_value" | grep -q ","; then
#           escaped_value="\"$escaped_value\""
#         fi
        

        
#         csv_row="$csv_row,$escaped_value"
        
#         line_num=$((line_num + 1))
#       done
      
#       # Write row to CSV
#       echo "$csv_row" >> "$csv_file"
#       success_count=$((success_count + 1))
#     fi
#   done
  
#   echo "✅ Converted $success_count logs to CSV"
  
#   if [ -f "$csv_file" ]; then
#     local csv_lines=$(wc -l < "$csv_file" | tr -d ' ')
#     local csv_size=$(wc -c < "$csv_file" | tr -d ' ')
#     local csv_size_kb=$((csv_size / 1024))
#     echo "💾 File: $csv_file (${csv_size_kb}KB, $((csv_lines - 1)) rows)"
#   fi

#   # Cleanup
#   rm -rf "$temp_dir"
  
#   return 0
# }

# # Convert CSV file to XLSX format using Python pandas
# # Parameters: csv_file_path
# # Returns: 0 on success, 1 on failure
# csv_to_xlsx(){
#   local csv_file=${1}
  
#   # Parameter check
#   if [ -z "$csv_file" ]; then
#     echo "❌ Error: CSV file path is required"
#     return 1
#   fi
  
#   # Check if input CSV file exists
#   if [ ! -f "$csv_file" ]; then
#     echo "❌ Error: CSV file not found: $csv_file"
#     return 1
#   fi
  
#   # Generate XLSX file path (same name but with .xlsx extension)
#   local xlsx_file="${csv_file%.csv}.xlsx"
  
#   # Check if XLSX file already exists
#   if [ -f "$xlsx_file" ]; then
#     echo "❌ Error: XLSX file already exists: $xlsx_file"
#     return 1
#   fi
  
#   echo ""
#   echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#   echo "📊 Converting CSV to XLSX"
#   echo "📁 Input: $csv_file"
#   echo "💾 Output: $xlsx_file"
  
#   # Check if Python is available
#   if ! command -v python3 >/dev/null 2>&1; then
#     echo "❌ Error: Python3 is not installed or not in PATH"
#     return 1
#   fi
  
#   # Create temporary Python script
#   local temp_dir=$(mktemp -d)
#   local python_script="$temp_dir/csv_to_xlsx.py"
  
#   cat > "$python_script" << 'EOF'
# import sys
# import pandas as pd
# from pathlib import Path

# def main():
#     if len(sys.argv) != 3:
#         print("❌ Error: Usage: python script.py <input_csv> <output_xlsx>")
#         sys.exit(1)
    
#     input_csv = sys.argv[1]
#     output_xlsx = sys.argv[2]
    
#     try:
#         # Read CSV file
#         df = pd.read_csv(input_csv)
        
#         # Write to XLSX with formatting
#         with pd.ExcelWriter(output_xlsx, engine='openpyxl') as writer:
#             df.to_excel(writer, index=False, sheet_name='Data')
            
#             # Get the workbook and worksheet
#             workbook = writer.book
#             worksheet = writer.sheets['Data']
            
#             # Auto-adjust column widths
#             for column in worksheet.columns:
#                 max_length = 0
#                 column_letter = column[0].column_letter
                
#                 for cell in column:
#                     try:
#                         if len(str(cell.value)) > max_length:
#                             max_length = len(str(cell.value))
#                     except:
#                         pass
                
#                 adjusted_width = min(max_length + 2, 50)  # Cap at 50 characters
#                 worksheet.column_dimensions[column_letter].width = adjusted_width
            
#             # Apply header formatting
#             from openpyxl.styles import PatternFill, Font
#             header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
#             header_font = Font(color="FFFFFF", bold=True)
            
#             for cell in worksheet[1]:
#                 cell.fill = header_fill
#                 cell.font = header_font
        
#         print(f"✅ Successfully converted {len(df)} rows")
        
#     except ImportError as e:
#         if 'pandas' in str(e):
#             print("❌ Error: pandas library is not installed. Please install it with: pip3 install pandas")
#         elif 'openpyxl' in str(e):
#             print("❌ Error: openpyxl library is not installed. Please install it with: pip3 install openpyxl")
#         else:
#             print(f"❌ Error: Missing required library: {e}")
#         sys.exit(1)
        
#     except pd.errors.EmptyDataError:
#         print("❌ Error: CSV file is empty or has no data")
#         sys.exit(1)
        
#     except pd.errors.ParserError as e:
#         print(f"❌ Error: Failed to parse CSV file: {e}")
#         sys.exit(1)
        
#     except Exception as e:
#         print(f"❌ Error: Conversion failed: {e}")
#         sys.exit(1)

# if __name__ == "__main__":
#     main()
# EOF
  
#   # Run Python script
#   echo "🔄 Converting CSV to XLSX..."
  
#   local python_output
#   python_output=$(python3 "$python_script" "$csv_file" "$xlsx_file" 2>&1)
#   local python_exit_code=$?
  
#   if [ $python_exit_code -eq 0 ]; then
#     echo "$python_output"
    
#     # Display file information
#     if [ -f "$xlsx_file" ]; then
#       local xlsx_size=$(wc -c < "$xlsx_file" | tr -d ' ')
#       local xlsx_size_kb=$((xlsx_size / 1024))
#       local csv_lines=$(wc -l < "$csv_file" | tr -d ' ')
#       echo "💾 File: $xlsx_file (${xlsx_size_kb}KB, $((csv_lines - 1)) rows)"
#       echo "✅ CSV to XLSX conversion completed successfully"
#     else
#       echo "❌ Error: XLSX file was not created"
#       rm -rf "$temp_dir"
#       return 1
#     fi
#   else
#     echo "$python_output"
#     echo "❌ Error: Python script failed"
#     rm -rf "$temp_dir"
#     return 1
#   fi
  
#   # Cleanup
#   rm -rf "$temp_dir"
  
#   return 0
# }

# # Extract event signature from interface file
# # Parameters: interface_file_path, event_def
# # Returns: cleaned event signature without "event" prefix
# extract_event_signature_from_file(){
#   local interface_file=${1}
#   local event_def=${2}
  
#   # 参数检查
#   if [ -z "$interface_file" ] || [ -z "$event_def" ]; then
#     echo "❌ Error: interface_file and event_def are required"
#     return 1
#   fi
  
#   # 检查文件是否存在
#   if [ ! -f "$interface_file" ]; then
#     echo "❌ Error: Interface file not found: $interface_file"
#     return 1
#   fi
  
#   # 提取事件签名
#   # 首先找到事件定义行，然后提取完整的事件签名（可能跨多行）
#   local event_signature=""
#   local in_event_block=false
#   local event_line=""
#   local paren_count=0
  
#   while IFS= read -r line; do
#     # 移除行首的空白字符
#     line=$(echo "$line" | sed 's/^ *//')
    
#     # 检查是否找到目标事件的开始
#     if echo "$line" | grep -q "^event *$event_def *(" && [ "$in_event_block" = false ]; then
#       in_event_block=true
#       event_line="$line"
#       # 计算左括号数量
#       paren_count=$(echo "$line" | tr -cd '(' | wc -c | tr -d ' ')
#       # 计算右括号数量并减去
#       paren_count=$((paren_count - $(echo "$line" | tr -cd ')' | wc -c | tr -d ' ')))
      
#       # 如果在同一行找到了完整的事件定义
#       if [ $paren_count -eq 0 ] && echo "$line" | grep -q ");"; then
#         event_signature="$line"
#         break
#       fi
#     elif [ "$in_event_block" = true ]; then
#       # 继续读取事件定义的后续行
#       # 如果当前行不为空，则添加到事件行中
#       if [ -n "$line" ]; then
#         if [ -n "$event_line" ]; then
#           event_line="$event_line $line"
#         else
#           event_line="$line"
#         fi
#       fi
#       # 计算括号平衡
#       paren_count=$((paren_count + $(echo "$line" | tr -cd '(' | wc -c | tr -d ' ') - $(echo "$line" | tr -cd ')' | wc -c | tr -d ' ')))
      
#       # 如果找到了事件结束标志
#       if [ $paren_count -eq 0 ] && echo "$line" | grep -q ");"; then
#         event_signature="$event_line"
#         break
#       fi
#     fi
#   done < "$interface_file"
  
#   # 清理事件签名
#   if [ -n "$event_signature" ]; then
#     # 移除 "event " 前缀和结尾的分号
#     event_signature=$(echo "$event_signature" | sed 's/^event *//' | sed 's/; *$//')
#     # 规范化空白字符，将多个空格替换为单个空格
#     event_signature=$(echo "$event_signature" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
#     # 移除括号内外的多余空格
#     event_signature=$(echo "$event_signature" | sed 's/( */(/g' | sed 's/ *)/)/g')
#     # 移除参数之间的多余空格，规范化逗号后的空格
#     event_signature=$(echo "$event_signature" | sed 's/, */, /g')
    
#     echo "$event_signature"
#     return 0
#   else
#     echo "❌ Error: Event '$event_def' not found in $interface_file"
#     return 1
#   fi
# }

# # 例如：contract_name=launch, event_def=DeployToken, 则返回ILOVE20Launch里的事件签名： DeployToken(address indexed tokenAddress, string tokenSymbol, address indexed parentTokenAddress, address indexed deployer)
# event_signature(){
#   local contract_name=${1}
#   local event_def=${2}
  
#   # 参数检查
#   if [ -z "$contract_name" ] || [ -z "$event_def" ]; then
#     echo "❌ Error: contract_name and event_def are required"
#     return 1
#   fi
  
#   # 特殊处理包含struct的事件签名 - 手动映射到展开的元组类型
#   if [ "$contract_name" = "submit" ] && [ "$event_def" = "ActionCreate" ]; then
#     echo "ActionCreate(address indexed tokenAddress, uint256 indexed round, address indexed author, uint256 actionId, (uint256,uint256,address[],string,string,string,string[],string[]))"
#     return 0
#   fi
  
#   # 构建接口文件路径
#   local interface_file=""
#   case "$contract_name" in
#     "launch")
#       interface_file="../../src/interfaces/ILOVE20Launch.sol"
#       ;;
#     "submit")
#       interface_file="../../src/interfaces/ILOVE20Submit.sol"
#       ;;
#     "vote")
#       interface_file="../../src/interfaces/ILOVE20Vote.sol"
#       ;;
#     "verify")
#       interface_file="../../src/interfaces/ILOVE20Verify.sol"
#       ;;
#     "stake")
#       interface_file="../../src/interfaces/ILOVE20Stake.sol"
#       ;;
#     "mint")
#       interface_file="../../src/interfaces/ILOVE20Mint.sol"
#       ;;
#     "join")
#       interface_file="../../src/interfaces/ILOVE20Join.sol"
#       ;;
#     "token")
#       interface_file="../../src/interfaces/ILOVE20Token.sol"
#       ;;
#     "tokenFactory")
#       interface_file="../../src/interfaces/ILOVE20TokenFactory.sol"
#       ;;
#     "slToken")
#       interface_file="../../src/interfaces/ILOVE20SLToken.sol"
#       ;;
#     "stToken")
#       interface_file="../../src/interfaces/ILOVE20STToken.sol"
#       ;;
#     "random")
#       interface_file="../../src/interfaces/ILOVE20Random.sol"
#       ;;
#     "erc20")
#       interface_file="../../src/interfaces/IERC20.sol"
#       ;;
#     "uniswapV2Factory")
#       interface_file="../../src/interfaces/IUniswapV2Factory.sol"
#       ;;
#     *)
#       echo "❌ Error: Unknown contract name: $contract_name"
#       return 1
#       ;;
#   esac
  
#   # 调用新的函数来提取事件签名
#   extract_event_signature_from_file "$interface_file" "$event_def"
# }

# # 获取用于CSV转换的展开事件签名（将struct展开为各个字段）
# event_signature_for_csv(){
#   local contract_name=${1}
#   local event_def=${2}
  
#   # 参数检查
#   if [ -z "$contract_name" ] || [ -z "$event_def" ]; then
#     echo "❌ Error: contract_name and event_def are required"
#     return 1
#   fi
  
#   # 特殊处理包含struct的事件签名 - 手动映射到展开的各个字段
#   if [ "$contract_name" = "submit" ] && [ "$event_def" = "ActionCreate" ]; then
#     echo "ActionCreate(address indexed tokenAddress, uint256 indexed round, address indexed author, uint256 actionId, uint256 minStake, uint256 maxRandomAccounts, address[] whiteList, string action, string consensus, string verificationRule, string[] verificationKeys, string[] verificationInfoGuides)"
#     return 0
#   fi
  
#   # 对于其他事件，使用标准的事件签名
#   event_signature "$contract_name" "$event_def"
# }





# fetch_event_logs(){
#   local contract_name=${1}
#   local event_def=${2}

#   local contract_address=$(contract_address $contract_name)
#   local event_signature=$(event_signature $contract_name $event_def)

#   cast_logs $contract_address $event_signature $from_block $to_block "$contract_name.$event_def"
# }

# convert_event_logs(){
#   local contract_name=${1}
#   local event_def=${2}

#   # Special handling for ActionCreate
#   if [ "$contract_name" = "submit" ] && [ "$event_def" = "ActionCreate" ]; then
#     convert_actioncreate_logs "$contract_name" "$event_def"
#   else
#     local event_signature=$(event_signature_for_csv $contract_name $event_def)
#     convert_to_csv "./output/$network/$contract_name.$event_def.event" "$event_signature" "$contract_name.$event_def"
#     csv_to_xlsx "./output/$network/$contract_name.$event_def.csv"
#   fi
# }

# # Precise manual parsing function for ActionCreate events
# parse_actioncreate_manual() {
#   local hex_data=$1
#   local entry_num=$2
#   local debug_file=$3
  
#   # Remove 0x prefix
#   hex_data=${hex_data#0x}
  
#   # Initialize all fields
#   local actionId="0"
#   local minStake="0"  
#   local maxRandomAccounts="0"
#   local whiteList="[]"
#   local action=""
#   local consensus=""
#   local verificationRule=""
#   local verificationKeys="[]"
#   local verificationInfoGuides="[]"
  
#   # Extract actionId (first 32 bytes)
#   local actionId_hex=$(echo "$hex_data" | cut -c1-64 | sed 's/^0*//' | sed 's/^$/0/')
#   if [ "$actionId_hex" != "0" ] && [ -n "$actionId_hex" ]; then
#     actionId=$((0x$actionId_hex))
#   fi
  
#   # Extract struct offset (second 32 bytes)
#   local struct_offset_hex=$(echo "$hex_data" | cut -c65-128 | sed 's/^0*//' | sed 's/^$/0/')
#   local struct_offset=$((0x$struct_offset_hex))
  
#   echo "Event $entry_num: actionId=$actionId, struct_offset=$struct_offset" >> "$debug_file"
  
#   if [ $struct_offset -gt 0 ]; then
#     local struct_start=$((struct_offset * 2))
    
#     # Read struct fields in order
#     # minStake (offset 0x00)
#     local minStake_start=$((struct_start + 1))
#     local minStake_end=$((minStake_start + 63))
#     if [ $minStake_end -le ${#hex_data} ]; then
#       local minStake_hex=$(echo "$hex_data" | cut -c${minStake_start}-${minStake_end} | sed 's/^0*//' | sed 's/^$/0/')
#       if [ "$minStake_hex" != "0" ] && [ -n "$minStake_hex" ]; then
#         minStake=$((0x$minStake_hex))
#       fi
#     fi
    
#     # maxRandomAccounts (offset 0x20)
#     local maxRA_start=$((struct_start + 65))
#     local maxRA_end=$((maxRA_start + 63))
#     if [ $maxRA_end -le ${#hex_data} ]; then
#       local maxRA_hex=$(echo "$hex_data" | cut -c${maxRA_start}-${maxRA_end} | sed 's/^0*//' | sed 's/^$/0/')
#       if [ "$maxRA_hex" != "0" ] && [ -n "$maxRA_hex" ]; then
#         maxRandomAccounts=$((0x$maxRA_hex))
#       fi
#     fi
    
#     # Read field offsets for dynamic types
#     # whiteList offset (offset 0x40)
#     local whiteList_offset_start=$((struct_start + 129))
#     local whiteList_offset_end=$((whiteList_offset_start + 63))
#     local whiteList_offset_hex=""
#     if [ $whiteList_offset_end -le ${#hex_data} ]; then
#       whiteList_offset_hex=$(echo "$hex_data" | cut -c${whiteList_offset_start}-${whiteList_offset_end} | sed 's/^0*//' | sed 's/^$/0/')
#     fi
    
#     # action offset (offset 0x60)
#     local action_offset_start=$((struct_start + 193))
#     local action_offset_end=$((action_offset_start + 63))
#     local action_offset_hex=""
#     if [ $action_offset_end -le ${#hex_data} ]; then
#       action_offset_hex=$(echo "$hex_data" | cut -c${action_offset_start}-${action_offset_end} | sed 's/^0*//' | sed 's/^$/0/')
#     fi
    
#     # consensus offset (offset 0x80)
#     local consensus_offset_start=$((struct_start + 257))
#     local consensus_offset_end=$((consensus_offset_start + 63))
#     local consensus_offset_hex=""
#     if [ $consensus_offset_end -le ${#hex_data} ]; then
#       consensus_offset_hex=$(echo "$hex_data" | cut -c${consensus_offset_start}-${consensus_offset_end} | sed 's/^0*//' | sed 's/^$/0/')
#     fi
    
#     # verificationRule offset (offset 0xa0)
#     local verificationRule_offset_start=$((struct_start + 321))
#     local verificationRule_offset_end=$((verificationRule_offset_start + 63))
#     local verificationRule_offset_hex=""
#     if [ $verificationRule_offset_end -le ${#hex_data} ]; then
#       verificationRule_offset_hex=$(echo "$hex_data" | cut -c${verificationRule_offset_start}-${verificationRule_offset_end} | sed 's/^0*//' | sed 's/^$/0/')
#     fi
    
#     # verificationKeys offset (offset 0xc0)
#     local verificationKeys_offset_start=$((struct_start + 385))
#     local verificationKeys_offset_end=$((verificationKeys_offset_start + 63))
#     local verificationKeys_offset_hex=""
#     if [ $verificationKeys_offset_end -le ${#hex_data} ]; then
#       verificationKeys_offset_hex=$(echo "$hex_data" | cut -c${verificationKeys_offset_start}-${verificationKeys_offset_end} | sed 's/^0*//' | sed 's/^$/0/')
#     fi
    
#     # verificationInfoGuides offset (offset 0xe0)
#     local verificationInfoGuides_offset_start=$((struct_start + 449))
#     local verificationInfoGuides_offset_end=$((verificationInfoGuides_offset_start + 63))
#     local verificationInfoGuides_offset_hex=""
#     if [ $verificationInfoGuides_offset_end -le ${#hex_data} ]; then
#       verificationInfoGuides_offset_hex=$(echo "$hex_data" | cut -c${verificationInfoGuides_offset_start}-${verificationInfoGuides_offset_end} | sed 's/^0*//' | sed 's/^$/0/')
#     fi
    
#     echo "Offsets: action=$action_offset_hex, consensus=$consensus_offset_hex, rule=$verificationRule_offset_hex, keys=$verificationKeys_offset_hex, guides=$verificationInfoGuides_offset_hex" >> "$debug_file"
    
#     # Parse strings using calculated offsets
#     if [ -n "$action_offset_hex" ] && [ "$action_offset_hex" != "0" ]; then
#       local action_abs_offset=$((struct_offset + 0x$action_offset_hex))
#       action=$(parse_string_at_offset "$hex_data" $action_abs_offset)
#     fi
    
#     if [ -n "$consensus_offset_hex" ] && [ "$consensus_offset_hex" != "0" ]; then
#       local consensus_abs_offset=$((struct_offset + 0x$consensus_offset_hex))
#       consensus=$(parse_string_at_offset "$hex_data" $consensus_abs_offset)
#     fi
    
#     if [ -n "$verificationRule_offset_hex" ] && [ "$verificationRule_offset_hex" != "0" ]; then
#       local verificationRule_abs_offset=$((struct_offset + 0x$verificationRule_offset_hex))
#       verificationRule=$(parse_string_at_offset "$hex_data" $verificationRule_abs_offset)
#     fi
    
#     if [ -n "$verificationKeys_offset_hex" ] && [ "$verificationKeys_offset_hex" != "0" ]; then
#       local verificationKeys_abs_offset=$((struct_offset + 0x$verificationKeys_offset_hex))
#       verificationKeys=$(parse_string_array_at_offset "$hex_data" $verificationKeys_abs_offset)
#     fi
    
#     if [ -n "$verificationInfoGuides_offset_hex" ] && [ "$verificationInfoGuides_offset_hex" != "0" ]; then
#       local verificationInfoGuides_abs_offset=$((struct_offset + 0x$verificationInfoGuides_offset_hex))
#       verificationInfoGuides=$(parse_string_array_at_offset "$hex_data" $verificationInfoGuides_abs_offset)
#     fi
#   fi
  
#   # Return results as JSON-like string with proper escaping
#   # Remove all newlines and carriage returns from string fields
#   action=$(echo "$action" | tr '\n\r' '  ' | sed 's/  */ /g')
#   consensus=$(echo "$consensus" | tr '\n\r' '  ' | sed 's/  */ /g')
#   verificationRule=$(echo "$verificationRule" | tr '\n\r' '  ' | sed 's/  */ /g')
#   verificationKeys=$(echo "$verificationKeys" | tr '\n\r' '  ' | sed 's/  */ /g')
#   verificationInfoGuides=$(echo "$verificationInfoGuides" | tr '\n\r' '  ' | sed 's/  */ /g')
  
#   echo "$actionId|$minStake|$maxRandomAccounts|$whiteList|$action|$consensus|$verificationRule|$verificationKeys|$verificationInfoGuides"
# }

# # Helper function to parse string at specific offset
# parse_string_at_offset() {
#   local hex_data=$1
#   local offset=$2
  
#   local hex_pos=$((offset * 2 + 1))
  
#   # Read string length (32 bytes)
#   if [ $((hex_pos + 63)) -le ${#hex_data} ]; then
#     local length_hex=$(echo "$hex_data" | cut -c${hex_pos}-$((hex_pos + 63)) | sed 's/^0*//' | sed 's/^$/0/')
#     local string_length=$((0x$length_hex))
    
#     if [ $string_length -gt 0 ] && [ $string_length -lt 10000 ]; then
#       # Read string data
#       local string_start=$((hex_pos + 64))
#       local string_end=$((string_start + string_length * 2 - 1))
      
#       if [ $string_end -le ${#hex_data} ]; then
#         local string_hex=$(echo "$hex_data" | cut -c${string_start}-${string_end})
#         echo "$string_hex" | xxd -r -p 2>/dev/null | tr -d '\0' | sed 's/[[:cntrl:]]//g' || echo ""
#       fi
#     fi
#   fi
# }

# # Helper function to parse string array at specific offset  
# parse_string_array_at_offset() {
#   local hex_data=$1
#   local offset=$2
  
#   local hex_pos=$((offset * 2 + 1))
  
#   # Read array length
#   if [ $((hex_pos + 63)) -le ${#hex_data} ]; then
#     local array_length_hex=$(echo "$hex_data" | cut -c${hex_pos}-$((hex_pos + 63)) | sed 's/^0*//' | sed 's/^$/0/')
#     local array_length=$((0x$array_length_hex))
    
#     if [ $array_length -eq 0 ]; then
#       echo "[]"
#       return
#     fi
    
#     if [ $array_length -gt 0 ] && [ $array_length -le 100 ]; then
#       local result="["
#       local i=0
      
#       while [ $i -lt $array_length ]; do
#         # Read element offset (relative to array start)
#         local element_offset_start=$((hex_pos + 64 + i * 64))
#         local element_offset_end=$((element_offset_start + 63))
        
#         if [ $element_offset_end -le ${#hex_data} ]; then
#           local element_offset_hex=$(echo "$hex_data" | cut -c${element_offset_start}-${element_offset_end} | sed 's/^0*//' | sed 's/^$/0/')
          
#           if [ "$element_offset_hex" != "0" ] && [ -n "$element_offset_hex" ]; then
#             # Calculate element position (relative to array start)
#             local element_pos=$((offset + 0x$element_offset_hex))
#             local element_hex_pos=$((element_pos * 2 + 1))
            
#             # Read string offset (relative to element position) - this is the key fix!
#             if [ $((element_hex_pos + 63)) -le ${#hex_data} ]; then
#               local string_offset_hex=$(echo "$hex_data" | cut -c${element_hex_pos}-$((element_hex_pos + 63)) | sed 's/^0*//' | sed 's/^$/0/')
#               local string_offset=$((0x$string_offset_hex))
              
#               # Calculate actual string data position
#               local string_data_pos=$((element_pos + string_offset))
#               local element_string=$(parse_string_at_offset "$hex_data" $string_data_pos)
              
#               if [ -n "$element_string" ]; then
#                 element_string=$(echo "$element_string" | sed 's/"/\\"/g' | sed 's/,/，/g')
#                 if [ $i -gt 0 ]; then
#                   result="$result,\"$element_string\""
#                 else
#                   result="$result\"$element_string\""
#                 fi
#               else
#                 if [ $i -gt 0 ]; then
#                   result="$result,\"\""
#                 else
#                   result="$result\"\""
#                 fi
#               fi
#             else
#               if [ $i -gt 0 ]; then
#                 result="$result,\"\""
#               else
#                 result="$result\"\""
#               fi
#             fi
#           else
#             if [ $i -gt 0 ]; then
#               result="$result,\"\""
#             else
#               result="$result\"\""
#             fi
#           fi
#         fi
        
#         i=$((i + 1))
#       done
      
#       result="$result]"
#       echo "$result"
#     else
#       echo "[]"
#     fi
#   else
#     echo "[]"
#   fi
# }

# # Specialized function for ActionCreate events with improved ABI decoding
# convert_actioncreate_logs(){
#   local contract_name=${1}
#   local event_def=${2}
#   local input_file="./output/$network/$contract_name.$event_def.event"
#   local csv_file="./output/$network/$contract_name.$event_def.csv"

#   echo ""
#   echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#   echo "📊 Converting ActionCreate to CSV (improved ABI decode)"
#   echo "📁 Input: $input_file"
#   echo "💾 Output: $csv_file"

#   # Create CSV header
#   echo "blockNumber,transactionHash,transactionIndex,logIndex,address,tokenAddress,round,author,actionId,minStake,maxRandomAccounts,whiteList,action,consensus,verificationRule,verificationKeys,verificationInfoGuides" > "$csv_file"

#   # Parse each event from the input file
#   local temp_dir=$(mktemp -d)
#   grep -n "^- address:" "$input_file" | cut -d: -f1 > "$temp_dir/log_starts.tmp"
#   local line_count=$(wc -l < "$input_file" | tr -d ' ')
#   echo $((line_count + 1)) >> "$temp_dir/log_starts.tmp"
  
#   local entry_count=0
#   local prev_start=0
  
#   # Helper function to decode hex string to UTF-8
#   decode_hex_string() {
#     local hex_string=$1
#     if [ -z "$hex_string" ] || [ ${#hex_string} -eq 0 ]; then
#       echo ""
#       return
#     fi
#     # Convert hex to UTF-8 string, remove null bytes
#     echo "$hex_string" | xxd -r -p 2>/dev/null | tr -d '\0' | sed 's/[[:cntrl:]]//g' || echo ""
#   }
  
#   # Helper function to extract string array from data using cast abi-decode
#   decode_string_array() {
#     local hex_data=$1
#     local offset=$2
    
#     if [ -z "$hex_data" ] || [ -z "$offset" ] || [ $offset -le 0 ]; then
#       echo "[]"
#       return
#     fi
    
#     # Extract data from offset
#     local data_start=$((offset * 2))
#     if [ $data_start -ge ${#hex_data} ]; then
#       echo "[]"
#       return
#     fi
    
#     local remaining_data="0x${hex_data:$data_start}"
    
#     # Try to decode as string array using cast
#     local decoded=$(cast abi-decode "decode(string[])" "$remaining_data" 2>/dev/null)
#     if [ $? -eq 0 ] && [ -n "$decoded" ]; then
#       # Convert decoded result to JSON-like format
#       echo "$decoded" | sed 's/\[/["/g' | sed 's/\]/"\]/g' | sed 's/, /", "/g'
#     else
#       echo "[]"
#     fi
#   }
  
#   while IFS= read -r start_line; do
#     if [ $prev_start -gt 0 ]; then
#       local end_line=$((start_line - 1))
#       sed -n "${prev_start},${end_line}p" "$input_file" > "$temp_dir/log_$entry_count.yaml"
      
#       # Extract basic fields
#       local address=$(grep "address:" "$temp_dir/log_$entry_count.yaml" | head -1 | sed 's/.*address: *//' | tr -d ' ')
#       local block_number=$(grep "blockNumber:" "$temp_dir/log_$entry_count.yaml" | sed 's/.*blockNumber: *//' | tr -d ' ')
#       local tx_hash=$(grep "transactionHash:" "$temp_dir/log_$entry_count.yaml" | sed 's/.*transactionHash: *//' | tr -d ' ')
#       local tx_index=$(grep "transactionIndex:" "$temp_dir/log_$entry_count.yaml" | sed 's/.*transactionIndex: *//' | tr -d ' ')
#       local log_index=$(grep "logIndex:" "$temp_dir/log_$entry_count.yaml" | sed 's/.*logIndex: *//' | tr -d ' ')
#       local data=$(grep "data:" "$temp_dir/log_$entry_count.yaml" | sed 's/.*data: *//' | tr -d ' ')
      
#       # Extract indexed parameters from topics
#       grep "0x" "$temp_dir/log_$entry_count.yaml" | grep -v "address\|data\|Hash" | sed 's/^[[:space:]]*//' | tail -n +2 > "$temp_dir/topics_$entry_count.tmp"
#       local tokenAddress=$(sed -n "1p" "$temp_dir/topics_$entry_count.tmp" | sed 's/^0x0*/0x/')
#       local round_hex=$(sed -n "2p" "$temp_dir/topics_$entry_count.tmp")
#       local author=$(sed -n "3p" "$temp_dir/topics_$entry_count.tmp" | sed 's/^0x0*/0x/')
#       local round=$((round_hex))
      
#       # Initialize all fields
#       local actionId="0"
#       local minStake="0"
#       local maxRandomAccounts="0"
#       local whiteList="[]"
#       local action=""
#       local consensus=""
#       local verificationRule=""
#       local verificationKeys="[]"
#       local verificationInfoGuides="[]"
      
#       if [ -n "$data" ] && [ "$data" != "0x" ]; then
#         # Use cast abi-decode to parse the entire data structure
#         local decoded_result=$(cast abi-decode "decode(uint256,(uint256,uint256,address[],string,string,string,string[],string[]))" "$data" 2>/dev/null)
        
#         if [ $? -eq 0 ] && [ -n "$decoded_result" ]; then
#           echo "成功解析事件 $entry_count: $decoded_result" >> "$temp_dir/decode_log.txt"
          
#           # Parse the decoded result to extract fields
#           # This is a simplified parsing - in reality we'd need more sophisticated parsing
#           actionId=$(echo "$decoded_result" | head -1 | tr -d ' ')
          
#           # Handle format like "6250000000000000000000000 [6.25e24]" for actionId
#           if echo "$actionId" | grep -q " \[.*\]"; then
#             actionId=$(echo "$actionId" | sed 's/ \[.*\]$//')
#           elif echo "$actionId" | grep -q " "; then
#             actionId=$(echo "$actionId" | cut -d' ' -f1)
#           fi
          
#           # Extract struct fields from the second part of the result
#           local struct_part=$(echo "$decoded_result" | tail -n +2)
#           if [ -n "$struct_part" ]; then
#             # Extract individual fields from struct (this is simplified)
#             minStake=$(echo "$struct_part" | sed -n '1p' | tr -d ' ')
#             maxRandomAccounts=$(echo "$struct_part" | sed -n '2p' | tr -d ' ')
            
#             # Handle format like "6250000000000000000000000 [6.25e24]" for uint256 fields
#             if echo "$minStake" | grep -q " \[.*\]"; then
#               minStake=$(echo "$minStake" | sed 's/ \[.*\]$//')
#             elif echo "$minStake" | grep -q " "; then
#               minStake=$(echo "$minStake" | cut -d' ' -f1)
#             fi
#             # Remove non-numeric characters
#             minStake=$(echo "$minStake" | sed 's/[^0-9]//g')
            
#             if echo "$maxRandomAccounts" | grep -q " \[.*\]"; then
#               maxRandomAccounts=$(echo "$maxRandomAccounts" | sed 's/ \[.*\]$//')
#             elif echo "$maxRandomAccounts" | grep -q " "; then
#               maxRandomAccounts=$(echo "$maxRandomAccounts" | cut -d' ' -f1)
#             fi
#             # Remove non-numeric characters
#             maxRandomAccounts=$(echo "$maxRandomAccounts" | sed 's/[^0-9]//g')
            
#             action=$(echo "$struct_part" | grep -E "^[^[].*[^]]$" | head -1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
#             consensus=$(echo "$struct_part" | grep -E "^[^[].*[^]]$" | head -2 | tail -1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
#             verificationRule=$(echo "$struct_part" | grep -E "^[^[].*[^]]$" | head -3 | tail -1 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
#           fi
#         else
#           # Use precise manual parsing
#           echo "Cast decode failed for event $entry_count, using precise manual parsing" >> "$temp_dir/decode_log.txt"
          
#           # Use the new precise parsing function
#           local parse_result=$(parse_actioncreate_manual "$data" "$entry_count" "$temp_dir/decode_log.txt")
          
#           # Parse the result string (format: actionId|minStake|maxRandomAccounts|whiteList|action|consensus|verificationRule|verificationKeys|verificationInfoGuides)
#           actionId=$(echo "$parse_result" | cut -d'|' -f1)
#           minStake=$(echo "$parse_result" | cut -d'|' -f2)
#           maxRandomAccounts=$(echo "$parse_result" | cut -d'|' -f3)
#           whiteList=$(echo "$parse_result" | cut -d'|' -f4)
#           action=$(echo "$parse_result" | cut -d'|' -f5)
#           consensus=$(echo "$parse_result" | cut -d'|' -f6)
#           verificationRule=$(echo "$parse_result" | cut -d'|' -f7)
#           verificationKeys=$(echo "$parse_result" | cut -d'|' -f8)
#           verificationInfoGuides=$(echo "$parse_result" | cut -d'|' -f9)
#         fi
#       fi
       
#       # Escape CSV values - replace problematic characters properly
#       action=$(echo "$action" | sed 's/"/\\"/g' | tr '\n\r' '  ' | sed 's/  */ /g' | sed 's/,/，/g')
#       consensus=$(echo "$consensus" | sed 's/"/\\"/g' | tr '\n\r' '  ' | sed 's/  */ /g' | sed 's/,/，/g')
#       verificationRule=$(echo "$verificationRule" | sed 's/"/\\"/g' | tr '\n\r' '  ' | sed 's/  */ /g' | sed 's/,/，/g')
#       verificationKeys=$(echo "$verificationKeys" | sed 's/"/\\"/g' | tr '\n\r' '  ' | sed 's/  */ /g' | sed 's/,/，/g')
#       verificationInfoGuides=$(echo "$verificationInfoGuides" | sed 's/"/\\"/g' | tr '\n\r' '  ' | sed 's/  */ /g' | sed 's/,/，/g')
      
#       # Ensure all fields have values (use empty string if null)
#       if [ -z "$action" ]; then action=""; fi
#       if [ -z "$consensus" ]; then consensus=""; fi
#       if [ -z "$verificationRule" ]; then verificationRule=""; fi
#       if [ -z "$verificationKeys" ]; then verificationKeys="[]"; fi
#       if [ -z "$verificationInfoGuides" ]; then verificationInfoGuides="[]"; fi
#       if [ -z "$whiteList" ]; then whiteList="[]"; fi
      
#       # Build CSV row with proper quoting
#       echo "$block_number,$tx_hash,$tx_index,$log_index,$address,$tokenAddress,$round,$author,$actionId,$minStake,$maxRandomAccounts,\"$whiteList\",\"$action\",\"$consensus\",\"$verificationRule\",\"$verificationKeys\",\"$verificationInfoGuides\"" >> "$csv_file"
      
#       entry_count=$((entry_count + 1))
#     fi
#     prev_start=$start_line
#   done < "$temp_dir/log_starts.tmp"

#   echo "✅ Converted $entry_count logs to CSV"
  
#   if [ -f "$csv_file" ]; then
#     local csv_lines=$(wc -l < "$csv_file" | tr -d ' ')
#     local csv_size=$(wc -c < "$csv_file" | tr -d ' ')
#     local csv_size_kb=$((csv_size / 1024))
#     echo "💾 File: $csv_file (${csv_size_kb}KB, $((csv_lines - 1)) rows)"
#   fi

#   # Show decode log if exists
#   if [ -f "$temp_dir/decode_log.txt" ]; then
#     echo "🔍 Decode log:"
#     cat "$temp_dir/decode_log.txt"
#   fi

#   # Cleanup
#   rm -rf "$temp_dir"
  
#   # Convert to XLSX
#   csv_to_xlsx "$csv_file"
# }

# process_event(){
#   local contract_name=${1}
#   local event_def=${2}

#   echo ""
#   echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#   echo "🚀 Processing: $contract_name.$event_def"
#   echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

#   # Step 1: Fetch event logs
#   echo "📡 Step 1: Fetching event logs..."
#   if fetch_event_logs "$contract_name" "$event_def"; then
#     echo "✅ Fetch completed successfully"
    
#     # Step 2: Convert to CSV
#     echo ""
#     echo "🔄 Step 2: Converting to CSV and XLSX..."
#     if convert_event_logs "$contract_name" "$event_def"; then
#       echo "✅ Conversion completed successfully"
#       echo ""
#       echo "🎉 Processing completed: $contract_name.$event_def"
#     else
#       echo "❌ Conversion failed for: $contract_name.$event_def"
#       return 1
#     fi
#   else
#     echo "❌ Fetch failed for: $contract_name.$event_def"
#     return 1
#   fi
# }

# # 获取token0和token1的pair地址
# contract_pair_address(){
#   local token0=${1}
#   local token1=${2}

#   local pairAddress=$(cast call $uniswapV2FactoryAddress "getPair(address,address)" $token0 $token1 --rpc-url $RPC_URL)

#   # 去掉多于的前缀0，如果 0x 前缀不存在，则补充 0x 前缀
#   pairAddress=$(echo "$pairAddress" | sed 's/^0x0*//')
#   if echo "$pairAddress" | grep -q "^0x"; then
#     echo "$pairAddress"
#   else
#     echo "0x$pairAddress"
#   fi
# }

# contract_pair_name(){
#   local token0=${1}
#   local token1=${2}
#   echo "pair.$token0.$token1"
# }

# fetch_pair_event_logs(){
#   local token0=${1}
#   local token1=${2}
#   local event_def=${3}

#   local contract_address=$(contract_pair_address $token0 $token1)
#   local contract_name=$(contract_pair_name $token0 $token1)
  
#   # For pair contracts, use IUniswapV2Pair interface
#   local event_signature=$(extract_event_signature_from_file "../../src/interfaces/IUniswapV2Pair.sol" "$event_def")

#   cast_logs $contract_address $event_signature $from_block $to_block "$contract_name.$event_def"
# }

# convert_pair_event_logs(){
#   local token0=${1}
#   local token1=${2}
#   local event_def=${3}

#   local contract_name=$(contract_pair_name $token0 $token1)
  
#   # For pair contracts, use IUniswapV2Pair interface
#   local event_signature=$(extract_event_signature_from_file "../../src/interfaces/IUniswapV2Pair.sol" "$event_def")
  
#   convert_to_csv "./output/$network/$contract_name.$event_def.event" "$event_signature" "$contract_name.$event_def"
#   csv_to_xlsx "./output/$network/$contract_name.$event_def.csv"
# }

# process_pair_event(){
#   local token0=${1}
#   local token1=${2}
#   local event_def=${3}

#   local contract_name=$(contract_pair_name $token0 $token1)

#   echo ""
#   echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
#   echo "🚀 Processing: $contract_name.$event_def"
#   echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

#   # Step 1: Fetch event logs
#   echo "📡 Step 1: Fetching event logs..."
#   if fetch_pair_event_logs "$token0" "$token1" "$event_def"; then
#     echo "✅ Fetch completed successfully"
    
#     # Step 2: Convert to CSV
#     echo ""
#     echo "🔄 Step 2: Converting to CSV and XLSX..."
#     if convert_pair_event_logs "$token0" "$token1" "$event_def"; then
#       echo "✅ Conversion completed successfully"
#       echo ""
#       echo "🎉 Processing completed: $contract_name.$event_def"
#     else
#       echo "❌ Conversion failed for: $contract_name.$event_def"
#       return 1
#     fi
#   else
#     echo "❌ Fetch failed for: $contract_name.$event_def"
#     return 1
#   fi
# }



