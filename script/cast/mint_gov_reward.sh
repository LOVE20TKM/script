#round=496

mintRound=$(($(call ILOVE20Verify $verifyAddress currentRound) - 1))

echo "===================="
echo " mint_gov_reward "
echo "===================="


echo "mintRound: $mintRound"

echo "balance of token before: $(call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS | show_in_eth)"

echo "govRewardByAccount before"
result=$(call ILOVE20Mint $mintAddress govRewardByAccount $tokenAddress $mintRound $ACCOUNT_ADDRESS)
echo "verifyReward: $(echo $result | sed -n '1p')"
echo "boostReward: $(echo $result | sed -n '2p')"
echo "burnReward: $(echo $result | sed -n '3p')"
echo "isMinted: $(echo $result | sed -n '4p')"

echo "mint gov reward"
echo "----------------------------------------"
send ILOVE20Mint $mintAddress mintGovReward $tokenAddress $mintRound
echo "----------------------------------------"

echo "govRewardMinted after"
call ILOVE20Mint $mintAddress govRewardMintedByAccount $tokenAddress $mintRound $ACCOUNT_ADDRESS | show_in_eth


echo "govRewardByAccount after"
result=$(call ILOVE20Mint $mintAddress govRewardByAccount $tokenAddress $mintRound $ACCOUNT_ADDRESS)
echo "verifyReward: $(echo $result | sed -n '1p')"
echo "boostReward: $(echo $result | sed -n '2p')"
echo "burnReward: $(echo $result | sed -n '3p')"
echo "isMinted: $(echo $result | sed -n '4p')"

echo "balance of token after: $(call ILOVE20Token $tokenAddress balanceOf $ACCOUNT_ADDRESS | show_in_eth)"

