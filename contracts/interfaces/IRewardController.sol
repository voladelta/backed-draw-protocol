// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRewardController {
    function enqueue(address beneficiary, address inputAsset, uint256 inputAmount) external;
}
