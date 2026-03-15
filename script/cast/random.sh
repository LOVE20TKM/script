round=$(call ILOVE20Verify $verifyAddress currentRound)

echo "===================="
echo "        random      "
echo "===================="

echo "round: $round"
echo "randomSeed: $(call ILOVE20Random $randomAddress randomSeed $round)"