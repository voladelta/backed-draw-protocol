// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ProtocolTypes } from "../types/ProtocolTypes.sol";

contract PullReceipt is ERC721 {
    error OnlyMarket();
    error ReceiptFrozen(uint256 receiptId);

    address public immutable market;
    mapping(uint256 receiptId => bool frozen) public isFrozen;
    mapping(uint256 receiptId => ProtocolTypes.PullReceiptData data) private _receiptData;

    constructor(string memory name_, string memory symbol_, address market_) ERC721(name_, symbol_) {
        market = market_;
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert OnlyMarket();
        _;
    }

    function mint(address to, uint256 receiptId, ProtocolTypes.PullReceiptData calldata data)
        external
        onlyMarket
    {
        _receiptData[receiptId] = data;
        isFrozen[receiptId] = true;
        _mint(to, receiptId);
    }

    function updateStatus(uint256 receiptId, ProtocolTypes.PullStatus status, bool frozen)
        external
        onlyMarket
    {
        _receiptData[receiptId].status = status;
        isFrozen[receiptId] = frozen;
    }

    function receiptData(uint256 receiptId) external view returns (ProtocolTypes.PullReceiptData memory) {
        return _receiptData[receiptId];
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = _ownerOf(tokenId);
        if (isFrozen[tokenId] && from != address(0) && to != address(0)) revert ReceiptFrozen(tokenId);
        return super._update(to, tokenId, auth);
    }
}
