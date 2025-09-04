#actionId=0  
abstentionScore=10
scores="[30]"

echo "===================="
echo "        verify      "
echo "===================="


# caculated vars
round=$(current_round $verifyAddress)
num=$(action_info_by_field $actionId "maxRandomAccounts")


echo "round: $round"
echo "actionId: $actionId"
echo "abstentionScore: $abstentionScore"
echo "scores: $scores"
echo "num: $num"

randomSeed=$(cast_call $randomAddress "randomSeed(uint256)(uint256)" $round | awk '{print $1}')
echo "randomSeed: $randomSeed"

echo "Get random accounts"
cast_call $joinAddress "randomAccounts(address,uint256,uint256)(address[])" $tokenAddress $round $actionId

echo "score before"
cast_call $verifyAddress "score(address,uint256)(uint256)" $tokenAddress $round

echo "scoreWithReward before"
cast_call $verifyAddress "scoreWithReward(address,uint256)(uint256)" $tokenAddress $round

echo "verify"
echo "----------------------------------------"
cast_send $verifyAddress "verify(address,uint256,uint256,uint256[])" $tokenAddress $actionId $abstentionScore "$scores"
echo "----------------------------------------"

echo "score after"
cast_call $verifyAddress "score(address,uint256)(uint256)" $tokenAddress $round

echo "scoreWithReward after"
cast_call $verifyAddress "scoreWithReward(address,uint256)(uint256)" $tokenAddress $round


next_phase_waiting_blocks $verifyAddress