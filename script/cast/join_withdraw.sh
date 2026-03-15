echo "===================="
echo "     join_withdraw  "
echo "===================="

echo "actionId: $actionId"


current_round $joinAddress

echo "amountByActionIdByAccount before"
call ILOVE20Join $joinAddress amountByActionIdByAccount $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "balance of account before"
call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS

# Withdraw stake
echo "Withdraw staked amount"
echo "----------------------------------------"
send ILOVE20Join $joinAddress withdraw $tokenAddress $actionId
echo "----------------------------------------"


echo "amountByActionIdByAccount after"
call ILOVE20Join $joinAddress amountByActionIdByAccount $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "balance of account after"
call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS


