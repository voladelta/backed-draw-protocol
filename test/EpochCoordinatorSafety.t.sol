// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { DrawMarket } from "../contracts/DrawMarket.sol";
import { EpochCoordinator } from "../contracts/EpochCoordinator.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { SwapAndPullRouter } from "../contracts/SwapAndPullRouter.sol";
import { IDrawMarketCore } from "../contracts/interfaces/IDrawMarketCore.sol";
import { IEligibilityPolicy } from "../contracts/interfaces/IEligibilityPolicy.sol";
import { IRandomnessAdapter } from "../contracts/interfaces/IRandomnessAdapter.sol";
import { PositionNFT } from "../contracts/tokens/PositionNFT.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { MockRandomnessAdapter } from "./mocks/MockRandomnessAdapter.sol";
import { MockRewardController } from "./mocks/MockRewardController.sol";

contract EpochCoordinatorSafetyEligibilityPolicy is IEligibilityPolicy {
    mapping(address user => mapping(uint256 positionId => bool denied)) public receiveDenied;
    mapping(address user => bool enabled) public receiveReverts;
    mapping(address user => bool enabled) public receiveMalformed;

    function setReceiveDenied(address user, uint256 positionId, bool denied) external {
        receiveDenied[user][positionId] = denied;
    }

    function setReceiveReverts(address user, bool enabled) external {
        receiveReverts[user] = enabled;
    }

    function setReceiveMalformed(address user, bool enabled) external {
        receiveMalformed[user] = enabled;
    }

    function canDeposit(address, uint256) external pure returns (bool) {
        return true;
    }

    function canPull(address, uint256) external pure returns (bool) {
        return true;
    }

    function canReceive(address user, uint256 positionId) external view returns (bool) {
        if (receiveReverts[user]) revert("receive policy failed");
        if (receiveMalformed[user]) {
            assembly ("memory-safe") {
                mstore(0, 1)
                return(31, 1)
            }
        }
        return !receiveDenied[user][positionId];
    }
}

error UnexpectedResolveFailure();

contract EpochCoordinatorSafetyReplayingAdapter is IRandomnessAdapter {
    bytes32 public constant REQUEST_ID = keccak256("replayed-request");

    uint256 public seed;
    bool public pending;

    function setSeed(uint256 seed_) external {
        seed = seed_;
    }

    function requestRandomness(bytes32, uint32) external returns (bytes32 requestId) {
        pending = true;
        return REQUEST_ID;
    }

    function verifyAndConsume(bytes32 requestId, bytes calldata) external returns (uint256[] memory words) {
        require(requestId == REQUEST_ID && pending, "not pending");
        pending = false;
        words = new uint256[](1);
        words[0] = seed;
    }

    function isRequestPending(bytes32 requestId) external view returns (bool) {
        return requestId == REQUEST_ID && pending;
    }
}

contract EpochCoordinatorSafetyTest is Test {
    using SafeCast for uint256;

    uint32 internal constant RANDOMNESS_TIMEOUT = 1 hours;

    MockERC20 internal asset;
    MockERC721 internal collection;
    MockRandomnessAdapter internal randomness;
    EpochCoordinatorSafetyEligibilityPolicy internal eligibility;
    ProtocolRegistry internal registry;
    ReferralRegistry internal referrals;
    DrawMarket internal market;
    MarketVault internal vault;
    SettlementEngine internal engine;
    EpochCoordinator internal coordinator;
    SwapAndPullRouter internal router;

    address internal governor = makeAddr("epoch-safety-governor");
    address internal guardian = makeAddr("epoch-safety-guardian");
    address internal depositor = makeAddr("epoch-safety-depositor");
    address internal buyer = makeAddr("epoch-safety-buyer");
    address internal receiver = makeAddr("epoch-safety-receiver");
    address internal victim = makeAddr("epoch-safety-victim");

    function setUp() external {
        asset = new MockERC20("Settlement", "SET", 18);
        collection = new MockERC721();
        randomness = new MockRandomnessAdapter();
        eligibility = new EpochCoordinatorSafetyEligibilityPolicy();
        registry = new ProtocolRegistry(governor);
        referrals = new ReferralRegistry(governor);
        router = new SwapAndPullRouter(governor, address(asset), address(0), address(registry));

        vm.startPrank(governor);
        registry.setRandomnessAdapter(address(randomness), true);
        registry.setEligibilityPolicy(address(eligibility), true);
        registry.setReferralRegistry(address(referrals), true);
        registry.setRouter(address(router), true);
        vm.stopPrank();

        ProtocolTypes.MarketConfig memory config = ProtocolTypes.MarketConfig({
            marketId: 1,
            collectionSetId: keccak256("EPOCH_SAFETY"),
            settlementAsset: address(asset),
            protocolRegistry: address(registry),
            governor: governor,
            guardian: guardian,
            treasury: makeAddr("epoch-safety-treasury"),
            insuranceReserve: makeAddr("epoch-safety-insurance"),
            buybackReceiver: makeAddr("epoch-safety-buyback"),
            randomnessAdapter: address(randomness),
            eligibilityPolicy: address(eligibility),
            referralRegistry: address(referrals),
            rewardController: address(new MockRewardController()),
            trustedRouter: address(router),
            minBacking: 1 ether,
            maxBacking: 1_000 ether,
            maxActivePositions: 8,
            maxDrawsPerEpoch: 8,
            collectionWindow: 0,
            randomnessTimeout: RANDOMNESS_TIMEOUT,
            decisionWindow: 24 hours,
            markupBps: 1_000
        });

        DrawMarket implementation = new DrawMarket();
        address marketAddress = Clones.clone(address(implementation));
        vault = new MarketVault(marketAddress, address(asset));
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

        vm.startPrank(governor);
        referrals.grantRole(referrals.MARKET_ROLE(), address(coordinator));
        registry.registerMarket(address(market), config.marketId, 1);
        vm.stopPrank();

        collection.mint(depositor, 1);
        asset.mint(depositor, 100 ether);
        vm.startPrank(depositor);
        collection.approve(address(vault), 1);
        asset.approve(address(vault), 100 ether);
        market.depositPosition(address(collection), 1, 100 ether, depositor);
        vm.stopPrank();

        asset.mint(buyer, 10_000 ether);
        vm.startPrank(buyer);
        asset.approve(address(vault), type(uint256).max);
        asset.approve(address(router), type(uint256).max);
        vm.stopPrank();

        asset.mint(victim, 1_000 ether);
        vm.prank(victim);
        asset.approve(address(vault), type(uint256).max);
    }

    function testRevertingRandomnessRequestRemainsPermissionlesslyCancellable() external {
        uint256 price = _requestPull(buyer, buyer, 1 hours);
        randomness.setRequestsRevert(true);

        coordinator.requestRandomness();

        (ProtocolTypes.EpochStatus status, uint48 requestedAt, bytes32 requestId,) = _epochState();
        assertEq(uint8(status), uint8(ProtocolTypes.EpochStatus.RandomnessRequested));
        assertEq(requestedAt, block.timestamp);
        assertEq(requestId, bytes32(0));

        vm.warp(block.timestamp + RANDOMNESS_TIMEOUT + 1);
        vm.prank(makeAddr("permissionless-canceller"));
        coordinator.cancelTimedOutEpoch(1);

        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Cancelled));
        assertEq(coordinator.refundClaims(buyer), price);
        assertFalse(market.epochLocked());
    }

    function testReplayedRequestIdCannotFulfillALaterEpoch() external {
        EpochCoordinatorSafetyReplayingAdapter replaying = new EpochCoordinatorSafetyReplayingAdapter();
        vm.startPrank(governor);
        registry.setRandomnessAdapter(address(replaying), true);
        coordinator.setRandomnessAdapter(address(replaying));
        vm.stopPrank();

        _requestPull(buyer, buyer, 1 hours);
        coordinator.requestRandomness();
        vm.warp(block.timestamp + RANDOMNESS_TIMEOUT + 1);
        coordinator.cancelTimedOutEpoch(1);

        _requestPull(buyer, buyer, 1 hours);
        coordinator.requestRandomness();
        replaying.setSeed(77);

        vm.expectRevert(EpochCoordinator.InvalidOrder.selector);
        coordinator.provideRandomness("");

        vm.warp(block.timestamp + RANDOMNESS_TIMEOUT + 1);
        coordinator.cancelTimedOutEpoch(1);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Cancelled));
        assertEq(market.activePositionCount(), 1);
    }

    function testRegistryDeapprovalImmediatelyRevokesRouterRoleAuthority() external {
        assertTrue(coordinator.hasRole(coordinator.ROUTER_ROLE(), address(router)));
        vm.prank(governor);
        registry.setRouter(address(router), false);

        uint256 price = market.currentPullPrice();
        uint256 buyerBalance = asset.balanceOf(buyer);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(EpochCoordinator.RouterNotApproved.selector, address(router)));
        router.swapAndPull(address(market), address(asset), price, _order(buyer, price, 1 hours), "");

        assertEq(asset.balanceOf(buyer), buyerBalance);
        assertEq(coordinator.orderCount(1), 0);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Idle));
    }

    function testRouterCannotDebitAnApprovedThirdPartyPayer() external {
        address maliciousRouter = makeAddr("malicious-router");
        vm.startPrank(governor);
        registry.setRouter(maliciousRouter, true);
        coordinator.grantRole(coordinator.ROUTER_ROLE(), maliciousRouter);
        vm.stopPrank();

        uint256 price = market.currentPullPrice();
        uint256 victimBalance = asset.balanceOf(victim);
        vm.prank(maliciousRouter);
        vm.expectRevert(
            abi.encodeWithSelector(EpochCoordinator.InvalidPayer.selector, victim, maliciousRouter)
        );
        coordinator.requestPullFor(victim, maliciousRouter, _order(maliciousRouter, price, 1 hours));

        assertEq(asset.balanceOf(victim), victimBalance);
        assertEq(coordinator.orderCount(1), 0);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Idle));
    }

    function testBundledRouterStillPaysFromItsOwnBalanceForBuyer() external {
        uint256 price = market.currentPullPrice();
        uint256 buyerBalance = asset.balanceOf(buyer);

        vm.prank(buyer);
        (uint256 orderIndex, uint256 amountIn) =
            router.swapAndPull(address(market), address(asset), price, _order(buyer, price, 1 hours), "");

        ProtocolTypes.PullOrder memory submitted = coordinator.orderAt(1, orderIndex);
        assertEq(amountIn, price);
        assertEq(submitted.buyer, buyer);
        assertEq(submitted.receiver, buyer);
        assertEq(asset.balanceOf(buyer), buyerBalance - price);
        assertEq(asset.balanceOf(address(router)), 0);
    }

    function testApprovedRouterCannotSubmitZeroBuyerOrNormalizedReceiver() external {
        address approvedRouter = makeAddr("approved-router");
        vm.startPrank(governor);
        registry.setRouter(approvedRouter, true);
        coordinator.grantRole(coordinator.ROUTER_ROLE(), approvedRouter);
        vm.stopPrank();

        uint256 price = market.currentPullPrice();
        asset.mint(approvedRouter, price);
        vm.prank(approvedRouter);
        asset.approve(address(vault), price);
        uint256 balanceBefore = asset.balanceOf(approvedRouter);

        vm.prank(approvedRouter);
        vm.expectRevert(EpochCoordinator.ZeroAddress.selector);
        coordinator.requestPullFor(approvedRouter, address(0), _order(receiver, price, 1 hours));

        vm.prank(approvedRouter);
        vm.expectRevert(EpochCoordinator.ZeroAddress.selector);
        coordinator.requestPullFor(approvedRouter, address(0), _order(address(0), price, 1 hours));

        assertEq(asset.balanceOf(approvedRouter), balanceBefore);
        assertEq(coordinator.orderCount(1), 0);
        assertEq(coordinator.totalLiabilities(), 0);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Idle));
    }

    function testIneligibleDirectReceiversAreRefundedWithinResolveBudget() external {
        eligibility.setReceiveDenied(receiver, 1, true);
        uint256 price = _requestPull(buyer, receiver, 1 hours);
        _requestPull(buyer, receiver, 1 hours);
        _requestPull(buyer, receiver, 1 hours);
        coordinator.requestRandomness();
        randomness.setSeed(13);
        coordinator.provideRandomness("");

        coordinator.resolveEpoch(2);

        assertEq(_orderCursor(), 2);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Resolving));
        assertEq(coordinator.refundClaims(buyer), price * 2);

        coordinator.resolveEpoch(2);

        (,,, uint32 totalResolved) = _epochState();
        assertEq(totalResolved, 0);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalized));
        assertEq(coordinator.refundClaims(buyer), price * 3);
        assertEq(market.activePositionCount(), 1);
    }

    function testRevertingReceivePolicyRefundsOrderAndContinues() external {
        eligibility.setReceiveReverts(receiver, true);
        uint256 price = _requestPull(buyer, receiver, 1 hours);
        _requestPull(buyer, buyer, 1 hours);
        coordinator.requestRandomness();
        randomness.setSeed(17);
        coordinator.provideRandomness("");

        coordinator.resolveEpoch(2);

        (,,, uint32 totalResolved) = _epochState();
        assertEq(totalResolved, 1);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalized));
        assertEq(coordinator.refundClaims(buyer), price);
        assertEq(coordinator.escrowLiability(), 0);
        assertEq(coordinator.refundLiability(), price);
        assertEq(market.activePositionCount(), 0);
    }

    function testMalformedReceivePolicyRefundsOrderAndContinues() external {
        eligibility.setReceiveMalformed(receiver, true);
        uint256 price = _requestPull(buyer, receiver, 1 hours);
        _requestPull(buyer, buyer, 1 hours);
        coordinator.requestRandomness();
        randomness.setSeed(23);
        coordinator.provideRandomness("");

        coordinator.resolveEpoch(2);

        (,,, uint32 totalResolved) = _epochState();
        assertEq(totalResolved, 1);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalized));
        assertEq(coordinator.refundClaims(buyer), price);
        assertEq(coordinator.escrowLiability(), 0);
        assertEq(coordinator.refundLiability(), price);
        assertEq(market.activePositionCount(), 0);
    }

    function testUnexpectedResolveFailureHasBoundedPermissionlessRecovery() external {
        _depositPosition(2, 100 ether);
        uint256 price = _requestPull(buyer, buyer, 1 hours);
        _requestPull(buyer, buyer, 1 hours);
        _requestPull(buyer, buyer, 1 hours);
        vm.prank(depositor);
        market.requestWithdrawal(2);
        coordinator.requestRandomness();

        uint256 totalWeight = market.totalWeight();
        uint256 seed;
        while (
            uint256(keccak256(abi.encode(seed, uint256(1), uint32(0), uint32(0)))) % totalWeight
                >= totalWeight / 2
        ) {
            ++seed;
        }
        randomness.setSeed(seed);
        coordinator.provideRandomness("");
        coordinator.resolveEpoch(1);

        assertEq(_orderCursor(), 1);
        assertEq(market.activePositionCount(), 1);
        assertEq(coordinator.escrowLiability(), price * 2);
        vm.mockCallRevert(
            address(market),
            abi.encodeWithSelector(IDrawMarketCore.resolveDraw.selector),
            abi.encodeWithSelector(UnexpectedResolveFailure.selector)
        );
        vm.expectRevert(UnexpectedResolveFailure.selector);
        coordinator.resolveEpoch(1);

        assertEq(_orderCursor(), 1);
        assertEq(coordinator.escrowLiability(), price * 2);
        assertEq(coordinator.refundLiability(), 0);
        assertEq(market.activePositionCount(), 1);

        vm.warp(block.timestamp + RANDOMNESS_TIMEOUT + 1);
        vm.prank(makeAddr("first-recovery-caller"));
        coordinator.cancelTimedOutEpoch(1);

        assertEq(_orderCursor(), 2);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Refunding));
        assertEq(coordinator.refundClaims(buyer), price);
        assertEq(coordinator.escrowLiability(), price);
        assertEq(coordinator.refundLiability(), price);
        vm.expectRevert(
            abi.encodeWithSelector(
                EpochCoordinator.InvalidEpochState.selector, ProtocolTypes.EpochStatus.Refunding
            )
        );
        coordinator.resolveEpoch(1);

        vm.prank(makeAddr("second-recovery-caller"));
        coordinator.cancelTimedOutEpoch(1);

        (,,, uint32 totalResolved) = _epochState();
        assertEq(totalResolved, 1);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Cancelling));
        assertEq(coordinator.refundClaims(buyer), price * 2);
        assertEq(coordinator.escrowLiability(), 0);
        assertEq(coordinator.refundLiability(), price * 2);
        assertTrue(market.epochBoundaryPending());

        coordinator.advanceEpochBoundary(1);

        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Cancelled));
        assertFalse(market.epochLocked());
        assertFalse(market.epochBoundaryPending());
        assertEq(market.activePositionCount(), 0);
        (,,,,, ProtocolTypes.PositionStatus selectedStatus,,,,,,) = market.positions(1);
        (,,,,, ProtocolTypes.PositionStatus withdrawnStatus,,,,,,) = market.positions(2);
        assertEq(uint8(selectedStatus), uint8(ProtocolTypes.PositionStatus.Selected));
        assertEq(uint8(withdrawnStatus), uint8(ProtocolTypes.PositionStatus.WithdrawalClaimable));
    }

    function testOverPriceOrdersConsumeResolveBudget() external {
        _depositPosition(2, 1_000 ether);
        uint256 price = market.currentPullPrice();
        for (uint256 i; i < 5; ++i) {
            _requestPull(buyer, buyer, 1 hours);
        }
        coordinator.requestRandomness();

        uint256 totalWeight = market.totalWeight();
        uint256 seed;
        while (uint256(keccak256(abi.encode(seed, uint256(1), uint32(0), uint32(0)))) % totalWeight >= 1e16) {
            ++seed;
        }
        randomness.setSeed(seed);
        coordinator.provideRandomness("");
        coordinator.resolveEpoch(1);
        assertGt(market.currentPullPrice(), price);

        coordinator.resolveEpoch(2);
        assertEq(_orderCursor(), 3);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Resolving));

        coordinator.resolveEpoch(2);
        assertEq(_orderCursor(), 5);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalized));
        assertEq(coordinator.refundClaims(buyer), price * 4);
    }

    function testExpiredOrdersConsumeResolveBudget() external {
        uint48 deadline = uint48(block.timestamp + 10);
        uint256 price = market.currentPullPrice();
        for (uint256 i; i < 5; ++i) {
            _requestPull(buyer, buyer, 10);
        }
        coordinator.requestRandomness();
        randomness.setSeed(99);
        coordinator.provideRandomness("");
        vm.warp(uint256(deadline) + 1);

        coordinator.resolveEpoch(2);
        assertEq(_orderCursor(), 2);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Resolving));

        coordinator.resolveEpoch(2);
        assertEq(_orderCursor(), 4);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Resolving));

        coordinator.resolveEpoch(2);
        assertEq(_orderCursor(), 5);
        assertEq(uint8(_epochStatus()), uint8(ProtocolTypes.EpochStatus.Finalized));
        assertEq(coordinator.refundClaims(buyer), price * 5);
    }

    function _requestPull(address requester, address orderReceiver, uint256 ttl)
        private
        returns (uint256 price)
    {
        price = market.currentPullPrice();
        vm.prank(requester);
        coordinator.requestPull(_order(orderReceiver, price, ttl));
    }

    function _depositPosition(uint256 tokenId, uint128 backing) private {
        collection.mint(depositor, tokenId);
        asset.mint(depositor, backing);
        vm.startPrank(depositor);
        collection.approve(address(vault), tokenId);
        asset.approve(address(vault), backing);
        market.depositPosition(address(collection), tokenId, backing, depositor);
        vm.stopPrank();
    }

    function _order(address orderReceiver, uint256 price, uint256 ttl)
        private
        view
        returns (ProtocolTypes.PullOrderInput memory)
    {
        return ProtocolTypes.PullOrderInput({
            receiver: orderReceiver,
            drawCount: 1,
            maxUnitPrice: price.toUint128(),
            maxTotalPrice: price.toUint128(),
            deadline: (block.timestamp + ttl).toUint48(),
            referralCode: bytes32(0)
        });
    }

    function _epochState()
        private
        view
        returns (
            ProtocolTypes.EpochStatus status,
            uint48 randomnessRequestedAt,
            bytes32 requestId,
            uint32 totalResolved
        )
    {
        (, status,, randomnessRequestedAt,,, totalResolved,,,,, requestId,) = coordinator.epoch();
    }

    function _epochStatus() private view returns (ProtocolTypes.EpochStatus status) {
        (, status,,,,,,,,,,,) = coordinator.epoch();
    }

    function _orderCursor() private view returns (uint32 cursor) {
        (,,,,, cursor,,,,,,,) = coordinator.epoch();
    }
}
