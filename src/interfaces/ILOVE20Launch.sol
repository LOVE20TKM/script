// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface ILOVE20LaunchErrors {
    error AlreadyInitialized();
    error InvalidTokenSymbol();
    error TokenSymbolExists();
    error NotEligibleToDeployToken();
    error LaunchAlreadyEnded();
    error LaunchNotEnded();
    error NoContribution();
    error NotEnoughWaitingBlocks();
    error TokensAlreadyClaimed();
    error LaunchAlreadyExists();
    error ParentTokenNotSet();
    error ZeroContribution();
    error InvalidParentToken();
    error NotEnoughChildTokenWaitingBlocks();
}

interface ILOVE20LaunchEvents {
    event DeployToken(
        address indexed tokenAddress,
        string tokenSymbol,
        address indexed parentTokenAddress,
        address indexed deployer
    );

    event Contribute(
        address indexed tokenAddress,
        address indexed contributor,
        uint256 amount,
        uint256 totalContributed,
        uint256 participantCount
    );

    event Withdraw(
        address indexed tokenAddress,
        address indexed contributor,
        uint256 amount
    );

    event Claim(
        address indexed tokenAddress,
        address indexed claimer,
        uint256 receivedTokenAmount,
        uint256 extraRefund
    );

    event SecondHalfStart(
        address indexed tokenAddress,
        uint256 secondHalfStartBlock,
        uint256 totalContributed
    );

    event LaunchEnd(
        address indexed tokenAddress,
        uint256 totalContributed,
        uint256 participantCount,
        uint256 endBlock
    );
}

interface ILOVE20Launch is ILOVE20LaunchErrors, ILOVE20LaunchEvents {
    struct LaunchInfo {
        address parentTokenAddress;
        uint256 parentTokenFundraisingGoal;
        uint256 secondHalfMinBlocks;
        uint256 launchAmount;
        uint256 startBlock;
        uint256 secondHalfStartBlock;
        bool hasEnded;
        uint256 participantCount;
        uint256 totalContributed;
        uint256 totalExtraRefunded;
    }

    function initialize(
        address tokenFactoryAddress_,
        address submitAddress_,
        address mintAddress_,
        address stakeAddress_,
        uint256 tokenSymbolLength,
        uint256 firstParentTokenFundraisingGoal,
        uint256 parentTokenFundraisingGoal,
        uint256 secondHalfMinBlocks,
        uint256 withdrawWaitingBlocks,
        uint256 childTokenWaitingBlocks
    ) external;

    function deployToken(
        string memory tokenSymbol,
        address parentTokenAddress
    ) external returns (address tokenAddress);

    function contribute(
        address tokenAddress,
        uint256 parentTokenAmount,
        address to
    ) external;

    function withdraw(address tokenAddress) external;

    function claim(
        address tokenAddress
    ) external returns (uint256 receivedTokenAmount, uint256 extraRefund);

    function canDeployToken(
        address accountAddress,
        address parentTokenAddress
    ) external view returns (bool isEligible);

    function launchInfos(
        address[] memory addresses
    ) external view returns (LaunchInfo[] memory launchInfos_);

    function tokenNum() external view returns (uint256 count);

    function tokensByPage(
        uint start,
        uint end,
        bool reverse
    ) external view returns (address[] memory tokens);

    function childTokenNum(
        address parentTokenAddress
    ) external view returns (uint256 count);

    function childTokensByPage(
        address parentTokenAddress,
        uint start,
        uint end,
        bool reverse
    ) external view returns (address[] memory tokens);

    function launchingTokenNum() external view returns (uint256 count);

    function launchingTokensByPage(
        uint start,
        uint end,
        bool reverse
    ) external view returns (address[] memory tokens);

    function launchedTokenNum() external view returns (uint256 count);

    function launchedTokensByPage(
        uint start,
        uint end,
        bool reverse
    ) external view returns (address[] memory tokens);

    function launchingChildTokenNum(
        address parentTokenAddress
    ) external view returns (uint256 count);

    function launchingChildTokensByPage(
        address parentTokenAddress,
        uint start,
        uint end,
        bool reverse
    ) external view returns (address[] memory tokens);

    function launchedChildTokenNum(
        address parentTokenAddress
    ) external view returns (uint256 count);

    function launchedChildTokensByPage(
        address parentTokenAddress,
        uint start,
        uint end,
        bool reverse
    ) external view returns (address[] memory tokens);

    function participatedTokenNum(
        address account
    ) external view returns (uint256 count);

    function participatedTokensByPage(
        address account,
        uint start,
        uint end,
        bool reverse
    ) external view returns (address[] memory tokens);

    function tokenFactoryAddress()
        external
        view
        returns (address factoryAddress);

    function stakeAddress() external view returns (address address_);

    function submitAddress() external view returns (address address_);

    function mintAddress() external view returns (address address_);

    function initialized() external view returns (bool isInitialized);

    function TOKEN_SYMBOL_LENGTH() external view returns (uint256 length);

    function FIRST_PARENT_TOKEN_FUNDRAISING_GOAL()
        external
        view
        returns (uint256 goal);

    function PARENT_TOKEN_FUNDRAISING_GOAL()
        external
        view
        returns (uint256 goal);

    function SECOND_HALF_MIN_BLOCKS() external view returns (uint256 blocks);

    function WITHDRAW_WAITING_BLOCKS() external view returns (uint256 blocks);

    function CHILD_TOKEN_WAITING_BLOCKS()
        external
        view
        returns (uint256 phases);

    function tokenAddresses(
        uint256 index
    ) external view returns (address tokenAddress);

    function tokenAddressBySymbol(
        string memory symbol
    ) external view returns (address tokenAddress);

    function launches(
        address tokenAddress
    ) external view returns (LaunchInfo memory info);

    function contributed(
        address tokenAddress,
        address account
    ) external view returns (uint256 amount);

    function lastContributedBlock(
        address tokenAddress,
        address account
    ) external view returns (uint256 blockNumber);

    function extraRefunded(
        address tokenAddress,
        address account
    ) external view returns (uint256 amount);

    function claimed(
        address tokenAddress,
        address account
    ) external view returns (bool hasClaimed);
}
