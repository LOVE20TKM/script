#round=496

mintRound=$(($(cast_call $verifyAddress "currentRound()(uint256)") - 1))

echo "===================="
echo " mint_gov_reward "
echo "===================="


echo "mintRound: $mintRound"

echo "balance of token before: $(cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS | show_in_eth)"

echo "govRewardByAccount before"
result=$(cast_call $mintAddress "govRewardByAccount(address,uint256,address)(uint256,uint256,uint256,bool)" $tokenAddress $mintRound $ACCOUNT_ADDRESS)
echo "verifyReward: $(echo $result | sed -n '1p')"
echo "boostReward: $(echo $result | sed -n '2p')"
echo "burnReward: $(echo $result | sed -n '3p')"
echo "isMinted: $(echo $result | sed -n '4p')"

echo "mint gov reward"
echo "----------------------------------------"
cast_send $mintAddress "mintGovReward(address,uint256)(uint256,uint256,uint256)" $tokenAddress $mintRound
echo "----------------------------------------"

echo "govRewardMinted after"
cast_call $mintAddress "govRewardMintedByAccount(address,uint256,address)(uint256)" $tokenAddress $mintRound $ACCOUNT_ADDRESS | show_in_eth


echo "govRewardByAccount after"
result=$(cast_call $mintAddress "govRewardByAccount(address,uint256,address)(uint256,uint256,uint256,bool)" $tokenAddress $mintRound $ACCOUNT_ADDRESS)
echo "verifyReward: $(echo $result | sed -n '1p')"
echo "boostReward: $(echo $result | sed -n '2p')"
echo "burnReward: $(echo $result | sed -n '3p')"
echo "isMinted: $(echo $result | sed -n '4p')"

echo "balance of token after: $(cast_call $tokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS | show_in_eth)"

