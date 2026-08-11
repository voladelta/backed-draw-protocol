// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IPositionTransferValidator } from "../interfaces/IPositionTransferValidator.sol";

contract PositionNFT is ERC721 {
    error OnlyMarket();
    error PositionFrozen(uint256 positionId);
    error TransferNotEligible(address from, address to, uint256 positionId);

    address public immutable market;
    mapping(uint256 positionId => bool frozen) public isFrozen;

    constructor(string memory name_, string memory symbol_, address market_) ERC721(name_, symbol_) {
        market = market_;
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert OnlyMarket();
        _;
    }

    function mint(address to, uint256 positionId) external onlyMarket {
        _safeMint(to, positionId);
    }

    function burn(uint256 positionId) external onlyMarket {
        _burn(positionId);
    }

    function setFrozen(uint256 positionId, bool frozen) external onlyMarket {
        isFrozen[positionId] = frozen;
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = _ownerOf(tokenId);
        if (isFrozen[tokenId] && from != address(0) && to != address(0)) revert PositionFrozen(tokenId);
        if (
            from != address(0) && to != address(0)
                && !IPositionTransferValidator(market).canTransferPosition(from, to, tokenId)
        ) revert TransferNotEligible(from, to, tokenId);
        return super._update(to, tokenId, auth);
    }
}
