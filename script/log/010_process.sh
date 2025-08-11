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
fetch_and_convert "launch" "LaunchToken"
fetch_and_convert "launch" "Contribute"
fetch_and_convert "launch" "Withdraw"
fetch_and_convert "launch" "Claim"
fetch_and_convert "launch" "SecondHalfStart"
fetch_and_convert "launch" "LaunchEnd"

# tokenFactory - 代币工厂创建代币
fetch_and_convert "tokenFactory" "TokenCreate"

# token - 代币操作
fetch_and_convert "token" "TokenMint"
fetch_and_convert "token" "TokenBurn"
fetch_and_convert "token" "BurnForParentToken"

# slToken - 流动性代币操作
fetch_and_convert "slToken" "TokenMint"
fetch_and_convert "slToken" "TokenBurn"
fetch_and_convert "slToken" "WithdrawFee"

# stToken - 质押代币操作
fetch_and_convert "stToken" "TokenMint"
fetch_and_convert "stToken" "TokenBurn"

# stake - 质押操作
fetch_and_convert "stake" "StakeLiquidity"
fetch_and_convert "stake" "StakeToken"
fetch_and_convert "stake" "Unstake"
fetch_and_convert "stake" "Withdraw"

# submit - 提交行动提案
fetch_and_convert "submit" "ActionCreate"
fetch_and_convert "submit" "ActionSubmit"

# vote - 投票
fetch_and_convert "vote" "Vote"

# join - 加入行动
fetch_and_convert "join" "Join"
fetch_and_convert "join" "Withdraw"
fetch_and_convert "join" "UpdateVerificationInfo"
fetch_and_convert "join" "PrepareRandomAccounts"

# verify - 验证
fetch_and_convert "verify" "Verify"

# mint - 铸造奖励
fetch_and_convert "mint" "PrepareReward"
fetch_and_convert "mint" "MintGovReward"
fetch_and_convert "mint" "MintActionReward"
fetch_and_convert "mint" "BurnActionReward"
fetch_and_convert "mint" "BurnBoostReward"

# random - 随机数更新（贯穿整个流程）
fetch_and_convert "random" "UpdateRandomSeed"

# erc20 - ERC20标准事件（代币转账和授权）
fetch_and_convert "erc20" "Transfer"
fetch_and_convert "erc20" "Approval"

# uniswapV2Factory - UniswapV2工厂合约事件（创建交易对）
fetch_and_convert "uniswapV2Factory" "PairCreated"

# # uniswapV2Pair - UniswapV2交易对合约事件（交易对创建和交易）
# process_pair_event $tokenAddress $rootParentTokenAddress "Transfer"
# process_pair_event $tokenAddress $rootParentTokenAddress "Sync"
# process_pair_event $tokenAddress $rootParentTokenAddress "Mint"
# process_pair_event $tokenAddress $rootParentTokenAddress "Burn"
# process_pair_event $tokenAddress $rootParentTokenAddress "Swap"

echo ""
echo "🎉 All event log processing completed!"
echo "📊 Check the output directory for both .event and .csv files:"
echo "   • *.event files contain raw event logs"
echo "   • *.csv files contain structured data ready for analysis"