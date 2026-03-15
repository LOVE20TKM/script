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

randomSeed=$(call ILOVE20Random $randomAddress randomSeed $round | awk '{print $1}')
echo "randomSeed: $randomSeed"

echo "Get random accounts"
call ILOVE20Join $joinAddress randomAccounts $tokenAddress $round $actionId

echo "score before"
call ILOVE20Verify $verifyAddress score $tokenAddress $round

echo "scoreWithReward before"
call ILOVE20Verify $verifyAddress scoreWithReward $tokenAddress $round

echo "verify"
echo "----------------------------------------"
send ILOVE20Verify $verifyAddress verify $tokenAddress $actionId $abstentionScore "$scores"
echo "----------------------------------------"

echo "score after"
call ILOVE20Verify $verifyAddress score $tokenAddress $round

echo "scoreWithReward after"
call ILOVE20Verify $verifyAddress scoreWithReward $tokenAddress $round


next_phase_waiting_blocks $verifyAddress