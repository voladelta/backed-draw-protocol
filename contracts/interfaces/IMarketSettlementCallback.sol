// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMarketSettlementCallback {
    function finalizeSelectedPosition(uint256 positionId) external;

    function relistFromSettlement(
        address payer,
        address owner,
        address collection,
        uint256 tokenId,
        uint128 backing,
        address earningsRecipient
    ) external returns (uint256 positionId);
}
