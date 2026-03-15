voteAmount=100

#actionId=0
round=$(call ILOVE20Vote $voteAddress currentRound $tokenAddress)

echo "===================="
echo "        vote        "
echo "===================="


echo "actionId: $actionId"
echo "voteAmount: $voteAmount"

echo "votesNum before"
call ILOVE20Vote $voteAddress votesNum $tokenAddress $round

echo "votesNumByActionId before"
call ILOVE20Vote $voteAddress votesNumByActionId $tokenAddress $round $actionId

echo "votesNumByAccountByActionId before"
call ILOVE20Vote $voteAddress votesNumByAccountByActionId $tokenAddress $round $ACCOUNT_ADDRESS $actionId


echo "vote action"
echo "----------------------------------------"
send ILOVE20Vote $voteAddress vote $tokenAddress "[$actionId]" "[$voteAmount]"
echo "----------------------------------------"

echo "votesNum after"
call ILOVE20Vote $voteAddress votesNum $tokenAddress $round

echo "votesNumByActionId after"
call ILOVE20Vote $voteAddress votesNumByActionId $tokenAddress $round $actionId

echo "votesNumByAccountByActionId after"
call ILOVE20Vote $voteAddress votesNumByAccountByActionId $tokenAddress $round $ACCOUNT_ADDRESS $actionId

next_phase_waiting_blocks $voteAddress