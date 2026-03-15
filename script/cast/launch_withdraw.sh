echo "===================="
echo "  launch_withdraw   "
echo "===================="

echo "parent token balance before: $(balance_of $parentTokenAddress $ACCOUNT_ADDRESS)"

echo "withdraw"
echo "----------------------------------------"
send ILOVE20Launch $launchAddress withdraw $tokenAddress
echo "----------------------------------------"

echo "parent token balance after:"
balance_of $parentTokenAddress $ACCOUNT_ADDRESS
