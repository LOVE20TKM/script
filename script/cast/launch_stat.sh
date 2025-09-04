echo "===================="
echo "    launch_stat     "
echo "===================="

launch_info $tokenAddress

echo "launchingTokensCount"
cast_call $launchAddress "launchingTokensCount()(uint256)"

echo "childTokensCount"
cast_call $launchAddress "childTokensCount(address)(uint256)" $parentTokenAddress


echo "launchedTokensCount"
cast_call $launchAddress "launchedTokensCount()(uint256)"

echo "launchingChildTokensCount"
cast_call $launchAddress "launchingChildTokensCount(address)(uint256)" $parentTokenAddress

echo "launchedChildTokensCount"
cast_call $launchAddress "launchedChildTokensCount(address)(uint256)" $parentTokenAddress

echo "participatedTokensCount"
cast_call $launchAddress "participatedTokensCount(address)(uint256)" $ACCOUNT_ADDRESS

