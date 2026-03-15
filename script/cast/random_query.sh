#!/bin/bash

echo "===================="
echo "    random_query     "
echo "===================="

# ------ Read Functions ------

echo "Modifier address:"
call ILOVE20Random $randomAddress modifierAddress

echo "Previous random seed:"
call ILOVE20Random $randomAddress prevRandomSeed

echo "Random seed for round 0:"
call ILOVE20Random $randomAddress randomSeed 0

echo "Random seed for round 1:"
call ILOVE20Random $randomAddress randomSeed 1

echo "Random seed for round 2:"
call ILOVE20Random $randomAddress randomSeed 2

echo "===================="
echo "Random Query Complete"
echo "====================" 