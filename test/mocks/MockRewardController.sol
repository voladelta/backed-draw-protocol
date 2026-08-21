// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IRewardController } from "../../contracts/interfaces/IRewardController.sol";

contract MockRewardController is IRewardController {
    error SettlementSwapRejected();

    mapping(address beneficiary => mapping(address asset => uint256 amount)) public queued;
    mapping(address beneficiary => mapping(address asset => uint256 amount)) public settlementInput;
    uint256 public lastMinDrawOut;
    bytes public lastRouteData;
    bool public rejectSettlementSwap;

    function enqueue(address beneficiary, address inputAsset, uint256 inputAmount) external {
        queued[beneficiary][inputAsset] += inputAmount;
    }

    function setRejectSettlementSwap(bool rejected) external {
        rejectSettlementSwap = rejected;
    }

    function swapSettlement(
        address beneficiary,
        address inputAsset,
        uint256 inputAmount,
        uint256 minDrawOut,
        bytes calldata routeData
    ) external returns (uint256 drawAmount) {
        if (rejectSettlementSwap) revert SettlementSwapRejected();
        settlementInput[beneficiary][inputAsset] += inputAmount;
        lastMinDrawOut = minDrawOut;
        lastRouteData = routeData;
        drawAmount = inputAmount;
    }
}
