// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IEligibilityPolicy {
    function canDeposit(address user, uint256 marketId) external view returns (bool);
    function canPull(address user, uint256 marketId) external view returns (bool);
    function canReceive(address user, uint256 positionId) external view returns (bool);
}
