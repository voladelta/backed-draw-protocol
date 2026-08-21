// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { DrawMarket } from "../contracts/DrawMarket.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { EpochCoordinator } from "../contracts/EpochCoordinator.sol";
import { PositionNFT } from "../contracts/tokens/PositionNFT.sol";
import { PullReceipt } from "../contracts/tokens/PullReceipt.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { IEligibilityPolicy } from "../contracts/interfaces/IEligibilityPolicy.sol";
import { MockDenylistERC20 } from "./mocks/MockDenylistERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { MockRandomnessAdapter } from "./mocks/MockRandomnessAdapter.sol";
import { MockRewardController } from "./mocks/MockRewardController.sol";

contract SettlementSafetyRejectingReceiver is IERC721Receiver {
    address public rejectedCollection;

    function setRejectedCollection(address collection) external {
        rejectedCollection = collection;
    }

    function deposit(
        DrawMarket market,
        MarketVault vault,
        IERC20 asset,
        IERC721 collection,
        uint256 tokenId,
        uint128 backing
    ) external returns (uint256 positionId) {
        asset.approve(address(vault), backing);
        collection.approve(address(vault), tokenId);
        positionId = market.depositPosition(address(collection), tokenId, backing, address(this));
    }

    function settleKeep(SettlementEngine engine, uint256 receiptId) external {
        engine.settleKeep(receiptId);
    }

    function claimNFT(SettlementEngine engine, address collection, uint256 tokenId, address receiver)
        external
    {
        engine.claimNFT(collection, tokenId, receiver);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender == rejectedCollection) revert("collection rejected");
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract SettlementSafetyEligibilityPolicy is IEligibilityPolicy {
    mapping(address user => bool allowed) public depositAllowed;
    mapping(address user => bool allowed) public pullAllowed;
    mapping(address user => bool allowed) public receiveAllowed;

    function setAllowed(address user, bool deposit, bool pull, bool canReceive_) external {
        depositAllowed[user] = deposit;
        pullAllowed[user] = pull;
        receiveAllowed[user] = canReceive_;
    }

    function canDeposit(address user, uint256) external view returns (bool) {
        return depositAllowed[user];
    }

    function canPull(address user, uint256) external view returns (bool) {
        return pullAllowed[user];
    }

    function canReceive(address user, uint256) external view returns (bool) {
        return receiveAllowed[user];
    }
}

contract SettlementSafetyTest is Test {
    MockDenylistERC20 internal asset;
    MockERC721 internal collection;
    MockRandomnessAdapter internal randomness;
    MockRewardController internal rewards;
    ReferralRegistry internal referrals;
    ProtocolRegistry internal registry;
    DrawMarket internal market;
    MarketVault internal vault;
    SettlementEngine internal engine;
    EpochCoordinator internal coordinator;

    address internal governor = makeAddr("settlement-safety-governor");
    address internal guardian = makeAddr("settlement-safety-guardian");
    address internal treasury = makeAddr("settlement-safety-treasury");
    address internal insurance = makeAddr("settlement-safety-insurance");
    address internal buyback = makeAddr("settlement-safety-buyback");
    address internal alice = makeAddr("settlement-safety-alice");
    address internal buyer = makeAddr("settlement-safety-buyer");
    address internal redirectedReceiver = makeAddr("settlement-safety-redirected-receiver");

    function setUp() external {
        asset = new MockDenylistERC20("Wrapped Ether", "WETH", 18);
        collection = new MockERC721();
        randomness = new MockRandomnessAdapter();
        rewards = new MockRewardController();
        referrals = new ReferralRegistry(governor);
        registry = new ProtocolRegistry(governor);
    }

    function testSettleKeepDefersRejectedDeliveryAndClaimOwnerCanRedirect() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        SettlementSafetyRejectingReceiver receiver = _newRejectingReceiver();

        _drawOne(address(receiver), 11);
        receiver.settleKeep(engine, 1);

        _assertDeferredClaim(receiver, 1);
        assertEq(uint8(_receiptData(1).status), uint8(ProtocolTypes.PullStatus.Settled));
        vm.expectRevert(SettlementEngine.InvalidReceipt.selector);
        receiver.settleKeep(engine, 1);

        vm.prank(governor);
        vm.expectRevert(SettlementEngine.NotNFTClaimOwner.selector);
        engine.claimNFT(address(collection), 1, governor);

        vm.expectRevert();
        receiver.claimNFT(engine, address(collection), 1, address(receiver));
        _assertDeferredClaim(receiver, 1);

        receiver.claimNFT(engine, address(collection), 1, redirectedReceiver);
        assertEq(collection.ownerOf(1), redirectedReceiver);
        assertEq(engine.pendingNFTClaims(address(collection), 1), address(0));
    }

    function testForceKeepDefersRejectedDeliveryWithoutBlockingSettlement() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        SettlementSafetyRejectingReceiver receiver = _newRejectingReceiver();
        _drawOne(address(receiver), 12);

        ProtocolTypes.PullReceiptData memory receipt = _receiptData(1);
        vm.warp(receipt.decisionDeadline + 1);
        engine.forceKeep(1);

        _assertDeferredClaim(receiver, 1);
        receiver.claimNFT(engine, address(collection), 1, redirectedReceiver);
        assertEq(collection.ownerOf(1), redirectedReceiver);
    }

    function testCashDefersRejectedReturnToPreviousOwner() external {
        SettlementSafetyRejectingReceiver owner = _deployWithRejectingPosition(1);
        _drawOne(buyer, 13);

        vm.prank(buyer);
        engine.settleCash(1);

        assertEq(engine.settlementClaims(buyer), 85 ether);
        _assertDeferredClaim(owner, 1);
        owner.claimNFT(engine, address(collection), 1, redirectedReceiver);
        assertEq(collection.ownerOf(1), redirectedReceiver);
    }

    function testDrawDefersRejectedReturnToPreviousOwner() external {
        SettlementSafetyRejectingReceiver owner = _deployWithRejectingPosition(1);
        _drawOne(buyer, 14);

        vm.prank(buyer);
        engine.settleDraw(1, 80 ether, hex"1234");

        assertEq(rewards.settlementInput(buyer, address(asset)), 85 ether);
        assertEq(rewards.lastMinDrawOut(), 80 ether);
        assertEq(rewards.lastRouteData(), hex"1234");
        _assertDeferredClaim(owner, 1);
        owner.claimNFT(engine, address(collection), 1, redirectedReceiver);
        assertEq(collection.ownerOf(1), redirectedReceiver);
    }

    function testDeniedPayoutRecipientCannotBlockKeepAndCanRedirectClaim() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 141);
        (,,,,, uint256 cashEarnings,) = engine.selectedPositions(1);
        asset.setRejectedRecipient(alice, true);

        vm.prank(buyer);
        engine.settleKeep(1);

        _assertSettledWithClaim(alice, 99 ether + cashEarnings);
    }

    function testDeniedPayoutRecipientCannotBlockPermissionlessForceKeep() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 142);
        (,,,,, uint256 cashEarnings,) = engine.selectedPositions(1);
        asset.setRejectedRecipient(alice, true);
        vm.warp(_receiptData(1).decisionDeadline + 1);

        vm.prank(governor);
        engine.forceKeep(1);

        _assertSettledWithClaim(alice, 99 ether + cashEarnings);
    }

    function testDeniedEarningsRecipientCannotBlockCashSettlement() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 143);
        (,,,,, uint256 cashEarnings,) = engine.selectedPositions(1);
        asset.setRejectedRecipient(alice, true);

        vm.prank(buyer);
        engine.settleCash(1);

        assertEq(engine.settlementClaims(buyer), 85 ether);
        _assertSettledWithClaim(alice, cashEarnings);
    }

    function testDeniedEarningsRecipientCannotBlockDrawSettlement() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 144);
        (,,,,, uint256 cashEarnings,) = engine.selectedPositions(1);
        asset.setRejectedRecipient(alice, true);

        vm.prank(buyer);
        engine.settleDraw(1, 84 ether, hex"cafe");

        assertEq(rewards.settlementInput(buyer, address(asset)), 85 ether);
        _assertSettledWithClaim(alice, cashEarnings);
    }

    function testDeniedPayoutRecipientCannotBlockRelistSettlement() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 145);
        (,,,,, uint256 cashEarnings,) = engine.selectedPositions(1);
        asset.setRejectedRecipient(alice, true);

        vm.prank(buyer);
        engine.settleRelist(1, 100 ether);

        _assertSettledWithClaim(alice, 99 ether + cashEarnings);
    }

    function testProtectedDrawSwapFailureLeavesReceiptUnconsumedForCashRetry() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 146);
        uint256 liabilitiesBefore = engine.totalLiabilities();
        rewards.setRejectSettlementSwap(true);

        vm.prank(buyer);
        vm.expectRevert(MockRewardController.SettlementSwapRejected.selector);
        engine.settleDraw(1, 85 ether, hex"deadbeef");

        assertEq(uint8(_receiptData(1).status), uint8(ProtocolTypes.PullStatus.Revealed));
        (,,,, uint128 backing,,) = engine.selectedPositions(1);
        assertEq(backing, 100 ether);
        assertEq(engine.selectedBackingLiability(), 100 ether);
        assertEq(engine.totalLiabilities(), liabilitiesBefore);
        assertEq(rewards.settlementInput(buyer, address(asset)), 0);
        assertEq(asset.balanceOf(address(rewards)), 0);
        assertEq(collection.ownerOf(1), address(vault));

        rewards.setRejectSettlementSwap(false);
        vm.prank(buyer);
        engine.settleCash(1);
        assertEq(uint8(_receiptData(1).status), uint8(ProtocolTypes.PullStatus.Settled));
        assertEq(engine.settlementClaims(buyer), 85 ether);
    }

    function testVaultRejectsUnsolicitedSafeTransferButAcceptsMarketDeposit() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        collection.mint(alice, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MarketVault.UnexpectedNFT.selector, address(collection), 1));
        collection.safeTransferFrom(alice, address(vault), 1);
        assertEq(collection.ownerOf(1), alice);

        asset.mint(alice, 100 ether);
        vm.startPrank(alice);
        collection.approve(address(vault), 1);
        asset.approve(address(vault), 100 ether);
        uint256 positionId = market.depositPosition(address(collection), 1, 100 ether, alice);
        vm.stopPrank();

        assertEq(positionId, 1);
        assertEq(collection.ownerOf(1), address(vault));
    }

    function testRelistRequiresDepositAndReceiveEligibility() external {
        SettlementSafetyEligibilityPolicy policy = new SettlementSafetyEligibilityPolicy();
        policy.setAllowed(alice, true, false, true);
        policy.setAllowed(buyer, false, true, true);
        _deployMarket(address(policy), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 15);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(DrawMarket.Ineligible.selector, buyer));
        engine.settleRelist(1, 100 ether);
        assertEq(uint8(_receiptData(1).status), uint8(ProtocolTypes.PullStatus.Revealed));

        policy.setAllowed(buyer, true, true, false);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(DrawMarket.Ineligible.selector, buyer));
        engine.settleRelist(1, 100 ether);
        assertEq(uint8(_receiptData(1).status), uint8(ProtocolTypes.PullStatus.Revealed));

        policy.setAllowed(buyer, true, true, true);
        vm.prank(buyer);
        uint256 newPositionId = engine.settleRelist(1, 100 ether);
        assertEq(market.positionToken().ownerOf(newPositionId), buyer);
        assertEq(collection.ownerOf(1), address(vault));
    }

    function testPermissionlessRelistRemainsAvailable() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 16);

        vm.prank(buyer);
        uint256 newPositionId = engine.settleRelist(1, 100 ether);

        assertEq(market.positionToken().ownerOf(newPositionId), buyer);
        assertEq(collection.ownerOf(1), address(vault));
    }

    function testInitializeRejectsMaxBackingWithZeroWeight() external {
        ProtocolTypes.MarketConfig memory config = _config(address(0), uint128(1e36 + 1), buyback);
        (PositionNFT positionToken) = _deployDependencies(config);
        vm.expectRevert(DrawMarket.InvalidConfiguration.selector);
        _initializeMarket(config, positionToken);
    }

    function testMaximumBackingBoundaryHasPositiveWeight() external {
        _deployMarket(address(0), uint128(1e36), buyback);
        _deposit(alice, 1, uint128(1e36));

        assertEq(market.totalWeight(), 1);
        assertEq(market.activePositionCount(), 1);
    }

    function testInitializeRejectsZeroBuybackReceiver() external {
        ProtocolTypes.MarketConfig memory config = _config(address(0), 1_000 ether, address(0));
        (PositionNFT positionToken) = _deployDependencies(config);
        vm.expectRevert(DrawMarket.ZeroAddress.selector);
        _initializeMarket(config, positionToken);
    }

    function _deployWithRejectingPosition(uint256 tokenId)
        private
        returns (SettlementSafetyRejectingReceiver owner)
    {
        _deployMarket(address(0), 1_000 ether, buyback);
        owner = _newRejectingReceiver();
        collection.mint(address(owner), tokenId);
        asset.mint(address(owner), 100 ether);
        owner.deposit(market, vault, asset, collection, tokenId, 100 ether);
    }

    function _newRejectingReceiver() private returns (SettlementSafetyRejectingReceiver receiver) {
        receiver = new SettlementSafetyRejectingReceiver();
        receiver.setRejectedCollection(address(collection));
    }

    function _deployMarket(address policy, uint128 maxBacking, address buybackReceiver) private {
        ProtocolTypes.MarketConfig memory config = _config(policy, maxBacking, buybackReceiver);
        _initializeFresh(config);
        bytes32 marketRole = referrals.MARKET_ROLE();
        vm.prank(governor);
        referrals.grantRole(marketRole, address(coordinator));
        asset.mint(buyer, maxBacking);
        vm.prank(buyer);
        asset.approve(address(vault), type(uint256).max);
    }

    function _initializeFresh(ProtocolTypes.MarketConfig memory config) private {
        PositionNFT positionToken = _deployDependencies(config);
        _initializeMarket(config, positionToken);
    }

    function _deployDependencies(ProtocolTypes.MarketConfig memory config)
        private
        returns (PositionNFT positionToken)
    {
        DrawMarket implementation = new DrawMarket();
        address marketAddress = Clones.clone(address(implementation));
        market = DrawMarket(marketAddress);
        vault = new MarketVault(marketAddress, address(asset));
        positionToken = new PositionNFT("Backed Position", "BKPOS", marketAddress);
        engine = new SettlementEngine(
            marketAddress,
            config.marketId,
            config.settlementAsset,
            config.governor,
            config.treasury,
            config.insuranceReserve,
            config.buybackReceiver,
            address(vault),
            config.rewardController,
            config.minBacking,
            config.maxBacking,
            config.decisionWindow
        );
        coordinator = new EpochCoordinator(
            config.marketId,
            marketAddress,
            address(vault),
            config.protocolRegistry,
            config.referralRegistry,
            config.randomnessAdapter,
            config.governor,
            config.guardian,
            config.trustedRouter,
            config.maxDrawsPerEpoch,
            config.collectionWindow,
            config.randomnessTimeout
        );
    }

    function _initializeMarket(ProtocolTypes.MarketConfig memory config, PositionNFT positionToken) private {
        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(collection);
        market.initialize(
            config,
            address(vault),
            address(positionToken),
            address(engine),
            address(coordinator),
            initialCollections
        );
    }

    function _config(address policy, uint128 maxBacking, address buybackReceiver)
        private
        view
        returns (ProtocolTypes.MarketConfig memory)
    {
        return ProtocolTypes.MarketConfig({
            marketId: 1,
            collectionSetId: keccak256("SETTLEMENT_SAFETY"),
            settlementAsset: address(asset),
            protocolRegistry: address(registry),
            governor: governor,
            guardian: guardian,
            treasury: treasury,
            insuranceReserve: insurance,
            buybackReceiver: buybackReceiver,
            randomnessAdapter: address(randomness),
            eligibilityPolicy: policy,
            referralRegistry: address(referrals),
            rewardController: address(rewards),
            trustedRouter: address(0),
            minBacking: 1,
            maxBacking: maxBacking,
            maxActivePositions: 8,
            maxDrawsPerEpoch: 1,
            collectionWindow: 0,
            randomnessTimeout: 1 hours,
            decisionWindow: 24 hours,
            markupBps: 1_000
        });
    }

    function _deposit(address owner, uint256 tokenId, uint128 backing) private {
        collection.mint(owner, tokenId);
        asset.mint(owner, backing);
        vm.startPrank(owner);
        collection.approve(address(vault), tokenId);
        asset.approve(address(vault), backing);
        market.depositPosition(address(collection), tokenId, backing, owner);
        vm.stopPrank();
    }

    function _drawOne(address receiver, uint256 seed) private {
        uint256 price = market.currentPullPrice();
        uint128 boundedPrice = SafeCast.toUint128(price);
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: receiver,
            drawCount: 1,
            maxUnitPrice: boundedPrice,
            maxTotalPrice: boundedPrice,
            deadline: uint48(block.timestamp + 1 hours),
            referralCode: bytes32(0)
        });
        vm.prank(buyer);
        coordinator.requestPull(input);
        coordinator.requestRandomness();
        randomness.setSeed(seed);
        coordinator.provideRandomness("");
        coordinator.resolveEpoch(1);
    }

    function _receiptData(uint256 receiptId) private view returns (ProtocolTypes.PullReceiptData memory) {
        return PullReceipt(address(engine.pullReceipt())).receiptData(receiptId);
    }

    function _assertDeferredClaim(SettlementSafetyRejectingReceiver owner, uint256 tokenId) private view {
        assertEq(collection.ownerOf(tokenId), address(vault));
        assertEq(engine.pendingNFTClaims(address(collection), tokenId), address(owner));
        assertEq(engine.selectedBackingLiability(), 0);
    }

    function _assertSettledWithClaim(address claimOwner, uint256 expectedClaim) private {
        assertEq(uint8(_receiptData(1).status), uint8(ProtocolTypes.PullStatus.Settled));
        assertEq(engine.settlementClaims(claimOwner), expectedClaim);
        uint256 totalClaimsBefore = engine.settlementClaimLiability();
        assertGe(totalClaimsBefore, expectedClaim);
        assertEq(engine.selectedBackingLiability(), 0);
        assertTrue(market.solvent());

        vm.prank(governor);
        vm.expectRevert(SettlementEngine.NothingToClaim.selector);
        engine.claimSettlement(redirectedReceiver);

        vm.prank(claimOwner);
        vm.expectRevert(abi.encodeWithSelector(MockDenylistERC20.RejectedRecipient.selector, claimOwner));
        engine.claimSettlement(claimOwner);
        assertEq(engine.settlementClaims(claimOwner), expectedClaim);

        uint256 receiverBefore = asset.balanceOf(redirectedReceiver);
        vm.prank(claimOwner);
        engine.claimSettlement(redirectedReceiver);
        assertEq(asset.balanceOf(redirectedReceiver) - receiverBefore, expectedClaim);
        assertEq(engine.settlementClaims(claimOwner), 0);
        assertEq(engine.settlementClaimLiability(), totalClaimsBefore - expectedClaim);
    }
}
