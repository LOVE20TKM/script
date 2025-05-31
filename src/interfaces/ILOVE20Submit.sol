// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {IPhase} from "./IPhase.sol";

struct ActionHead {
    // managed by contract
    uint256 id;
    address author;
    uint256 createAtBlock;
}

struct ActionBody {
    // max token amount for staking
    uint256 minStake;
    // max random accounts for verification
    uint256 maxRandomAccounts;
    // contract must comply with IWhiteList. If not set, all users can join the action.
    address[] whiteList;
    // action info
    string action;
    string consensus;
    string verificationRule;
    // guide for inputting verification info
    string[] verificationKeys;
    string[] verificationInfoGuides;
}

struct ActionInfo {
    ActionHead head;
    ActionBody body;
}

struct ActionSubmitInfo {
    address submitter;
    uint256 actionId;
}
interface ILOVE20SubmitErrors {
    error AlreadyInitialized();
    error CannotSubmitAction();
    error ActionIdNotExist();
    error StartGreaterThanEnd();
    error MinStakeZero();
    error MaxRandomAccountsZero();
    error AlreadySubmitted();
    error OnlyOneSubmitPerRound();
}
interface ILOVE20SubmitEvents {
    // Events
    event ActionCreate(
        address indexed tokenAddress,
        uint256 indexed round,
        address indexed author,
        uint256 actionId,
        ActionBody actionBody
    );

    event ActionSubmit(
        address indexed tokenAddress,
        uint256 indexed round,
        address submitter,
        uint256 indexed actionId
    );
}

interface ILOVE20Submit is ILOVE20SubmitErrors, ILOVE20SubmitEvents, IPhase {
    function stakeAddress() external view returns (address);

    function SUBMIT_MIN_PER_THOUSAND() external view returns (uint256);

    function canSubmit(
        address tokenAddress,
        address accountAddress
    ) external view returns (bool);

    function actionNum(address tokenAddress) external view returns (uint256);
    function submitNewAction(
        address tokenAddress,
        ActionBody calldata actionBody
    ) external returns (uint256 actionId);

    function submit(address tokenAddress, uint256 actionId) external;

    function isSubmitted(
        address tokenAddress,
        uint256 round,
        uint256 actionId
    ) external view returns (bool);

    function isInWhiteList(
        address tokenAddress,
        uint256 actionId,
        address account
    ) external view returns (bool);

    function actionInfo(
        address tokenAddress,
        uint256 actionId
    ) external view returns (ActionInfo memory);

    function actionSubmits(
        address tokenAddress,
        uint256 round
    ) external view returns (ActionSubmitInfo[] memory);

    function actionIdsByAuthor(
        address tokenAddress,
        address author
    ) external view returns (uint256[] memory);

    function actionInfosByIds(
        address tokenAddress,
        uint256[] calldata actionIds
    ) external view returns (ActionInfo[] memory);

    function actionInfosByPage(
        address tokenAddress,
        uint256 start,
        uint256 end,
        bool reverse
    ) external view returns (ActionInfo[] memory);
}
