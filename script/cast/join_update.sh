#actionId=0
#round=100
#verificationKey="default"
#verificationInfo="verification info"
verificationKeys="[\"$verificationKey\"]"
verificationInfos="[\"updated verificationInfo\"]"

echo "===================="
echo "     join_update    "
echo "===================="

echo "actionId: $actionId"
echo "round: $round"
echo "verificationKey: $verificationKey"

echo "verificationInfo before"
call ILOVE20Join $joinAddress verificationInfo $tokenAddress $ACCOUNT_ADDRESS $actionId $verificationKey


# Update verification information
echo "updateVerificationInfo"
echo "----------------------------------------"
send ILOVE20Join $joinAddress updateVerificationInfo $tokenAddress $actionId $verificationKeys $verificationInfos
echo "----------------------------------------"

echo "verificationInfo after"
call ILOVE20Join $joinAddress verificationInfo $tokenAddress $ACCOUNT_ADDRESS $actionId $verificationKey