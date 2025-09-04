#!/bin/bash

echo "===================="
echo "    stake_query      "
echo "===================="

# ------ Read Functions ------

echo "Promised waiting phases min:"
cast_call $stakeAddress "PROMISED_WAITING_PHASES_MIN()(uint256)"

echo "Promised waiting phases max:"
cast_call $stakeAddress "PROMISED_WAITING_PHASES_MAX()(uint256)"

echo "Gov votes num for tokenAddress:"
cast_call $stakeAddress "govVotesNum(address)(uint256)" $tokenAddress

echo "Account stake status for tokenAddress:"
cast_call $stakeAddress "accountStakeStatus(address,address)((uint256,uint256,uint256,uint256,uint256))" $tokenAddress $ACCOUNT_ADDRESS

echo "Valid gov votes for tokenAddress:"
cast_call $stakeAddress "validGovVotes(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Initial stake round for tokenAddress:"
cast_call $stakeAddress "initialStakeRound(address)(uint256)" $tokenAddress

echo "Calculate gov votes (example with lpAmount=1000, promisedWaitingPhases=3):"
cast_call $stakeAddress "caculateGovVotes(uint256,uint256)(uint256)" 1000 3

echo "Cumulated token amount for tokenAddress round 0:"
cast_call $stakeAddress "cumulatedTokenAmount(address,uint256)(uint256)" $tokenAddress 0

echo "Cumulated token amount by account for tokenAddress round 0:"
cast_call $stakeAddress "cumulatedTokenAmountByAccount(address,uint256,address)(uint256)" $tokenAddress 0 $ACCOUNT_ADDRESS

echo "Stake token updated rounds count for tokenAddress:"
cast_call $stakeAddress "stakeTokenUpdatedRoundsCount(address)(uint256)" $tokenAddress

echo "Stake token updated rounds at index 0 for tokenAddress:"
cast_call $stakeAddress "stakeTokenUpdatedRoundsAtIndex(address,uint256)(uint256)" $tokenAddress 0

echo "Stake token updated rounds by account count for tokenAddress:"
cast_call $stakeAddress "stakeTokenUpdatedRoundsByAccountCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Stake token updated rounds by account at index 0 for tokenAddress:"
cast_call $stakeAddress "stakeTokenUpdatedRoundsByAccountAtIndex(address,address,uint256)(uint256)" $tokenAddress $ACCOUNT_ADDRESS 0

echo "===================="
echo "Stake Query Complete"
echo "====================" 