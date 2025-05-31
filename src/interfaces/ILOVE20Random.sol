// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;
import {IPhase} from "./IPhase.sol";

interface ILOVE20RandomEvents {
    event RandomSeedUpdate(
        uint256 indexed round,
        uint256 newRandomSeed,
        uint256 prevRandomSeed,
        address indexed verifierAddress,
        uint256 blockNumber
    );
}

interface ILOVE20RandomErrors {
    error AlreadyInitialized();
    error NotEligible2UpdateRandomSeed();
    error ModifierAddressCannotBeZero();
}

interface ILOVE20Random is IPhase, ILOVE20RandomEvents, ILOVE20RandomErrors {
    function modifierAddress() external view returns (address);
    function prevRandomSeed() external view returns (uint256);
    function initialize(address modifierAddress_) external;
    function updateRandomSeed(
        address verifierAddress
    ) external returns (uint256 newRandomSeed);
    function randomSeed(uint256 round) external view returns (uint256);
}
