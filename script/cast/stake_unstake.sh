echo "===================="
echo "    stake_unstake   "
echo "===================="

echo "stake status before"
stake_status $tokenAddress $ACCOUNT_ADDRESS

echo "get slAddress"
slAddress=$(cast_call $tokenAddress "slAddress()(address)")
echo $slAddress

echo "get sl token balance"
slBalance=$(cast_call $slAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS | awk '{print $1}')
echo $slBalance

echo "approve sl token"
echo "----------------------------------------"
cast_send $slAddress "approve(address,uint256)" $stakeAddress $slBalance
echo "----------------------------------------"

echo "get stAddress"
stAddress=$(cast_call $tokenAddress "stAddress()(address)")
echo $stAddress

echo "get st token balance"
stBalance=$(cast_call $stAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS | awk '{print $1}')
echo $stBalance


echo "approve st token"
echo "----------------------------------------"
cast_send $stAddress "approve(address,uint256)" $stakeAddress $stBalance
echo "----------------------------------------"

echo "unstake"
echo "----------------------------------------"
cast_send $stakeAddress "unstake(address)" $tokenAddress 
echo "----------------------------------------"


slBalance=$(cast_call $slAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS)
echo $slBalance

stBalance=$(cast_call $stAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS)
echo $stBalance

echo "stake status after"
stake_status $tokenAddress $ACCOUNT_ADDRESS
