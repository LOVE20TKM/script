echo "===================="
echo "  launch_withdraw   "
echo "===================="

echo "parent token balance before: $(balance_of $parentTokenAddress $ACCOUNT_ADDRESS)"

echo "withdraw"
echo "----------------------------------------"
cast_send $launchAddress "withdraw(address)($uint256)" $tokenAddress
echo "----------------------------------------"

echo "parent token balance after:"
balance_of $parentTokenAddress $ACCOUNT_ADDRESS
