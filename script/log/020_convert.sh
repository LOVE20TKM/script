# 将所有事件日志转换为csv文件

# launch - 项目启动和众筹
convert_event_logs "launch" "DeployToken"
convert_event_logs "launch" "Contribute"
convert_event_logs "launch" "Withdraw"
convert_event_logs "launch" "Claim"
convert_event_logs "launch" "SecondHalfStart"
convert_event_logs "launch" "LaunchEnd"

# tokenFactory - 代币工厂创建代币
convert_event_logs "tokenFactory" "TokenCreate"

# token - 代币操作
convert_event_logs "token" "Mint"
convert_event_logs "token" "Burn"
convert_event_logs "token" "BurnForParentToken"

# slToken - 流动性代币操作
convert_event_logs "slToken" "TokenMint"
convert_event_logs "slToken" "TokenBurn"
convert_event_logs "slToken" "FeeWithdraw"

# stToken - 质押代币操作
convert_event_logs "stToken" "TokenMint"
convert_event_logs "stToken" "TokenBurn"

# stake - 质押操作
convert_event_logs "stake" "StakeLiquidity"
convert_event_logs "stake" "StakeToken"
convert_event_logs "stake" "Unstake"
convert_event_logs "stake" "Withdraw"

# submit - 提交行动提案
convert_event_logs "submit" "ActionCreate"
convert_event_logs "submit" "ActionSubmit"

# vote - 投票
convert_event_logs "vote" "Vote"

# join - 加入行动
convert_event_logs "join" "Join"
convert_event_logs "join" "Withdraw"
convert_event_logs "join" "UpdateVerificationInfo"

# verify - 验证
convert_event_logs "verify" "Verify"

# mint - 铸造奖励
convert_event_logs "mint" "PrepareReward"
convert_event_logs "mint" "MintGovReward"
convert_event_logs "mint" "MintActionReward"
convert_event_logs "mint" "BurnAbstentionActionReward"
convert_event_logs "mint" "BurnBoostReward"

# random - 随机数更新（贯穿整个流程）
convert_event_logs "random" "RandomSeedUpdate"









