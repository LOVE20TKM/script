actionIdSubmit=0
round=$(call ILOVE20Submit $submitAddress currentRound)

echo "===================="
echo "    submit    "
echo "===================="

echo "actionIdSubmit: $actionIdSubmit"

echo "isSubmitted before"
call ILOVE20Submit $submitAddress isSubmitted $tokenAddress $round $actionIdSubmit

echo "submitInfo before"
call ILOVE20Submit $submitAddress submitInfo $tokenAddress $round $actionIdSubmit

echo "submit action $actionIdSubmit"
echo "----------------------------------------"
send ILOVE20Submit $submitAddress submit $tokenAddress $actionIdSubmit
echo "----------------------------------------"

echo "isSubmitted after"
call ILOVE20Submit $submitAddress isSubmitted $tokenAddress $round $actionIdSubmit

echo "submitInfo after"
call ILOVE20Submit $submitAddress submitInfo $tokenAddress $round $actionIdSubmit

next_phase_waiting_blocks $submitAddress