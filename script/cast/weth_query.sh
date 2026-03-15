#!/bin/bash

echo "===================="
echo "      weth_query     "
echo "===================="

# ------ Read Functions ------

echo "Contract name:"
call IETH20 $rootParentTokenAddress name

echo "Contract symbol:"
call IETH20 $rootParentTokenAddress symbol

echo "Contract decimals:"
call IETH20 $rootParentTokenAddress decimals

echo "Total supply:"
call IETH20 $rootParentTokenAddress totalSupply

echo "Balance of current account:"
call IETH20 $rootParentTokenAddress balanceOf $ACCOUNT_ADDRESS

echo "Query contract allowance: launchAddress: " $launchAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $launchAddress

echo "Query contract allowance: stakeAddress: " $stakeAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $stakeAddress

echo "Query contract allowance: voteAddress: " $voteAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $voteAddress

echo "Query contract allowance: joinAddress: " $joinAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $joinAddress

echo "Query contract allowance: verifyAddress: " $verifyAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $verifyAddress

echo "Query contract allowance: mintAddress: " $mintAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $mintAddress

echo "Query contract allowance: randomAddress: " $randomAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $randomAddress

echo "Query contract allowance: submitAddress: " $submitAddress
call IETH20 $rootParentTokenAddress allowance $ACCOUNT_ADDRESS $submitAddress

echo "===================="
echo "WETH Query Complete"
echo "====================" 