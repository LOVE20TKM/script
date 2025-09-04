# tokenAmountForLP=100000
# parentTokenAmountForLP=50000
# promisedWaitingPhases=PROMISED_WAITING_PHASES_MIN

echo "===================="
echo "  stake_liquidity   "
echo "===================="

echo "tokenAmountForLP: $tokenAmountForLP"
echo "parentTokenAmountForLP: $parentTokenAmountForLP"
echo "promisedWaitingPhases: $promisedWaitingPhases"

echo "stake status before"
stake_status $tokenAddress $ACCOUNT_ADDRESS

echo "token allowance before"
cast_call $tokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $stakeAddress

echo "parent token allowance before"
cast_call $parentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $stakeAddress


echo "set token allowance"
echo "----------------------------------------"
cast_send $tokenAddress "approve(address,uint256)" $stakeAddress $tokenAmountForLP
echo "----------------------------------------"

echo "set parent token allowance"
echo "----------------------------------------"
cast_send $parentTokenAddress "approve(address,uint256)" $stakeAddress $parentTokenAmountForLP
echo "----------------------------------------"

echo "stake liquidity"
echo $tokenAddress $tokenAmountForLP $parentTokenAmountForLP $promisedWaitingPhases $ACCOUNT_ADDRESS
echo "----------------------------------------"
cast_send $stakeAddress "stakeLiquidity(address,uint256,uint256,uint256,address)(uint256,uint256)" $tokenAddress $tokenAmountForLP $parentTokenAmountForLP $promisedWaitingPhases $ACCOUNT_ADDRESS
echo "----------------------------------------"

echo "get slAddress"
slAddress=$(cast_call $tokenAddress "slAddress()(address)")
echo "slAddress: $slAddress"

echo "get sl token balance"
cast_call $slAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "stake status after"
stake_status $tokenAddress $ACCOUNT_ADDRESS
