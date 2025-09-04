round=$(cast_call $verifyAddress "currentRound()(uint256)")

echo "===================="
echo "        random      "
echo "===================="

echo "round: $round"
echo "randomSeed: $(cast_call $randomAddress "randomSeed(uint256)" $round)"