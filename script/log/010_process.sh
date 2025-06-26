# 抓取并转换所有事件日志为CSV格式

# 清除历史文件
if [ -d "$output_dir" ]; then
  echo "📁 Clearing directory: $output_dir"
  rm -rf $output_dir/*
  echo "✅ Directory cleared"
fi

echo ""
echo "🎯 Starting comprehensive event log processing..."
echo "📊 This will fetch raw logs and convert them to CSV format"
echo ""

# launch - 项目启动和众筹
process_event "launch" "DeployToken"
process_event "launch" "Contribute"
process_event "launch" "Withdraw"
process_event "launch" "Claim"
process_event "launch" "SecondHalfStart"
process_event "launch" "LaunchEnd"

# tokenFactory - 代币工厂创建代币
process_event "tokenFactory" "TokenCreate"

# token - 代币操作
process_event "token" "Mint"
process_event "token" "Burn"
process_event "token" "BurnForParentToken"

# slToken - 流动性代币操作
process_event "slToken" "TokenMint"
process_event "slToken" "TokenBurn"
process_event "slToken" "FeeWithdraw"

# stToken - 质押代币操作
process_event "stToken" "TokenMint"
process_event "stToken" "TokenBurn"

# stake - 质押操作
process_event "stake" "StakeLiquidity"
process_event "stake" "StakeToken"
process_event "stake" "Unstake"
process_event "stake" "Withdraw"

# submit - 提交行动提案
process_event "submit" "ActionCreate"
process_event "submit" "ActionSubmit"

# vote - 投票
process_event "vote" "Vote"

# join - 加入行动
process_event "join" "Join"
process_event "join" "Withdraw"
process_event "join" "UpdateVerificationInfo"
process_event "join" "PrepareRandomAccounts"

# verify - 验证
process_event "verify" "Verify"

# mint - 铸造奖励
process_event "mint" "PrepareReward"
process_event "mint" "MintGovReward"
process_event "mint" "MintActionReward"
process_event "mint" "BurnAbstentionActionReward"
process_event "mint" "BurnBoostReward"

# random - 随机数更新（贯穿整个流程）
process_event "random" "RandomSeedUpdate"

# erc20 - ERC20标准事件（代币转账和授权）
process_event "erc20" "Transfer"
process_event "erc20" "Approval"

echo ""
echo "🎉 All event log processing completed!"
echo "📊 Check the output directory for both .event and .csv files:"
echo "   • *.event files contain raw event logs"
echo "   • *.csv files contain structured data ready for analysis"