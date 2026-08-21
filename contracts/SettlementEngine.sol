// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MarketVault } from "./MarketVault.sol";
import { PullReceipt } from "./tokens/PullReceipt.sol";
import { ProtocolTypes } from "./types/ProtocolTypes.sol";
import { IRewardController } from "./interfaces/IRewardController.sol";
import { IMarketSettlementCallback } from "./interfaces/IMarketSettlementCallback.sol";

contract SettlementEngine is ReentrancyGuard {
    error OnlyMarket();
    error OnlyGovernor();
    error InvalidReceipt();
    error NotReceiptOwner();
    error DeadlineExpired();
    error DecisionWindowActive();
    error InvalidBacking(uint256 backing);
    error NothingToClaim();
    error NotNFTClaimOwner();
    error InvalidNFTClaimReceiver();
    error InvalidSettlementClaimReceiver();
    error NFTClaimAlreadyExists();
    error SolvencyInvariantBroken(uint256 assets, uint256 liabilities);

    uint256 public constant BPS = 10_000;
    uint256 public constant KEEP_PAYOUT_BPS = 9_900;
    uint256 public constant CASH_PAYOUT_BPS = 8_500;

    struct SelectedPosition {
        address collection;
        uint256 tokenId;
        address previousOwner;
        address earningsRecipient;
        uint128 backing;
        uint256 cashEarnings;
        uint256 rewardInput;
    }

    address public immutable market;
    uint256 public immutable marketId;
    address public immutable settlementAsset;
    address public immutable governor;
    address public immutable treasury;
    address public immutable insuranceReserve;
    address public immutable buybackReceiver;
    uint128 public immutable minBacking;
    uint128 public immutable maxBacking;
    uint32 public immutable decisionWindow;
    MarketVault public immutable vault;
    IRewardController public immutable rewardController;
    PullReceipt public immutable pullReceipt;

    uint256 public nextReceiptId = 1;
    mapping(uint256 receiptId => SelectedPosition position) public selectedPositions;
    mapping(uint256 receiptId => address referrer) public receiptReferrer;
    mapping(address referrer => uint256 amount) public referralClaims;
    mapping(address account => uint256 amount) public settlementClaims;
    mapping(address collection => mapping(uint256 tokenId => address owner)) public pendingNFTClaims;

    uint256 public selectedBackingLiability;
    uint256 public earningsLiability;
    uint256 public rewardInputLiability;
    uint256 public referralLiability;
    uint256 public securityLiability;
    uint256 public buybackLiability;
    uint256 public protocolLiability;
    uint256 public settlementClaimLiability;

    event SelectionRegistered(
        uint256 indexed receiptId, uint256 indexed positionId, address indexed buyer, uint256 backing
    );
    event ReceiptSettled(
        uint256 indexed receiptId, uint256 indexed positionId, ProtocolTypes.SettlementChoice choice
    );
    event NFTDeliveryDeferred(
        address indexed collection, uint256 indexed tokenId, address indexed claimOwner
    );
    event NFTClaimed(
        address indexed collection, uint256 indexed tokenId, address indexed claimOwner, address receiver
    );
    event SettlementPayoutAccrued(address indexed claimOwner, uint256 amount);
    event SettlementPayoutClaimed(address indexed claimOwner, address indexed receiver, uint256 amount);

    constructor(
        address market_,
        uint256 marketId_,
        address settlementAsset_,
        address governor_,
        address treasury_,
        address insuranceReserve_,
        address buybackReceiver_,
        address vault_,
        address rewardController_,
        uint128 minBacking_,
        uint128 maxBacking_,
        uint32 decisionWindow_
    ) {
        market = market_;
        marketId = marketId_;
        settlementAsset = settlementAsset_;
        governor = governor_;
        treasury = treasury_;
        insuranceReserve = insuranceReserve_;
        buybackReceiver = buybackReceiver_;
        vault = MarketVault(vault_);
        rewardController = IRewardController(rewardController_);
        minBacking = minBacking_;
        maxBacking = maxBacking_;
        decisionWindow = decisionWindow_;
        pullReceipt = new PullReceipt("Backed Pull Receipt", "BKPULL", address(this));
    }

    modifier onlyMarket() {
        if (msg.sender != market) revert OnlyMarket();
        _;
    }

    function registerSelection(
        uint256 epochId,
        uint256 positionId,
        address buyer,
        address receiver,
        address collection,
        uint256 tokenId,
        address previousOwner,
        address earningsRecipient,
        uint128 chargedPrice,
        uint128 backing,
        uint256 cashEarnings,
        uint256 rewardInput,
        address referrer
    ) external onlyMarket returns (uint256 receiptId) {
        receiptId = nextReceiptId++;
        selectedPositions[receiptId] = SelectedPosition({
            collection: collection,
            tokenId: tokenId,
            previousOwner: previousOwner,
            earningsRecipient: earningsRecipient,
            backing: backing,
            cashEarnings: cashEarnings,
            rewardInput: rewardInput
        });
        receiptReferrer[receiptId] = referrer;
        selectedBackingLiability += backing;
        earningsLiability += cashEarnings;
        rewardInputLiability += rewardInput;
        ProtocolTypes.PullReceiptData memory data = ProtocolTypes.PullReceiptData({
            marketId: marketId,
            epochId: epochId,
            positionId: positionId,
            originalBuyer: buyer,
            receiver: receiver,
            chargedPrice: chargedPrice,
            selectedBacking: backing,
            revealedAt: uint48(block.timestamp),
            decisionDeadline: uint48(block.timestamp + decisionWindow),
            status: ProtocolTypes.PullStatus.Revealed
        });
        pullReceipt.mint(receiver, receiptId, data);
        emit SelectionRegistered(receiptId, positionId, buyer, backing);
    }

    function settleKeep(uint256 receiptId) external nonReentrant {
        ProtocolTypes.PullReceiptData memory data = _requireReceiptOwner(receiptId);
        _settleKeep(receiptId, data, msg.sender);
    }

    function forceKeep(uint256 receiptId) external nonReentrant {
        ProtocolTypes.PullReceiptData memory data = pullReceipt.receiptData(receiptId);
        if (data.status != ProtocolTypes.PullStatus.Revealed) revert InvalidReceipt();
        if (block.timestamp <= data.decisionDeadline) revert DecisionWindowActive();
        _settleKeep(receiptId, data, pullReceipt.ownerOf(receiptId));
    }

    function settleCash(uint256 receiptId) external nonReentrant {
        ProtocolTypes.PullReceiptData memory data = _requireReceiptOwner(receiptId);
        SelectedPosition memory position = selectedPositions[receiptId];
        _markSettled(receiptId, data.positionId, ProtocolTypes.SettlementChoice.Cash);
        uint256 buyerPayout = uint256(position.backing) * CASH_PAYOUT_BPS / BPS;
        selectedBackingLiability -= position.backing;
        _allocateSettlementRevenue(uint256(position.backing) - buyerPayout, receiptReferrer[receiptId]);
        _accrueSettlementClaim(msg.sender, buyerPayout);
        _consumeEarnings(position);
        delete selectedPositions[receiptId];
        IMarketSettlementCallback(market).finalizeSelectedPosition(data.positionId);
        _fundRewardInput(position);
        _deliverOrDeferNFT(position.previousOwner, position.collection, position.tokenId);
        _assertSolvent();
    }

    function settleDraw(uint256 receiptId, uint256 minDrawOut, bytes calldata routeData)
        external
        nonReentrant
        returns (uint256 drawAmount)
    {
        ProtocolTypes.PullReceiptData memory data = _requireReceiptOwner(receiptId);
        SelectedPosition memory position = selectedPositions[receiptId];
        _markSettled(receiptId, data.positionId, ProtocolTypes.SettlementChoice.Draw);
        uint256 rewardAmount = uint256(position.backing) * CASH_PAYOUT_BPS / BPS;
        selectedBackingLiability -= position.backing;
        _allocateSettlementRevenue(uint256(position.backing) - rewardAmount, receiptReferrer[receiptId]);
        _consumeEarnings(position);
        delete selectedPositions[receiptId];
        IMarketSettlementCallback(market).finalizeSelectedPosition(data.positionId);
        _fundRewardInput(position);
        vault.releaseSettlement(address(rewardController), rewardAmount);
        drawAmount = rewardController.swapSettlement(
            msg.sender, settlementAsset, rewardAmount, minDrawOut, routeData
        );
        _deliverOrDeferNFT(position.previousOwner, position.collection, position.tokenId);
        _assertSolvent();
    }

    function settleRelist(uint256 receiptId, uint128 newBacking)
        external
        nonReentrant
        returns (uint256 positionId)
    {
        if (newBacking < minBacking || newBacking > maxBacking) {
            revert InvalidBacking(newBacking);
        }
        ProtocolTypes.PullReceiptData memory data = _requireReceiptOwner(receiptId);
        SelectedPosition memory position = selectedPositions[receiptId];
        _markSettled(receiptId, data.positionId, ProtocolTypes.SettlementChoice.Relist);
        uint256 ownerPayout = uint256(position.backing) * KEEP_PAYOUT_BPS / BPS;
        selectedBackingLiability -= position.backing;
        _allocateSettlementRevenue(uint256(position.backing) - ownerPayout, receiptReferrer[receiptId]);
        _accrueSettlementClaim(position.previousOwner, ownerPayout);
        _consumeEarnings(position);
        delete selectedPositions[receiptId];
        IMarketSettlementCallback(market).finalizeSelectedPosition(data.positionId);
        _fundRewardInput(position);
        positionId = IMarketSettlementCallback(market)
            .relistFromSettlement(
                msg.sender, msg.sender, position.collection, position.tokenId, newBacking, msg.sender
            );
        _assertSolvent();
    }

    function claimSettlement(address receiver) external nonReentrant {
        if (receiver == address(0)) revert InvalidSettlementClaimReceiver();
        uint256 amount = settlementClaims[msg.sender];
        if (amount == 0) revert NothingToClaim();
        settlementClaims[msg.sender] = 0;
        settlementClaimLiability -= amount;
        vault.releaseSettlement(receiver, amount);
        emit SettlementPayoutClaimed(msg.sender, receiver, amount);
        _assertSolvent();
    }

    function claimReferral() external nonReentrant {
        uint256 amount = referralClaims[msg.sender];
        if (amount == 0) revert NothingToClaim();
        referralClaims[msg.sender] = 0;
        referralLiability -= amount;
        vault.releaseSettlement(msg.sender, amount);
        _assertSolvent();
    }

    function claimProtocolRevenue() external nonReentrant {
        if (msg.sender != governor) revert OnlyGovernor();
        uint256 amount = protocolLiability;
        if (amount == 0) revert NothingToClaim();
        protocolLiability = 0;
        vault.releaseSettlement(treasury, amount);
        _assertSolvent();
    }

    function claimSecurityRevenue() external nonReentrant {
        uint256 amount = securityLiability;
        if (amount == 0) revert NothingToClaim();
        securityLiability = 0;
        vault.releaseSettlement(insuranceReserve, amount);
        _assertSolvent();
    }

    function claimBuybackRevenue() external nonReentrant {
        uint256 amount = buybackLiability;
        if (amount == 0) revert NothingToClaim();
        buybackLiability = 0;
        vault.releaseSettlement(buybackReceiver, amount);
        _assertSolvent();
    }

    function claimNFT(address collection, uint256 tokenId, address receiver) external nonReentrant {
        if (pendingNFTClaims[collection][tokenId] != msg.sender) revert NotNFTClaimOwner();
        if (receiver == address(0)) revert InvalidNFTClaimReceiver();
        delete pendingNFTClaims[collection][tokenId];
        vault.releaseNFT(receiver, collection, tokenId);
        emit NFTClaimed(collection, tokenId, msg.sender, receiver);
    }

    function totalLiabilities() public view returns (uint256) {
        return selectedBackingLiability + earningsLiability + rewardInputLiability + referralLiability
            + securityLiability + buybackLiability + protocolLiability + settlementClaimLiability;
    }

    function _settleKeep(uint256 receiptId, ProtocolTypes.PullReceiptData memory data, address receiptOwner)
        private
    {
        SelectedPosition memory position = selectedPositions[receiptId];
        _markSettled(receiptId, data.positionId, ProtocolTypes.SettlementChoice.Keep);
        uint256 ownerPayout = uint256(position.backing) * KEEP_PAYOUT_BPS / BPS;
        selectedBackingLiability -= position.backing;
        _allocateSettlementRevenue(uint256(position.backing) - ownerPayout, receiptReferrer[receiptId]);
        _accrueSettlementClaim(position.previousOwner, ownerPayout);
        _consumeEarnings(position);
        delete selectedPositions[receiptId];
        IMarketSettlementCallback(market).finalizeSelectedPosition(data.positionId);
        _fundRewardInput(position);
        _deliverOrDeferNFT(receiptOwner, position.collection, position.tokenId);
        _assertSolvent();
    }

    function _deliverOrDeferNFT(address recipient, address collection, uint256 tokenId) private {
        if (vault.tryReleaseNFT(recipient, collection, tokenId)) return;
        if (pendingNFTClaims[collection][tokenId] != address(0)) revert NFTClaimAlreadyExists();
        pendingNFTClaims[collection][tokenId] = recipient;
        emit NFTDeliveryDeferred(collection, tokenId, recipient);
    }

    function _consumeEarnings(SelectedPosition memory position) private {
        if (position.cashEarnings != 0) {
            earningsLiability -= position.cashEarnings;
            _accrueSettlementClaim(position.earningsRecipient, position.cashEarnings);
        }
        if (position.rewardInput != 0) rewardInputLiability -= position.rewardInput;
    }

    function _fundRewardInput(SelectedPosition memory position) private {
        if (position.rewardInput != 0) {
            vault.releaseSettlement(address(rewardController), position.rewardInput);
            rewardController.enqueue(position.earningsRecipient, settlementAsset, position.rewardInput);
        }
    }

    function _accrueSettlementClaim(address claimOwner, uint256 amount) private {
        if (amount == 0) return;
        settlementClaims[claimOwner] += amount;
        settlementClaimLiability += amount;
        emit SettlementPayoutAccrued(claimOwner, amount);
    }

    function _allocateSettlementRevenue(uint256 revenue, address referrer) private {
        uint256 referralShare = revenue * 2_000 / BPS;
        uint256 securityShare = revenue * 2_000 / BPS;
        uint256 buybackShare = revenue * 2_000 / BPS;
        uint256 treasuryShare = revenue - referralShare - securityShare - buybackShare;
        if (referrer == address(0)) {
            securityShare += referralShare;
        } else {
            referralClaims[referrer] += referralShare;
            referralLiability += referralShare;
        }
        securityLiability += securityShare;
        buybackLiability += buybackShare;
        protocolLiability += treasuryShare;
    }

    function _markSettled(uint256 receiptId, uint256 positionId, ProtocolTypes.SettlementChoice choice)
        private
    {
        pullReceipt.updateStatus(receiptId, ProtocolTypes.PullStatus.Settled, false);
        emit ReceiptSettled(receiptId, positionId, choice);
    }

    function _requireReceiptOwner(uint256 receiptId)
        private
        view
        returns (ProtocolTypes.PullReceiptData memory data)
    {
        if (pullReceipt.ownerOf(receiptId) != msg.sender) revert NotReceiptOwner();
        data = pullReceipt.receiptData(receiptId);
        if (data.status != ProtocolTypes.PullStatus.Revealed) revert InvalidReceipt();
        if (block.timestamp > data.decisionDeadline) revert DeadlineExpired();
    }

    function _assertSolvent() private view {
        uint256 assets = vault.settlementAsset().balanceOf(address(vault));
        uint256 liabilities = totalLiabilities();
        if (assets < liabilities) revert SolvencyInvariantBroken(assets, liabilities);
    }
}
