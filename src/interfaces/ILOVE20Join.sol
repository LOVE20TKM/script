// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.19;

import {IPhase} from "./IPhase.sol";

interface ILOVE20JoinEvents {
    // Events
    event Join(
        address indexed tokenAddress,
        uint256 indexed currentRound,
        uint256 indexed actionId,
        address account,
        uint256 additionalStakeAmount
    );

    event Withdraw(
        address indexed tokenAddress,
        uint256 indexed currentRound,
        uint256 indexed actionId,
        address account,
        uint256 withdrawnAmount
    );

    event UpdateVerificationInfo(
        address indexed tokenAddress,
        address indexed account,
        string indexed verificationKey,
        uint256 round,
        string verificationInfo
    );

    event PrepareRandomAccounts(
        address indexed tokenAddress,
        uint256 indexed round,
        uint256 indexed actionId,
        address[] accounts
    );
}
interface ILOVE20JoinErrors {
    // Custom errors
    error AlreadyInitialized();
    error AddressCannotBeZero();
    error CannotGenerateAtCurrentRound();

    error LastBlocksOfPhaseCannotJoin();
    error ActionNotVoted();
    error InvalidToAddress();
    error AmountIsZero();
    error JoinedAmountIsZero();
    error NotInWhiteList();
    error JoinAmountLessThanMinStake();
}

interface ILOVE20Join is ILOVE20JoinEvents, ILOVE20JoinErrors, IPhase {
    // ------ init ------
    function initialize(
        address submitAddress_,
        address voteAddress_,
        address randomAddress_,
        uint256 joinEndPhaseBlocks
    ) external;

    function submitAddress() external view returns (address);

    function voteAddress() external view returns (address);
    function randomAddress() external view returns (address);

    function JOIN_END_PHASE_BLOCKS() external view returns (uint256);

    // ------ verification info ------
    function updateVerificationInfo(
        address tokenAddress,
        string[] memory verificationKeys,
        string[] memory verificationInfos
    ) external;

    function verificationInfo(
        address tokenAddress,
        address account,
        string calldata verificationKey
    ) external view returns (string memory);

    function verificationInfoByRound(
        address tokenAddress,
        address accountAddress,
        string calldata verificationKey,
        uint256 round
    ) external view returns (string memory);

    // ------ join & withdraw ------
    function join(
        address tokenAddress,
        uint256 actionId,
        uint256 additionalAmount,
        string[] calldata verificationInfos,
        address to
    ) external;

    function withdraw(
        address tokenAddress,
        uint256 actionId
    ) external returns (uint256);

    // ------ random accounts ------
    function prepareRandomAccountsIfNeeded(
        address tokenAddress,
        uint256 actionId
    ) external;

    function randomAccounts(
        address tokenAddress,
        uint256 round,
        uint256 actionId
    ) external view returns (address[] memory);

    function randomAccountsByRandomSeed(
        address tokenAddress,
        uint256 actionId,
        uint256 randomSeed,
        uint256 num
    ) external view returns (address[] memory);

    // ------ joined amount ------

    function amountByActionId(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);

    function amountByActionIdByAccount(
        address tokenAddress,
        uint256 actionId,
        address account
    ) external view returns (uint256);

    function amountByAccount(
        address tokenAddress,
        address account
    ) external view returns (uint256);

    // ------ joined action ids ------
    function actionIdsByAccount(
        address tokenAddress,
        address account
    ) external view returns (uint256[] memory);

    // ------ index & account ------
    function numOfAccounts(
        address tokenAddress,
        uint256 actionId
    ) external view returns (uint256);

    // 1-indexed
    function indexToAccount(
        address tokenAddress,
        uint256 actionId,
        uint256 index
    ) external view returns (address);

    function accountToIndex(
        address tokenAddress,
        uint256 actionId,
        address account
    ) external view returns (uint256);

    function prefixSum(
        address tokenAddress,
        uint256 actionId,
        uint256 index
    ) external view returns (uint256);
}
