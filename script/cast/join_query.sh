#!/bin/bash

echo "===================="
echo "     join_query      "
echo "===================="

# ------ Read Functions ------

echo "Submit address:"
call ILOVE20Join $joinAddress submitAddress

echo "Vote address:"
call ILOVE20Join $joinAddress voteAddress

echo "Random address:"
call ILOVE20Join $joinAddress randomAddress

echo "Join end phase blocks:"
call ILOVE20Join $joinAddress JOIN_END_PHASE_BLOCKS

echo "Verification info for tokenAddress:"
call ILOVE20Join $joinAddress verificationInfo $tokenAddress $ACCOUNT_ADDRESS $actionId "default"

echo "Verification info by round for tokenAddress:"
call ILOVE20Join $joinAddress verificationInfoByRound $tokenAddress $ACCOUNT_ADDRESS $actionId "default" $round

echo "Verification info update rounds count for tokenAddress:"
call ILOVE20Join $joinAddress verificationInfoUpdateRoundsCount $tokenAddress $ACCOUNT_ADDRESS $actionId "default"

echo "Verification info update rounds at index 0 for tokenAddress:"
call ILOVE20Join $joinAddress verificationInfoUpdateRoundsAtIndex $tokenAddress $ACCOUNT_ADDRESS $actionId "default" 0

echo "Random accounts for tokenAddress:"
call ILOVE20Join $joinAddress randomAccounts $tokenAddress $round $actionId

echo "Random accounts by random seed for tokenAddress:"
call ILOVE20Join $joinAddress randomAccountsByRandomSeed $tokenAddress $actionId 12345 5

echo "Random accounts by action id count for tokenAddress:"
call ILOVE20Join $joinAddress randomAccountsByActionIdCount $tokenAddress $round $actionId

echo "Random accounts by action id at index 0 for tokenAddress:"
call ILOVE20Join $joinAddress randomAccountsByActionIdAtIndex $tokenAddress $round $actionId 0

echo "Amount by action id for tokenAddress:"
call ILOVE20Join $joinAddress amountByActionId $tokenAddress $actionId

echo "Amount by action id by account for tokenAddress:"
call ILOVE20Join $joinAddress amountByActionIdByAccount $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "Amount by account for tokenAddress:"
call ILOVE20Join $joinAddress amountByAccount $tokenAddress $ACCOUNT_ADDRESS

echo "Action ids by account for tokenAddress:"
call ILOVE20Join $joinAddress actionIdsByAccount $tokenAddress $ACCOUNT_ADDRESS

echo "Action ids by account count for tokenAddress:"
call ILOVE20Join $joinAddress actionIdsByAccountCount $tokenAddress $ACCOUNT_ADDRESS

echo "Action ids by account at index 0 for tokenAddress:"
call ILOVE20Join $joinAddress actionIdsByAccountAtIndex $tokenAddress $ACCOUNT_ADDRESS 0

echo "Num of accounts for tokenAddress:"
call ILOVE20Join $joinAddress numOfAccounts $tokenAddress $actionId

echo "Index to account for tokenAddress:"
call ILOVE20Join $joinAddress indexToAccount $tokenAddress $actionId 1

echo "Account to index for tokenAddress:"
call ILOVE20Join $joinAddress accountToIndex $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "Prefix sum for tokenAddress:"
call ILOVE20Join $joinAddress prefixSum $tokenAddress $actionId 1

echo "===================="
echo "Join Query Complete"
echo "====================" 
