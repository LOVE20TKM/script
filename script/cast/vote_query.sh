#!/bin/bash

echo "===================="
echo "     vote_query      "
echo "===================="

# ------ Read Functions ------

echo "Stake address:"
cast_call $voteAddress "stakeAddress()(address)"

echo "Submit address:"
cast_call $voteAddress "submitAddress()(address)"

echo "Votes num for tokenAddress:"
cast_call $voteAddress "votesNum(address,uint256)(uint256)" $tokenAddress $round 

echo "Votes num by action id for tokenAddress:"
cast_call $voteAddress "votesNumByActionId(address,uint256,uint256)(uint256)" $tokenAddress $round $actionId 

echo "Votes num by account for tokenAddress:"
cast_call $voteAddress "votesNumByAccount(address,uint256,address)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS

echo "Votes num by account by action id for tokenAddress:"
cast_call $voteAddress "votesNumByAccountByActionId(address,uint256,address,uint256)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS $actionId

echo "Can vote for tokenAddress:"
cast_call $voteAddress "canVote(address,address)(bool)" $tokenAddress $ACCOUNT_ADDRESS

echo "Max votes num for tokenAddress:"
cast_call $voteAddress "maxVotesNum(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Is action id voted for tokenAddress:"
cast_call $voteAddress "isActionIdVoted(address,uint256,uint256)(bool)" $tokenAddress $round $actionId

echo "Voted action ids count for tokenAddress:"
cast_call $voteAddress "votedActionIdsCount(address,uint256)(uint256)" $tokenAddress $round

echo "Voted action ids at index 0 for tokenAddress:"
cast_call $voteAddress "votedActionIdsAtIndex(address,uint256,uint256)(uint256)" $tokenAddress $round 0

echo "Account voted action ids count for tokenAddress:"
cast_call $voteAddress "accountVotedActionIdsCount(address,uint256,address)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS

echo "Account voted action ids at index 0 for tokenAddress:"
cast_call $voteAddress "accountVotedActionIdsAtIndex(address,uint256,address,uint256)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS 0

echo "Votes nums by account for tokenAddress:"
cast_call $voteAddress "votesNumsByAccount(address,uint256,address)(uint256[],uint256[])" $tokenAddress $round $ACCOUNT_ADDRESS

echo "Votes nums by account by action ids for tokenAddress:"
cast_call $voteAddress "votesNumsByAccountByActionIds(address,uint256,address,uint256[])(uint256[])" $tokenAddress $round $ACCOUNT_ADDRESS "[0,2]"

echo "===================="
echo "Vote Query Complete"
echo "====================" 