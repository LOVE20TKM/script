#!/bin/bash

echo "===================="
echo "    launch_query     "
echo "===================="

# ------ Read Functions ------

echo "Token factory address:"
call ILOVE20Launch $launchAddress tokenFactoryAddress

echo "Submit address:"
call ILOVE20Launch $launchAddress submitAddress

echo "Mint address:"
call ILOVE20Launch $launchAddress mintAddress

echo "Token symbol length:"
call ILOVE20Launch $launchAddress TOKEN_SYMBOL_LENGTH

echo "First parent token fundraising goal:"
call ILOVE20Launch $launchAddress FIRST_PARENT_TOKEN_FUNDRAISING_GOAL

echo "Parent token fundraising goal:"
call ILOVE20Launch $launchAddress PARENT_TOKEN_FUNDRAISING_GOAL

echo "Second half min blocks:"
call ILOVE20Launch $launchAddress SECOND_HALF_MIN_BLOCKS

echo "Withdraw waiting blocks:"
call ILOVE20Launch $launchAddress WITHDRAW_WAITING_BLOCKS

echo "Min gov reward mints to launch:"
call ILOVE20Launch $launchAddress MIN_GOV_REWARD_MINTS_TO_LAUNCH

echo "Is LOVE20 token check for tokenAddress:"
call ILOVE20Launch $launchAddress isLOVE20Token $tokenAddress

echo "Tokens count:"
call ILOVE20Launch $launchAddress tokensCount

echo "Tokens at index 0:"
call ILOVE20Launch $launchAddress tokensAtIndex 0

echo "Child tokens by launcher count:"
call ILOVE20Launch $launchAddress childTokensByLauncherCount $tokenAddress $ACCOUNT_ADDRESS

echo "Child tokens count for tokenAddress:"
call ILOVE20Launch $launchAddress childTokensCount $tokenAddress

echo "Child tokens at index 0 for tokenAddress:"
call ILOVE20Launch $launchAddress childTokensAtIndex $tokenAddress 0

echo "Launching tokens count:"
call ILOVE20Launch $launchAddress launchingTokensCount

echo "Launched tokens count:"
call ILOVE20Launch $launchAddress launchedTokensCount

echo "Launching child tokens count:"
call ILOVE20Launch $launchAddress launchingChildTokensCount $tokenAddress

echo "Launched child tokens count:"
call ILOVE20Launch $launchAddress launchedChildTokensCount $tokenAddress

echo "Participated tokens count:"
call ILOVE20Launch $launchAddress participatedTokensCount $ACCOUNT_ADDRESS

echo "Token address by symbol 'CHILD1':"
call ILOVE20Launch $launchAddress tokenAddressBySymbol "CHILD1"

echo "Launch info for tokenAddress:"
call ILOVE20Launch $launchAddress launchInfo $tokenAddress

echo "Contributed amount for tokenAddress:"
call ILOVE20Launch $launchAddress contributed $tokenAddress $ACCOUNT_ADDRESS

echo "Last contributed block for tokenAddress:"
call ILOVE20Launch $launchAddress lastContributedBlock $tokenAddress $ACCOUNT_ADDRESS

echo "Remaining launch count for tokenAddress:"
call ILOVE20Launch $launchAddress remainingLaunchCount $tokenAddress $ACCOUNT_ADDRESS

echo "Claim info for tokenAddress:"
call ILOVE20Launch $launchAddress claimInfo $tokenAddress $ACCOUNT_ADDRESS

launch_info $tokenAddress

echo "===================="
echo "Launch Query Complete"
echo "====================" 