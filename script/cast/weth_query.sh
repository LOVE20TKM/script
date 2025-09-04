#!/bin/bash

echo "===================="
echo "      weth_query     "
echo "===================="

# ------ Read Functions ------

echo "Contract name:"
cast_call $rootParentTokenAddress "name()(string)"

echo "Contract symbol:"
cast_call $rootParentTokenAddress "symbol()(string)"

echo "Contract decimals:"
cast_call $rootParentTokenAddress "decimals()(uint8)"

echo "Total supply:"
cast_call $rootParentTokenAddress "totalSupply()(uint256)"

echo "Balance of current account:"
cast_call $rootParentTokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "Query contract allowance: launchAddress: " $launchAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $launchAddress

echo "Query contract allowance: stakeAddress: " $stakeAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $stakeAddress

echo "Query contract allowance: voteAddress: " $voteAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $voteAddress

echo "Query contract allowance: joinAddress: " $joinAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $joinAddress

echo "Query contract allowance: verifyAddress: " $verifyAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $verifyAddress

echo "Query contract allowance: mintAddress: " $mintAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $mintAddress

echo "Query contract allowance: randomAddress: " $randomAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $randomAddress

echo "Query contract allowance: submitAddress: " $submitAddress
cast_call $rootParentTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $submitAddress

echo "===================="
echo "WETH Query Complete"
echo "====================" 