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
send ILOVE20Token $tokenAddress approve $stakeAddress $tokenAmountForStake
echo "----------------------------------------"

echo "check allowance"
call ILOVE20Token $tokenAddress allowance $ACCOUNT_ADDRESS $stakeAddress 

echo "stake token"
echo "----------------------------------------"
send ILOVE20Stake $stakeAddress stakeToken $tokenAddress $tokenAmountForStake $promisedWaitingPhases $ACCOUNT_ADDRESS
echo "----------------------------------------"

echo "get stAddress"
stAddress=$(call ILOVE20Token $tokenAddress stAddress)
echo $stAddress

echo "check stAddress balance"
call ILOVE20STToken $stAddress balanceOf $ACCOUNT_ADDRESS

echo "stake status after"
stake_status $tokenAddress $ACCOUNT_ADDRESS