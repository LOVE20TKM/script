newActionId=$(cast_call $submitAddress "actionsCount(address)(uint256)" $tokenAddress)

minStake=10
maxRandomAccounts=3
whiteListAddress='0x0000000000000000000000000000000000000000'
action="action${newActionId}"
verificationRule="verify whatever you want"
verificationKeys='["default"]'
verificationInfoGuides='["your account link on xxxscan"]'

echo "===================="
echo "  submit_new_action "
echo "===================="

echo "newActionId: $newActionId"
echo "minStake: $minStake"
echo "maxRandomAccounts: $maxRandomAccounts"
echo "whiteListAddress: $whiteListAddress"
echo "action: $action"
echo "verificationRule: $verificationRule"
echo "verificationKeys: $verificationKeys"


echo "action count before"
cast_call $submitAddress "actionsCount(address)(uint256)" $tokenAddress


echo "Submit new action"
echo "----------------------------------------"
cast_send $submitAddress "submitNewAction(address,(uint256,uint256,address,string,string,string[],string[]))" \
$tokenAddress \
"($minStake,$maxRandomAccounts,$whiteListAddress,$action,$verificationRule,$verificationKeys,$verificationInfoGuides)"
echo "----------------------------------------"

echo "action count after"
actionNum=$(cast_call $submitAddress "actionsCount(address)(uint256)" $tokenAddress)
echo "actionNum: $actionNum"


actionId=$(($actionNum - 1))
echo "actionId: $actionId"

action_info $actionId

next_phase_waiting_blocks $submitAddress