#!/bin/bash

echo "===================="
echo "    stake_query      "
echo "===================="

# ------ Read Functions ------

echo "Promised waiting phases min:"
call ILOVE20Stake $stakeAddress PROMISED_WAITING_PHASES_MIN

echo "Promised waiting phases max:"
call ILOVE20Stake $stakeAddress PROMISED_WAITING_PHASES_MAX

echo "Gov votes num for tokenAddress:"
call ILOVE20Stake $stakeAddress govVotesNum $tokenAddress

echo "Account stake status for tokenAddress:"
call ILOVE20Stake $stakeAddress accountStakeStatus $tokenAddress $ACCOUNT_ADDRESS

echo "Valid gov votes for tokenAddress:"
call ILOVE20Stake $stakeAddress validGovVotes $tokenAddress $ACCOUNT_ADDRESS

echo "Initial stake round for tokenAddress:"
call ILOVE20Stake $stakeAddress initialStakeRound $tokenAddress

echo "Calculate gov votes (example with lpAmount=1000, promisedWaitingPhases=3):"
call ILOVE20Stake $stakeAddress caculateGovVotes 1000 3

echo "Cumulated token amount for tokenAddress round 0:"
call ILOVE20Stake $stakeAddress cumulatedTokenAmount $tokenAddress 0

echo "Cumulated token amount by account for tokenAddress round 0:"
call ILOVE20Stake $stakeAddress cumulatedTokenAmountByAccount $tokenAddress 0 $ACCOUNT_ADDRESS

echo "Stake token updated rounds count for tokenAddress:"
call ILOVE20Stake $stakeAddress stakeTokenUpdatedRoundsCount $tokenAddress

echo "Stake token updated rounds at index 0 for tokenAddress:"
call ILOVE20Stake $stakeAddress stakeTokenUpdatedRoundsAtIndex $tokenAddress 0

echo "Stake token updated rounds by account count for tokenAddress:"
call ILOVE20Stake $stakeAddress stakeTokenUpdatedRoundsByAccountCount $tokenAddress $ACCOUNT_ADDRESS

echo "Stake token updated rounds by account at index 0 for tokenAddress:"
call ILOVE20Stake $stakeAddress stakeTokenUpdatedRoundsByAccountAtIndex $tokenAddress $ACCOUNT_ADDRESS 0

echo "===================="
echo "Stake Query Complete"
echo "====================" 