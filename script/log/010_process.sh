# 清除CSV/XLSX输出文件（保留db目录）
if [ -d "$output_dir" ]; then
  echo "📁 Clearing CSV/XLSX files in: $output_dir"
  rm -f $output_dir/*.csv $output_dir/*.xlsx $output_dir/*.event
  echo "✅ Output files cleared"
fi

echo ""
echo "🎯 Starting incremental event log processing..."
echo "📊 This will fetch new logs since last sync and export to CSV/XLSX"
echo ""

# launch - 项目启动和众筹
fetch_and_convert "launch" "LaunchToken"
  # Topic: 0x4923528950c404c138bdd8625228bbd379f3963a9a6f54f41fea23680470b6b8 (LaunchToken(address,string,address,address))

fetch_and_convert "launch" "Contribute"
  # Topic: 0x003a002894ca2620295e71671a091bbc1a3c6a3c14c80812024a552f26aca809 (Contribute(address,address,uint256,uint256,uint256))

fetch_and_convert "launch" "Withdraw"
  # Topic: 0x33c228f6d123fce4988a7f7e8bc6bd78b5cde4b31de6f171599eb73df1129d2c (Withdraw(address,uint256,address,uint256,uint256,uint256,uint256,uint256))

fetch_and_convert "launch" "Claim"
  # Topic: 0x865ca08d59f5cb456e85cd2f7ef63664ea4f73327414e9d8152c4158b0e94645 (Claim(address,address,uint256,uint256))

fetch_and_convert "launch" "SecondHalfStart"
  # Topic: 0x87c631bf98ca55bf60b33a8463f37bd1b9039f3ccbdf980910057eac2ff07fb9 (SecondHalfStart(address,uint256,uint256))

fetch_and_convert "launch" "LaunchEnd"
  # Topic: 0x7d51a6b28c644edd635f534b373ac3e437432b8fb158e0581ef829b9d164eb4e (LaunchEnd(address,uint256,uint256,uint256))


# tokenFactory - 代币工厂创建代币
fetch_and_convert "tokenFactory" "TokenCreate"
  # Topic: 0x5d7dd57fab91e2cf4bd1d7fb901a4e4b230789b1b952b8da25418cfd50cb97b6 (TokenCreate(address,address,string,string))


# token - 代币操作
fetch_and_convert "token" "TokenMint"
  # Topic: 0x36bf5aa3964be01dbd95a0154a8930793fe68353bdc580871ffb2c911366bbc7 (TokenMint(address,uint256))

fetch_and_convert "token" "TokenBurn"
  # Topic: 0xab85194d35c4ea153d0b51f3a304d1d22cb8023e499a6503fb6c28c5864ae90e (TokenBurn(address,uint256))

fetch_and_convert "token" "BurnForParentToken"
  # Topic: 0x33051b7b99352b2f771717639e25e4bf8dc930b1d6f8530cdc36d0fad8a922d5 (BurnForParentToken(address,uint256,uint256))


# slToken - 流动性代币操作
fetch_and_convert "slToken" "TokenMint"
fetch_and_convert "slToken" "TokenBurn"
fetch_and_convert "slToken" "WithdrawFee"
  # Topic: 0x66c5250772d453a9d1a98e03b718d4c68e88eb5a5cf6a5d530be91fd4e01085b (WithdrawFee(address,uint256,uint256,uint256,uint256,uint256))


# stToken - 质押代币操作
fetch_and_convert "stToken" "TokenMint"
fetch_and_convert "stToken" "TokenBurn"

# stake - 质押操作
fetch_and_convert "stake" "StakeLiquidity"
  # Topic: 0x056566edf8d057d3cc5e020474c0afb6ae4883dc8361722db1dd79e510c33518 (StakeLiquidity(address,uint256,address,uint256,uint256,uint256,uint256,uint256,uint256,uint256))

fetch_and_convert "stake" "StakeToken"
  # Topic: 0x1934107c15c038151a1e59cc446e6cf10b60967de3f796c8bac9ee673c866aa2 (StakeToken(address,uint256,address,uint256,uint256,uint256,uint256,uint256))

fetch_and_convert "stake" "Unstake"
  # Topic: 0x108b92088a71bee20d3a80081f73cc78d067bc26dd14d7a04593a5d6a2c85135 (Unstake(address,uint256,address,uint256,uint256,uint256,uint256))

fetch_and_convert "stake" "Withdraw"

# submit - 提交行动提案
fetch_and_convert "submit" "ActionCreate"
  # Topic: 0xdc2fcbcf6e1dfff7389fe51c48dbf29e6c9f6e16b566606d792ca581b8b56dbd (ActionCreate(address,uint256,address,uint256,tuple))

fetch_and_convert "submit" "ActionSubmit"
  # Topic: 0x2ff46b28cd16740b4bb431c556195ba7ee859036ed04f912596d87a5b183ef01 (ActionSubmit(address,uint256,address,uint256))


# vote - 投票
fetch_and_convert "vote" "Vote"
  # Topic: 0x6c17a8756560e46a88d1a56b2b590b6bfda147e871aef072d48b98b15fed0190 (Vote(address,uint256,address,uint256,uint256))


# join - 加入行动
fetch_and_convert "join" "Join"
  # Topic: 0xe37fea01e65dea7d589abafc4bd0d5282a09ddce3e9ea971ed3399d776a1a296 (Join(address,uint256,uint256,address,uint256))

fetch_and_convert "join" "Withdraw"
fetch_and_convert "join" "UpdateVerificationInfo"
  # Topic: 0xff176c339295def81410968806a88c81984ef8dfe1672fe908b3d6f236c615fb (UpdateVerificationInfo(address,address,uint256,string,uint256,string))

fetch_and_convert "join" "PrepareRandomAccounts"
  # Topic: 0x4c3fd86a7f7f6af84d13a177aa8885d020b91a4bdc96c663661dba824d7bda5b (PrepareRandomAccounts(address,uint256,uint256,address[]))


# verify - 验证
fetch_and_convert "verify" "Verify"
  # Topic: 0xd7dc37ae32c2d2ca3224a6e9e869016b03c8bd5641b74c29d39536e4769af955 (Verify(address,uint256,address,uint256,uint256,uint256[]))


# mint - 铸造奖励
fetch_and_convert "mint" "PrepareReward"
  # Topic: 0x927c129ccca74ea3ce1fe2e23c516905cefd743b3720a39cece9b85d7af2c792 (PrepareReward(address,uint256,uint256,uint256))

fetch_and_convert "mint" "MintGovReward"
  # Topic: 0xe1f6d49001858e00e07a7b319093ad95741f7db8b714ffdc8be5ceed8d02d07e (MintGovReward(address,uint256,address,uint256,uint256,uint256))

fetch_and_convert "mint" "MintActionReward"
  # Topic: 0x120fa5956f98e84e02afa17d313655f548292531d6bb26b5efcd9ca5997003bf (MintActionReward(address,uint256,uint256,address,uint256))

fetch_and_convert "mint" "BurnActionReward"
  # Topic: 0x84876f59d125f6bc865d23eb05d04b0bcdd836786c8bf902a715875845e6fa63 (BurnActionReward(address,uint256,uint256))

fetch_and_convert "mint" "BurnBoostReward"
  # Topic: 0xa515936692cbf03079e834f2d21c7f754d9fb58493fd39721bcdcb945851b5f7 (BurnBoostReward(address,uint256,uint256))


# random - 随机数更新（贯穿整个流程）
fetch_and_convert "random" "UpdateRandomSeed"
  # Topic: 0xea1b99131ca79df127faa5c4d9a55dd791329864188b9d825029de6153ec2328 (UpdateRandomSeed(uint256,uint256,uint256,address,uint256))


# erc20 - ERC20标准事件（代币转账和授权）
fetch_and_convert "erc20" "Transfer"
  # Topic: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef (Transfer(address,address,uint256))

fetch_and_convert "erc20" "Approval"
  # Topic: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925 (Approval(address,address,uint256))

fetch_and_convert "TUSDT" "Transfer"
fetch_and_convert "TUSDT" "Approval"


# uniswapV2Factory - UniswapV2工厂合约事件（创建交易对）
fetch_and_convert "uniswapV2Factory" "PairCreated"
  # Topic: 0x0d3648bd0f6ba80134a33ba9275ac585d9d315f0ad8355cddefde31afa28d0e9 (PairCreated(address,address,address,uint256))


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