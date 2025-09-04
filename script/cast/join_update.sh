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
cast_call $joinAddress "verificationInfo(address,address,uint256,string)(string)" $tokenAddress $ACCOUNT_ADDRESS $actionId $verificationKey


# Update verification information
echo "updateVerificationInfo"
echo "----------------------------------------"
cast_send $joinAddress "updateVerificationInfo(address,uint256,string[],string[])" $tokenAddress $actionId $verificationKeys $verificationInfos
echo "----------------------------------------"

echo "verificationInfo after"
cast_call $joinAddress "verificationInfo(address,address,uint256,string)(string)" $tokenAddress $ACCOUNT_ADDRESS $actionId $verificationKey