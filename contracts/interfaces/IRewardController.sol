// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IRewardController {
    function enqueue(address beneficiary, address inputAsset, uint256 inputAmount) external;

    function swapSettlement(
        address beneficiary,
        address inputAsset,
        uint256 inputAmount,
        uint256 minDrawOut,
        bytes calldata routeData
    ) external returns (uint256 drawAmount);
}
