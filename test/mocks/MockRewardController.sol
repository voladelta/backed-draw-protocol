// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IRewardController } from "../../contracts/interfaces/IRewardController.sol";

contract MockRewardController is IRewardController {
    mapping(address beneficiary => mapping(address asset => uint256 amount)) public queued;

    function enqueue(address beneficiary, address inputAsset, uint256 inputAmount) external {
        queued[beneficiary][inputAsset] += inputAmount;
    }
}
