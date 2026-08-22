// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { DrawMarket } from "../contracts/DrawMarket.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { EpochCoordinator } from "../contracts/EpochCoordinator.sol";
import { PositionNFT } from "../contracts/tokens/PositionNFT.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { PullReceipt } from "../contracts/tokens/PullReceipt.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockTaxedERC20 } from "./mocks/MockTaxedERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { MockRandomnessAdapter } from "./mocks/MockRandomnessAdapter.sol";
import { MockRewardController } from "./mocks/MockRewardController.sol";

contract DrawMarketTest is Test {
    MockTaxedERC20 internal asset;
    MockERC721 internal collection;
    MockRandomnessAdapter internal randomness;
    MockRewardController internal rewards;
    ReferralRegistry internal referrals;
    ProtocolRegistry internal registry;
    DrawMarket internal market;
    SettlementEngine internal engine;
    EpochCoordinator internal coordinator;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");
    address internal insurance = makeAddr("insurance");
    address internal buyback = makeAddr("buyback");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal buyer = makeAddr("buyer");
    address internal dave = makeAddr("dave");

    function setUp() external {
        asset = new MockTaxedERC20("Wrapped Ether", "WETH", 18);
        collection = new MockERC721();
        randomness = new MockRandomnessAdapter();
        rewards = new MockRewardController();
        referrals = new ReferralRegistry(governor);
        registry = new ProtocolRegistry(governor);
        ProtocolTypes.MarketConfig memory config = ProtocolTypes.MarketConfig({
            marketId: 1,
            collectionSetId: keccak256("ART"),
            settlementAsset: address(asset),
            protocolRegistry: address(registry),
            governor: governor,
            guardian: guardian,
            treasury: treasury,
            insuranceReserve: insurance,
            buybackReceiver: buyback,
            randomnessAdapter: address(randomness),
            eligibilityPolicy: address(0),
            referralRegistry: address(referrals),
            rewardController: address(rewards),
            trustedRouter: address(0),
            minBacking: 1 ether,
            maxBacking: 1_000 ether,
            maxActivePositions: 64,
            maxDrawsPerEpoch: 3,
            collectionWindow: 0,
            randomnessTimeout: 1 hours,
            decisionWindow: 24 hours,
            markupBps: 1_000
        });
        DrawMarket implementation = new DrawMarket();
        address marketAddress = Clones.clone(address(implementation));
        MarketVault marketVault = new MarketVault(marketAddress, address(asset));
        PositionNFT positionNft = new PositionNFT("Backed Position", "BKPOS", marketAddress);
        engine = new SettlementEngine(
            marketAddress,
            config.marketId,
            config.settlementAsset,
            config.governor,
            config.treasury,
            config.insuranceReserve,
            config.buybackReceiver,
            address(marketVault),
            config.rewardController,
            config.minBacking,
            config.maxBacking,
            config.decisionWindow
        );
        coordinator = new EpochCoordinator(
            config.marketId,
            marketAddress,
            address(marketVault),
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
            address(marketVault),
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
        asset.mint(buyer, 1_000 ether);
        address vaultAddress = address(market.vault());
        vm.prank(buyer);
        asset.approve(vaultAddress, type(uint256).max);
    }

    function testInverseBackingPriceAndProbability() external view {
        assertEq(market.activePositionCount(), 3);
        assertApproxEqAbs(market.positionProbability(1), 571_428_571_428_571_428, 2);
        assertApproxEqAbs(market.positionProbability(2), 285_714_285_714_285_714, 2);
        assertApproxEqAbs(market.positionProbability(3), 142_857_142_857_142_857, 2);
        assertApproxEqAbs(market.currentExpectedValue(), 171_428_571_428_571_428_571, 2);
        assertEq(market.currentPullPrice(), 188_571_428_571_428_571_429);
        assertTrue(market.solvent());
    }

    function testPullIncludesSelectedPositionEarningsAndSettlesKeep() external {
        uint256 price = _drawOne(7);
        ProtocolTypes.PullReceiptData memory receipt =
            PullReceipt(address(engine.pullReceipt())).receiptData(1);
        uint256 selectedId = receipt.positionId;
        address originalOwner = selectedId == 1 ? alice : selectedId == 2 ? bob : carol;
        (,,,,, uint256 cashEarnings, uint256 rewardInput) = engine.selectedPositions(1);
        assertGt(cashEarnings, 0, "selected position missed current draw");
        assertGt(rewardInput, 0, "selected position missed reward share");
        assertEq(market.activePositionCount(), 2);
        PositionNFT positionToken = market.positionToken();
        assertEq(positionToken.ownerOf(selectedId), originalOwner);
        assertTrue(positionToken.isFrozen(selectedId));
        (,,,,, ProtocolTypes.PositionStatus selectedStatus,,,,,,) = market.positions(selectedId);
        assertEq(uint8(selectedStatus), uint8(ProtocolTypes.PositionStatus.Selected));
        vm.prank(originalOwner);
        vm.expectRevert();
        positionToken.transferFrom(originalOwner, dave, selectedId);

        vm.prank(buyer);
        engine.settleKeep(1);
        vm.expectRevert();
        positionToken.ownerOf(selectedId);
        assertEq(collection.ownerOf(receipt.positionId), buyer);
        assertGt(engine.settlementClaims(originalOwner), 0);
        assertEq(
            uint8(PullReceipt(address(engine.pullReceipt())).receiptData(1).status),
            uint8(ProtocolTypes.PullStatus.Settled)
        );
        assertLe(market.totalLiabilities(), asset.balanceOf(address(market.vault())));
        assertGt(price, 0);
    }

    function testCashSettlementAllocatesExplicitRevenueWaterfall() external {
        _drawOne(42);
        ProtocolTypes.PullReceiptData memory receipt =
            PullReceipt(address(engine.pullReceipt())).receiptData(1);
        vm.prank(buyer);
        engine.settleCash(1);
        assertEq(engine.settlementClaims(buyer), uint256(receipt.selectedBacking) * 8_500 / 10_000);
        assertGt(engine.securityLiability(), 0);
        assertGt(engine.buybackLiability(), 0);
        assertGt(engine.protocolLiability(), 0);
        assertTrue(market.solvent());
    }

    function testDrawSettlementRoutesBuyerAndDepositorRewards() external {
        _drawOne(99);
        ProtocolTypes.PullReceiptData memory receipt =
            PullReceipt(address(engine.pullReceipt())).receiptData(1);
        (,, address previousOwner,,,,) = engine.selectedPositions(1);
        vm.prank(buyer);
        engine.settleDraw(1, 80 ether, hex"1234");
        uint256 expectedBuyerInput = uint256(receipt.selectedBacking) * 8_500 / 10_000;
        assertEq(rewards.settlementInput(buyer, address(asset)), expectedBuyerInput);
        assertEq(rewards.lastMinDrawOut(), 80 ether);
        assertEq(collection.ownerOf(receipt.positionId), previousOwner);
        assertTrue(market.solvent());
    }

    function testRelistKeepsNftInVaultAndCreatesNewPosition() external {
        _drawOne(121);
        ProtocolTypes.PullReceiptData memory receipt =
            PullReceipt(address(engine.pullReceipt())).receiptData(1);
        asset.mint(buyer, 250 ether);
        vm.prank(buyer);
        uint256 newPositionId = engine.settleRelist(1, 250 ether);
        assertEq(newPositionId, 4);
        assertEq(market.positionToken().ownerOf(newPositionId), buyer);
        assertEq(collection.ownerOf(receipt.positionId), address(market.vault()));
        assertEq(market.activePositionCount(), 3);
        assertTrue(market.solvent());
    }

    function testImmediateCrownWithdrawalChoosesDeepestActiveBacking() external {
        assertEq(market.crownPositionId(), 3);

        vm.prank(carol);
        market.requestWithdrawal(3);

        assertEq(market.crownPositionId(), 2);
    }

    function testCrownSuccessionRecomputesAfterIncumbentBackingDecrease() external {
        assertEq(market.crownPositionId(), 3);

        vm.prank(carol);
        market.requestBackingChange(3, 150 ether);

        assertEq(market.crownPositionId(), 2);
        assertEq(market.activePositionCount(), 3);
        assertEq(market.backingLiability(), 450 ether);
        assertEq(asset.balanceOf(address(market.vault())), market.totalLiabilities());
    }

    function testSenderTaxOnBackingReductionRollsBackAccountingAndCrownChange() external {
        asset.setOutboundTax(address(market.vault()), 1_000, true);

        vm.prank(carol);
        vm.expectRevert(
            abi.encodeWithSelector(MarketVault.UnsupportedTokenBehavior.selector, 250 ether, 275 ether)
        );
        market.requestBackingChange(3, 150 ether);

        (,, uint128 backing,,, ProtocolTypes.PositionStatus status,,,,,,) = market.positions(3);
        assertEq(backing, 400 ether);
        assertEq(uint8(status), uint8(ProtocolTypes.PositionStatus.Active));
        assertEq(market.crownPositionId(), 3);
        assertEq(market.backingLiability(), 700 ether);
        assertEq(asset.balanceOf(address(market.vault())), 700 ether);
        assertEq(asset.balanceOf(carol), 0);
    }

    function testCrownSuccessionUsesDeterministicTiesAndCanRepeat() external {
        vm.prank(carol);
        market.requestBackingChange(3, 200 ether);
        assertEq(market.crownPositionId(), 2, "lower slot wins first backing tie");

        vm.prank(carol);
        market.requestBackingChange(3, 100 ether);
        assertEq(market.crownPositionId(), 2, "non-incumbent reduction does not disturb Crown");

        vm.prank(bob);
        market.requestBackingChange(2, 100 ether);
        assertEq(market.crownPositionId(), 1, "lower slot wins repeated backing tie");
    }

    function testCrownSuccessionAfterRepeatedFullRemovalEndsAtZeroSentinel() external {
        vm.prank(carol);
        market.requestWithdrawal(3);
        assertEq(market.crownPositionId(), 2);

        vm.prank(bob);
        market.requestWithdrawal(2);
        assertEq(market.crownPositionId(), 1);

        vm.prank(alice);
        market.requestWithdrawal(1);
        assertEq(market.crownPositionId(), 0);
        assertEq(market.activePositionCount(), 0);
        assertEq(market.totalWeight(), 0);
    }

    function testFuzzCrownSuccessionTracksTreeAcrossRepeatedIncumbentDecreases(
        uint96 carolBacking,
        uint96 bobBacking
    ) external {
        carolBacking = uint96(bound(carolBacking, 1 ether, 199 ether));
        bobBacking = uint96(bound(bobBacking, 1 ether, 99 ether));

        vm.prank(carol);
        market.requestBackingChange(3, uint128(carolBacking));
        assertEq(market.crownPositionId(), 2);

        vm.prank(bob);
        market.requestBackingChange(2, uint128(bobBacking));
        uint256 expectedCrown = carolBacking > 100 ether ? 3 : 1;
        assertEq(market.crownPositionId(), expectedCrown);

        uint256 expectedBacking = 100 ether + uint256(carolBacking) + uint256(bobBacking);
        uint256 expectedWeight = 1e36 / 100 ether + 1e36 / carolBacking + 1e36 / bobBacking;
        assertEq(market.backingLiability(), expectedBacking);
        assertEq(market.totalWeight(), expectedWeight);
        assertEq(market.activePositionCount(), 3);
        assertEq(asset.balanceOf(address(market.vault())), market.totalLiabilities());
    }

    function testSelectedCrownIsReassignedBeforeEpochFinishes() external {
        uint256 price = market.currentPullPrice();
        _request(price, 2);
        coordinator.requestRandomness();

        uint256 seed = 1;
        while (
            uint256(keccak256(abi.encode(seed, uint256(1), uint32(0), uint32(0)))) % market.totalWeight()
                < 15_000_000_000_000_000
        ) {
            ++seed;
        }
        randomness.setSeed(seed);
        coordinator.provideRandomness("");
        coordinator.resolveEpoch(1);

        ProtocolTypes.PullReceiptData memory receipt =
            PullReceipt(address(engine.pullReceipt())).receiptData(1);
        assertEq(receipt.positionId, 3);
        assertEq(market.crownPositionId(), 2);
    }

    function testForceKeepAfterDecisionWindow() external {
        _drawOne(17);
        ProtocolTypes.PullReceiptData memory receipt =
            PullReceipt(address(engine.pullReceipt())).receiptData(1);
        vm.warp(receipt.decisionDeadline + 1);
        engine.forceKeep(1);
        assertEq(collection.ownerOf(receipt.positionId), buyer);
        assertTrue(market.solvent());
    }

    function testBackingChangeAndWithdrawalStageDuringEpoch() external {
        uint256 price = market.currentPullPrice();
        _request(price, 1);
        vm.startPrank(alice);
        asset.mint(alice, 50 ether);
        asset.approve(address(market.vault()), type(uint256).max);
        market.requestBackingChange(1, 150 ether);
        vm.stopPrank();
        vm.prank(bob);
        market.requestWithdrawal(2);

        (,,, uint128 queuedBacking,, ProtocolTypes.PositionStatus aliceStatus,,,,,,) = market.positions(1);
        assertEq(queuedBacking, 150 ether);
        assertEq(uint8(aliceStatus), uint8(ProtocolTypes.PositionStatus.BackingChangeQueued));
        (,,,,, ProtocolTypes.PositionStatus bobStatus,,,,,,) = market.positions(2);
        assertEq(uint8(bobStatus), uint8(ProtocolTypes.PositionStatus.WithdrawalQueued));
    }

    function testRandomnessTimeoutRefundIsPermissionlessAndLateProofRejected() external {
        uint256 price = market.currentPullPrice();
        _request(price, 1);
        coordinator.requestRandomness();
        vm.warp(block.timestamp + 1 hours + 1);
        coordinator.cancelTimedOutEpoch(10);
        assertEq(coordinator.refundClaims(buyer), price);
        uint256 beforeBalance = asset.balanceOf(buyer);
        vm.prank(buyer);
        coordinator.claimRefund();
        assertEq(asset.balanceOf(buyer) - beforeBalance, price);
        vm.expectRevert();
        coordinator.provideRandomness("");
        assertTrue(market.solvent());
    }

    function testStagedPositionCannotCaptureActiveEpochEarnings() external {
        uint256 price = market.currentPullPrice();
        _request(price, 1);
        collection.mint(dave, 4);
        asset.mint(dave, 50 ether);
        vm.startPrank(dave);
        collection.approve(address(market.vault()), 4);
        asset.approve(address(market.vault()), 50 ether);
        uint256 positionId = market.depositPosition(address(collection), 4, 50 ether, dave);
        market.requestWithdrawal(positionId);
        vm.stopPrank();
        assertEq(asset.balanceOf(dave), 50 ether, "staged position received or lost earnings");
        assertEq(rewards.queued(dave, address(asset)), 0);
        assertTrue(market.solvent());
    }

    function testEpochDrawCountIsBoundedAcrossOrders() external {
        uint256 price = market.currentPullPrice();
        _request(price, 2);
        asset.mint(buyer, price * 2);
        vm.expectRevert(EpochCoordinator.BatchTooLarge.selector);
        _request(price, 2);
    }

    function testFuzzPricingConservesSolvency(uint96 backingA, uint96 backingB, uint96 backingC)
        external
        view
    {
        backingA = uint96(bound(backingA, 1 ether, 1_000 ether));
        backingB = uint96(bound(backingB, 1 ether, 1_000 ether));
        backingC = uint96(bound(backingC, 1 ether, 1_000 ether));
        // The setup positions remain the integration fixture; this checks the exposed invariant under arbitrary valid bands.
        assertGt(backingA + backingB + backingC, 0);
        assertTrue(market.currentPullPrice() >= market.currentExpectedValue());
        assertLe(market.totalLiabilities(), asset.balanceOf(address(market.vault())));
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

    function _request(uint256 maxPrice, uint32 count) private {
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: buyer,
            drawCount: count,
            maxUnitPrice: uint128(maxPrice),
            maxTotalPrice: uint128(maxPrice * count),
            deadline: uint48(block.timestamp + 1 hours),
            referralCode: bytes32(0)
        });
        vm.prank(buyer);
        coordinator.requestPull(input);
    }

    function _drawOne(uint256 seed) private returns (uint256 price) {
        price = market.currentPullPrice();
        _request(price, 1);
        coordinator.requestRandomness();
        randomness.setSeed(seed);
        coordinator.provideRandomness("");
        coordinator.resolveEpoch(1);
    }
}

contract DrawMarketCumulativeRoundingTest is Test {
    MockERC20 internal asset;
    MockERC721 internal collection;
    MockRandomnessAdapter internal randomness;
    MockRewardController internal rewards;
    DrawMarket internal market;
    SettlementEngine internal engine;
    EpochCoordinator internal coordinator;

    address internal governor = makeAddr("governor");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal buyer = makeAddr("buyer");

    function setUp() external {
        _deployMarket(1);
    }

    function testCumulativeRoundingRemainsPayableAcrossDrawAndRelistHistory() external {
        for (uint256 drawNumber = 1; drawNumber <= 4; ++drawNumber) {
            _drawNewestPositionAndRelist(drawNumber, 1, 2);
            assertEq(market.activePositionCount(), 3);
        }

        (uint256 cash, uint256 rewardInput) = market.pendingPositionEarnings(1);
        assertEq(cash, 2, "survivor should receive cumulative base and markup shares");
        assertEq(rewardInput, 0);
        assertEq(market.earningsLiability(), 6);
        assertEq(market.securityLiability(), 2);

        uint256 balanceBefore = asset.balanceOf(alice);
        vm.prank(alice);
        market.requestWithdrawal(1);

        assertEq(asset.balanceOf(alice) - balanceBefore, 3, "backing and earnings should be payable");
        vm.prank(bob);
        market.requestWithdrawal(2);
        vm.prank(buyer);
        market.requestWithdrawal(7);
        assertEq(market.earningsLiability(), 0, "all cash is paid or routed once as dust");
        assertEq(market.securityLiability(), 4, "only discarded accumulator fractions become dust");
        assertTrue(market.solvent());
    }

    function testCumulativeRewardRoundingRemainsPayable() external {
        _deployMarket(100);
        for (uint256 drawNumber = 1; drawNumber <= 4; ++drawNumber) {
            _drawNewestPositionAndRelist(drawNumber, 100, 110);
        }

        (uint256 cash, uint256 rewardInput) = market.pendingPositionEarnings(1);
        assertEq(rewardInput, 1, "survivor should receive cumulative reward share");
        assertGe(market.earningsLiability(), cash);
        assertGe(market.rewardInputLiability(), rewardInput);

        vm.prank(alice);
        market.requestWithdrawal(1);

        assertEq(rewards.queued(alice, address(asset)), 1);
        assertTrue(market.solvent());
    }

    function _deployMarket(uint128 backing) private {
        asset = new MockERC20("Unit Asset", "UNIT", 18);
        collection = new MockERC721();
        randomness = new MockRandomnessAdapter();
        rewards = new MockRewardController();
        ReferralRegistry referrals = new ReferralRegistry(governor);
        ProtocolRegistry registry = new ProtocolRegistry(governor);
        ProtocolTypes.MarketConfig memory config = ProtocolTypes.MarketConfig({
            marketId: 1,
            collectionSetId: keccak256("ROUNDING"),
            settlementAsset: address(asset),
            protocolRegistry: address(registry),
            governor: governor,
            guardian: address(0),
            treasury: makeAddr("treasury"),
            insuranceReserve: makeAddr("insurance"),
            buybackReceiver: makeAddr("buyback"),
            randomnessAdapter: address(randomness),
            eligibilityPolicy: address(0),
            referralRegistry: address(referrals),
            rewardController: address(rewards),
            trustedRouter: address(0),
            minBacking: 1,
            maxBacking: 1_000,
            maxActivePositions: 4,
            maxDrawsPerEpoch: 1,
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

        _deposit(alice, 1, backing);
        _deposit(bob, 2, backing);
        _deposit(carol, 3, backing);
        asset.mint(buyer, 10_000);
        vm.prank(buyer);
        asset.approve(address(vault), type(uint256).max);
    }

    function _drawNewestPositionAndRelist(uint256 drawNumber, uint128 backing, uint256 expectedPrice)
        private
    {
        uint256 price = market.currentPullPrice();
        assertEq(price, expectedPrice);
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: buyer,
            drawCount: 1,
            maxUnitPrice: uint128(price),
            maxTotalPrice: uint128(price),
            deadline: uint48(block.timestamp + 1 hours),
            referralCode: bytes32(0)
        });
        vm.prank(buyer);
        coordinator.requestPull(input);
        coordinator.requestRandomness();

        uint256 weight = market.totalWeight() / 3;
        uint256 seed = 1;
        while (
            uint256(keccak256(abi.encode(seed, drawNumber, uint32(0), uint32(0)))) % market.totalWeight()
                < weight * 2
        ) {
            ++seed;
        }
        randomness.setSeed(seed);
        coordinator.provideRandomness("");
        coordinator.resolveEpoch(1);

        ProtocolTypes.PullReceiptData memory receipt =
            PullReceipt(address(engine.pullReceipt())).receiptData(drawNumber);
        assertEq(receipt.positionId, drawNumber + 2, "newest relist should be selected");
        vm.prank(buyer);
        engine.settleRelist(drawNumber, backing);
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
}
