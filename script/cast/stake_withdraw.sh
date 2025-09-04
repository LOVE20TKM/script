echo "===================="
echo "    stake_withdraw  "
echo "===================="

echo "balance of tokenAddress before"
cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "balance of parentTokenAddress before"
cast_call $parentTokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "withdraw"
echo "----------------------------------------"
cast_send $stakeAddress "withdraw(address)" $tokenAddress
echo "----------------------------------------"

echo "balance of tokenAddress after"
cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "balance of parentTokenAddress after"
cast_call $parentTokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS