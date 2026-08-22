// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { DrawMarket } from "../contracts/DrawMarket.sol";
import { EpochCoordinator } from "../contracts/EpochCoordinator.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { PositionNFT } from "../contracts/tokens/PositionNFT.sol";
import { PullReceipt } from "../contracts/tokens/PullReceipt.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { MockRandomnessAdapter } from "./mocks/MockRandomnessAdapter.sol";
import { MockRewardController } from "./mocks/MockRewardController.sol";

contract EpochBoundaryTest is Test {
    MockERC20 internal asset;
    MockERC721 internal collection;
    MockRandomnessAdapter internal randomness;
    DrawMarket internal market;
    EpochCoordinator internal coordinator;
    SettlementEngine internal engine;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");
    address internal insurance = makeAddr("insurance");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal buyer = makeAddr("buyer");

    function setUp() external {
        asset = new MockERC20("Wrapped Ether", "WETH", 18);
        collection = new MockERC721();
        randomness = new MockRandomnessAdapter();
        MockRewardController rewards = new MockRewardController();
        ReferralRegistry referrals = new ReferralRegistry(governor);
        ProtocolRegistry registry = new ProtocolRegistry(governor);
        ProtocolTypes.MarketConfig memory config = ProtocolTypes.MarketConfig({
            marketId: 1,
            collectionSetId: keccak256("ART"),
            settlementAsset: address(asset),
            protocolRegistry: address(registry),
            governor: governor,
            guardian: guardian,
            treasury: treasury,
            insuranceReserve: insurance,
            buybackReceiver: makeAddr("buyback"),
            randomnessAdapter: address(randomness),
            eligibilityPolicy: address(0),
            referralRegistry: address(referrals),
            rewardController: address(rewards),
            trustedRouter: address(0),
            minBacking: 1 ether,
            maxBacking: 1_000 ether,
            maxActivePositions: 8,
            maxDrawsPerEpoch: 3,
            collectionWindow: 0,
            randomnessTimeout: 1 hours,
            decisionWindow: 24 hours,
            markupBps: 1_000
        });

        DrawMarket implementation = new DrawMarket();
        address marketAddress = Clones.clone(address(implementation));
        MarketVault vault = new MarketVault(marketAddress, address(asset));
        PositionNFT positionNft = new PositionNFT("Backed Position", "BKPOS", marketAddress);
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
        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(collection);
        market = DrawMarket(marketAddress);
        market.initialize(
            config,
            address(vault),
            address(positionNft),
            address(engine),
            address(coordinator),
            initialCollections
        );
        bytes32 marketRole = referrals.MARKET_ROLE();
        vm.prank(governor);
        referrals.grantRole(marketRole, address(coordinator));

        _deposit(alice, 1, 100 ether);
        _deposit(bob, 2, 200 ether);
        _deposit(carol, 3, 400 ether);
        asset.mint(buyer, 2_000 ether);
        vm.prank(buyer);
        asset.approve(address(vault), type(uint256).max);
    }

    function testQueuedWithdrawalLeavesTreeBeforeNextSnapshotAndDeliveryCanRetry() external {
        uint48 deadline = _startEpoch();
        vm.prank(bob);
        market.requestWithdrawal(2);

        _finalizeOrdersAfterDeadline(deadline);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalizing));
        assertTrue(market.epochBoundaryPending());
        assertEq(market.activePositionCount(), 3, "pre-fix tree still contains queued leaf");

        _expectNextEpochBlocked();
        coordinator.advanceEpochBoundary(1);

        assertEq(uint8(_positionStatus(2)), uint8(ProtocolTypes.PositionStatus.WithdrawalClaimable));
        assertEq(market.activePositionCount(), 2);
        assertEq(market.positionProbability(2), 0);
        assertFalse(market.epochBoundaryPending());

        vm.prank(bob);
        vm.expectRevert();
        market.claimWithdrawal(2, address(coordinator));
        assertEq(uint8(_positionStatus(2)), uint8(ProtocolTypes.PositionStatus.WithdrawalClaimable));

        _requestPull(uint48(block.timestamp + 1 hours));
        assertEq(_epochId(), 2);
        assertEq(_activeCountSnapshot(), 2);

        uint256 backingBefore = asset.balanceOf(bob);
        vm.prank(bob);
        market.claimWithdrawal(2, bob);
        assertEq(asset.balanceOf(bob) - backingBefore, 200 ether);
        assertEq(collection.ownerOf(2), bob);
        assertEq(uint8(_positionStatus(2)), uint8(ProtocolTypes.PositionStatus.Withdrawn));
    }

    function testQueuedBoundaryWorkDoesNotCloseCurrentCollectionWindow() external {
        _startEpoch();
        vm.prank(bob);
        market.requestWithdrawal(2);

        _requestPull(uint48(block.timestamp + 1 hours));

        assertEq(coordinator.orderCount(1), 2);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Collecting));
    }

    function testSelectedPositionIsSkippedAsStaleBoundaryWork() external {
        _startEpoch();
        vm.prank(alice);
        market.requestWithdrawal(1);
        vm.prank(bob);
        market.requestWithdrawal(2);
        vm.prank(carol);
        market.requestWithdrawal(3);

        coordinator.requestRandomness();
        randomness.setSeed(91);
        coordinator.provideRandomness("");
        coordinator.resolveEpoch(1);
        coordinator.advanceEpochBoundary(3);

        uint256 selectedId = PullReceipt(address(engine.pullReceipt())).receiptData(1).positionId;
        assertEq(uint8(_positionStatus(selectedId)), uint8(ProtocolTypes.PositionStatus.Selected));
        assertEq(market.activePositionCount(), 0);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalized));
    }

    function testStagedActivationCannotBypassCrownWithdrawalOrdering() external {
        uint48 deadline = _startEpoch();
        assertEq(market.crownPositionId(), 3);
        vm.prank(carol);
        market.requestWithdrawal(3);
        _deposit(dave, 4, 50 ether);

        _finalizeOrdersAfterDeadline(deadline);
        vm.expectRevert(DrawMarket.EpochBoundaryPending.selector);
        market.activatePosition(4);
        vm.prank(bob);
        vm.expectRevert(DrawMarket.EpochBoundaryPending.selector);
        market.requestWithdrawal(2);
        vm.prank(bob);
        vm.expectRevert(DrawMarket.EpochBoundaryPending.selector);
        market.requestBackingChange(2, 200 ether);
        coordinator.advanceEpochBoundary(2);

        assertEq(market.activePositionCount(), 3);
        assertEq(market.crownPositionId(), 2);
    }

    function testBoundaryReassignsCrownWhenNoLaterMutationDoes() external {
        uint48 deadline = _startEpoch();
        vm.prank(carol);
        market.requestWithdrawal(3);

        _finalizeOrdersAfterDeadline(deadline);
        coordinator.advanceEpochBoundary(1);

        assertEq(market.activePositionCount(), 2);
        assertEq(market.crownPositionId(), 2);
    }

    function testQueuedCrownWithdrawalReassignsBeforeBoundaryCompletes() external {
        _startEpoch();
        vm.prank(carol);
        market.requestWithdrawal(3);
        vm.prank(alice);
        market.requestWithdrawal(1);

        coordinator.requestRandomness();
        vm.warp(block.timestamp + 1 hours + 1);
        coordinator.cancelTimedOutEpoch(1);
        coordinator.advanceEpochBoundary(1);

        assertTrue(market.epochBoundaryPending());
        assertEq(market.crownPositionId(), 2);
    }

    function testQueuedBackingChangeAppliedBeforeNextSnapshot() external {
        uint48 deadline = _startEpoch();
        vm.prank(alice);
        market.requestBackingChange(1, 80 ether);

        _finalizeOrdersAfterDeadline(deadline);
        vm.expectRevert(DrawMarket.EpochBoundaryPending.selector);
        market.applyQueuedBackingChange(1);
        coordinator.advanceEpochBoundary(1);

        (,, uint128 backing, uint128 pending,, ProtocolTypes.PositionStatus status,,,,,,) =
            market.positions(1);
        assertEq(backing, 80 ether);
        assertEq(pending, 0);
        assertEq(uint8(status), uint8(ProtocolTypes.PositionStatus.Active));
        assertEq(market.settlementClaims(alice), 20 ether);

        uint256 updatedWeight = market.totalWeight();
        _requestPull(uint48(block.timestamp + 1 hours));
        assertEq(_totalWeightSnapshot(), updatedWeight);
    }

    function testQueuedIncumbentBackingDecreaseRecomputesCrownAtBoundary() external {
        uint48 deadline = _startEpoch();
        vm.prank(carol);
        market.requestBackingChange(3, 150 ether);

        _finalizeOrdersAfterDeadline(deadline);
        coordinator.advanceEpochBoundary(1);

        assertEq(market.crownPositionId(), 2);
        assertEq(market.settlementClaims(carol), 250 ether);
        assertEq(market.activePositionCount(), 3);
        assertEq(market.backingLiability(), 450 ether);
    }

    function testStagedDepositActivatesBeforeNextSnapshotWhenCapacityAllows() external {
        uint48 deadline = _startEpoch();
        _deposit(dave, 4, 50 ether);
        assertEq(uint8(_positionStatus(4)), uint8(ProtocolTypes.PositionStatus.Staged));

        _finalizeOrdersAfterDeadline(deadline);
        coordinator.advanceEpochBoundary(1);

        assertEq(uint8(_positionStatus(4)), uint8(ProtocolTypes.PositionStatus.Active));
        assertEq(market.activePositionCount(), 4);
        _requestPull(uint48(block.timestamp + 1 hours));
        assertEq(_activeCountSnapshot(), 4);
    }

    function testNextEpochBlockedUntilBoundedBoundaryWorkCompletes() external {
        uint48 deadline = _startEpoch();
        vm.prank(bob);
        market.requestWithdrawal(2);
        vm.prank(alice);
        market.requestBackingChange(1, 80 ether);
        _deposit(dave, 4, 50 ether);

        _finalizeOrdersAfterDeadline(deadline);
        coordinator.advanceEpochBoundary(1);
        (uint256 withdrawals, uint256 backingChanges, uint256 activations) = market.epochBoundaryState();
        assertEq(withdrawals, 0);
        assertEq(backingChanges, 1);
        assertEq(activations, 1);
        _expectNextEpochBlocked();

        coordinator.advanceEpochBoundary(1);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalizing));
        coordinator.advanceEpochBoundary(1);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalized));
    }

    function testCancellationUsesSameBoundaryGateAndOrdering() external {
        _startEpoch();
        vm.prank(bob);
        market.requestWithdrawal(2);
        vm.prank(alice);
        market.requestBackingChange(1, 80 ether);
        _deposit(dave, 4, 50 ether);

        coordinator.requestRandomness();
        vm.warp(block.timestamp + 1 hours + 1);
        coordinator.cancelTimedOutEpoch(1);

        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Cancelling));
        _expectNextEpochBlocked();
        coordinator.advanceEpochBoundary(3);

        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Cancelled));
        assertEq(uint8(_positionStatus(2)), uint8(ProtocolTypes.PositionStatus.WithdrawalClaimable));
        assertEq(uint8(_positionStatus(1)), uint8(ProtocolTypes.PositionStatus.Active));
        assertEq(uint8(_positionStatus(4)), uint8(ProtocolTypes.PositionStatus.Active));
        assertEq(market.activePositionCount(), 3);
    }

    function _startEpoch() private returns (uint48 deadline) {
        deadline = uint48(block.timestamp + 1 hours);
        _requestPull(deadline);
    }

    function _finalizeOrdersAfterDeadline(uint48 deadline) private {
        coordinator.requestRandomness();
        randomness.setSeed(77);
        coordinator.provideRandomness("");
        vm.warp(uint256(deadline) + 1);
        coordinator.resolveEpoch(1);
    }

    function _expectNextEpochBlocked() private {
        uint256 price = market.currentPullPrice();
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: buyer,
            drawCount: 1,
            maxUnitPrice: uint128(price),
            maxTotalPrice: uint128(price),
            deadline: uint48(block.timestamp + 1 hours),
            referralCode: bytes32(0)
        });
        vm.expectRevert(EpochCoordinator.EpochBoundaryPending.selector);
        vm.prank(buyer);
        coordinator.requestPull(input);
    }

    function _requestPull(uint48 deadline) private {
        uint256 price = market.currentPullPrice();
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: buyer,
            drawCount: 1,
            maxUnitPrice: uint128(price),
            maxTotalPrice: uint128(price),
            deadline: deadline,
            referralCode: bytes32(0)
        });
        vm.prank(buyer);
        coordinator.requestPull(input);
    }

    function _deposit(address owner, uint256 tokenId, uint128 backing) private {
        collection.mint(owner, tokenId);
        asset.mint(owner, backing);
        vm.startPrank(owner);
        collection.approve(address(market.vault()), tokenId);
        asset.approve(address(market.vault()), backing);
        market.depositPosition(address(collection), tokenId, backing, owner);
        vm.stopPrank();
    }

    function _positionStatus(uint256 positionId) private view returns (ProtocolTypes.PositionStatus status) {
        (,,,,, status,,,,,,) = market.positions(positionId);
    }

    function _epochStatus() private view returns (ProtocolTypes.EpochStatus status) {
        (, status,,,,,,,,,,,) = coordinator.epoch();
    }

    function _epochId() private view returns (uint256 id) {
        (id,,,,,,,,,,,,) = coordinator.epoch();
    }

    function _activeCountSnapshot() private view returns (uint32 count) {
        (,,,, count,,,,,,,,) = coordinator.epoch();
    }

    function _totalWeightSnapshot() private view returns (uint256 weight) {
        (,,,,,,,, weight,,,,) = coordinator.epoch();
    }
}
