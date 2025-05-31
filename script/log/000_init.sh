maxBlocksPerRequest=4000
maxRetries=3
maxConcurrentJobs=10

network=$1
if [ -z "$network" ]; then
  echo "Network parameter is required."
  return 1
fi

source ../network/$network/address.params 
source ../network/$network/network.params

output_dir="./output/$network"

# Create output directory if it doesn't exist
if [ ! -d "$output_dir" ]; then
  echo "📁 Creating output directory..."
  mkdir -p "$output_dir"
  echo "✅ Output directory created: $output_dir"
fi

cast_logs(){
  local contract_address=${1}
  local event_name=${2}
  local from_block=${3}
  local to_block=${4}
  local output_file_name=${5}

  local output_file="$output_dir/$output_file_name"
  local current_from_block=$from_block
  local pids=()
  local temp_dir=$(mktemp -d)
  local success_count=0
  local failure_count=0
  local retry_count=0
  local total_ranges=0

  # make sure output_file not exists
  if [ -f "$output_file" ]; then
    echo "Output file $output_file already exists"
    return 1
  fi

  echo "==========================================================="
  echo "📊 Event Log Fetcher"
  echo "==========================================================="
  echo "🎯 Contract: $contract_address"
  echo "🔄 Event: $event_name"
  echo "📦 Block Range: $from_block → $to_block"
  echo "==========================================================="

  # Calculate total ranges
  local temp_from=$from_block
  while [ $temp_from -le $to_block ]; do
    total_ranges=$((total_ranges + 1))
    temp_from=$((temp_from + maxBlocksPerRequest))
  done
  echo "📋 Total block ranges to process: $total_ranges"
  echo "⚙️  Max concurrent jobs: $maxConcurrentJobs"
  echo "🔄 Max retries per range: $maxRetries"
  echo ""

  # Function to fetch logs for a specific block range with retry mechanism
  fetch_logs_range() {
    local start_block=$1
    local end_block=$2
    local temp_output_file=$3
    local range_id=$4
    local retry_attempt=${5:-0}

    # Silent execution, only log status to files
    local logs=$(cast logs --from-block $start_block --to-block $end_block --address $contract_address "$event_name" --rpc-url $RPC_URL 2>/dev/null)
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
          
          printf "\r🔄 Processing: %3d%% (%d/%d) | Jobs: %d" \
            $progress $completed $total_ranges $running_jobs
          
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
  printf "\r🔄 Processing: 100%% (%d/%d) | Completed!                    \n" $total_ranges $total_ranges

  # Analyze results
  echo ""
  echo "==========================================================="
  echo "📊 Processing Summary"
  echo "==========================================================="
  
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
    
    echo "📦 Total ranges processed: $total_ranges"
    echo "✅ Successful ranges: $success_count"
    echo "❌ Failed ranges: $failure_count"
    echo "📄 Total event logs found: $total_logs"
    
    if [ $total_ranges -gt 0 ]; then
      local success_rate=$((success_count * 100 / total_ranges))
      echo "📈 Success rate: $success_rate%"
    fi
    
    if [ $failure_count -gt 0 ]; then
      echo ""
      echo "❌ Failed Ranges Details:"
      echo "-----------------------------------------------------------"
      grep "^FAILURE:" "$temp_dir/status.log" | while IFS=':' read -r log_status range_id start_block end_block attempts; do
        echo "   Range $range_id: blocks $start_block-$end_block (failed after $attempts attempts)"
      done
    fi
  else
    success_count=$total_ranges
    failure_count=0
    echo "📦 Total ranges processed: $total_ranges"
    echo "✅ All ranges processed successfully"
    echo "❌ Failed ranges: 0"
  fi

  # Create output file if specified, even if no logs found
  if [ -n "$output_file" ]; then
    # Create output directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    touch "$output_file"
  fi

  # Output results in order to file if specified, otherwise to stdout
  echo ""
  echo "🔄 Collecting and saving results..."
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
  echo "==========================================================="
  echo "🎉 Execution Completed!"
  echo "==========================================================="
  echo "📄 Total event logs collected: $total_log_count"
  
  if [ -n "$output_file" ]; then
    if [ -f "$output_file" ]; then
      local file_size=$(wc -c < "$output_file" | tr -d '\n')
      local file_size_kb=$((file_size / 1024))
      echo "💾 Output file: $output_file (${file_size_kb}KB)"
    else
      echo "💾 Output file: $output_file (empty)"
    fi
  else
    echo "💾 Output: stdout"
  fi
  
  if [ $failure_count -gt 0 ]; then
    echo ""
    echo "⚠️  Warning: $failure_count ranges failed after retries"
    echo "   💡 Tip: Check network connectivity or try running again"
  else
    echo "✨ All ranges processed successfully!"
  fi
  echo "==========================================================="

  # Cleanup
  rm -rf "$temp_dir"
  
  # Return non-zero exit code if there were failures
  if [ $failure_count -gt 0 ]; then
    return 1
  fi
  return 0
}


# Convert event logs to CSV format using cast abi-decode
convert_to_csv(){
  local input_file=${1}
  local event_signature=${2}
  local output_file_name=${3}
  local output_file="$output_dir/$output_file_name"
  local csv_file="$output_dir/$output_file_name.csv"

  # Check if input file exists
  if [ ! -f "$input_file" ]; then
    echo "❌ Input file not found: $input_file"
    return 1
  fi

  # Check if CSV file already exists
  if [ -f "$csv_file" ]; then
    echo "❌ CSV file already exists: $csv_file"
    return 1
  fi

  echo "==========================================================="
  echo "📊 Event Log CSV Converter"
  echo "==========================================================="
  echo "📁 Input file: $input_file"
  echo "🎯 Event signature: $event_signature"
  echo "💾 Output CSV: $csv_file"
  echo "==========================================================="

  # Parse event signature
  local event_name=$(echo "$event_signature" | cut -d'(' -f1)
  local params_part=$(echo "$event_signature" | sed 's/.*(\(.*\)).*/\1/')
  
  # Create temporary directory
  local temp_dir=$(mktemp -d)
  
  # Parse parameters manually to avoid array issues
  echo "$params_part" | sed 's/,/\n/g' > "$temp_dir/params.txt"
  
  # Count parameters
  local param_count=$(wc -l < "$temp_dir/params.txt" | tr -d ' ')
  echo "📋 Found $param_count parameters"
  
  # Create CSV header
  local csv_header="blockNumber,transactionHash,transactionIndex,logIndex,address"
  
  # Process each parameter for header
  local line_num=1
  while [ $line_num -le $param_count ]; do
    local param=$(sed -n "${line_num}p" "$temp_dir/params.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$param" ]; then
      # Remove indexed keyword
      param=$(echo "$param" | sed 's/indexed[[:space:]]*//')
      # Extract parameter name (second word)
      local param_name=$(echo "$param" | awk '{print $2}')
      csv_header="$csv_header,$param_name"
    fi
    line_num=$((line_num + 1))
  done
  
  echo "$csv_header" > "$csv_file"
  echo "📋 CSV header created"

  # Process event logs
  echo "🔄 Processing event logs..."
  
  # Split input file into individual log entries
  grep -n "^- address:" "$input_file" | cut -d: -f1 > "$temp_dir/log_starts.tmp"
  local line_count=$(wc -l < "$input_file" | tr -d ' ')
  echo $((line_count + 1)) >> "$temp_dir/log_starts.tmp"
  
  local entry_count=0
  local prev_start=0
  
  while IFS= read -r start_line; do
    if [ $prev_start -gt 0 ]; then
      local end_line=$((start_line - 1))
      sed -n "${prev_start},${end_line}p" "$input_file" > "$temp_dir/log_$entry_count.yaml"
      entry_count=$((entry_count + 1))
    fi
    prev_start=$start_line
  done < "$temp_dir/log_starts.tmp"
  
  echo "📊 Found $entry_count event log entries to process"

  # Process each log entry
  local success_count=0
  local error_count=0
  
  for i in $(seq 0 $((entry_count - 1))); do
    local log_file="$temp_dir/log_$i.yaml"
    
    if [ -f "$log_file" ]; then
      # Extract basic fields
      local address=$(grep "address:" "$log_file" | head -1 | sed 's/.*address: *//' | tr -d ' ')
      local block_number=$(grep "blockNumber:" "$log_file" | sed 's/.*blockNumber: *//' | tr -d ' ')
      local tx_hash=$(grep "transactionHash:" "$log_file" | sed 's/.*transactionHash: *//' | tr -d ' ')
      local tx_index=$(grep "transactionIndex:" "$log_file" | sed 's/.*transactionIndex: *//' | tr -d ' ')
      local log_index=$(grep "logIndex:" "$log_file" | sed 's/.*logIndex: *//' | tr -d ' ')
      local data=$(grep "data:" "$log_file" | sed 's/.*data: *//' | tr -d ' ')
      
      # Extract topics (skip first one which is event signature)
      grep "0x" "$log_file" | grep -v "address\|data\|Hash" | sed 's/^[[:space:]]*//' | tail -n +2 > "$temp_dir/topics_$i.tmp"
      
      # Build CSV row
      local csv_row="$block_number,$tx_hash,$tx_index,$log_index,$address"
      
      # Process parameters in order
      local topic_index=1
      local non_indexed_data=""
      local non_indexed_types=""
      
      # First pass: collect non-indexed types for decoding
      local line_num=1
      while [ $line_num -le $param_count ]; do
        local param=$(sed -n "${line_num}p" "$temp_dir/params.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$param" ]; then
          if ! echo "$param" | grep -q "indexed"; then
            # Non-indexed parameter
            local param_type=$(echo "$param" | awk '{print $1}')
            if [ -n "$non_indexed_types" ]; then
              non_indexed_types="$non_indexed_types,$param_type"
            else
              non_indexed_types="$param_type"
            fi
          fi
        fi
        line_num=$((line_num + 1))
      done
      
      # Decode non-indexed data if exists
      if [ -n "$data" ] && [ "$data" != "0x" ] && [ -n "$non_indexed_types" ]; then
        cast abi-decode --input "decode($non_indexed_types)" "$data" 2>/dev/null > "$temp_dir/decoded_$i.tmp"
      fi
      
      # Second pass: build CSV row with values
      local line_num=1
      local non_indexed_index=1
      while [ $line_num -le $param_count ]; do
        local param=$(sed -n "${line_num}p" "$temp_dir/params.txt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        local value=""
        
        if [ -n "$param" ]; then
          if echo "$param" | grep -q "indexed"; then
            # Indexed parameter - get from topics
            if [ -f "$temp_dir/topics_$i.tmp" ]; then
              local topic=$(sed -n "${topic_index}p" "$temp_dir/topics_$i.tmp")
              if [ -n "$topic" ]; then
                local param_type=$(echo "$param" | sed 's/indexed[[:space:]]*//' | awk '{print $1}')
                if [ "$param_type" = "address" ]; then
                  value="0x${topic:26}"  # Remove padding
                else
                  value="$topic"
                fi
              fi
              topic_index=$((topic_index + 1))
            fi
          else
            # Non-indexed parameter - get from decoded data
            if [ -f "$temp_dir/decoded_$i.tmp" ]; then
              value=$(sed -n "${non_indexed_index}p" "$temp_dir/decoded_$i.tmp" | sed 's/^"//;s/"$//')
              non_indexed_index=$((non_indexed_index + 1))
            fi
          fi
        fi
        
        # Escape CSV value
        local escaped_value=$(echo "$value" | sed 's/"/\\"/g')
        if echo "$escaped_value" | grep -q ","; then
          escaped_value="\"$escaped_value\""
        fi
        csv_row="$csv_row,$escaped_value"
        
        line_num=$((line_num + 1))
      done
      
      # Write row to CSV
      echo "$csv_row" >> "$csv_file"
      success_count=$((success_count + 1))
    fi
    
    # Progress indicator
    if [ $((i % 10)) -eq 0 ] || [ $i -eq $((entry_count - 1)) ]; then
      local progress=$((i * 100 / entry_count))
      printf "\r🔄 Progress: %3d%% (%d/%d)" $progress $i $entry_count
    fi
  done
  
  echo ""
  echo "==========================================================="
  echo "📊 Conversion Summary"
  echo "==========================================================="
  echo "📄 Total logs processed: $entry_count"
  echo "✅ Successfully converted: $success_count"
  
  if [ -f "$csv_file" ]; then
    local csv_lines=$(wc -l < "$csv_file" | tr -d ' ')
    local csv_size=$(wc -c < "$csv_file" | tr -d ' ')
    local csv_size_kb=$((csv_size / 1024))
    echo "💾 CSV file: $csv_file"
    echo "📊 CSV rows: $((csv_lines - 1)) (excluding header)"
    echo "📦 File size: ${csv_size_kb}KB"
  fi
  
  echo "✨ Conversion completed successfully!"
  echo "==========================================================="

  # Cleanup
  rm -rf "$temp_dir"
  
  return 0
}

# 例如：contract_name=launch, event_name=DeployToken, 则返回ILOVE20Launch里的事件签名： DeployToken(address indexed tokenAddress, string tokenSymbol, address indexed parentTokenAddress, address indexed deployer)
event_signature(){
  local contract_name=${1}
  local event_name=${2}
  
  # 参数检查
  if [ -z "$contract_name" ] || [ -z "$event_name" ]; then
    echo "❌ Error: contract_name and event_name are required"
    return 1
  fi
  
  # 构建接口文件路径
  local interface_file=""
  case "$contract_name" in
    "launch")
      interface_file="../../src/interfaces/ILOVE20Launch.sol"
      ;;
    "submit")
      interface_file="../../src/interfaces/ILOVE20Submit.sol"
      ;;
    "vote")
      interface_file="../../src/interfaces/ILOVE20Vote.sol"
      ;;
    "verify")
      interface_file="../../src/interfaces/ILOVE20Verify.sol"
      ;;
    "stake")
      interface_file="../../src/interfaces/ILOVE20Stake.sol"
      ;;
    "mint")
      interface_file="../../src/interfaces/ILOVE20Mint.sol"
      ;;
    "join")
      interface_file="../../src/interfaces/ILOVE20Join.sol"
      ;;
    "token")
      interface_file="../../src/interfaces/ILOVE20Token.sol"
      ;;
    "tokenFactory")
      interface_file="../../src/interfaces/ILOVE20TokenFactory.sol"
      ;;
    "slToken")
      interface_file="../../src/interfaces/ILOVE20SLToken.sol"
      ;;
    "stToken")
      interface_file="../../src/interfaces/ILOVE20STToken.sol"
      ;;
    "random")
      interface_file="../../src/interfaces/ILOVE20Random.sol"
      ;;
    *)
      echo "❌ Error: Unknown contract name: $contract_name"
      return 1
      ;;
  esac
  
  # 检查文件是否存在
  if [ ! -f "$interface_file" ]; then
    echo "❌ Error: Interface file not found: $interface_file"
    return 1
  fi
  
  # 提取事件签名
  # 首先找到事件定义行，然后提取完整的事件签名（可能跨多行）
  local event_signature=""
  local in_event_block=false
  local event_line=""
  local paren_count=0
  
  while IFS= read -r line; do
    # 移除行首的空白字符
    line=$(echo "$line" | sed 's/^ *//')
    
    # 检查是否找到目标事件的开始
    if echo "$line" | grep -q "^event *$event_name *(" && [ "$in_event_block" = false ]; then
      in_event_block=true
      event_line="$line"
      # 计算左括号数量
      paren_count=$(echo "$line" | tr -cd '(' | wc -c | tr -d ' ')
      # 计算右括号数量并减去
      paren_count=$((paren_count - $(echo "$line" | tr -cd ')' | wc -c | tr -d ' ')))
      
      # 如果在同一行找到了完整的事件定义
      if [ $paren_count -eq 0 ] && echo "$line" | grep -q ");"; then
        event_signature="$line"
        break
      fi
    elif [ "$in_event_block" = true ]; then
      # 继续读取事件定义的后续行
      # 如果当前行不为空，则添加到事件行中
      if [ -n "$line" ]; then
        if [ -n "$event_line" ]; then
          event_line="$event_line $line"
        else
          event_line="$line"
        fi
      fi
      # 计算括号平衡
      paren_count=$((paren_count + $(echo "$line" | tr -cd '(' | wc -c | tr -d ' ') - $(echo "$line" | tr -cd ')' | wc -c | tr -d ' ')))
      
      # 如果找到了事件结束标志
      if [ $paren_count -eq 0 ] && echo "$line" | grep -q ");"; then
        event_signature="$event_line"
        break
      fi
    fi
  done < "$interface_file"
  
  # 清理事件签名
  if [ -n "$event_signature" ]; then
    # 移除 "event " 前缀和结尾的分号
    event_signature=$(echo "$event_signature" | sed 's/^event *//' | sed 's/; *$//')
    # 规范化空白字符，将多个空格替换为单个空格
    event_signature=$(echo "$event_signature" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
    # 移除括号内外的多余空格
    event_signature=$(echo "$event_signature" | sed 's/( */(/g' | sed 's/ *)/)/g')
    # 移除参数之间的多余空格，规范化逗号后的空格
    event_signature=$(echo "$event_signature" | sed 's/, */, /g')
    
    echo "$event_signature"
    return 0
  else
    echo "❌ Error: Event '$event_name' not found in $interface_file"
    return 1
  fi
}


# launch
fetch_launch_DeployToken(){
  local from_block=${1}
  local to_block=${2}
  cast_logs $launchAddress "DeployToken(address indexed tokenAddress, string tokenSymbol, address indexed parentTokenAddress, address indexed deployer)" $from_block $to_block "launch_DeployToken.event"
}

fetch_launch_Contribute(){
  local from_block=${1}
  local to_block=${2}
  cast_logs $launchAddress "Contribute(address indexed tokenAddress, address indexed contributor, uint256 amount, uint256 totalContributed, uint256 participantCount)" $from_block $to_block "launch_Contribute.event"
}

fetch_launch_Withdraw(){
  local from_block=${1}
  local to_block=${2}
  cast_logs $launchAddress "Withdraw(address indexed tokenAddress, address indexed contributor, uint256 amount)" $from_block $to_block "launch_Withdraw.event"
}


convert_launch_DeployToken(){
  convert_to_csv "./output/$network/launch_DeployToken.event" "DeployToken(address indexed tokenAddress, string tokenSymbol, address indexed parentTokenAddress, address indexed deployer)" "launch_DeployToken"
}

convert_launch_Contribute(){
  convert_to_csv "./output/$network/launch_Contribute.event" "Contribute(address indexed tokenAddress, address indexed contributor, uint256 amount, uint256 totalContributed, uint256 participantCount)" "launch_Contribute"
}

convert_launch_Withdraw(){
  convert_to_csv "./output/$network/launch_Withdraw.event" "Withdraw(address indexed tokenAddress, address indexed contributor, uint256 amount)" "launch_Withdraw"
}
