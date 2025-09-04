actionIdSubmit=0
round=$(cast_call $submitAddress "currentRound()(uint256)")

echo "===================="
echo "    submit    "
echo "===================="

echo "actionIdSubmit: $actionIdSubmit"

echo "isSubmitted before"
cast_call $submitAddress "isSubmitted(address,uint256,uint256)(bool)" $tokenAddress $round $actionIdSubmit

echo "submitInfo before"
cast_call $submitAddress "submitInfo(address,uint256,uint256)((address,uint256))" $tokenAddress $round $actionIdSubmit

echo "submit action $actionIdSubmit"
echo "----------------------------------------"
cast_send $submitAddress "submit(address,uint256)" $tokenAddress $actionIdSubmit
echo "----------------------------------------"

echo "isSubmitted after"
cast_call $submitAddress "isSubmitted(address,uint256,uint256)(bool)" $tokenAddress $round $actionIdSubmit

echo "submitInfo after"
cast_call $submitAddress "submitInfo(address,uint256,uint256)((address,uint256))" $tokenAddress $round $actionIdSubmit

next_phase_waiting_blocks $submitAddress