#!/bin/bash

echo "===================="
echo "    verify_query     "
echo "===================="

# ------ Read Functions ------

echo "First token address:"
call ILOVE20Verify $verifyAddress firstTokenAddress

echo "Random address:"
call ILOVE20Verify $verifyAddress randomAddress

echo "Stake address:"
call ILOVE20Verify $verifyAddress stakeAddress

echo "Vote address:"
call ILOVE20Verify $verifyAddress voteAddress

echo "Join address:"
call ILOVE20Verify $verifyAddress joinAddress

echo "Random seed update min per ten thousand:"
call ILOVE20Verify $verifyAddress RANDOM_SEED_UPDATE_MIN_PER_TEN_THOUSAND

echo "Score for tokenAddress:"
call ILOVE20Verify $verifyAddress score $tokenAddress $round

echo "Score with reward for tokenAddress:"
call ILOVE20Verify $verifyAddress scoreWithReward $tokenAddress $round 

echo "Abstention score with reward for tokenAddress:"
call ILOVE20Verify $verifyAddress abstentionScoreWithReward $tokenAddress $round

echo "Score by action id for tokenAddress:"
call ILOVE20Verify $verifyAddress scoreByActionId $tokenAddress $round $actionId

echo "Abstention score by action id for tokenAddress:"
call ILOVE20Verify $verifyAddress scoreByActionIdByAccount $tokenAddress $round $actionId $ZERO_ADDRESS


echo "Score by action id by account for tokenAddress:"
call ILOVE20Verify $verifyAddress scoreByActionIdByAccount $tokenAddress $round $actionId $ACCOUNT_ADDRESS

echo "Score by verifier for tokenAddress:"
call ILOVE20Verify $verifyAddress scoreByVerifier $tokenAddress $round $ACCOUNT_ADDRESS

echo "Score by verifier by action id for tokenAddress:"
call ILOVE20Verify $verifyAddress scoreByVerifierByActionId $tokenAddress $round $ACCOUNT_ADDRESS $actionId

echo "Staked amount of verifiers for tokenAddress:"
call ILOVE20Verify $verifyAddress stakedAmountOfVerifiers $tokenAddress $round

echo "===================="
echo "Verify Query Complete"
echo "====================" 