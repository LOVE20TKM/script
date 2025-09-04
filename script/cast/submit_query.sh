#!/bin/bash

# if round is 0 then set round to current round
if [ "$round" -eq "0" ]; then
    round=$(cast_call $submitAddress "currentRound()(uint256)")
fi

echo "===================="
echo "    submit_query     "
echo "===================="

# ------ Read Functions ------

echo "Stake address:"
cast_call $submitAddress "stakeAddress()(address)"

echo "Submit min per thousand:"
cast_call $submitAddress "SUBMIT_MIN_PER_THOUSAND()(uint256)"

echo "Max verification key length:"
cast_call $submitAddress "MAX_VERIFICATION_KEY_LENGTH()(uint256)"

echo "Current round:"
cast_call $submitAddress "currentRound()(uint256)"

echo "Phase blocks:"
cast_call $submitAddress "phaseBlocks()(uint256)"

echo "Origin blocks:"
cast_call $submitAddress "originBlocks()(uint256)"

echo "Initialized:"
cast_call $submitAddress "initialized()(bool)"

echo "Actions count for token:"
cast_call $submitAddress "actionsCount(address)(uint256)" $tokenAddress

echo "Can submit for current account:"
cast_call $submitAddress "canSubmit(address,address)(bool)" $tokenAddress $ACCOUNT_ADDRESS

echo "Is submitted for token:"
cast_call $submitAddress "isSubmitted(address,uint256,uint256)(bool)" $tokenAddress $round $actionId

echo "Can join for current account action:"
cast_call $submitAddress "canJoin(address,uint256,address)(bool)" $tokenAddress $actionId $ACCOUNT_ADDRESS

echo "Action submits count for token:"
cast_call $submitAddress "actionSubmitsCount(address,uint256)(uint256)" $tokenAddress $round

echo "Author action ids count for current account:"
cast_call $submitAddress "authorActionIdsCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS

# Query action info if actions exist
actionCount=$(cast_call $submitAddress "actionsCount(address)(uint256)" $tokenAddress)
if [ "$actionCount" -gt "0" ]; then
    echo "Action info at index:"
    cast_call $submitAddress "actionsAtIndex(address,uint256)(tuple(tuple(uint256,address,uint256),tuple(uint256,uint256,address,string,string,string[],string[])))" $tokenAddress $actionId
    
    echo "Action info for action id:"
    cast_call $submitAddress "actionInfo(address,uint256)(tuple(tuple(uint256,address,uint256),tuple(uint256,uint256,address,string,string,string[],string[])))" $tokenAddress $actionId
fi

# Query submit info if submits exist
submitCount=$(cast_call $submitAddress "actionSubmitsCount(address,uint256)(uint256)" $tokenAddress $round)
if [ "$submitCount" -gt "0" ]; then
    echo "Action submit info at index:"
    cast_call $submitAddress "actionSubmitsAtIndex(address,uint256,uint256)((address,uint256))" $tokenAddress $round $actionId
    
    echo "Submit info for action id:"
    cast_call $submitAddress "submitInfo(address,uint256,uint256)((address,uint256))" $tokenAddress $round $actionId
fi

# Query author action ids if author has actions
authorActionCount=$(cast_call $submitAddress "authorActionIdsCount(address,address)(uint256)" $tokenAddress $ACCOUNT_ADDRESS)
if [ "$authorActionCount" -gt "0" ]; then
    echo "Author action id at index:"
    cast_call $submitAddress "authorActionIdsAtIndex(address,address,uint256)(uint256)" $tokenAddress $ACCOUNT_ADDRESS $actionId
fi

echo "===================="
echo "Submit Query Complete"
echo "====================" 