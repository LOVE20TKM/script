deposit_eth_amount=0.5

echo "===================="
echo "    weth_deposit    "
echo "===================="

echo "deposit_eth_amount: $deposit_eth_amount"

echo "WETH balance before: " $ACCOUNT_ADDRESS
wethBalance=$(balance_of_wei $rootParentTokenAddress $ACCOUNT_ADDRESS)
echo "WETH balance in wei: $wethBalance"
echo "WETH balance in ETH: $(echo $wethBalance | show_in_eth)"

echo "ETH balance before: " $ACCOUNT_ADDRESS
ethBalance=$(balance_eth_in_wei $ACCOUNT_ADDRESS)
echo "ETH balance in wei: $ethBalance"
echo "ETH balance in ETH: $(echo $ethBalance | show_in_eth)"

echo "Deposit ETH to WETH:"
echo "----------------------------------------"
cast_send $rootParentTokenAddress "deposit()" --value "${deposit_eth_amount}ether"
echo "----------------------------------------"

echo "WETH balance after: " $ACCOUNT_ADDRESS
wethBalance=$(balance_of_wei $rootParentTokenAddress $ACCOUNT_ADDRESS)
echo "WETH balance in wei: $wethBalance"
echo "WETH balance in ETH: $(echo $wethBalance | show_in_eth)"

echo "ETH balance after: " $ACCOUNT_ADDRESS
ethBalance=$(balance_eth_in_wei $ACCOUNT_ADDRESS)
echo "ETH balance in wei: $ethBalance"
echo "ETH balance in ETH: $(echo $ethBalance | show_in_eth)"