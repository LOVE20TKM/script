#actionId=0
additionalStakeAmount=100
verificationInfos="[\"verification info\"]"
round=$(call ILOVE20Join $joinAddress currentRound) 

echo "===================="
echo "        join        "
echo "===================="


echo "round: $round"
echo "actionId: $actionId"
echo "additionalStakeAmount: $additionalStakeAmount"
echo "verificationInfos: $verificationInfos"



echo "check action $actionId is voted"
call ILOVE20Vote $voteAddress isActionIdVoted $tokenAddress $round $actionId

echo "joined amount before"
call ILOVE20Join $joinAddress amountByActionIdByAccount $tokenAddress $actionId $ACCOUNT_ADDRESS


echo "set allowance"
echo "----------------------------------------"
send ILOVE20Token $tokenAddress approve $joinAddress $additionalStakeAmount
echo "----------------------------------------"

echo "join action $actionId"
echo "----------------------------------------"
send ILOVE20Join $joinAddress join $tokenAddress $actionId $additionalStakeAmount $verificationInfos
echo "----------------------------------------"

echo "joined amount after"
call ILOVE20Join $joinAddress amountByActionIdByAccount $tokenAddress $actionId $ACCOUNT_ADDRESS








# ------ read ------
echo "amount by action id"
call ILOVE20Join $joinAddress amountByActionId $tokenAddress $actionId



echo "Get verification information"
call ILOVE20Join $joinAddress verificationInfo $tokenAddress $ACCOUNT_ADDRESS $actionId $verificationKey

echo "amount by account"
call ILOVE20Join $joinAddress amountByAccount $tokenAddress $ACCOUNT_ADDRESS 

echo "amount by actionId by account"
call ILOVE20Join $joinAddress amountByActionIdByAccount $tokenAddress $actionId $ACCOUNT_ADDRESS

next_phase_waiting_blocks $joinAddress

# Generate and store random accounts
#send ILOVE20Join $joinAddress generateAndStoreRandomAccounts $tokenAddress $round $actionId $randomSeed $num
