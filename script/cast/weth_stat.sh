echo "===================="
echo "      weth_stat     "
echo "===================="

# ------ Read Functions ------

echo "Contract name:"
call IETH20 $rootParentTokenAddress name

echo "Contract symbol:"
call IETH20 $rootParentTokenAddress symbol

echo "Total supply:"
call IETH20 $rootParentTokenAddress totalSupply

echo "Query contract allowance: launchAddress: " $launchAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $launchAddress

echo "Query contract allowance: stakeAddress: " $stakeAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $stakeAddress


