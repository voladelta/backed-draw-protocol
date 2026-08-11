// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IReferralRegistry {
    function bindFromMarket(address user, bytes32 code) external returns (address referrer);
    function resolve(address user, bytes32 suppliedCode) external view returns (address referrer);
}
