#!/bin/bash

echo "===================="
echo "     mint_query      "
echo "===================="

# ------ Read Functions ------

echo "Vote address:"
call ILOVE20Mint $mintAddress voteAddress

echo "Verify address:"
call ILOVE20Mint $mintAddress verifyAddress

echo "Stake address:"
call ILOVE20Mint $mintAddress stakeAddress

echo "Action reward min vote per thousand:"
call ILOVE20Mint $mintAddress ACTION_REWARD_MIN_VOTE_PER_THOUSAND

echo "Round reward gov per thousand:"
call ILOVE20Mint $mintAddress ROUND_REWARD_GOV_PER_THOUSAND

echo "Round reward action per thousand:"
call ILOVE20Mint $mintAddress ROUND_REWARD_ACTION_PER_THOUSAND

echo "Max gov boost reward multiplier:"
call ILOVE20Mint $mintAddress MAX_GOV_BOOST_REWARD_MULTIPLIER

echo "Is action id with reward for tokenAddress:"
call ILOVE20Mint $mintAddress isActionIdWithReward $tokenAddress $round $actionId

echo "Reward reserved for tokenAddress:"
call ILOVE20Mint $mintAddress rewardReserved $tokenAddress

echo "Reward minted for tokenAddress:"
call ILOVE20Mint $mintAddress rewardMinted $tokenAddress

echo "Reward burned for tokenAddress:"
call ILOVE20Mint $mintAddress rewardBurned $tokenAddress

echo "Is reward prepared for tokenAddress:"
call ILOVE20Mint $mintAddress isRewardPrepared $tokenAddress $round

echo "Reward available for tokenAddress:"
call ILOVE20Mint $mintAddress rewardAvailable $tokenAddress

echo "Reserved available for tokenAddress:"
call ILOVE20Mint $mintAddress reservedAvailable $tokenAddress

echo "Calculate round gov reward for tokenAddress:"
call ILOVE20Mint $mintAddress calculateRoundGovReward $tokenAddress

echo "Gov reward for tokenAddress:"
call ILOVE20Mint $mintAddress govReward $tokenAddress $round

echo "Boost reward burned for tokenAddress:"
call ILOVE20Mint $mintAddress boostRewardBurnCheckeded $tokenAddress $round

echo "Gov reward minted by account for tokenAddress:"
call ILOVE20Mint $mintAddress govRewardMintedByAccount $tokenAddress $round $ACCOUNT_ADDRESS

echo "Gov verify reward for tokenAddress:"
call ILOVE20Mint $mintAddress govVerifyReward $tokenAddress $round

echo "Gov boost reward for tokenAddress:"
call ILOVE20Mint $mintAddress govBoostReward $tokenAddress $round

echo "Gov reward by account for tokenAddress:"
call ILOVE20Mint $mintAddress govRewardByAccount $tokenAddress $round $ACCOUNT_ADDRESS

echo "Calculate round action reward for tokenAddress:"
call ILOVE20Mint $mintAddress calculateRoundActionReward $tokenAddress

echo "Action reward for tokenAddress:"
call ILOVE20Mint $mintAddress actionReward $tokenAddress $round

echo "Abstention action reward burned for tokenAddress:"
call ILOVE20Mint $mintAddress actionRewardBurnChecked $tokenAddress $round

echo "Action reward minted by account for tokenAddress:"
call ILOVE20Mint $mintAddress actionRewardMintedByAccount $tokenAddress $round $actionId $ACCOUNT_ADDRESS

echo "Action reward by action id by account for tokenAddress:"
call ILOVE20Mint $mintAddress actionRewardByActionIdByAccount $tokenAddress $round $actionId $ACCOUNT_ADDRESS

echo "Num of mint gov reward by account for tokenAddress:"
call ILOVE20Mint $mintAddress numOfMintGovRewardByAccount $tokenAddress $ACCOUNT_ADDRESS

echo "===================="
echo "Mint Query Complete"
echo "====================" 