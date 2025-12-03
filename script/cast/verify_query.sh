#!/bin/bash

echo "===================="
echo "    verify_query     "
echo "===================="

# ------ Read Functions ------

echo "First token address:"
cast_call $verifyAddress "firstTokenAddress()(address)"

echo "Random address:"
cast_call $verifyAddress "randomAddress()(address)"

echo "Stake address:"
cast_call $verifyAddress "stakeAddress()(address)"

echo "Vote address:"
cast_call $verifyAddress "voteAddress()(address)"

echo "Join address:"
cast_call $verifyAddress "joinAddress()(address)"

echo "Random seed update min per ten thousand:"
cast_call $verifyAddress "RANDOM_SEED_UPDATE_MIN_PER_TEN_THOUSAND()(uint256)"

echo "Score for tokenAddress:"
cast_call $verifyAddress "score(address,uint256)(uint256)" $tokenAddress $round

echo "Score with reward for tokenAddress:"
cast_call $verifyAddress "scoreWithReward(address,uint256)(uint256)" $tokenAddress $round 

echo "Abstention score with reward for tokenAddress:"
cast_call $verifyAddress "abstentionScoreWithReward(address,uint256)(uint256)" $tokenAddress $round

echo "Score by action id for tokenAddress:"
cast_call $verifyAddress "scoreByActionId(address,uint256,uint256)(uint256)" $tokenAddress $round $actionId

echo "Abstention score by action id for tokenAddress:"
cast_call $verifyAddress "scoreByActionIdByAccount(address,uint256,uint256,address)(uint256)" $tokenAddress $round $actionId $ZERO_ADDRESS


echo "Score by action id by account for tokenAddress:"
cast_call $verifyAddress "scoreByActionIdByAccount(address,uint256,uint256,address)(uint256)" $tokenAddress $round $actionId $ACCOUNT_ADDRESS

echo "Score by verifier for tokenAddress:"
cast_call $verifyAddress "scoreByVerifier(address,uint256,address)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS

echo "Score by verifier by action id for tokenAddress:"
cast_call $verifyAddress "scoreByVerifierByActionId(address,uint256,address,uint256)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS $actionId

echo "Staked amount of verifiers for tokenAddress:"
cast_call $verifyAddress "stakedAmountOfVerifiers(address,uint256)(uint256)" $tokenAddress $round

echo "===================="
echo "Verify Query Complete"
echo "====================" 