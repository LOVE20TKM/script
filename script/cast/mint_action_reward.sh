#actionId=0
mintRound=$(($(cast_call $verifyAddress "currentRound()(uint256)") - 1))

echo "===================="
echo " mint_action_reward "
echo "===================="

echo "actionId: $actionId"
echo "mintRound: $mintRound"

echo "balance of token before: $(cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS | show_in_eth)"

echo "actionRewardByAccount before"
result=$(cast_call $mintAddress "actionRewardByActionIdByAccount(address,uint256,uint256,address)(uint256,bool)" $tokenAddress $mintRound $actionId $ACCOUNT_ADDRESS)
echo "actionReward: $(echo $result | sed -n '1p')"
echo "isMinted: $(echo $result | sed -n '2p')"

echo "mint action reward"
echo "----------------------------------------"
cast_send $mintAddress "mintActionReward(address,uint256,uint256)(uint256)" $tokenAddress $mintRound $actionId
echo "----------------------------------------"


echo "balance of token after: $(cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS | show_in_eth)"

echo "actionRewardByAccount after"
result=$(cast_call $mintAddress "actionRewardByActionIdByAccount(address,uint256,uint256,address)(uint256,bool)" $tokenAddress $mintRound $actionId $ACCOUNT_ADDRESS)
echo "actionReward: $(echo $result | sed -n '1p')"
echo "isMinted: $(echo $result | sed -n '2p')"