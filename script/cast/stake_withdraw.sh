echo "===================="
echo "    stake_withdraw  "
echo "===================="

echo "balance of tokenAddress before"
call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS

echo "balance of parentTokenAddress before"
call ILOVE20Token $parentTokenAddress balanceOf $ACCOUNT_ADDRESS

echo "withdraw"
echo "----------------------------------------"
send ILOVE20Stake $stakeAddress withdraw $tokenAddress
echo "----------------------------------------"

echo "balance of tokenAddress after"
call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS

echo "balance of parentTokenAddress after"
call ILOVE20Token $parentTokenAddress balanceOf $ACCOUNT_ADDRESS