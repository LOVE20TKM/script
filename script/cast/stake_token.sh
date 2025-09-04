tokenAmountForStake=200
# promisedWaitingPhases=PROMISED_WAITING_PHASES_MIN

echo "===================="
echo "     stake_token    "
echo "===================="

echo "tokenAmountForStake: $tokenAmountForStake"
echo "promisedWaitingPhases: $promisedWaitingPhases"

echo "stake status before"
stake_status $tokenAddress $ACCOUNT_ADDRESS

echo "set allowance to stake contract"
echo "----------------------------------------"
cast_send $tokenAddress "approve(address,uint256)" $stakeAddress $tokenAmountForStake
echo "----------------------------------------"

echo "check allowance"
cast_call $tokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $stakeAddress 

echo "stake token"
echo "----------------------------------------"
cast_send $stakeAddress "stakeToken(address,uint256,uint256,address)" $tokenAddress $tokenAmountForStake $promisedWaitingPhases $ACCOUNT_ADDRESS
echo "----------------------------------------"

echo "get stAddress"
stAddress=$(cast_call $tokenAddress "stAddress()(address)")
echo $stAddress

echo "check stAddress balance"
cast_call $stAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "stake status after"
stake_status $tokenAddress $ACCOUNT_ADDRESS