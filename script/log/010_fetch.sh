# 抓取所有事件日志

# 清除历史文件
if [ -d "$output_dir" ]; then
  echo "📁 Clearing directory: $output_dir"
  rm -rf $output_dir/*
  echo "✅ Directory cleared"
fi

# launch - 项目启动和众筹
fetch_event_logs "launch" "DeployToken"
fetch_event_logs "launch" "Contribute"
fetch_event_logs "launch" "Withdraw"
fetch_event_logs "launch" "Claim"
fetch_event_logs "launch" "SecondHalfStart"
fetch_event_logs "launch" "LaunchEnd"

# tokenFactory - 代币工厂创建代币
fetch_event_logs "tokenFactory" "TokenCreate"

# token - 代币操作
fetch_event_logs "token" "Mint"
fetch_event_logs "token" "Burn"
fetch_event_logs "token" "BurnForParentToken"

# slToken - 流动性代币操作
fetch_event_logs "slToken" "TokenMint"
fetch_event_logs "slToken" "TokenBurn"
fetch_event_logs "slToken" "FeeWithdraw"

# stToken - 质押代币操作
fetch_event_logs "stToken" "TokenMint"
fetch_event_logs "stToken" "TokenBurn"

# stake - 质押操作
fetch_event_logs "stake" "StakeLiquidity"
fetch_event_logs "stake" "StakeToken"
fetch_event_logs "stake" "Unstake"
fetch_event_logs "stake" "Withdraw"

# submit - 提交行动提案
fetch_event_logs "submit" "ActionCreate"
fetch_event_logs "submit" "ActionSubmit"

# vote - 投票
fetch_event_logs "vote" "Vote"

# join - 加入行动
fetch_event_logs "join" "Join"
fetch_event_logs "join" "Withdraw"
fetch_event_logs "join" "UpdateVerificationInfo"

# verify - 验证
fetch_event_logs "verify" "Verify"

# mint - 铸造奖励
fetch_event_logs "mint" "PrepareReward"
fetch_event_logs "mint" "MintGovReward"
fetch_event_logs "mint" "MintActionReward"
fetch_event_logs "mint" "BurnAbstentionActionReward"
fetch_event_logs "mint" "BurnBoostReward"

# random - 随机数更新（贯穿整个流程）
fetch_event_logs "random" "RandomSeedUpdate"