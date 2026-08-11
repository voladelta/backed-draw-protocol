// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPositionTransferValidator {
    function canTransferPosition(address from, address to, uint256 positionId) external view returns (bool);
}
