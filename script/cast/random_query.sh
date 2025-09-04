#!/bin/bash

echo "===================="
echo "    random_query     "
echo "===================="

# ------ Read Functions ------

echo "Modifier address:"
cast_call $randomAddress "modifierAddress()(address)"

echo "Previous random seed:"
cast_call $randomAddress "prevRandomSeed()(uint256)"

echo "Random seed for round 0:"
cast_call $randomAddress "randomSeed(uint256)(uint256)" 0

echo "Random seed for round 1:"
cast_call $randomAddress "randomSeed(uint256)(uint256)" 1

echo "Random seed for round 2:"
cast_call $randomAddress "randomSeed(uint256)(uint256)" 2

echo "===================="
echo "Random Query Complete"
echo "====================" 