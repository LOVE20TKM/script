// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
interface ILOVE20SLTokenEvents {
    event TokenMint(address indexed to, uint256 slAmount, uint256 lpAmount);
    event TokenBurn(address indexed to, uint256 slAmount, uint256 lpAmount);
    event FeeWithdraw(address indexed to, uint256 lpAmount);
}

interface ILOVE20SLTokenErrors {
    error NotEligibleToMint();
    error InvalidAddress();
    error NoTokensToBurn();
    error InsufficientLiquidity();
    error TotalLpExceedsBalance();
    error InvalidRatio();
}

interface ILOVE20SLToken is
    IERC20,
    IERC20Metadata,
    ILOVE20SLTokenEvents,
    ILOVE20SLTokenErrors
{
    function minter() external view returns (address);
    function tokenAddress() external view returns (address);
    function parentTokenAddress() external view returns (address);
    function uniswapV2Pair() external view returns (address);
    function MAX_WITHDRAWABLE_TO_FEE_RATIO() external view returns (uint256);

    function mint(address to) external returns (uint256 slAmount);
    function burn(address to) external;
    function withdrawFee(address to) external;

    function tokenAmountsBySlAmount(
        uint256 slAmount
    ) external view returns (uint256 tokenAmount, uint256 parentTokenAmount);

    function tokenAmounts()
        external
        view
        returns (
            uint256 tokenAmount,
            uint256 parentTokenAmount,
            uint256 feeTokenAmount,
            uint256 feeParentTokenAmount
        );
}
