echo "===================="
echo "   weth_withdraw    "
echo "===================="


echo "Account WETH balance before withdraw: " $ACCOUNT_ADDRESS
balance=$(cast_call $rootParentTokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS | awk '{print $1}') 

echo "Balance in wei: $balance"
echo "Balance in ETH: $(echo $balance | show_in_eth)"

echo "ETH balance before withdraw: " $ACCOUNT_ADDRESS
ethBalance=$(balance_eth_in_wei $ACCOUNT_ADDRESS)
echo "ETH balance in wei: $ethBalance"
echo "ETH balance in ETH: $(echo $ethBalance | show_in_eth)"

echo "Withdraw ETH from WETH"
echo "----------------------------------------"
cast_send $rootParentTokenAddress "withdraw(uint256)" $balance
echo "----------------------------------------"

echo "Account WETH balance after withdraw: " $ACCOUNT_ADDRESS
balance=$(cast_call $rootParentTokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS | awk '{print $1}') 
echo "Balance in wei: $balance"
echo "Balance in ETH: $(echo $balance | show_in_eth)"

echo "ETH balance after withdraw: " $ACCOUNT_ADDRESS
ethBalance=$(balance_eth_in_wei $ACCOUNT_ADDRESS)
echo "ETH balance in wei: $ethBalance"
echo "ETH balance in ETH: $(echo $ethBalance | show_in_eth)"

