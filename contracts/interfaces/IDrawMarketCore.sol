// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IDrawMarketCore {
    function activePositionCount() external view returns (uint32);
    function currentPullPrice() external view returns (uint256);
    function canPullUser(address user) external view returns (bool);
    function epochBoundaryPending() external view returns (bool);
    function lockEpoch() external returns (uint32 activeCount, uint256 totalWeight, bytes32 treeRoot);
    function unlockEpoch() external;
    function processEpochBoundary(uint32 maxPositions) external returns (uint32 processed, bool complete);
    function resolveDraw(
        uint256 epochId,
        address buyer,
        address receiver,
        uint128 chargedPrice,
        address referrer,
        uint256 randomValue
    ) external returns (uint256 receiptId, uint256 positionId, uint128 backing);
}
