// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

interface ILOVE20TokenFactoryErrors {
    error AlreadyInitialized();

    error ZeroAddress(string parameter);

    error EmptyString(string parameter);

    error InvalidAmount();

    error UnauthorizedCaller();
}

interface ILOVE20TokenFactoryEvents {
    event TokenCreate(
        address indexed tokenAddress,
        address indexed parentTokenAddress,
        string name,
        string symbol,
        address indexed to
    );
}

interface ILOVE20TokenFactory is
    ILOVE20TokenFactoryErrors,
    ILOVE20TokenFactoryEvents
{
    function uniswapV2Factory() external view returns (address);

    function launchAddress() external view returns (address);

    function stakeAddress() external view returns (address);

    function mintAddress() external view returns (address);

    function LAUNCH_AMOUNT() external view returns (uint256);

    function MAX_SUPPLY() external view returns (uint256);

    function MAX_WITHDRAWABLE_TO_FEE_RATIO() external view returns (uint256);

    function initialized() external view returns (bool);

    function initialize(
        address uniswapV2Factory_,
        address launchAddress_,
        address stakeAddress_,
        address mintAddress_,
        uint256 launchAmount_,
        uint256 maxSupply_,
        uint256 maxWithdrawableToFeeRatio_
    ) external;

    function createToken(
        address parentTokenAddress,
        string memory name,
        string memory symbol,
        address to
    ) external returns (address tokenAddress);
}
