# parentTokenAmountForContribute=$((FIRST_PARENT_TOKEN_FUNDRAISING_GOAL/2))  

echo "===================="
echo " launch_contribute  "
echo "===================="

# ------------------- params -------------------
echo "parent token amount for contribute"
echo "in eth: " $(echo $parentTokenAmountForContribute | show_in_eth)
echo "in wei: " $parentTokenAmountForContribute


# ------------------- contribute -------------------

echo "contributed amount before"
contributedAmount=$(call ILOVE20Launch $launchAddress contributed $tokenAddress $ACCOUNT_ADDRESS | awk '{print $1}')
echo "in wei: $contributedAmount"
echo "in eth: $(echo $contributedAmount | show_in_eth)"


echo "Approve parent token to launch contract"
echo "----------------------------------------"
send ILOVE20Token $parentTokenAddress approve $launchAddress $parentTokenAmountForContribute
echo "----------------------------------------"

echo "Contribute to launch"
echo "----------------------------------------"
send ILOVE20Launch $launchAddress contribute $tokenAddress $parentTokenAmountForContribute $ACCOUNT_ADDRESS
echo "----------------------------------------"

echo "contributed amount after"
contributedAmount=$(call ILOVE20Launch $launchAddress contributed $tokenAddress $ACCOUNT_ADDRESS | awk '{print $1}')
echo "in wei: $contributedAmount"
echo "in eth: $(echo $contributedAmount | show_in_eth)"


launch_info $tokenAddress

echo "SECOND_HALF_MIN_BLOCKS: $SECOND_HALF_MIN_BLOCKS"


echo "Get participated token num by account"
call ILOVE20Launch $launchAddress participatedTokensCount $ACCOUNT_ADDRESS | awk '{print $1}'

echo "block number: $(cast_block number)"

next_phase_waiting_blocks $stakeAddress