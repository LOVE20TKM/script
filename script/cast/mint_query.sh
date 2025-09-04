#!/bin/bash

echo "===================="
echo "     mint_query      "
echo "===================="

# ------ Read Functions ------

echo "Vote address:"
cast_call $mintAddress "voteAddress()(address)"

echo "Verify address:"
cast_call $mintAddress "verifyAddress()(address)"

echo "Stake address:"
cast_call $mintAddress "stakeAddress()(address)"

echo "Action reward min vote per thousand:"
cast_call $mintAddress "ACTION_REWARD_MIN_VOTE_PER_THOUSAND()(uint256)"

echo "Round reward gov per thousand:"
cast_call $mintAddress "ROUND_REWARD_GOV_PER_THOUSAND()(uint256)"

echo "Round reward action per thousand:"
cast_call $mintAddress "ROUND_REWARD_ACTION_PER_THOUSAND()(uint256)"

echo "Max gov boost reward multiplier:"
cast_call $mintAddress "MAX_GOV_BOOST_REWARD_MULTIPLIER()(uint256)"

echo "Is action id with reward for tokenAddress:"
cast_call $mintAddress "isActionIdWithReward(address,uint256,uint256)(bool)" $tokenAddress $round $actionId

echo "Reward reserved for tokenAddress:"
cast_call $mintAddress "rewardReserved(address)(uint256)" $tokenAddress

echo "Reward minted for tokenAddress:"
cast_call $mintAddress "rewardMinted(address)(uint256)" $tokenAddress

echo "Reward burned for tokenAddress:"
cast_call $mintAddress "rewardBurned(address)(uint256)" $tokenAddress

echo "Is reward prepared for tokenAddress:"
cast_call $mintAddress "isRewardPrepared(address,uint256)(bool)" $tokenAddress $round

echo "Reward available for tokenAddress:"
cast_call $mintAddress "rewardAvailable(address)(uint256)" $tokenAddress

echo "Reserved available for tokenAddress:"
cast_call $mintAddress "reservedAvailable(address)(uint256)" $tokenAddress

echo "Calculate round gov reward for tokenAddress:"
cast_call $mintAddress "calculateRoundGovReward(address)(uint256)" $tokenAddress

echo "Gov reward for tokenAddress:"
cast_call $mintAddress "govReward(address,uint256)(uint256)" $tokenAddress $round

echo "Boost reward burned for tokenAddress:"
cast_call $mintAddress "boostRewardBurnCheckeded(address,uint256)(bool)" $tokenAddress $round

echo "Gov reward minted by account for tokenAddress:"
cast_call $mintAddress "govRewardMintedByAccount(address,uint256,address)(uint256)" $tokenAddress $round $ACCOUNT_ADDRESS

echo "Gov verify reward for tokenAddress:"
cast_call $mintAddress "govVerifyReward(address,uint256)(uint256)" $tokenAddress $round

echo "Gov boost reward for tokenAddress:"
cast_call $mintAddress "govBoostReward(address,uint256)(uint256)" $tokenAddress $round

echo "Gov reward by account for tokenAddress:"
cast_call $mintAddress "govRewardByAccount(address,uint256,address)((uint256,uint256,uint256,bool))" $tokenAddress $round $ACCOUNT_ADDRESS

echo "Calculate round action reward for tokenAddress:"
cast_call $mintAddress "calculateRoundActionReward(address)(uint256)" $tokenAddress

echo "Action reward for tokenAddress:"
cast_call $mintAddress "actionReward(address,uint256)(uint256)" $tokenAddress $round

echo "Abstention action reward burned for tokenAddress:"
cast_call $mintAddress "actionRewardBurnChecked(address,uint256)(bool)" $tokenAddress $round

echo "Action reward minted by account for tokenAddress:"
cast_call $mintAddress "actionRewardMintedByAccount(address,uint256,uint256,address)(uint256)" $tokenAddress $round $actionId $ACCOUNT_ADDRESS

echo "Action reward by action id by account for tokenAddress:"
cast_call $mintAddress "actionRewardByActionIdByAccount(address,uint256,uint256,address)((uint256,bool))" $tokenAddress $round $actionId $ACCOUNT_ADDRESS

echo "Num of mint gov reward by account for tokenAddress:"
cast_call $mintAddress "numOfMintGovRewardByAccount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "===================="
echo "Mint Query Complete"
echo "====================" 