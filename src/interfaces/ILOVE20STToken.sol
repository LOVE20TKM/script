// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ILOVE20STTokenErrors {
    error NotEligibleToMint();
    error InvalidAddress();
    error AmountIsGreaterThanReserve();
}

interface ILOVE20STToken is IERC20, IERC20Metadata, ILOVE20STTokenErrors {
    function minter() external view returns (address);

    function tokenAddress() external view returns (address);

    function reserve() external view returns (uint256);

    function mint(address to) external;

    function burn(address to) external;
}
