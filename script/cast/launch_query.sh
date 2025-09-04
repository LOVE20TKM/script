#!/bin/bash

echo "===================="
echo "    launch_query     "
echo "===================="

# ------ Read Functions ------

echo "Token factory address:"
cast_call $launchAddress "tokenFactoryAddress()(address)"

echo "Submit address:"
cast_call $launchAddress "submitAddress()(address)"

echo "Mint address:"
cast_call $launchAddress "mintAddress()(address)"

echo "Initialized status:"
cast_call $launchAddress "initialized()(bool)"

echo "Token symbol length:"
cast_call $launchAddress "TOKEN_SYMBOL_LENGTH()(uint256)"

echo "First parent token fundraising goal:"
cast_call $launchAddress "FIRST_PARENT_TOKEN_FUNDRAISING_GOAL()(uint256)"

echo "Parent token fundraising goal:"
cast_call $launchAddress "PARENT_TOKEN_FUNDRAISING_GOAL()(uint256)"

echo "Second half min blocks:"
cast_call $launchAddress "SECOND_HALF_MIN_BLOCKS()(uint256)"

echo "Withdraw waiting blocks:"
cast_call $launchAddress "WITHDRAW_WAITING_BLOCKS()(uint256)"

echo "Min gov reward mints to launch:"
cast_call $launchAddress "MIN_GOV_REWARD_MINTS_TO_LAUNCH()(uint256)"

echo "Is LOVE20 token check for tokenAddress:"
cast_call $launchAddress "isLOVE20Token(address)(bool)" $tokenAddress

echo "Tokens count:"
cast_call $launchAddress "tokensCount()(uint256)"

echo "Tokens at index 0:"
cast_call $launchAddress "tokensAtIndex(uint256)(address)" 0

echo "Child tokens by launcher count:"
cast_call $launchAddress "childTokensByLauncherCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Child tokens count for tokenAddress:"
cast_call $launchAddress "childTokensCount(address)(uint256)" $tokenAddress

echo "Child tokens at index 0 for tokenAddress:"
cast_call $launchAddress "childTokensAtIndex(address,uint256)(address)" $tokenAddress 0

echo "Launching tokens count:"
cast_call $launchAddress "launchingTokensCount()(uint256)"

echo "Launched tokens count:"
cast_call $launchAddress "launchedTokensCount()(uint256)"

echo "Launching child tokens count:"
cast_call $launchAddress "launchingChildTokensCount(address)(uint256)" $tokenAddress

echo "Launched child tokens count:"
cast_call $launchAddress "launchedChildTokensCount(address)(uint256)" $tokenAddress

echo "Participated tokens count:"
cast_call $launchAddress "participatedTokensCount(address)(uint256)" $ACCOUNT_ADDRESS

echo "Token address by symbol 'CHILD1':"
cast_call $launchAddress "tokenAddressBySymbol(string)(address)" "CHILD1"

echo "Launch info for tokenAddress:"
cast_call $launchAddress "launchInfo(address)((address,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint256,uint256,uint256))" $tokenAddress

echo "Contributed amount for tokenAddress:"
cast_call $launchAddress "contributed(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Last contributed block for tokenAddress:"
cast_call $launchAddress "lastContributedBlock(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Remaining launch count for tokenAddress:"
cast_call $launchAddress "remainingLaunchCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

echo "Claim info for tokenAddress:"
cast_call $launchAddress "claimInfo(address,address)((uint256,uint256,bool))" $tokenAddress $ACCOUNT_ADDRESS

launch_info $tokenAddress

echo "===================="
echo "Launch Query Complete"
echo "====================" 