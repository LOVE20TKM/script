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
call ILOVE20Token $tokenAddress allowance $ACCOUNT_ADDRESS $stakeAddress

echo "parent token allowance before"
call ILOVE20Token $parentTokenAddress allowance $ACCOUNT_ADDRESS $stakeAddress


echo "set token allowance"
echo "----------------------------------------"
send ILOVE20Token $tokenAddress approve $stakeAddress $tokenAmountForLP
echo "----------------------------------------"

echo "set parent token allowance"
echo "----------------------------------------"
send ILOVE20Token $parentTokenAddress approve $stakeAddress $parentTokenAmountForLP
echo "----------------------------------------"

echo "stake liquidity"
echo $tokenAddress $tokenAmountForLP $parentTokenAmountForLP $promisedWaitingPhases $ACCOUNT_ADDRESS
echo "----------------------------------------"
send ILOVE20Stake $stakeAddress stakeLiquidity $tokenAddress $tokenAmountForLP $parentTokenAmountForLP $promisedWaitingPhases $ACCOUNT_ADDRESS
echo "----------------------------------------"

echo "get slAddress"
slAddress=$(call ILOVE20Token $tokenAddress slAddress)
echo "slAddress: $slAddress"

echo "get sl token balance"
call ILOVE20SLToken $slAddress balanceOf $ACCOUNT_ADDRESS

echo "stake status after"
stake_status $tokenAddress $ACCOUNT_ADDRESS
