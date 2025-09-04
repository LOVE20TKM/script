#!/bin/bash

echo "===================="
echo "     token_query     "
echo "===================="

# ------ Read Functions ------

echo "Token name:"
cast_call $firstTokenAddress "name()(string)"

echo "Token symbol:"
cast_call $firstTokenAddress "symbol()(string)"

echo "Token decimals:"
cast_call $firstTokenAddress "decimals()(uint8)"

echo "Total supply:"
cast_call $firstTokenAddress "totalSupply()(uint256)"

echo "Max supply:"
cast_call $firstTokenAddress "maxSupply()(uint256)"

echo "Minter address:"
cast_call $firstTokenAddress "minter()(address)"

echo "Parent token address:"
cast_call $firstTokenAddress "parentTokenAddress()(address)"

echo "SL token address:"
cast_call $firstTokenAddress "slAddress()(address)"

echo "ST token address:"
cast_call $firstTokenAddress "stAddress()(address)"

echo "Initialized status:"
cast_call $firstTokenAddress "initialized()(bool)"

echo "Parent pool amount:"
cast_call $firstTokenAddress "parentPool()(uint256)"

echo "Balance of current account:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $ACCOUNT_ADDRESS

echo "Balance of launch address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $launchAddress

echo "Balance of stake address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $stakeAddress

echo "Balance of vote address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $voteAddress

echo "Balance of join address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $joinAddress

echo "Balance of verify address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $verifyAddress

echo "Balance of mint address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $mintAddress

echo "Balance of random address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $randomAddress

echo "Balance of submit address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $submitAddress

echo "Balance of token factory address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $tokenFactoryAddress

echo "Balance of root parent token address:"
cast_call $firstTokenAddress "balanceOf(address)(uint256)" $rootParentTokenAddress

echo "Allowance for launch address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $launchAddress

echo "Allowance for stake address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $stakeAddress

echo "Allowance for vote address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $voteAddress

echo "Allowance for join address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $joinAddress

echo "Allowance for verify address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $verifyAddress

echo "Allowance for mint address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $mintAddress

echo "Allowance for random address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $randomAddress

echo "Allowance for submit address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $submitAddress

echo "Allowance for token factory address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $tokenFactoryAddress

echo "Allowance for root parent token address:"
cast_call $firstTokenAddress "allowance(address,address)(uint256)" $ACCOUNT_ADDRESS $rootParentTokenAddress

echo "===================="
echo "Token Query Complete"
echo "====================" 