#tokenSymbolForDeploy="CHILD1"

echo "===================="
echo "    launch_deploy   "
echo "===================="

echo "tokenSymbolForDeploy: $tokenSymbolForDeploy"

echo "remainingLaunchCount before: $(cast_call $launchAddress "remainingLaunchCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS)"

echo "tokenNum before: $(cast_call $launchAddress "tokensCount()(uint256)")"
echo "childTokensByLauncherCount before: $(cast_call $launchAddress "childTokensByLauncherCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS)"

# Deploy a new token
echo "Deploy new token"
echo "----------------------------------------"
cast_send $launchAddress "launchToken(string,address)(address)" $tokenSymbolForDeploy $tokenAddress
echo "----------------------------------------"

# Get the current number of tokens
tokenNum=$(cast_call $launchAddress "tokensCount()(uint256)")
echo "tokenNum after: $tokenNum"

latestTokenAddress=$(cast_call $launchAddress "tokensAtIndex(uint256)(address)" $((tokenNum - 1)))
echo "latestTokenAddress after: $latestTokenAddress"

echo "childTokensByLauncherCount after: $(cast_call $launchAddress "childTokensByLauncherCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS)"

# Get launch information for multiple addresses
launch_info $latestTokenAddress

