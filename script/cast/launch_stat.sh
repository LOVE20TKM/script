echo "===================="
echo "    launch_stat     "
echo "===================="

launch_info $tokenAddress

echo "launchingTokensCount"
call ILOVE20Launch $launchAddress launchingTokensCount

echo "childTokensCount"
call ILOVE20Launch $launchAddress childTokensCount $parentTokenAddress


echo "launchedTokensCount"
call ILOVE20Launch $launchAddress launchedTokensCount

echo "launchingChildTokensCount"
call ILOVE20Launch $launchAddress launchingChildTokensCount $parentTokenAddress

echo "launchedChildTokensCount"
call ILOVE20Launch $launchAddress launchedChildTokensCount $parentTokenAddress

echo "participatedTokensCount"
call ILOVE20Launch $launchAddress participatedTokensCount $ACCOUNT_ADDRESS

