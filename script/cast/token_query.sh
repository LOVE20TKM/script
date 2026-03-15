#!/bin/bash

echo "===================="
echo "     token_query     "
echo "===================="

# ------ Read Functions ------

echo "Token name:"
call ILOVE20Token $firstTokenAddress name

echo "Token symbol:"
call ILOVE20Token $firstTokenAddress symbol

echo "Token decimals:"
call ILOVE20Token $firstTokenAddress decimals

echo "Total supply:"
call ILOVE20Token $firstTokenAddress totalSupply

echo "Max supply:"
call ILOVE20Token $firstTokenAddress maxSupply

echo "Minter address:"
call ILOVE20Token $firstTokenAddress minter

echo "Parent token address:"
call ILOVE20Token $firstTokenAddress parentTokenAddress

echo "SL token address:"
call ILOVE20Token $firstTokenAddress slAddress

echo "ST token address:"
call ILOVE20Token $firstTokenAddress stAddress

echo "Parent pool amount:"
call ILOVE20Token $firstTokenAddress parentPool

echo "Balance of current account:"
call ILOVE20Token $firstTokenAddress balanceOf $ACCOUNT_ADDRESS

echo "Balance of launch address:"
call ILOVE20Token $firstTokenAddress balanceOf $launchAddress

echo "Balance of stake address:"
call ILOVE20Token $firstTokenAddress balanceOf $stakeAddress

echo "Balance of vote address:"
call ILOVE20Token $firstTokenAddress balanceOf $voteAddress

echo "Balance of join address:"
call ILOVE20Token $firstTokenAddress balanceOf $joinAddress

echo "Balance of verify address:"
call ILOVE20Token $firstTokenAddress balanceOf $verifyAddress

echo "Balance of mint address:"
call ILOVE20Token $firstTokenAddress balanceOf $mintAddress

echo "Balance of random address:"
call ILOVE20Token $firstTokenAddress balanceOf $randomAddress

echo "Balance of submit address:"
call ILOVE20Token $firstTokenAddress balanceOf $submitAddress

echo "Balance of token factory address:"
call ILOVE20Token $firstTokenAddress balanceOf $tokenFactoryAddress

echo "Balance of root parent token address:"
call ILOVE20Token $firstTokenAddress balanceOf $rootParentTokenAddress

echo "Allowance for launch address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $launchAddress

echo "Allowance for stake address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $stakeAddress

echo "Allowance for vote address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $voteAddress

echo "Allowance for join address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $joinAddress

echo "Allowance for verify address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $verifyAddress

echo "Allowance for mint address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $mintAddress

echo "Allowance for random address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $randomAddress

echo "Allowance for submit address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $submitAddress

echo "Allowance for token factory address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $tokenFactoryAddress

echo "Allowance for root parent token address:"
call ILOVE20Token $firstTokenAddress allowance $ACCOUNT_ADDRESS $rootParentTokenAddress

echo "===================="
echo "Token Query Complete"
echo "====================" 
