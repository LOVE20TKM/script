echo "===================="
echo "    launch_claim    "
echo "===================="

# Get the claim result using cast call (simulation)
echo "--- Claim Status Before ---"
result=$(cast_call $launchAddress "claimInfo(address,address)(uint256,uint256,bool)" $tokenAddress $ACCOUNT_ADDRESS)
claimableAmount=$(echo "$result" | sed -n '1p' | awk '{print $1}')
extraRefundAmount=$(echo "$result" | sed -n '2p')
claimed=$(echo "$result" | sed -n '3p')
echo "claimable amount in wei: $claimableAmount"
echo "claimable amount in eth: $(echo $claimableAmount | show_in_eth)"
echo "extra refund amount in wei: $extraRefundAmount"
echo "extra refund amount in eth: $(echo $extraRefundAmount | show_in_eth)"
echo "is claimed: $claimed"



echo "--- Balance Status Before ---"
balance=$(balance_of_wei $tokenAddress $ACCOUNT_ADDRESS)
echo "balance in wei: $balance"
echo "balance in eth: $(echo $balance | show_in_eth)"
parentBalance=$(balance_of_wei $parentTokenAddress $ACCOUNT_ADDRESS)
echo "parent balance in wei: $parentBalance"
echo "parent balance in eth: $(echo $parentBalance | show_in_eth)"

# ------------------- Claim -------------------
echo "claim"
echo "----------------------------------------"
cast_send $launchAddress "claim(address)" $tokenAddress
echo "----------------------------------------"
# ------------------- Claim -------------------

echo "--- Claim Status After ---"
result=$(cast_call $launchAddress "claimInfo(address,address)(uint256,uint256,bool)" $tokenAddress $ACCOUNT_ADDRESS)
claimableAmount=$(echo "$result" | sed -n '1p' | awk '{print $1}')
extraRefundAmount=$(echo "$result" | sed -n '2p')
claimed=$(echo "$result" | sed -n '3p')
echo "claimable amount in wei: $claimableAmount"
echo "claimable amount in eth: $(echo $claimableAmount | show_in_eth)"
echo "extra refund amount in wei: $extraRefundAmount"
echo "extra refund amount in eth: $(echo $extraRefundAmount | show_in_eth)"
echo "is claimed: $claimed"

echo "--- Balance Status After ---"
balance=$(balance_of_wei $tokenAddress $ACCOUNT_ADDRESS)
echo "balance in wei: $balance"
echo "balance in eth: $(echo $balance | show_in_eth)"
parentBalance=$(balance_of_wei $parentTokenAddress $ACCOUNT_ADDRESS)
echo "parent balance in wei: $parentBalance"
echo "parent balance in eth: $(echo $parentBalance | show_in_eth)"