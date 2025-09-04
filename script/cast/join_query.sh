#!/bin/bash

echo "===================="
echo "     join_query      "
echo "===================="

# ------ Read Functions ------

echo "Submit address:"
cast_call $joinAddress "submitAddress()(address)"

echo "Vote address:"
cast_call $joinAddress "voteAddress()(address)"

echo "Random address:"
cast_call $joinAddress "randomAddress()(address)"

echo "Join end phase blocks:"
cast_call $joinAddress "JOIN_END_PHASE_BLOCKS()(uint256)"

echo "Verification info for tokenAddress:"
cast_call $joinAddress "verificationInfo(address,address,uint256,string)(string)" $tokenAddress $ACCOUNT_ADDRESS $actionId "default"

echo "Verification info by round for tokenAddress:"
cast_call $joinAddress "verificationInfoByRound(address,address,uint256,string,uint256)(string)" $tokenAddress $ACCOUNT_ADDRESS $actionId "default" $round

echo "Verification info update rounds count for tokenAddress:"
cast_call $joinAddress "verificationInfoUpdateRoundsCount(address,address,uint256,string)(uint256)" $tokenAddress $ACCOUNT_ADDRESS $actionId "default"

echo "Verification info update rounds at index 0 for tokenAddress:"
cast_call $joinAddress "verificationInfoUpdateRoundsAtIndex(address,address,uint256,string,uint256)(uint256)" $tokenAddress $ACCOUNT_ADDRESS $actionId "default" 0

echo "Random accounts for tokenAddress:"
cast_call $joinAddress "randomAccounts(address,uint256,uint256)(address[])" $tokenAddress $round $actionId

echo "Random accounts by random seed for tokenAddress:"
cast_call $joinAddress "randomAccountsByRandomSeed(address,uint256,uint256,uint256)(address[])" $tokenAddress $round $actionId 12345 5

echo "Random accounts by action id count for tokenAddress:"
cast_call $joinAddress "randomAccountsByActionIdCount(address,uint256,uint256)(uint256)" $tokenAddress $round $actionId

echo "Random accounts by action id at index 0 for tokenAddress:"
cast_call $joinAddress "randomAccountsByActionIdAtIndex(address,uint256,uint256,uint256)(address)" $tokenAddress $round $actionId 0

echo "Amount by action id for tokenAddress:"
cast_call $joinAddress "amountByActionId(address,uint256)(uint256)" $tokenAddress $actionId

echo "Amount by action id by account for tokenAddress:"
cast_call $joinAddress "amountByActionIdByAccount(address,uint256,address)(uint256)" $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "Amount by account for tokenAddress:"
cast_call $joinAddress "amountByAccount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Action ids by account for tokenAddress:"
cast_call $joinAddress "actionIdsByAccount(address,address)(uint256[])" $tokenAddress $ACCOUNT_ADDRESS

echo "Action ids by account count for tokenAddress:"
cast_call $joinAddress "actionIdsByAccountCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Action ids by account at index 0 for tokenAddress:"
cast_call $joinAddress "actionIdsByAccountAtIndex(address,address,uint256)(uint256)" $tokenAddress $ACCOUNT_ADDRESS 0

echo "Num of accounts for tokenAddress:"
cast_call $joinAddress "numOfAccounts(address,uint256)(uint256)" $tokenAddress $actionId

echo "Index to account for tokenAddress:"
cast_call $joinAddress "indexToAccount(address,uint256,uint256)(address)" $tokenAddress $actionId 1

echo "Account to index for tokenAddress:"
cast_call $joinAddress "accountToIndex(address,uint256,address)(uint256)" $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "Prefix sum for tokenAddress:"
cast_call $joinAddress "prefixSum(address,uint256,uint256)(uint256)" $tokenAddress $actionId 1

echo "===================="
echo "Join Query Complete"
echo "====================" 