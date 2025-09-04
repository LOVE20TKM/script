amountForBurn=9999999999999999999998585

echo "===================="
echo " burnForParentToken "
echo "===================="

echo "amountForBurn: $amountForBurn"

echo "totalSupply before"
cast_call $tokenAddress "totalSupply()(uint256)"

echo "balance of tokenAddress before"
cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "balance of parentTokenAddress before"
cast_call $parentTokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "parent pool before"
cast_call $tokenAddress "parentPool()(uint256)"

echo "burn for parent token"
echo "----------------------------------------"
cast_send $tokenAddress "burnForParentToken(uint256)(uint256)" $amountForBurn
echo "----------------------------------------"

echo "totalSupply after"
cast_call $tokenAddress "totalSupply()(uint256)"

echo "balance of tokenAddress after"
cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "balance of parentTokenAddress after"
cast_call $parentTokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "parent pool after"
cast_call $tokenAddress "parentPool()(uint256)"


