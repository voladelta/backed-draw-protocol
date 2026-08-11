// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ProtocolTypes } from "../types/ProtocolTypes.sol";

interface IDrawMarket {
    function settlementAsset() external view returns (address);
    function vault() external view returns (address);
    function epochCoordinator() external view returns (address);
}

interface IEpochCoordinator {
    function requestPullFor(address payer, address buyer, ProtocolTypes.PullOrderInput calldata input)
        external
        returns (uint256 orderIndex);
}
