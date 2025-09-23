# Load contract and network configuration 
# Note: 
# 1. Update deployed contract addresses in address.params
# 2. address.params and LOVE20.params not conflict with each other
# 3. set base_dir to the correct directory




#  ------ set base_dir before run this script ------ 
export network=$1
# check network is set and network is a sub directory of network   
if [ -z "$network" ] || [ ! -d "../network/$network" ]; then
    echo -e "\033[31mError:\033[0m Network parameter is required."
    echo -e "\nAvailable networks:"
    for net in $(ls ../network); do
        echo "  - $net"
    done
    return 1
fi

# --------------------------------------------------
base_dir="../network/$network"

source "$base_dir/.account"
source "$base_dir/address.params"
source "$base_dir/network.params"
source "$base_dir/WETH.params"
source "$base_dir/LOVE20.params"

# ------ Request keystore password ------
echo -e "\nPlease enter keystore password (for $KEYSTORE_ACCOUNT):"
read -s KEYSTORE_PASSWORD
export KEYSTORE_PASSWORD
echo "Password saved, will not be requested again in this session"

# ------ user defined variables ------ 
tokenAddress=$firstTokenAddress 
parentTokenAmountForContribute=$((FIRST_PARENT_TOKEN_FUNDRAISING_GOAL/2))  
verificationKey="default"
promisedWaitingPhases=$PROMISED_WAITING_PHASES_MIN

# tokenAddress=0xdC68df72eBe8bbcF283b3d7833407840Fbd15E14
# parentTokenAmountForContribute=$(echo "scale=0; $PARENT_TOKEN_FUNDRAISING_GOAL / 2" | bc) 
tokenAmountForLP=100000
parentTokenAmountForLP=50000


tokenSymbolForDeploy="CHILD1"


# ------ functions ------
cast_send() {
    local address=$1
    local function_signature=$2
    shift 2
    local args=("$@")

    # echo "Executing cast send: $address $function_signature ${args[@]}"
    cast send "$address" \
        "$function_signature" \
        "${args[@]}" \
        --rpc-url "$RPC_URL" \
        --account "$KEYSTORE_ACCOUNT" \
        --password "$KEYSTORE_PASSWORD" \
        --legacy
}
echo "cast_send() loaded"

cast_call() {
    local address=$1
    local function_signature=$2
    shift 2
    local args=("$@")

    # echo "Executing cast call: $address $function_signature ${args[@]}"
    cast call "$address" \
        "$function_signature" \
        "${args[@]}" \
        --rpc-url "$RPC_URL" \
        --account "$KEYSTORE_ACCOUNT" \
        --password "$KEYSTORE_PASSWORD"
}
echo "cast_call() loaded"

cast_receipt(){
    local tx_hash=$1
    cast receipt $tx_hash --rpc-url $RPC_URL ## --json 
}
echo "cast_receipt() loaded"


show_hex_3() {
    local hex_value decimal

    # Check if there's an argument passed
    if [ $# -gt 0 ]; then
        hex_value="$1"
    else
        # If no argument, read from standard input
        read -r hex_value
    fi

    # Remove possible "0x" prefix
    hex_value="${hex_value#0x}"

    # Convert to uppercase using tr
    hex_value=$(echo "$hex_value" | tr '[:lower:]' '[:upper:]')

    echo "0x$hex_value"
    decimal=$(echo "ibase=16; $hex_value" | bc)
    echo "$decimal"
    
    # Convert to scientific notation using awk
    echo "$decimal" | awk '{printf "%.6e\n", $0}'
}
echo "show_hex_3() loaded"

# input: 13886575830208168899279802 [1.388e25]
# output: 13886575.830208168899279802
show_in_eth(){
    local wei_value

    # Check if there's an argument passed
    if [ $# -gt 0 ]; then
        wei_value="$1"
    else
        # If no argument, read from standard input
        read -r wei_value
    fi

    # Remove possible scientific notation format and trailing spaces
    wei_value=$(echo "$wei_value" | sed 's/\[.*\]//' | tr -d ' ')

    # Convert wei to eth using bc for precise calculation
    echo "scale=18; $wei_value / 1000000000000000000" | bc | sed 's/0*$//' | sed 's/\.$//'

}
echo "show_in_eth() loaded"


# Accept a contract address, calculate the number of blocks until the next round based on roundRange and current block height
next_phase_waiting_blocks(){
    # Check if required variables are loaded
    if [ -z "$PHASE_BLOCKS" ]; then
        echo "Error: PHASE_BLOCKS is not set. Please make sure LOVE20.params is properly loaded."
        return 1
    fi

    local contract_address=$1
    if [ -z "$contract_address" ]; then
        echo "Error: Contract address is required"
        return 1
    fi

    local current_round=$(cast_call $contract_address "currentRound()(uint256)")
    printf "current_round: %s\n" $current_round
    local current_block=$(cast block latest --field number --rpc-url $RPC_URL)
    printf "current_block: %s\n" $current_block

    # Ensure all variables are numbers
    if ! [[ "$current_round" =~ ^[0-9]+$ ]] || ! [[ "$current_block" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid number format for current_round or current_block"
        return 1
    fi

    # Get origin_blocks and remove any scientific notation format and trailing spaces
    local origin_blocks=$(cast_call $contract_address "originBlocks()(uint256)" | sed 's/\[.*\]//' | tr -d ' ')
    printf "origin_blocks: %s\n" $origin_blocks

    # Ensure origin_blocks is a number
    if ! [[ "$origin_blocks" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid number format for origin_blocks"
        return 1
    fi

    # Ensure PHASE_BLOCKS is a number
    if ! [[ "$PHASE_BLOCKS" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid number format for PHASE_BLOCKS"
        return 1
    fi

    local start_block=$((origin_blocks + PHASE_BLOCKS * current_round))
    local end_block=$((origin_blocks + PHASE_BLOCKS * (current_round + 1) - 1))

    printf "start_block: %s\n" $start_block
    printf "end_block: %s\n" $end_block
    
    # Calculate the number of blocks until the next round
    if [ "$current_block" -le "$end_block" ]; then
        local next_phase_block=$((end_block - current_block))
        echo "Blocks until next round: $next_phase_block"
    else
        echo "Current block is already past the end of this round"
        echo "Consider checking the next round"
    fi
}
echo "next_phase_waiting_blocks() loaded"


current_round(){
    local contract_address=$1
    cast_call $contract_address "currentRound()(uint256)"
}
echo "current_round() loaded"


launch_info(){
    local token_address=$1
    echo "token_address: $token_address"
    cast_call $launchAddress "launchInfo(address)((address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint256,uint256,uint256))" $token_address --json | jq -r '.[0] | gsub("[() ]";"") | split(",") | {
        parentTokenAddress: .[0],
        parentTokenFundraisingGoal: .[1],
        secondHalfMinBlocks: .[2],
        launchAmount: .[3],
        startBlock: .[4],
        secondHalfStartBlock: .[5],
        endBlock: .[6],
        hasEnded: .[7],
        participantCount: .[8],
        totalContributed: .[9],
        totalExtraRefunded: .[10]
    }' | jq
}
launch_info_by_index(){
    local token_address=$(cast_call $launchAddress "tokensAtIndex(uint256)(address)" $1)
    launch_info $token_address
}
echo "launch_info() loaded"




stake_status(){
    local token_address=$1
    local account_address=$2
    local slAmount slAmountSci stAmount promisedWaitingPhases requestedUnstakeRound govVotes
    
    cast_call $stakeAddress "accountStakeStatus(address,address)(int256,uint256,uint256,uint256,uint256)" $token_address $account_address | {
        read slAmount slAmountSci
        read stAmount
        read promisedWaitingPhases
        read requestedUnstakeRound
        read govVotes

        echo "{"
        echo "    slAmount: $slAmount $slAmountSci"
        echo "    stAmount: $stAmount"
        echo "    promisedWaitingPhases: $promisedWaitingPhases"
        echo "    requestedUnstakeRound: $requestedUnstakeRound"
        echo "    govVotes: $govVotes"
        echo "}"
    }
}
echo "stake_status() loaded"

action_info(){
    local action_id=$1
    echo "action_id: $action_id"

    cast_call $submitAddress "actionInfo(address,uint256)(tuple(tuple(uint256,address,uint256),tuple(uint256,uint256,address,string,string,string[],string[])))" $tokenAddress $action_id | sed 's/^((//' | sed 's/))$//' | awk -F'), \\(' '{
        split($1, head, ", ");
        split($2, body, ", ");
        print "ActionHead:";
        print "  id: " head[1];
        print "  author: " head[2];
        print "  createAtBlock: " head[3];
        print "ActionBody:";
        print "  minStake: " body[1];
        print "  maxRandomAccounts: " body[2];
        print "  whiteListAddress: " body[3];
        print "  action: " body[4];
        print "  verificationRule: " body[5];
        print "  verificationKeys: " body[6];
        print "  verificationInfoGuides: " body[7];
    }' | sed 's/"//g'
}
echo "action_info() loaded"

action_info_by_field() {
    local action_id=$1
    local field=$2

    # Call the original action_info function and pipe the output to awk
    action_info $action_id | awk -v field="$field" '
    BEGIN { found = 0 }
    $1 == field ":" {
        found = 1
        # Print all content after the colon (removing leading spaces)
        for (i=2; i<=NF; i++) printf "%s%s", (i>2?" ":""), $i
        print ""
        exit
    }
    END {
        if (!found) print "Field not found: " field > "/dev/stderr"
    }'
}
echo "action_info_by_field() loaded"

join_status() {
  local token_address=$1
  local action_id=$2

  local num_of_accounts=$(cast_call $joinAddress "numOfAccounts(address,uint256)(uint256)" $token_address $action_id)
  local amount_by_action_id=$(cast_call $joinAddress "amountByActionId(address,uint256)(uint256) " $token_address $action_id | show_in_eth)

  echo "numOfAccounts: $num_of_accounts"
  echo "amountByActionId: $amount_by_action_id"

  if [ "$num_of_accounts" -gt 0 ]; then
    echo "index account amountByActionIdByAccount"
  fi

  for ((i=1; i<= num_of_accounts; i++)); do
    local account=$(cast_call $joinAddress "indexToAccount(address,uint256,uint256)(address)" $token_address $action_id $i)
    local amount_by_action_id_by_account=$(cast_call $joinAddress "amountByActionIdByAccount(address,uint256,address)(uint256)" $token_address $action_id $account | show_in_eth)
    
    echo "$i $account $amount_by_action_id_by_account"
  done
}
echo "join_status() loaded"

account_status() {
    local token_address=$1
  local account_address=$2

  local amount_by_account=$(cast_call $joinAddress "amountByAccount(address,address)(uint256)" $token_address $account_address | show_in_eth)
  local action_ids_by_account=$(cast_call $joinAddress "actionIdsByAccount(address,address)(uint256[])" $token_address $account_address)

  echo "--------------------"
  echo "Action Status"
  echo "--------------------"

  echo "amountByAccount: $amount_by_account"
  echo "actionIdsByAccount: $action_ids_by_account"

  if [ -n "$action_ids_by_account" ] && [ "$action_ids_by_account" != "[]" ]; then
    action_ids_clean=$(echo "$action_ids_by_account" | sed 's/\[//g' | sed 's/\]//g')
    
    echo "$action_ids_clean" | tr ',' '\n' | while read -r action_id; do
      action_id=$(echo "$action_id" | xargs)
      if [ -n "$action_id" ]; then
        local amount_by_action_id_by_account=$(cast_call $joinAddress "amountByActionIdByAccount(address,uint256,address)(uint256)" $token_address $action_id $account_address | show_in_eth)
        echo "actionId: $action_id, amountByActionIdByAccount: $amount_by_action_id_by_account"
      fi
    done
  fi
}
echo "account_status() loaded"

balance_of(){
    local token_address=$1
    local account_address=$2
    cast_call $token_address "balanceOf(address)(uint256)" $account_address | awk '{printf "%.6f\n", $1 / 10^18}'
}
echo "balance_of() loaded"

balance_of_wei(){
    local token_address=$1
    local account_address=$2
    cast_call $token_address "balanceOf(address)(uint256)" $account_address
}
echo "balance_of_wei() loaded"


balance_eth_in_wei  (){
    local address=$1
    cast balance $address --rpc-url $RPC_URL
}
echo "balance_eth_in_wei() loaded"

balance_eth(){
    local address=$1
    balance_eth_in_wei $address | awk '{printf "%.6f\n", $1 / 10^18}'
}
echo "balance_eth() loaded"


# eg: cast_block number
cast_block(){
    local field=$1
    cast block latest --field $field --rpc-url $RPC_URL
}
echo "cast_block() loaded"

send_eth_in_wei(){
    local address=$1
    local amount_in_wei=$2
    cast send $address --value $amount_in_wei --rpc-url $RPC_URL --account $KEYSTORE_ACCOUNT --password $KEYSTORE_PASSWORD --legacy
}
echo "send_eth_in_wei() loaded"

send_eth(){
    local address=$1
    local amount_in_eth=$2
    local amount_in_wei=$(echo "$amount_in_eth * 10^18" | bc)
    send_eth_in_wei $address $amount_in_wei
}
echo "send_eth() loaded"

send_token_in_wei(){
    local token_address=$1
    local account_address=$2
    local amount_in_wei=$3
    cast_send $token_address "transfer(address,uint256)" $account_address $amount_in_wei
}
echo "send_token_in_wei() loaded"

send_token(){
    local token_address=$1
    local account_address=$2
    local amount_in_eth=$3
    local amount_in_wei=$(echo "$amount_in_eth * 10^18" | bc)
    send_token_in_wei $token_address $account_address $amount_in_wei
}

countdown() {
    local total_seconds=$1

    for ((i=total_seconds; i>0; i--)); do
        local hours=$((i / 3600))
        local minutes=$(((i % 3600) / 60))
        local seconds=$((i % 60))
        
        printf "\r%02d:%02d:%02d (%d seconds left)               " \
            $hours $minutes $seconds $i
        
        sleep 1
    done

    printf "\rDone! 00:00:00 (0 seconds left)          \n"
}

current_block(){
    cast block latest --field number --rpc-url $RPC_URL
}
echo "current_block() loaded"

next_phase() {
    local currentRound=$(current_round $submitAddress)
    local nextRound=$((currentRound + 1))
    
    while [ "$nextRound" -gt "$currentRound" ]; do
        local currentBlock=$(current_block)

        local blocksSinceOrigin=$((currentBlock - originBlocks))
        local blocksInCurrentRound=$((blocksSinceOrigin % PHASE_BLOCKS))
        local remainingBlocks=$((PHASE_BLOCKS - blocksInCurrentRound))
        
        echo "currentRound: $currentRound"
        echo "Remaining blocks until next phase: $remainingBlocks"
        
        local seconds=$(echo "$remainingBlocks * $SECONDS_PER_BLOCK"| bc)
        countdown $seconds

        currentRound=$(current_round $submitAddress)
    done
}
echo "next_phase() loaded"
skip_promised_waiting_phases() {
    local seconds=$(echo "$PHASE_BLOCKS * $SECONDS_PER_BLOCK * ($promisedWaitingPhases + 1)" | bc)
    countdown $seconds
}
echo "skip_promised_waiting_phases() loaded"
skip_second_half_min_blocks() {
    local seconds=$(echo "$SECOND_HALF_MIN_BLOCKS * $SECONDS_PER_BLOCK" | bc)
    countdown $seconds
}
echo "skip_second_half_min_blocks() loaded"
skip_withdraw_waiting_blocks() {
    local seconds=$(echo "$WITHDRAW_WAITING_BLOCKS * $SECONDS_PER_BLOCK" | bc)
    countdown $seconds
}
echo "skip_withdraw_waiting_blocks() loaded"

echo "------ user defined variables ------";
echo "tokenAddress: $tokenAddress"
echo "parentTokenAmountForContribute: $parentTokenAmountForContribute"

echo "------ calculated variables ------";
parentTokenAddress=$(cast_call $tokenAddress "parentTokenAddress()(address)")
echo "parentTokenAddress: $parentTokenAddress"

launch_info $tokenAddress

echo "------ $base_dir/.account loaded ------";
echo "ACCOUNT_ADDRESS: $ACCOUNT_ADDRESS"

echo "------ $base_dir/network.params loaded ------";
echo "RPC_URL: $RPC_URL"

echo "------ $base_dir/address.params loaded ------";
echo "originBlocks: $originBlocks"
echo "uniswapV2FactoryAddress: $uniswapV2FactoryAddress"
echo "rootParentTokenAddress: $rootParentTokenAddress"
echo "tokenFactoryAddress: $tokenFactoryAddress"
echo "launchAddress: $launchAddress"
echo "stakeAddress: $stakeAddress"
echo "submitAddress: $submitAddress"
echo "voteAddress: $voteAddress"
echo "joinAddress: $joinAddress"
echo "randomAddress: $randomAddress"
echo "verifyAddress: $verifyAddress"
echo "mintAddress: $mintAddress"
echo "firstTokenAddress: $firstTokenAddress"
slTokenAddress=$(cast_call $firstTokenAddress "slAddress()(address)")
echo "firstSLTokenAddress: $slTokenAddress"
stTokenAddress=$(cast_call $firstTokenAddress "stAddress()(address)")
echo "firstSTTokenAddress: $stTokenAddress"

echo "------ $base_dir/WETH.params loaded ------";
echo "WETH_NAME: $WETH_NAME"
echo "WETH_SYMBOL: $WETH_SYMBOL"

echo "------ $base_dir/LOVE20.params loaded ------";
echo "FIRST_TOKEN_SYMBOL: $FIRST_TOKEN_SYMBOL"
echo "TOKEN_SYMBOL_LENGTH: $TOKEN_SYMBOL_LENGTH"
echo "MAX_SUPPLY: $MAX_SUPPLY"
echo "FIRST_PARENT_TOKEN_FUNDRAISING_GOAL: $FIRST_PARENT_TOKEN_FUNDRAISING_GOAL"
echo "PARENT_TOKEN_FUNDRAISING_GOAL: $PARENT_TOKEN_FUNDRAISING_GOAL"
echo "LAUNCH_AMOUNT: $LAUNCH_AMOUNT"
echo "WITHDRAW_WAITING_BLOCKS: $WITHDRAW_WAITING_BLOCKS"
echo "SECOND_HALF_MIN_BLOCKS: $SECOND_HALF_MIN_BLOCKS"
echo "MIN_GOV_REWARD_MINTS_TO_LAUNCH: $MIN_GOV_REWARD_MINTS_TO_LAUNCH"
echo "PHASE_BLOCKS: $PHASE_BLOCKS"
echo "JOIN_END_PHASE_BLOCKS: $JOIN_END_PHASE_BLOCKS"
echo "PROMISED_WAITING_PHASES_MIN: $PROMISED_WAITING_PHASES_MIN"
echo "PROMISED_WAITING_PHASES_MAX: $PROMISED_WAITING_PHASES_MAX"
echo "MAX_WITHDRAWABLE_TO_FEE_RATIO: $MAX_WITHDRAWABLE_TO_FEE_RATIO"
echo "SUBMIT_MIN_PER_THOUSAND: $SUBMIT_MIN_PER_THOUSAND"
echo "RANDOM_SEED_UPDATE_MIN_PER_TEN_THOUSAND: $RANDOM_SEED_UPDATE_MIN_PER_TEN_THOUSAND"
echo "ACTION_REWARD_MIN_VOTE_PER_THOUSAND: $ACTION_REWARD_MIN_VOTE_PER_THOUSAND"
echo "ROUND_REWARD_GOV_PER_THOUSAND: $ROUND_REWARD_GOV_PER_THOUSAND"
echo "ROUND_REWARD_ACTION_PER_THOUSAND: $ROUND_REWARD_ACTION_PER_THOUSAND"
echo "MAX_GOV_BOOST_REWARD_MULTIPLIER: $MAX_GOV_BOOST_REWARD_MULTIPLIER"

# ------ help function ------
help() {
    echo -e "\n\033[32m=== Available Functions ===\033[0m"
    echo -e "\033[33mCore Functions:\033[0m"
    echo "  cast_send(address, function_signature, args...)     - Send transaction to contract"
    echo "  cast_call(address, function_signature, args...)     - Call contract function (view)"
    echo "  cast_receipt(tx_hash)                              - Get transaction receipt"
    
    echo -e "\n\033[33mUtility Functions:\033[0m"
    echo "  show_hex_3(hex_value)                             - Convert hex to decimal and scientific notation"
    echo "  show_in_eth(wei_value)                            - Convert wei to ETH"
    echo "  countdown(seconds)                                 - Countdown timer"
    
    echo -e "\n\033[33mBlock and Phase Functions:\033[0m"
    echo "  next_phase_waiting_blocks(contract_address)        - Calculate blocks until next round"
    echo "  current_round(contract_address)                    - Get current round number"
    echo "  current_block()                                    - Get current block number"
    echo "  cast_block(field)                                  - Get block field (number, hash, etc.)"
    echo "  next_phase()                                       - Wait for next phase"
    echo "  skip_promised_waiting_phases()                     - Skip promised waiting phases"
    echo "  skip_second_half_min_blocks()                      - Skip second half min blocks"
    echo "  skip_withdraw_waiting_blocks()                     - Skip withdraw waiting blocks"
    
    echo -e "\n\033[33mContract Query Functions:\033[0m"
    echo "  launch_info(token_address)                         - Get launch information"
    echo "  launch_info_by_index(index)                       - Get launch info by index"
    echo "  stake_status(token_address, account_address)       - Get stake status"
    echo "  action_info(action_id)                            - Get action information"
    echo "  action_info_by_field(action_id, field)            - Get specific action field"
    echo "  join_status(token_address, action_id)             - Get join status"
    echo "  account_status(token_address, account_address)     - Get account status"
    
    echo -e "\n\033[33mBalance Functions:\033[0m"
    echo "  balance_of(token_address, account_address)         - Get token balance in ETH"
    echo "  balance_of_wei(token_address, account_address)     - Get token balance in wei"
    echo "  balance_eth_in_wei(address)                       - Get ETH balance in wei"
    echo "  balance_eth(address)                       - Get ETH balance in ETH"
    
    echo -e "\n\033[33mTransfer Functions:\033[0m"
    echo "  send_eth_in_wei(address, amount_in_wei)           - Send ETH in wei"
    echo "  send_eth(address, amount_in_eth)           - Send ETH in ETH"
    echo "  send_token_in_wei(token_address, account_address, amount_in_wei)"
    echo "                                                     - Send tokens in wei"
    echo "  send_token(token_address, account_address, amount_in_eth)"
    echo "                                                     - Send tokens in ETH"
    
    echo -e "\n\033[33mOther Functions:\033[0m"
    echo "  help()                                             - Show this help message"
    
    echo -e "\n\033[32m=== Usage Examples ===\033[0m"
    echo "  help                                               - Show this help"
    echo "  balance_of \$tokenAddress \$ACCOUNT_ADDRESS         - Check token balance"
    echo "  current_round \$submitAddress                       - Check current round"
    echo "  launch_info \$tokenAddress                         - Get launch info"
    echo "  stake_status \$tokenAddress \$ACCOUNT_ADDRESS       - Check stake status"
    
    echo -e "\n\033[32m=== Variables ===\033[0m"
    echo "  tokenAddress: $tokenAddress"
    echo "  parentTokenAmountForContribute: $parentTokenAmountForContribute"
    echo "  tokenSymbolForDeploy: $tokenSymbolForDeploy"
    echo "  base_dir: $base_dir"
    echo "  network: $network"
}
echo "help() loaded"

# ------ Display help by default ------
echo -e "\n\033[32m=== Script Loaded Successfully ===\033[0m"
echo "Type 'help' to see all available functions"