amountForBurn=9999999999999999999998585

echo "===================="
echo " burnForParentToken "
echo "===================="

echo "amountForBurn: $amountForBurn"

echo "totalSupply before"
call ILOVE20Token $tokenAddress totalSupply

echo "balance of tokenAddress before"
call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS

echo "balance of parentTokenAddress before"
call ILOVE20Token $parentTokenAddress balanceOf $ACCOUNT_ADDRESS

echo "parent pool before"
call ILOVE20Token $tokenAddress parentPool

echo "burn for parent token"
echo "----------------------------------------"
send ILOVE20Token $tokenAddress burnForParentToken $amountForBurn
echo "----------------------------------------"

echo "totalSupply after"
call ILOVE20Token $tokenAddress totalSupply

echo "balance of tokenAddress after"
call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS

echo "balance of parentTokenAddress after"
call ILOVE20Token $parentTokenAddress balanceOf $ACCOUNT_ADDRESS

echo "parent pool after"
call ILOVE20Token $tokenAddress parentPool


