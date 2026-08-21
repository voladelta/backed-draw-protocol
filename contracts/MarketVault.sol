// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MarketVault is IERC721Receiver {
    using SafeERC20 for IERC20;

    error OnlyMarket();
    error UnsupportedTokenBehavior(uint256 expected, uint256 received);
    error UnexpectedNFT(address collection, uint256 tokenId);
    error OperatorsAlreadySet();

    address public immutable market;
    IERC20 public immutable settlementAsset;
    address public settlementEngine;
    address public epochCoordinator;

    address private _expectedCollection;
    address private _expectedFrom;
    uint256 private _expectedTokenId;
    bool private _acceptingDeposit;

    constructor(address market_, address settlementAsset_) {
        market = market_;
        settlementAsset = IERC20(settlementAsset_);
    }

    modifier onlyMarket() {
        if (msg.sender != market && msg.sender != settlementEngine && msg.sender != epochCoordinator) {
            revert OnlyMarket();
        }
        _;
    }

    function setOperators(address engine, address coordinator) external {
        if (msg.sender != market) revert OnlyMarket();
        if (settlementEngine != address(0) || epochCoordinator != address(0)) revert OperatorsAlreadySet();
        settlementEngine = engine;
        epochCoordinator = coordinator;
    }

    function depositSettlement(address from, uint256 amount) external onlyMarket {
        uint256 beforeBalance = settlementAsset.balanceOf(address(this));
        settlementAsset.safeTransferFrom(from, address(this), amount);
        uint256 received = settlementAsset.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert UnsupportedTokenBehavior(amount, received);
    }

    function releaseSettlement(address to, uint256 amount) external onlyMarket {
        settlementAsset.safeTransfer(to, amount);
    }

    function depositNFT(address from, address collection, uint256 tokenId) external onlyMarket {
        _expectedCollection = collection;
        _expectedFrom = from;
        _expectedTokenId = tokenId;
        _acceptingDeposit = true;
        IERC721(collection).safeTransferFrom(from, address(this), tokenId);
        _acceptingDeposit = false;
        delete _expectedCollection;
        delete _expectedFrom;
        delete _expectedTokenId;
        if (IERC721(collection).ownerOf(tokenId) != address(this)) revert UnexpectedNFT(collection, tokenId);
    }

    function releaseNFT(address to, address collection, uint256 tokenId) external onlyMarket {
        IERC721(collection).safeTransferFrom(address(this), to, tokenId);
    }

    function tryReleaseNFT(address to, address collection, uint256 tokenId)
        external
        onlyMarket
        returns (bool delivered)
    {
        try IERC721(collection).safeTransferFrom(address(this), to, tokenId) {
            delivered = true;
        } catch { }
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata)
        external
        view
        returns (bytes4)
    {
        if (
            !_acceptingDeposit || operator != address(this) || msg.sender != _expectedCollection
                || from != _expectedFrom || tokenId != _expectedTokenId
        ) revert UnexpectedNFT(msg.sender, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
}
