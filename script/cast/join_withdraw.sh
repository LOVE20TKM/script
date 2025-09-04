echo "===================="
echo "     join_withdraw  "
echo "===================="

echo "actionId: $actionId"


current_round $joinAddress

echo "amountByActionIdByAccount before"
cast_call $joinAddress "amountByActionIdByAccount(address,uint256,address)(uint256)" $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "balance of account before"
cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

# Withdraw stake
echo "Withdraw staked amount"
echo "----------------------------------------"
cast_send $joinAddress "withdraw(address,uint256)" $tokenAddress $actionId
echo "----------------------------------------"


echo "amountByActionIdByAccount after"
cast_call $joinAddress "amountByActionIdByAccount(address,uint256,address)(uint256)" $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "balance of account after"
cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS


