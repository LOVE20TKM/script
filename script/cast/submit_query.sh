#!/bin/bash

# if round is 0 then set round to current round
if [ "$round" -eq "0" ]; then
    round=$(call ILOVE20Submit $submitAddress currentRound)
fi

echo "===================="
echo "    submit_query     "
echo "===================="

# ------ Read Functions ------

echo "Stake address:"
call ILOVE20Submit $submitAddress stakeAddress

echo "Submit min per thousand:"
call ILOVE20Submit $submitAddress SUBMIT_MIN_PER_THOUSAND

echo "Max verification key length:"
call ILOVE20Submit $submitAddress MAX_VERIFICATION_KEY_LENGTH

echo "Current round:"
call ILOVE20Submit $submitAddress currentRound

echo "Phase blocks:"
call ILOVE20Submit $submitAddress phaseBlocks

echo "Origin blocks:"
call ILOVE20Submit $submitAddress originBlocks

echo "Actions count for token:"
call ILOVE20Submit $submitAddress actionsCount $tokenAddress

echo "Can submit for current account:"
call ILOVE20Submit $submitAddress canSubmit $tokenAddress $ACCOUNT_ADDRESS

echo "Is submitted for token:"
call ILOVE20Submit $submitAddress isSubmitted $tokenAddress $round $actionId

echo "Can join for current account action:"
call ILOVE20Submit $submitAddress canJoin $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "Action submits count for token:"
call ILOVE20Submit $submitAddress actionSubmitsCount $tokenAddress $round

echo "Author action ids count for current account:"
call ILOVE20Submit $submitAddress authorActionIdsCount $tokenAddress $ACCOUNT_ADDRESS

# Query action info if actions exist
actionCount=$(call ILOVE20Submit $submitAddress actionsCount $tokenAddress)
if [ "$actionCount" -gt "0" ]; then
    echo "Action info at index:"
    call ILOVE20Submit $submitAddress actionsAtIndex $tokenAddress $actionId
    
    echo "Action info for action id:"
    call ILOVE20Submit $submitAddress actionInfo $tokenAddress $actionId
fi

# Query submit info if submits exist
submitCount=$(call ILOVE20Submit $submitAddress actionSubmitsCount $tokenAddress $round)
if [ "$submitCount" -gt "0" ]; then
    echo "Action submit info at index:"
    call ILOVE20Submit $submitAddress actionSubmitsAtIndex $tokenAddress $round $actionId
    
    echo "Submit info for action id:"
    call ILOVE20Submit $submitAddress submitInfo $tokenAddress $round $actionId
fi

# Query author action ids if author has actions
authorActionCount=$(call ILOVE20Submit $submitAddress authorActionIdsCount $tokenAddress $ACCOUNT_ADDRESS)
if [ "$authorActionCount" -gt "0" ]; then
    echo "Author action id at index:"
    call ILOVE20Submit $submitAddress authorActionIdsAtIndex $tokenAddress $ACCOUNT_ADDRESS $actionId
fi

echo "===================="
echo "Submit Query Complete"
echo "====================" 
