voteAmount=100

#actionId=0
round=$(cast_call $voteAddress "currentRound()(uint256)" $tokenAddress)

echo "===================="
echo "        vote        "
echo "===================="


echo "actionId: $actionId"
echo "voteAmount: $voteAmount"

echo "votesNum before"
cast_call $voteAddress "votesNum(address,uint256)(uint256)" $tokenAddress $round

echo "votesNumByActionId before"
cast_call $voteAddress "votesNumByActionId(address,uint256,uint256)(uint256)" $tokenAddress $round $actionId

echo "votesNumByAccountByActionId before"
cast_call $voteAddress "votesNumByAccountByActionId(address,uint256,address,uint256)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS $actionId


echo "vote action"
echo "----------------------------------------"
cast_send $voteAddress "vote(address,uint256[],uint256[])" $tokenAddress "[$actionId]" "[$voteAmount]"
echo "----------------------------------------"

echo "votesNum after"
cast_call $voteAddress "votesNum(address,uint256)(uint256)" $tokenAddress $round

echo "votesNumByActionId after"
cast_call $voteAddress "votesNumByActionId(address,uint256,uint256)(uint256)" $tokenAddress $round $actionId

echo "votesNumByAccountByActionId after"
cast_call $voteAddress "votesNumByAccountByActionId(address,uint256,address,uint256)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS $actionId

next_phase_waiting_blocks $voteAddress