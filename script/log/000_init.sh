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

# Create output directory if it doesn't exist
if [ ! -d "./output" ]; then
  echo "📁 Creating output directory..."
  mkdir -p ./output
  echo "✅ Output directory created: ./output"
fi

cast_logs(){
  local contract_address=${1}
  local event_name=${2}
  local from_block=${3}
  local to_block=${4}
  local output_file=${5}

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


# launch
event_launch_DeployToken(){
  local from_block=${1}
  local to_block=${2}
  cast_logs $launchAddress "DeployToken(address tokenAddress, string tokenSymbol, address parentTokenAddress, address deployer)" $from_block $to_block "./output/launch_DeployToken.event"
}

event_launch_Contribute(){
  local from_block=${1}
  local to_block=${2}
  cast_logs $launchAddress "Contribute(address tokenAddress, address contributor, uint256 amount, uint256 totalContributed, uint256 participantCount)" $from_block $to_block "./output/launch_Contribute.event"
}

event_launch_Withdraw(){
  local from_block=${1}
  local to_block=${2}
  cast_logs $launchAddress "Withdraw(address tokenAddress, address contributor, uint256 amount)" $from_block $to_block "./output/launch_Withdraw.event"
}