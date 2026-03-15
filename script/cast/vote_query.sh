#!/bin/bash

echo "===================="
echo "     vote_query      "
echo "===================="

# ------ Read Functions ------

echo "Stake address:"
call ILOVE20Vote $voteAddress stakeAddress

echo "Submit address:"
call ILOVE20Vote $voteAddress submitAddress

echo "Votes num for tokenAddress:"
call ILOVE20Vote $voteAddress votesNum $tokenAddress $round 

echo "Votes num by action id for tokenAddress:"
call ILOVE20Vote $voteAddress votesNumByActionId $tokenAddress $round $actionId 

echo "Votes num by account for tokenAddress:"
call ILOVE20Vote $voteAddress votesNumByAccount $tokenAddress $round $ACCOUNT_ADDRESS

echo "Votes num by account by action id for tokenAddress:"
call ILOVE20Vote $voteAddress votesNumByAccountByActionId $tokenAddress $round $ACCOUNT_ADDRESS $actionId

echo "Can vote for tokenAddress:"
call ILOVE20Vote $voteAddress canVote $tokenAddress $ACCOUNT_ADDRESS

echo "Max votes num for tokenAddress:"
call ILOVE20Vote $voteAddress maxVotesNum $tokenAddress $ACCOUNT_ADDRESS

echo "Is action id voted for tokenAddress:"
call ILOVE20Vote $voteAddress isActionIdVoted $tokenAddress $round $actionId

echo "Voted action ids count for tokenAddress:"
call ILOVE20Vote $voteAddress votedActionIdsCount $tokenAddress $round

echo "Voted action ids at index 0 for tokenAddress:"
call ILOVE20Vote $voteAddress votedActionIdsAtIndex $tokenAddress $round 0

echo "Account voted action ids count for tokenAddress:"
call ILOVE20Vote $voteAddress accountVotedActionIdsCount $tokenAddress $round $ACCOUNT_ADDRESS

echo "Account voted action ids at index 0 for tokenAddress:"
call ILOVE20Vote $voteAddress accountVotedActionIdsAtIndex $tokenAddress $round $ACCOUNT_ADDRESS 0

echo "Votes nums by account for tokenAddress:"
call ILOVE20Vote $voteAddress votesNumsByAccount $tokenAddress $round $ACCOUNT_ADDRESS

echo "Votes nums by account by action ids for tokenAddress:"
call ILOVE20Vote $voteAddress votesNumsByAccountByActionIds $tokenAddress $round $ACCOUNT_ADDRESS "[0,2]"

echo "===================="
echo "Vote Query Complete"
echo "====================" 