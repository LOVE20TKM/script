#actionId=0
additionalStakeAmount=100
verificationInfos="[\"verification info\"]"
round=$(cast_call $joinAddress "currentRound()(uint256)") 

echo "===================="
echo "        join        "
echo "===================="


echo "round: $round"
echo "actionId: $actionId"
echo "additionalStakeAmount: $additionalStakeAmount"
echo "verificationInfos: $verificationInfos"



echo "check action $actionId is voted"
cast_call $voteAddress "isActionIdVoted(address,uint256,uint256)(bool)" $tokenAddress $round $actionId

echo "joined amount before"
cast_call $joinAddress "amountByActionIdByAccount(address,uint256,address)(uint256)" $tokenAddress $actionId $ACCOUNT_ADDRESS


echo "set allowance"
echo "----------------------------------------"
cast_send $tokenAddress "approve(address,uint256)" $joinAddress $additionalStakeAmount
echo "----------------------------------------"

echo "join action $actionId"
echo "----------------------------------------"
cast_send $joinAddress "join(address,uint256,uint256,string[])" $tokenAddress $actionId $additionalStakeAmount $verificationInfos
echo "----------------------------------------"

echo "joined amount after"
cast_call $joinAddress "amountByActionIdByAccount(address,uint256,address)(uint256)" $tokenAddress $actionId $ACCOUNT_ADDRESS








# ------ read ------
echo "amount by action id"
cast_call $joinAddress "amountByActionId(address,uint256)(uint256)" $tokenAddress $actionId



echo "Get verification information"
cast_call $joinAddress "verificationInfo(address,address,uint256,string)(string)" $tokenAddress $ACCOUNT_ADDRESS $actionId $verificationKey

echo "amount by account"
cast_call $joinAddress "amountByAccount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS 

echo "amount by actionId by account"
cast_call $joinAddress "amountByActionIdByAccount(address,uint256,address)(uint256)" $tokenAddress $actionId $ACCOUNT_ADDRESS

next_phase_waiting_blocks $joinAddress

# Generate and store random accounts
#cast_send $joinAddress "generateAndStoreRandomAccounts(address,uint256,uint256,uint256,uint256)" $tokenAddress $round $actionId $randomSeed $num
