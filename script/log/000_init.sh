network=$1
if [ -z "$network" ]; then
  echo "Network parameter is required."
  return 1
fi


source ../network/$network/address.params 
source ../network/$network/network.params
source ../network/$network/LOVE20.params

from_block=$originBlocks
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

maxBlocksPerRequest=50000  # Large chunks for Python processor
maxRetries=5
maxConcurrentJobs=10  # Reduced concurrency to avoid RPC rate limiting

# Script directory for Python processor
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_PROCESSOR="$SCRIPT_DIR/event_processor.py"

output_dir="./output/$network"
db_dir="./db/$network"

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
if command -v python3.11 >/dev/null 2>&1 && python3.11 -c "import eth_abi, pandas, openpyxl, httpx" 2>/dev/null; then
  PYTHON_CMD="python3.11"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import eth_abi, pandas, openpyxl, httpx" 2>/dev/null; then
  PYTHON_CMD="python3"
else
  PYTHON_CMD=""
fi

check_python_deps() {
  if [ -z "$PYTHON_CMD" ]; then
    echo "❌ Python dependencies not installed"
    echo "💡 Install with: pip install eth-abi eth-utils pandas openpyxl httpx"
    return 1
  fi
  return 0
}


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
    "TUSDT")
      echo $tusdtAddress
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
    "TUSDT")
      echo "$abi_dir/IERC20.sol/IERC20.json"
      ;;
    "uniswapV2Factory")
      echo "$abi_dir/IUniswapV2Factory.sol/IUniswapV2Factory.0.5.16.json"
      ;;
    "uniswapV2Pair")
      echo "$abi_dir/IUniswapV2Pair.sol/IUniswapV2Pair.0.5.16.json"
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
  
  # Build type expansion function for tuple types
  local expand_type_def='
    def expand_type(input):
      if input.type == "tuple" and (input | has("components")) then
        "(" + (input.components | map(expand_type(.)) | join(",")) + ")"
      else
        input.type
      end;
  '

  # 修正的jq查询 - 正确处理indexed字段和tuple展开
  local signature=$(jq -r --arg name "$event_name" "$expand_type_def"'
    .abi[] | 
    select(.type == "event" and .name == $name) | 
    .name + "(" + 
    (.inputs | map(expand_type(.) + (if .indexed then " indexed" else "" end)) | join(", ")) + 
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

# ============================================================================
# HIGH-PERFORMANCE Python-based event processing (RECOMMENDED)
# Usage: fetch_and_convert "launch" "Contributed"
# Performance: 10-50x faster than shell-based processing
# ============================================================================
fetch_and_convert(){
  local contract_name=${1}
  local event_name=${2}
  
  # Check if Python processor is available
  if [ -f "$PYTHON_PROCESSOR" ] && check_python_deps 2>/dev/null; then
    fetch_and_convert_py "$contract_name" "$event_name"
  else
    echo "⚠️  Python processor not available, falling back to shell-based processing"
    echo "💡 For 10-50x better performance, install Python dependencies:"
    echo "   pip install -r $SCRIPT_DIR/requirements.txt"
    fetch_and_convert_shell "$contract_name" "$event_name"
  fi
}

# Python-based high-performance implementation (Direct RPC)
fetch_and_convert_py(){
  local contract_name=${1}
  local event_name=${2}
  
  local contract_addr=$(contract_address $contract_name)
  local abi_file=$(abi_file_path $contract_name)
  
  if [ -z "$contract_addr" ] || [ -z "$abi_file" ]; then
    echo "❌ Invalid contract name: $contract_name"
    return 1
  fi
  
  # Resolve relative ABI path to absolute
  local abs_abi_file
  if [[ "$abi_file" == /* ]]; then
    abs_abi_file="$abi_file"
  else
    abs_abi_file="$SCRIPT_DIR/$abi_file"
  fi
  
  $PYTHON_CMD "$PYTHON_PROCESSOR" \
    --contract "$contract_addr" \
    --abi "$abs_abi_file" \
    --event "$event_name" \
    --rpc "$RPC_URL" \
    --from-block "$from_block" \
    --to-block "$to_block" \
    --output-dir "$output_dir" \
    --name "$contract_name" \
    --max-blocks "$maxBlocksPerRequest" \
    --concurrency "$maxConcurrentJobs" \
    --retries "$maxRetries" \
    --db-path "$db_dir/events.db" \
    --origin-blocks "$originBlocks" \
    --phase-blocks "$PHASE_BLOCKS"
}

# Legacy shell-based implementation (slower, kept for compatibility)
fetch_and_convert_shell(){
  local contract_name=${1}
  local event_name=${2}

  local output_file_name="$(get_output_file_name $contract_name $event_name)"
  local abi_file_path=$(abi_file_path $contract_name)

  fetch_events $contract_name $event_name $output_file_name
  convert_event_file_to_csv $output_file_name $abi_file_path $event_name
  convert_csv_to_xlsx $output_file_name
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

  cast_logs $contract_address "$event_def" $from_block $to_block $output_file_name
}

convert_csv_to_xlsx(){
  local output_file_name=${1}

  local csv_file="$output_dir/$output_file_name.csv"
  local xlsx_file="$output_dir/$output_file_name.xlsx"
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Converting CSV to Excel: $output_file_name"
  echo "📁 Input: $csv_file"
  echo "💾 Output: $xlsx_file"

  # Input validation
  if ! validate_csv_for_xlsx_conversion "$csv_file" "$xlsx_file"; then
    echo "❌ Validation failed"
    return 1
  fi

  # Check for available conversion tools
  local conversion_method=""
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import pandas, openpyxl" 2>/dev/null; then
      conversion_method="pandas"
    elif python3 -c "import csv, xlsxwriter" 2>/dev/null; then
      conversion_method="xlsxwriter"
    fi
  fi

  if [ -z "$conversion_method" ] && command -v libreoffice >/dev/null 2>&1; then
    conversion_method="libreoffice"
  fi

  if [ -z "$conversion_method" ]; then
    echo "❌ No suitable conversion tool found"
    echo "💡 Please install one of the following:"
    echo "   - Python3 with pandas and openpyxl: pip install pandas openpyxl"
    echo "   - Python3 with xlsxwriter: pip install xlsxwriter"
    echo "   - LibreOffice: apt-get install libreoffice (Linux) or brew install --cask libreoffice (macOS)"
    return 1
  fi

  echo "🔧 Using conversion method: $conversion_method"

  # Perform conversion based on available method
  case "$conversion_method" in
    "pandas")
      convert_with_pandas "$csv_file" "$xlsx_file"
      ;;
    "xlsxwriter")
      convert_with_xlsxwriter "$csv_file" "$xlsx_file"
      ;;
    "libreoffice")
      convert_with_libreoffice "$csv_file" "$xlsx_file"
      ;;
    *)
      echo "❌ Unknown conversion method: $conversion_method"
      return 1
      ;;
  esac

  local conversion_result=$?

  # Validate output and generate report
  if [ $conversion_result -eq 0 ]; then
    generate_xlsx_conversion_report "$csv_file" "$xlsx_file"
  else
    echo "❌ Conversion failed"
    return 1
  fi

  return 0
}

# Validate inputs for XLSX conversion
validate_csv_for_xlsx_conversion() {
  local csv_file=$1
  local xlsx_file=$2

  # Check if CSV file exists and is readable
  if [ ! -f "$csv_file" ]; then
    echo "❌ CSV file not found: $csv_file"
    return 1
  fi

  if [ ! -r "$csv_file" ]; then
    echo "❌ CSV file not readable: $csv_file"
    return 1
  fi

  # Check if CSV file is not empty
  if [ ! -s "$csv_file" ]; then
    echo "❌ CSV file is empty: $csv_file"
    return 1
  fi

  # Check if output file already exists
  if [ -f "$xlsx_file" ]; then
    echo "⚠️  Excel file already exists: $xlsx_file"
    echo "🔄 Overwriting existing file..."
    rm -f "$xlsx_file"
  fi

  # Check if output directory is writable
  local output_dir=$(dirname "$xlsx_file")
  if [ ! -w "$output_dir" ]; then
    echo "❌ Output directory not writable: $output_dir"
    return 1
  fi

  # Check available disk space (require at least 50MB)
  local available_space=$(df "$output_dir" | awk 'NR==2 {print $4}')
  if [ "$available_space" -lt 51200 ]; then
    echo "❌ Insufficient disk space (need at least 50MB)"
    return 1
  fi

  # Validate CSV structure (basic check)
  local header_line=$(head -1 "$csv_file" 2>/dev/null)
  if [ -z "$header_line" ]; then
    echo "❌ CSV file appears to have no header"
    return 1
  fi

  echo "✅ Input validation passed"
  return 0
}

# Convert using pandas (most robust method)
convert_with_pandas() {
  local csv_file=$1
  local xlsx_file=$2

  echo "🐍 Converting with pandas..."

  python3 << EOF
import sys
import pandas as pd
from datetime import datetime
import traceback

def convert_csv_to_xlsx(csv_file, xlsx_file):
    try:
        print("📖 Reading CSV file...")
        
        # Read CSV with error handling for encoding issues
        try:
            df = pd.read_csv(csv_file, encoding='utf-8')
        except UnicodeDecodeError:
            print("⚠️  UTF-8 encoding failed, trying latin-1...")
            df = pd.read_csv(csv_file, encoding='latin-1')
        
        if df.empty:
            print("❌ CSV file is empty or has no valid data")
            return False
            
        print(f"📊 Loaded {len(df)} rows and {len(df.columns)} columns")
        
        # Data preprocessing and type optimization
        print("🔧 Optimizing data types...")
        
        # Convert numeric columns where possible
        for col in df.columns:
            if df[col].dtype == 'object':
                # Try to convert to numeric
                numeric_series = pd.to_numeric(df[col], errors='ignore')
                if not numeric_series.equals(df[col]):
                    df[col] = numeric_series
                    
                # Try to convert to datetime for timestamp-like columns
                elif 'time' in col.lower() or 'date' in col.lower():
                    try:
                        df[col] = pd.to_datetime(df[col], errors='ignore')
                    except:
                        pass
        
        print("💾 Writing Excel file...")
        
        # Create Excel writer with engine
        with pd.ExcelWriter(xlsx_file, engine='openpyxl') as writer:
            
            # Write main data sheet
            df.to_excel(writer, sheet_name='Events', index=False, freeze_panes=(1, 0))
            
            # Get the workbook and worksheet
            workbook = writer.book
            worksheet = writer.sheets['Events']
            
            # Auto-adjust column widths
            for column in worksheet.columns:
                max_length = 0
                column_letter = column[0].column_letter
                
                for cell in column:
                    try:
                        if len(str(cell.value)) > max_length:
                            max_length = len(str(cell.value))
                    except:
                        pass
                
                # Set column width (max 50 characters)
                adjusted_width = min(max_length + 2, 50)
                worksheet.column_dimensions[column_letter].width = adjusted_width
            
            # Add formatting to header row
            from openpyxl.styles import Font, PatternFill, Border, Side
            
            header_font = Font(bold=True, color="FFFFFF")
            header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")
            header_border = Border(
                left=Side(style='thin'),
                right=Side(style='thin'),
                top=Side(style='thin'),
                bottom=Side(style='thin')
            )
            
            # Apply header formatting
            for cell in worksheet[1]:
                cell.font = header_font
                cell.fill = header_fill
                cell.border = header_border
            
            # Add summary sheet with metadata
            summary_data = {
                'Metric': [
                    'Total Rows',
                    'Total Columns', 
                    'File Size (CSV)',
                    'Conversion Time',
                    'Generated By'
                ],
                'Value': [
                    len(df),
                    len(df.columns),
                    f"{csv_file}",
                    datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                    'LOVE20 Event Log Processor'
                ]
            }
            
            summary_df = pd.DataFrame(summary_data)
            summary_df.to_excel(writer, sheet_name='Summary', index=False)
            
            # Format summary sheet
            summary_ws = writer.sheets['Summary']
            for column in summary_ws.columns:
                max_length = 0
                column_letter = column[0].column_letter
                for cell in column:
                    try:
                        if len(str(cell.value)) > max_length:
                            max_length = len(str(cell.value))
                    except:
                        pass
                adjusted_width = min(max_length + 2, 30)
                summary_ws.column_dimensions[column_letter].width = adjusted_width
        
        print("✅ Excel file created successfully")
        return True
        
    except Exception as e:
        print(f"❌ Error during conversion: {str(e)}")
        traceback.print_exc()
        return False

# Execute conversion
success = convert_csv_to_xlsx('$csv_file', '$xlsx_file')
sys.exit(0 if success else 1)
EOF

  return $?
}

# Convert using xlsxwriter (lightweight alternative)
convert_with_xlsxwriter() {
  local csv_file=$1
  local xlsx_file=$2

  echo "📝 Converting with xlsxwriter..."

  python3 << EOF
import sys
import csv
import xlsxwriter
from datetime import datetime
import traceback

def convert_csv_to_xlsx(csv_file, xlsx_file):
    try:
        print("📖 Reading CSV file...")
        
        # Create workbook and worksheet
        workbook = xlsxwriter.Workbook(xlsx_file)
        worksheet = workbook.add_worksheet('Events')
        
        # Define formats
        header_format = workbook.add_format({
            'bold': True,
            'fg_color': '#366092',
            'font_color': 'white',
            'border': 1
        })
        
        cell_format = workbook.add_format({'border': 1})
        
        row_count = 0
        col_count = 0
        
        # Read and write CSV data
        with open(csv_file, 'r', encoding='utf-8') as f:
            csv_reader = csv.reader(f)
            
            for row_num, row in enumerate(csv_reader):
                col_count = max(col_count, len(row))
                
                for col_num, cell_value in enumerate(row):
                    if row_num == 0:  # Header row
                        worksheet.write(row_num, col_num, cell_value, header_format)
                    else:
                        # Try to convert to number if possible
                        try:
                            if '.' in cell_value:
                                worksheet.write(row_num, col_num, float(cell_value), cell_format)
                            else:
                                worksheet.write(row_num, col_num, int(cell_value), cell_format)
                        except (ValueError, TypeError):
                            worksheet.write(row_num, col_num, cell_value, cell_format)
                
                row_count = row_num + 1
                
                if row_count % 1000 == 0:
                    print(f"🔄 Processed {row_count} rows...")
        
        # Auto-adjust column widths (basic implementation)
        for col in range(col_count):
            worksheet.set_column(col, col, 15)  # Set default width
        
        # Add summary worksheet
        summary_ws = workbook.add_worksheet('Summary')
        summary_data = [
            ['Metric', 'Value'],
            ['Total Rows', row_count - 1],  # Excluding header
            ['Total Columns', col_count],
            ['Source File', csv_file],
            ['Conversion Time', datetime.now().strftime('%Y-%m-%d %H:%M:%S')],
            ['Generated By', 'LOVE20 Event Log Processor']
        ]
        
        for row_num, row_data in enumerate(summary_data):
            for col_num, cell_value in enumerate(row_data):
                if row_num == 0:
                    summary_ws.write(row_num, col_num, cell_value, header_format)
                else:
                    summary_ws.write(row_num, col_num, cell_value, cell_format)
        
        workbook.close()
        
        print(f"✅ Excel file created with {row_count} rows and {col_count} columns")
        return True
        
    except Exception as e:
        print(f"❌ Error during conversion: {str(e)}")
        traceback.print_exc()
        return False

# Execute conversion
success = convert_csv_to_xlsx('$csv_file', '$xlsx_file')
sys.exit(0 if success else 1)
EOF

  return $?
}

# Convert using LibreOffice (system tool alternative)
convert_with_libreoffice() {
  local csv_file=$1
  local xlsx_file=$2

  echo "📊 Converting with LibreOffice..."

  # Use LibreOffice headless mode for conversion
  libreoffice --headless --convert-to xlsx --outdir "$(dirname "$xlsx_file")" "$csv_file" 2>/dev/null

  local conversion_result=$?

  if [ $conversion_result -eq 0 ]; then
    # LibreOffice creates file with same name but .xlsx extension
    local base_name=$(basename "$csv_file" .csv)
    local lo_output="$(dirname "$xlsx_file")/${base_name}.xlsx"
    
    # Rename to expected output filename if different
    if [ "$lo_output" != "$xlsx_file" ]; then
      mv "$lo_output" "$xlsx_file" 2>/dev/null
    fi
    
    if [ -f "$xlsx_file" ]; then
      echo "✅ LibreOffice conversion completed"
      return 0
    else
      echo "❌ LibreOffice conversion failed - output file not found"
      return 1
    fi
  else
    echo "❌ LibreOffice conversion failed with exit code: $conversion_result"
    return 1
  fi
}

# Generate comprehensive conversion report
generate_xlsx_conversion_report() {
  local csv_file=$1
  local xlsx_file=$2

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Conversion Report"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [ -f "$xlsx_file" ]; then
    # File size comparison
    local csv_size=$(wc -c < "$csv_file" | tr -d ' ')
    local xlsx_size=$(wc -c < "$xlsx_file" | tr -d ' ')
    local csv_size_kb=$((csv_size / 1024))
    local xlsx_size_kb=$((xlsx_size / 1024))
    
    # Row count from CSV
    local csv_rows=$(wc -l < "$csv_file" | tr -d ' ')
    local data_rows=$((csv_rows - 1))  # Excluding header
    
    echo "✅ Conversion successful!"
    echo "📁 Input (CSV): $csv_file (${csv_size_kb}KB)"
    echo "📁 Output (Excel): $xlsx_file (${xlsx_size_kb}KB)"
    echo "📊 Data rows: $data_rows"
    
    # Calculate compression ratio
    if [ $csv_size -gt 0 ]; then
      local compression_ratio=$((xlsx_size * 100 / csv_size))
      echo "📈 Size ratio: ${compression_ratio}% of original"
    fi
    
    # Verify Excel file can be opened (basic test)
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "
import pandas as pd
try:
    df = pd.read_excel('$xlsx_file', sheet_name='Events')
    print(f'✅ Excel file verification: {len(df)} rows loaded successfully')
except Exception as e:
    print(f'⚠️  Excel file verification failed: {e}')
" 2>/dev/null
    fi
    
    echo "🎉 Ready to open in Excel, LibreOffice, or other spreadsheet applications!"
    
  else
    echo "❌ Conversion failed - output file not created"
    return 1
  fi

  return 0
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

# Generate CSV header with proper escaping and tuple expansion
generate_csv_header() {
  local event_abi=$1

  local header
  header=$(echo "$event_abi" | jq -r '
    def expand_param_name(param; prefix):
      if param.type == "tuple" and (param | has("components")) then
        (param.name | if . == null then "param" else . end) as $tuple_name |
        param.components | map(expand_param_name(.; prefix + $tuple_name + ".")) | join(",")
      else
        prefix + (param.name | if . == null then "param" else . end)
      end;
    
    "blockNumber,transactionHash,transactionIndex,logIndex,address," +
    (.inputs | map(expand_param_name(.; "")) | join(","))
  ' 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$header" ]; then
    echo "❌ Failed to generate CSV header" >&2
    return 1
  fi

  echo "$header"
  return 0
}

# Extract parameter metadata for processing with tuple expansion
extract_parameter_metadata() {
  local event_abi=$1
  local temp_dir=$2

  # Extract parameter details with tuple expansion
  echo "$event_abi" | jq -r '
    def expand_param(param):
      if param.type == "tuple" and (param | has("components")) then
        param.components | map(. + {
          "parent_name": param.name,
          "parent_indexed": (param.indexed | if . == null then false else . end)
        })
      else
        [param]
      end;
    
    [.inputs[] | expand_param(.)] | flatten | .[] | @json
  ' > "$temp_dir/params.json"
  
  if [ $? -ne 0 ]; then
    echo "❌ Failed to extract parameter metadata" >&2
    return 1
  fi

  # Generate type information for cast abi-decode (non-indexed only) with tuple expansion
  local non_indexed_types
  non_indexed_types=$(echo "$event_abi" | jq -r '
    def expand_type(input):
      if input.type == "tuple" and (input | has("components")) then
        "(" + (input.components | map(expand_type(.)) | join(",")) + ")"
      else
        input.type
      end;
    
    [.inputs[] | select(.indexed != true) | expand_type(.)] | join(",")
  ' 2>/dev/null)

  if [ $? -ne 0 ]; then
    echo "❌ Failed to generate type information" >&2
    return 1
  fi

  echo "$non_indexed_types" > "$temp_dir/non_indexed_types.txt"

  # Store original parameter structure for tuple processing
  echo "$event_abi" | jq -r '.inputs[] | @json' > "$temp_dir/original_params.json"

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

# Process event parameters with tuple expansion support
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

    # Process original parameters and expand tuples
    local original_param_index=0
    local expanded_param_index=0
    
    while IFS= read -r original_param_json; do
      if [ -n "$original_param_json" ] && [ "$original_param_json" != "null" ]; then
        local param_type=$(echo "$original_param_json" | jq -r '.type // ""' 2>/dev/null)
        local param_indexed=$(echo "$original_param_json" | jq -r '.indexed // false' 2>/dev/null)
        
        if [ "$param_indexed" = "true" ]; then
          # Indexed parameter - process directly
          local value=$(process_indexed_parameter "$topics_json" $topic_index "$param_type" 2>/dev/null)
          value=$(escape_csv_value "$value" 2>/dev/null)
          param_values="$param_values,$value"
          topic_index=$((topic_index + 1))
          
        elif [ "$param_type" = "tuple" ]; then
          # Non-indexed tuple - parse and expand
          local tuple_data=$(parse_tuple_data "$decoded_values" "$temp_dir/original_params.json" $non_indexed_index $original_param_index 2>/dev/null)
          
          # Get component count for this tuple
          local component_count=$(echo "$original_param_json" | jq -r '.components | length' 2>/dev/null)
          
          # Process each tuple component
          local component_index=0
          while [ $component_index -lt $component_count ]; do
            local component_value=$(echo "$tuple_data" | sed -n "$((component_index + 1))p" 2>/dev/null)
            
            # Get component type for proper formatting
            local component_type=$(echo "$original_param_json" | jq -r ".components[$component_index].type // \"string\"" 2>/dev/null)
            
            # Apply type-specific formatting
            component_value=$(format_value_by_type "$component_value" "$component_type" 2>/dev/null)
            component_value=$(escape_csv_value "$component_value" 2>/dev/null)
            param_values="$param_values,$component_value"
            
            component_index=$((component_index + 1))
          done
          
          non_indexed_index=$((non_indexed_index + 1))
          
        else
          # Non-indexed simple parameter
          local value=$(get_decoded_value "$decoded_values" $non_indexed_index "$param_type" 2>/dev/null)
          value=$(escape_csv_value "$value" 2>/dev/null)
          param_values="$param_values,$value"
          non_indexed_index=$((non_indexed_index + 1))
        fi
      fi
      original_param_index=$((original_param_index + 1))
    done < "$temp_dir/original_params.json"

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

# Format value according to its type
format_value_by_type() {
  local old_opts="$-"
  set +x  # Disable debug output
  
  {
    local value=$1
    local param_type=$2

    if [ -z "$value" ]; then
      echo ""
      return 0
    fi

    # Type-specific cleanup (similar to get_decoded_value)
    case "$param_type" in
      *"[]")
        # Array type - format properly for CSV
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/ \[[^]]*\]//g')
        if [ -n "$value" ] && [ "$value" != "null" ]; then
          if ! echo "$value" | grep -q '^\[.*\]$'; then
            value="[$value]"
          fi
          value=$(echo "$value" | sed 's/, */;/g' | sed 's/ *,/;/g')
        else
          value="[]"
        fi
        ;;
      uint*|int*)
        value=$(echo "$value" | sed 's/ \[.*\]$//' | awk '{print $1}' | tr -d '\n\r\t')
        ;;
      bytes*)
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$value" ] && ! echo "$value" | grep -q '^0x'; then
          value="0x$value"
        fi
        ;;
      bool)
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$value" in
          "true"|"True"|"TRUE"|"1") value="true" ;;
          "false"|"False"|"FALSE"|"0") value="false" ;;
        esac
        ;;
      address)
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "$value" ] && command -v cast >/dev/null 2>&1; then
          normalized=$(cast --to-checksum-address "$value" 2>/dev/null)
          if [ $? -eq 0 ] && [ -n "$normalized" ]; then
            value="$normalized"
          fi
        fi
        ;;
      string)
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
}

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

# Parse tuple data into individual components using improved Python parser
parse_tuple_data() {
  local old_opts="$-"
  set +x  # Disable debug output
  
  {
    local decoded_values=$1
    local original_params_file=$2
    local decoded_line_index=$3
    local param_def_index=$4
    
    # Get the parameter definition
    local param_def=$(sed -n "$((param_def_index + 1))p" "$original_params_file" 2>/dev/null)
    
    if [ -z "$param_def" ] || [ "$param_def" = "null" ]; then
      echo ""
      return 1
    fi
    
    # Check if this parameter is a tuple
    local param_type=$(echo "$param_def" | jq -r '.type // ""' 2>/dev/null)
    
    if [ "$param_type" != "tuple" ]; then
      # Not a tuple, return the value as-is
      echo "$decoded_values" | sed -n "$((decoded_line_index + 1))p" 2>/dev/null
      return 0
    fi
    
    # Parse tuple components - handle multi-line tuple data
    # For tuple data, we need to extract from the specified line to the end
    # since tuple data might span multiple lines due to embedded newlines
    local all_lines
    all_lines=$(echo "$decoded_values")
    
    # Get total line count
    local total_lines=$(echo "$decoded_values" | wc -l)
    
    # Extract from the target line to the end, then join into single line
    local tuple_line=""
    if [ $decoded_line_index -lt $total_lines ]; then
      tuple_line=$(echo "$decoded_values" | tail -n +$((decoded_line_index + 1)) | tr '\n' ' ' | sed 's/  */ /g')
    fi
    
    if [ -z "$tuple_line" ]; then
      echo ""
      return 1
    fi
    
    # Use Python to parse the complex tuple format from cast abi-decode
    echo "$tuple_line" | python3 -c "
import sys
import re

def parse_cast_tuple(line):
    '''Parse tuple output from cast abi-decode with improved error handling'''
    line = line.strip()
    
    # Remove outer parentheses
    if line.startswith('(') and line.endswith(')'):
        line = line[1:-1]
    
    components = []
    current = ''
    in_quotes = False
    paren_depth = 0
    bracket_depth = 0
    
    i = 0
    while i < len(line):
        try:
            char = line[i]
            
            if char == '\"':
                in_quotes = not in_quotes
                current += char
            elif not in_quotes:
                if char == '(':
                    paren_depth += 1
                    current += char
                elif char == ')':
                    paren_depth -= 1
                    current += char
                elif char == '[':
                    bracket_depth += 1
                    current += char
                elif char == ']':
                    bracket_depth -= 1
                    current += char
                elif char == ',' and paren_depth == 0 and bracket_depth == 0:
                    # Found a top-level comma separator
                    if current.strip():
                        components.append(current.strip())
                    current = ''
                else:
                    current += char
            else:
                current += char
            
            i += 1
        except Exception:
            # Skip problematic characters and continue
            i += 1
            continue
    
    # Add the last component
    if current.strip():
        components.append(current.strip())
    
    return components

def clean_component(comp):
    '''Clean up individual components with better error handling'''
    try:
        comp = comp.strip()
        
        # Remove scientific notation annotations like '[1e20]'
        comp = re.sub(r'\s+\[[^\]]*\]$', '', comp)
        
        # Clean up quotes more carefully
        if len(comp) >= 2 and comp.startswith('\"') and comp.endswith('\"'):
            comp = comp[1:-1]
        
        return comp
    except Exception:
        return str(comp) if comp else ''

try:
    line = sys.stdin.read().strip()
    if not line:
        # Return original line if empty
        print(line)
        sys.exit(0)
    
    # If line doesn't look like a tuple, return as-is
    if not (line.startswith('(') and ')' in line):
        print(line)
        sys.exit(0)
    
    components = parse_cast_tuple(line)
    
    # If parsing failed or returned too few components, fallback
    if len(components) < 2:
        print(line)
        sys.exit(0)
    
    for comp in components:
        print(clean_component(comp))
        
except Exception as e:
    # Fallback: return original line
    try:
        line = sys.stdin.read().strip()
        print(line)
    except:
        pass
" 2>/dev/null
    
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
        # Convert "1, 2, 3" format to "[1;2;3]" format (use semicolon to avoid CSV parsing issues)
        if [ -n "$value" ] && [ "$value" != "null" ]; then
          # Check if it's already in bracket format
          if ! echo "$value" | grep -q '^\[.*\]$'; then
            # Convert comma-separated values to bracketed format
            value="[$value]"
          fi
          # Clean up spaces around commas and replace commas with semicolons for CSV safety
          value=$(echo "$value" | sed 's/, */;/g' | sed 's/ *,/;/g')
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

    # Remove control characters first
    value=$(echo "$value" | tr -d '\r\n\t')
    
    # Handle string values that are already properly quoted by cast abi-decode
    # If value is wrapped in quotes (check for proper quote pairing)
    if echo "$value" | grep -q '^".*"$' && [ "$(echo "$value" | grep -o '"' | wc -l)" -eq 2 ]; then
      # Extract the content inside quotes
      local inner_content
      inner_content=$(echo "$value" | sed 's/^"\(.*\)"$/\1/')
      
      # Check if inner content needs quoting (contains comma, quote, or whitespace)
      if echo "$inner_content" | grep -q '[,"]' || echo "$inner_content" | grep -q '[[:space:]]'; then
        # Keep the quotes and escape internal quotes
        value=$(echo "$inner_content" | sed 's/"/\"\"/g')
        echo "\"$value\""
      else
        # Simple string - remove outer quotes
        echo "$inner_content"
      fi
    # Check if quoting is needed for unquoted values
    elif echo "$value" | grep -q '[,"]' || echo "$value" | grep -q '[[:space:]]'; then
      # Escape quotes by doubling them (CSV standard)
      value=$(echo "$value" | sed 's/"/\"\"/g')
      # Wrap in quotes
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

  # Cross-platform atomic write function using lock directory
  atomic_write_status() {
    local message=$1
    local lock_dir="$temp_dir/status.lock.dir"
    local max_wait=300  # Increased from 30 to 300 (30 seconds total)
    local waited=0
    local retry_count=0
    local max_retries=3
    
    # Retry loop for acquiring lock
    while [ $retry_count -lt $max_retries ]; do
      waited=0
      # Try to acquire lock (mkdir is atomic)
      while ! mkdir "$lock_dir" 2>/dev/null; do
        sleep 0.1
        waited=$((waited + 1))
        if [ $waited -gt $max_wait ]; then
          # Timeout - remove stale lock and retry
          rm -rf "$lock_dir" 2>/dev/null
          retry_count=$((retry_count + 1))
          break
        fi
      done
      
      # Check if we got the lock
      if [ -d "$lock_dir" ] || mkdir "$lock_dir" 2>/dev/null; then
        # Success - write to file
        echo "$message" >> "$temp_dir/status.log"
        # Release lock
        rm -rf "$lock_dir" 2>/dev/null
        return 0
      fi
    done
    
    # All retries failed - write error to stderr
    echo "ERROR: Failed to acquire lock after $max_retries retries for: $message" >&2
    return 1
  }

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
      # Use atomic write to prevent concurrent write conflicts
      atomic_write_status "SUCCESS:$range_id:$start_block:$end_block:$log_count"
    elif [ $cast_exit_code -eq 0 ]; then
      # No logs found, but request was successful
      atomic_write_status "SUCCESS:$range_id:$start_block:$end_block:0"
    else
      # Request failed
      if [ $retry_attempt -lt $maxRetries ]; then
        sleep 2
        fetch_logs_range $start_block $end_block "$temp_output_file" $range_id $((retry_attempt + 1))
      else
        atomic_write_status "FAILURE:$range_id:$start_block:$end_block:$((retry_attempt + 1))"
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
  
  # Debug: list temp files and analyze status
  local temp_file_count=$(ls -1 "$temp_dir"/logs_* 2>/dev/null | wc -l | tr -d ' ')
  echo "🔍 Temp files created: $temp_file_count"
  if [ $temp_file_count -gt 0 ] && [ $temp_file_count -le 10 ]; then
    ls -lh "$temp_dir"/logs_* 2>/dev/null | awk '{print "   "$9" ("$5")"}'
  elif [ $temp_file_count -gt 10 ]; then
    echo "   (showing first 5 and last 5)"
    ls -lh "$temp_dir"/logs_* 2>/dev/null | head -5 | awk '{print "   "$9" ("$5")"}'
    echo "   ..."
    ls -lh "$temp_dir"/logs_* 2>/dev/null | tail -5 | awk '{print "   "$9" ("$5")"}'
  fi

  # Analyze results
  if [ -f "$temp_dir/status.log" ]; then
    success_count=$(grep -c "^SUCCESS:" "$temp_dir/status.log" 2>/dev/null | tr -d '\n' || echo "0")
    failure_count=$(grep -c "^FAILURE:" "$temp_dir/status.log" 2>/dev/null | tr -d '\n' || echo "0")
    
    # Count successes with events vs empty
    local success_with_events=$(grep "^SUCCESS:" "$temp_dir/status.log" | grep -v ":0$" | wc -l | tr -d ' ')
    local success_empty=$(grep "^SUCCESS:" "$temp_dir/status.log" | grep ":0$" | wc -l | tr -d ' ')
    echo "🔍 Status summary:"
    echo "   Success with events: $success_with_events"
    echo "   Success (empty): $success_empty"
    echo "   Failed: $failure_count"
    
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
  local merged_ranges=0
  local empty_ranges=0
  local missing_ranges=0
  
  current_from_block=$from_block
  while [ $current_from_block -le $to_block ]; do
    local current_to_block=$((current_from_block + maxBlocksPerRequest - 1))
    if [ $current_to_block -gt $to_block ]; then
      current_to_block=$to_block
    fi
    
    local temp_output_file="$temp_dir/logs_${current_from_block}_${current_to_block}"
    if [ -f "$temp_output_file" ]; then
      if [ -s "$temp_output_file" ]; then
        # Count actual event logs (lines starting with "- address:")
        local log_count=$(grep -c "^- address:" "$temp_output_file" 2>/dev/null | tr -d '\n' || echo "0")
        total_log_count=$((total_log_count + log_count))
        merged_ranges=$((merged_ranges + 1))
        if [ -n "$output_file" ]; then
          cat "$temp_output_file" >> "$output_file"
        else
          cat "$temp_output_file"
        fi
      else
        empty_ranges=$((empty_ranges + 1))
      fi
    else
      missing_ranges=$((missing_ranges + 1))
    fi
    
    current_from_block=$((current_to_block + 1))
  done
  
  # Debug output
  local keep_temp_dir=0
  if [ $merged_ranges -eq 0 ] && [ $total_ranges -gt 0 ]; then
    echo "🔍 Debug: merged=$merged_ranges, empty=$empty_ranges, missing=$missing_ranges, total=$total_ranges"
    echo "🔍 Temp dir: $temp_dir"
    echo "🔍 Temp files count: $(ls -1 "$temp_dir"/logs_* 2>/dev/null | wc -l | tr -d ' ')"
    echo "🔍 Checking first temp file content:"
    ls -lh "$temp_dir"/logs_* 2>/dev/null | head -3
    keep_temp_dir=1
  fi

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

  # Cleanup (keep temp dir for debugging if no data merged)
  if [ $keep_temp_dir -eq 0 ]; then
    rm -rf "$temp_dir"
  else
    echo "🔍 Temp dir preserved for debugging: $temp_dir"
  fi
  
  # Return non-zero exit code if there were failures
  if [ $failure_count -gt 0 ]; then
    return 1
  fi
  return 0
}

# ============================================================================
# Quick Reference
# ============================================================================
# 
# RECOMMENDED (Python - 10-50x faster):
#   fetch_and_convert "launch" "Contributed"
#   fetch_and_convert "stake" "Staked"
#
# LEGACY (Shell - slower, for compatibility):
#   fetch_and_convert_shell "launch" "Contributed"
#
# Available contracts:
#   launch, submit, vote, verify, stake, mint, join, token, 
#   tokenFactory, slToken, stToken, random, erc20, TUSDT,
#   uniswapV2Factory, uniswapV2Pair
#
# Install Python dependencies:
#   pip install -r requirements.txt
# ============================================================================