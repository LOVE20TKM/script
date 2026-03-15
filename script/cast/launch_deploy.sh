#tokenSymbolForDeploy="CHILD1"

echo "===================="
echo "    launch_deploy   "
echo "===================="

echo "tokenSymbolForDeploy: $tokenSymbolForDeploy"

echo "remainingLaunchCount before: $(call ILOVE20Launch $launchAddress remainingLaunchCount $tokenAddress $ACCOUNT_ADDRESS)"

echo "tokenNum before: $(call ILOVE20Launch $launchAddress tokensCount)"
echo "childTokensByLauncherCount before: $(call ILOVE20Launch $launchAddress childTokensByLauncherCount $tokenAddress $ACCOUNT_ADDRESS)"

# Deploy a new token
echo "Deploy new token"
echo "----------------------------------------"
send ILOVE20Launch $launchAddress launchToken $tokenSymbolForDeploy $tokenAddress
echo "----------------------------------------"

# Get the current number of tokens
tokenNum=$(call ILOVE20Launch $launchAddress tokensCount)
echo "tokenNum after: $tokenNum"

latestTokenAddress=$(call ILOVE20Launch $launchAddress tokensAtIndex $((tokenNum - 1)))
echo "latestTokenAddress after: $latestTokenAddress"

echo "childTokensByLauncherCount after: $(call ILOVE20Launch $launchAddress childTokensByLauncherCount $tokenAddress $ACCOUNT_ADDRESS)"

# Get launch information for multiple addresses
launch_info $latestTokenAddress

