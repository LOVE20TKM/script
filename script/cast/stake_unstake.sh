echo "===================="
echo "    stake_unstake   "
echo "===================="

echo "stake status before"
stake_status $tokenAddress $ACCOUNT_ADDRESS

echo "get slAddress"
slAddress=$(call ILOVE20Token $tokenAddress slAddress)
echo $slAddress

echo "get sl token balance"
slBalance=$(call ILOVE20SLToken $slAddress balanceOf $ACCOUNT_ADDRESS | awk '{print $1}')
echo $slBalance

echo "approve sl token"
echo "----------------------------------------"
send ILOVE20SLToken $slAddress approve $stakeAddress $slBalance
echo "----------------------------------------"

echo "get stAddress"
stAddress=$(call ILOVE20Token $tokenAddress stAddress)
echo $stAddress

echo "get st token balance"
stBalance=$(call ILOVE20STToken $stAddress balanceOf $ACCOUNT_ADDRESS | awk '{print $1}')
echo $stBalance


echo "approve st token"
echo "----------------------------------------"
send ILOVE20STToken $stAddress approve $stakeAddress $stBalance
echo "----------------------------------------"

echo "unstake"
echo "----------------------------------------"
send ILOVE20Stake $stakeAddress unstake $tokenAddress 
echo "----------------------------------------"


slBalance=$(call ILOVE20SLToken $slAddress balanceOf $ACCOUNT_ADDRESS)
echo $slBalance

stBalance=$(call ILOVE20STToken $stAddress balanceOf $ACCOUNT_ADDRESS)
echo $stBalance

echo "stake status after"
stake_status $tokenAddress $ACCOUNT_ADDRESS
