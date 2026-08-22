// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IRewardController } from "../../contracts/interfaces/IRewardController.sol";

contract MockRewardController is IRewardController {
    error EnqueueRejected();
    error SettlementSwapRejected();

    mapping(address beneficiary => mapping(address asset => uint256 amount)) public queued;
    mapping(address beneficiary => mapping(address asset => uint256 amount)) public settlementInput;
    uint256 public lastMinDrawOut;
    bytes public lastRouteData;
    bool public rejectSettlementSwap;
    bool public rejectEnqueue;
    bool public ignoreEnqueue;

    function enqueue(address beneficiary, address inputAsset, uint256 inputAmount) external {
        if (rejectEnqueue) revert EnqueueRejected();
        if (ignoreEnqueue) return;
        queued[beneficiary][inputAsset] += inputAmount;
    }

    function queuedInput(address beneficiary, address inputAsset) external view returns (uint256) {
        return queued[beneficiary][inputAsset];
    }

    function setRejectEnqueue(bool rejected) external {
        rejectEnqueue = rejected;
    }

    function setIgnoreEnqueue(bool ignored) external {
        ignoreEnqueue = ignored;
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
