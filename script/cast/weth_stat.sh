echo "===================="
echo "      weth_stat     "
echo "===================="

# ------ Read Functions ------

echo "Contract name:"
cast_call $rootParentTokenAddress "name()(string)"

echo "Contract symbol:"
cast_call $rootParentTokenAddress "symbol()(string)"

echo "Total supply:"
cast_call $rootParentTokenAddress "totalSupply()(uint256)"

echo "Query contract allowance: launchAddress: " $launchAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $launchAddress

echo "Query contract allowance: stakeAddress: " $stakeAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $stakeAddress


