#actionId=0
mintRound=$(($(call ILOVE20Verify $verifyAddress currentRound) - 1))

echo "===================="
echo " mint_action_reward "
echo "===================="

echo "actionId: $actionId"
echo "mintRound: $mintRound"

echo "balance of token before: $(call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS | show_in_eth)"

echo "actionRewardByAccount before"
result=$(call ILOVE20Mint $mintAddress actionRewardByActionIdByAccount $tokenAddress $mintRound $actionId $ACCOUNT_ADDRESS)
echo "actionReward: $(echo $result | sed -n '1p')"
echo "isMinted: $(echo $result | sed -n '2p')"

echo "mint action reward"
echo "----------------------------------------"
send ILOVE20Mint $mintAddress mintActionReward $tokenAddress $mintRound $actionId
echo "----------------------------------------"


echo "balance of token after: $(call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS | show_in_eth)"

echo "actionRewardByAccount after"
result=$(call ILOVE20Mint $mintAddress actionRewardByActionIdByAccount $tokenAddress $mintRound $actionId $ACCOUNT_ADDRESS)
echo "actionReward: $(echo $result | sed -n '1p')"
echo "isMinted: $(echo $result | sed -n '2p')"