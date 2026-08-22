// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { DrawMarket } from "../contracts/DrawMarket.sol";
import { RewardController } from "../contracts/RewardController.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { EpochCoordinator } from "../contracts/EpochCoordinator.sol";
import { PositionNFT } from "../contracts/tokens/PositionNFT.sol";
import { PullReceipt } from "../contracts/tokens/PullReceipt.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { IEligibilityPolicy } from "../contracts/interfaces/IEligibilityPolicy.sol";
import { ISwapAdapter } from "../contracts/interfaces/ISwapAdapter.sol";
import { MockDenylistERC20 } from "./mocks/MockDenylistERC20.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { MockRandomnessAdapter } from "./mocks/MockRandomnessAdapter.sol";
import { MockRewardController } from "./mocks/MockRewardController.sol";

contract SettlementSafetyNoOutputAdapter is ISwapAdapter {
    function swapExactOutput(address, address, uint256, uint256, address, bytes calldata)
        external
        pure
        returns (uint256)
    {
        revert("not implemented");
    }

    function swapExactInput(address inputAsset, address, uint256 amountIn, uint256, address, bytes calldata)
        external
        returns (uint256)
    {
        require(IERC20(inputAsset).transferFrom(msg.sender, address(this), amountIn));
        return type(uint256).max;
    }
}

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

    function requestWithdrawal(DrawMarket market, uint256 positionId, address nftReceiver) external {
        market.requestWithdrawal(positionId, nftReceiver);
    }

    function claimNFT(SettlementEngine engine, address collection, uint256 tokenId, address receiver)
        external
    {
        engine.claimNFT(collection, tokenId, receiver);
    }

    function claimMarketNFT(DrawMarket market, address collection, uint256 tokenId, address receiver)
        external
    {
        market.claimNFT(collection, tokenId, receiver);
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

    function testConfiguredCashPayoutControlsCashAndDrawSettlements() external {
        _deployMarketWithPolicy(8_123, 9_567);
        assertEq(engine.cashPayoutBps(), 8_123);
        assertEq(engine.keepPayoutBps(), 9_567);
        _deposit(alice, 901, 100 ether);
        _drawOne(buyer, 901);

        vm.prank(buyer);
        engine.settleCash(1);

        assertEq(engine.settlementClaims(buyer), 81.23 ether);
        assertTrue(market.solvent());

        _deployMarketWithPolicy(8_123, 9_567);
        _deposit(alice, 902, 100 ether);
        _drawOne(buyer, 902);

        vm.prank(buyer);
        uint256 drawAmount = engine.settleDraw(1, 81.23 ether, "");

        assertEq(drawAmount, 81.23 ether);
        assertEq(rewards.settlementInput(buyer, address(asset)), 81.23 ether);
        assertTrue(market.solvent());
    }

    function testConfiguredKeepPayoutControlsKeepRelistAndForceKeep() external {
        _deployMarketWithPolicy(8_123, 9_567);
        _deposit(alice, 911, 100 ether);
        _drawOne(buyer, 911);
        (,,,,, uint256 keepEarnings,) = engine.selectedPositions(1);

        vm.prank(buyer);
        engine.settleKeep(1);

        assertEq(engine.settlementClaims(alice), 95.67 ether + keepEarnings);
        assertTrue(market.solvent());

        _deployMarketWithPolicy(8_123, 9_567);
        _deposit(alice, 912, 100 ether);
        _drawOne(buyer, 912);
        (,,,,, uint256 relistEarnings,) = engine.selectedPositions(1);

        vm.prank(buyer);
        engine.settleRelist(1, 100 ether);

        assertEq(engine.settlementClaims(alice), 95.67 ether + relistEarnings);
        assertTrue(market.solvent());

        _deployMarketWithPolicy(8_123, 9_567);
        _deposit(alice, 913, 100 ether);
        _drawOne(buyer, 913);
        (,,,,, uint256 forceKeepEarnings,) = engine.selectedPositions(1);
        vm.warp(_receiptData(1).decisionDeadline + 1);

        engine.forceKeep(1);

        assertEq(engine.settlementClaims(alice), 95.67 ether + forceKeepEarnings);
        assertTrue(market.solvent());
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

        assertEq(engine.settlementClaims(buyer), 90 ether);
        _assertDeferredClaim(owner, 1);
        owner.claimNFT(engine, address(collection), 1, redirectedReceiver);
        assertEq(collection.ownerOf(1), redirectedReceiver);
    }

    function testDrawDefersRejectedReturnToPreviousOwner() external {
        SettlementSafetyRejectingReceiver owner = _deployWithRejectingPosition(1);
        _drawOne(buyer, 14);

        vm.prank(buyer);
        engine.settleDraw(1, 80 ether, hex"1234");

        assertEq(rewards.settlementInput(buyer, address(asset)), 90 ether);
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

        assertEq(engine.settlementClaims(buyer), 90 ether);
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

        assertEq(rewards.settlementInput(buyer, address(asset)), 90 ether);
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
        engine.settleDraw(1, 90 ether, hex"deadbeef");

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
        assertEq(engine.settlementClaims(buyer), 90 ether);
    }

    function testNoOutputAdapterCannotConsumeProtectedDrawSettlement() external {
        MockERC20 draw = new MockERC20("Draw", "DRAW", 18);
        SettlementSafetyNoOutputAdapter adapter = new SettlementSafetyNoOutputAdapter();
        RewardController protectedRewards = new RewardController(governor, address(draw), address(adapter));
        _deployMarketWithRewardController(address(protectedRewards));
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 147);
        uint256 liabilitiesBefore = engine.totalLiabilities();
        bytes32 marketRole = protectedRewards.MARKET_ROLE();
        vm.prank(governor);
        protectedRewards.grantRole(marketRole, address(engine));

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(RewardController.SlippageExceeded.selector, 0, 90 ether));
        engine.settleDraw(1, 90 ether, "");

        assertEq(uint8(_receiptData(1).status), uint8(ProtocolTypes.PullStatus.Revealed));
        (,,,, uint128 backing,, uint256 rewardInput) = engine.selectedPositions(1);
        assertEq(backing, 100 ether);
        assertGt(rewardInput, 0);
        assertEq(engine.selectedBackingLiability(), 100 ether);
        assertEq(engine.totalLiabilities(), liabilitiesBefore);
        assertEq(protectedRewards.queuedInput(alice, address(asset)), 0);
        assertEq(asset.balanceOf(address(protectedRewards)), 0);
        assertEq(asset.balanceOf(address(adapter)), 0);
        assertEq(draw.balanceOf(buyer), 0);
        assertEq(collection.ownerOf(1), address(vault));
    }

    function testRewardControllerFailureCannotBlockKeep() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 201);
        (,,,,, uint256 cashEarnings, uint256 rewardInput) = engine.selectedPositions(1);
        rewards.setRejectEnqueue(true);

        vm.prank(buyer);
        engine.settleKeep(1);

        assertGt(rewardInput, 0);
        assertEq(engine.settlementClaims(alice), 99 ether + cashEarnings + rewardInput);
        assertEq(rewards.queued(alice, address(asset)), 0);
        assertEq(asset.balanceOf(address(rewards)), 0);
        assertTrue(market.solvent());
    }

    function testRewardControllerFailureCannotBlockForceKeep() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 202);
        (,,,,, uint256 cashEarnings, uint256 rewardInput) = engine.selectedPositions(1);
        rewards.setRejectEnqueue(true);
        vm.warp(_receiptData(1).decisionDeadline + 1);

        engine.forceKeep(1);

        assertGt(rewardInput, 0);
        assertEq(engine.settlementClaims(alice), 99 ether + cashEarnings + rewardInput);
        assertEq(rewards.queued(alice, address(asset)), 0);
        assertEq(asset.balanceOf(address(rewards)), 0);
        assertTrue(market.solvent());
    }

    function testRewardControllerFailureCannotBlockCashSettlement() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 203);
        (,,,,, uint256 cashEarnings, uint256 rewardInput) = engine.selectedPositions(1);
        rewards.setRejectEnqueue(true);

        vm.prank(buyer);
        engine.settleCash(1);

        assertGt(rewardInput, 0);
        assertEq(engine.settlementClaims(alice), cashEarnings + rewardInput);
        assertEq(engine.settlementClaims(buyer), 90 ether);
        assertEq(rewards.queued(alice, address(asset)), 0);
        assertEq(asset.balanceOf(address(rewards)), 0);
        assertTrue(market.solvent());
    }

    function testSilentRewardEnqueueFailureCannotConsumeFunding() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 207);
        (,,,,, uint256 cashEarnings, uint256 rewardInput) = engine.selectedPositions(1);
        rewards.setIgnoreEnqueue(true);

        vm.prank(buyer);
        engine.settleCash(1);

        assertGt(rewardInput, 0);
        assertEq(engine.settlementClaims(alice), cashEarnings + rewardInput);
        assertEq(rewards.queued(alice, address(asset)), 0);
        assertEq(asset.balanceOf(address(rewards)), 0);
        assertTrue(market.solvent());
    }

    function testRevokedRewardMarketRoleCannotBlockCashSettlement() external {
        MockERC20 draw = new MockERC20("Draw", "DRAW", 18);
        RewardController revokedRewards = new RewardController(governor, address(draw), address(0));
        _deployMarketWithRewardController(address(revokedRewards));
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 206);
        (,,,,, uint256 cashEarnings, uint256 rewardInput) = engine.selectedPositions(1);
        bytes32 marketRole = revokedRewards.MARKET_ROLE();
        vm.startPrank(governor);
        revokedRewards.grantRole(marketRole, address(engine));
        revokedRewards.revokeRole(marketRole, address(engine));
        vm.stopPrank();

        vm.prank(buyer);
        engine.settleCash(1);

        assertGt(rewardInput, 0);
        assertEq(engine.settlementClaims(alice), cashEarnings + rewardInput);
        assertEq(engine.settlementClaims(buyer), 90 ether);
        assertEq(asset.balanceOf(address(revokedRewards)), 0);
        assertEq(collection.ownerOf(1), alice);
        assertTrue(market.solvent());
    }

    function testRewardControllerFailureCannotBlockRelistSettlement() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 204);
        (,,,,, uint256 cashEarnings, uint256 rewardInput) = engine.selectedPositions(1);
        rewards.setRejectEnqueue(true);

        vm.prank(buyer);
        uint256 newPositionId = engine.settleRelist(1, 100 ether);

        assertGt(rewardInput, 0);
        assertEq(engine.settlementClaims(alice), 99 ether + cashEarnings + rewardInput);
        assertEq(market.positionToken().ownerOf(newPositionId), buyer);
        assertEq(rewards.queued(alice, address(asset)), 0);
        assertEq(asset.balanceOf(address(rewards)), 0);
        assertTrue(market.solvent());
    }

    function testRewardEnqueueFailureCannotBlockSuccessfulDrawSettlement() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _drawOne(buyer, 205);
        (,,,,, uint256 cashEarnings, uint256 rewardInput) = engine.selectedPositions(1);
        rewards.setRejectEnqueue(true);

        vm.prank(buyer);
        uint256 drawAmount = engine.settleDraw(1, 90 ether, hex"deadbeef");

        assertEq(drawAmount, 90 ether);
        assertGt(rewardInput, 0);
        assertEq(engine.settlementClaims(alice), cashEarnings + rewardInput);
        assertEq(engine.settlementClaims(buyer), 0);
        assertEq(rewards.queued(alice, address(asset)), 0);
        assertEq(rewards.settlementInput(buyer, address(asset)), 90 ether);
        assertEq(asset.balanceOf(address(rewards)), 90 ether);
        assertEq(collection.ownerOf(1), alice);
        assertTrue(market.solvent());
    }

    function testImmediateWithdrawalCanChooseAlternateNFTReceiver() external {
        SettlementSafetyRejectingReceiver owner = _deployWithRejectingPosition(1);

        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(DrawMarket.Ineligible.selector, governor));
        market.requestWithdrawal(1, redirectedReceiver);

        owner.requestWithdrawal(market, 1, redirectedReceiver);

        assertEq(collection.ownerOf(1), redirectedReceiver);
        assertEq(asset.balanceOf(address(owner)), 100 ether);
        (,,,,, ProtocolTypes.PositionStatus status,,,,,,) = market.positions(1);
        assertEq(uint8(status), uint8(ProtocolTypes.PositionStatus.Withdrawn));
    }

    function testImmediateWithdrawalDefersRejectingNFTWithoutBlockingBacking() external {
        SettlementSafetyRejectingReceiver owner = _deployWithRejectingPosition(1);

        owner.requestWithdrawal(market, 1, address(owner));

        assertEq(asset.balanceOf(address(owner)), 100 ether);
        assertEq(collection.ownerOf(1), address(vault));
        assertEq(market.pendingNFTClaims(address(collection), 1), address(owner));
        owner.claimMarketNFT(market, address(collection), 1, redirectedReceiver);
        assertEq(collection.ownerOf(1), redirectedReceiver);
        assertEq(market.pendingNFTClaims(address(collection), 1), address(0));
    }

    function testImmediateWithdrawalOwnerCanRedirectDenylistedBackingClaim() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        asset.setRejectedRecipient(alice, true);

        vm.prank(alice);
        market.requestWithdrawal(1, redirectedReceiver);

        assertEq(collection.ownerOf(1), redirectedReceiver);
        assertEq(market.settlementClaims(alice), 100 ether);
        assertEq(market.settlementClaimLiability(), 100 ether);
        assertTrue(market.solvent());

        vm.prank(alice);
        vm.expectRevert(DrawMarket.ZeroAddress.selector);
        market.claimSettlement(address(0));
        assertEq(market.settlementClaims(alice), 100 ether);

        vm.prank(governor);
        vm.expectRevert(DrawMarket.NothingToClaim.selector);
        market.claimSettlement(redirectedReceiver);

        uint256 receiverBefore = asset.balanceOf(redirectedReceiver);
        vm.prank(alice);
        market.claimSettlement(redirectedReceiver);
        assertEq(asset.balanceOf(redirectedReceiver) - receiverBefore, 100 ether);
        assertEq(market.settlementClaims(alice), 0);
    }

    function testDistinctDenylistedEarningsRecipientOwnsCashAndRewardFallback() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        address earningsRecipient = makeAddr("distinct-earnings-recipient");
        _depositFor(alice, 1, 100 ether, earningsRecipient);
        _depositFor(alice, 2, 200 ether, earningsRecipient);
        _drawOne(buyer, 31);
        uint256 selectedPositionId = _receiptData(1).positionId;
        uint256 survivor = selectedPositionId == 1 ? 2 : 1;
        (uint256 cash, uint256 rewardInput) = market.pendingPositionEarnings(survivor);
        assertGt(cash, 0);
        assertGt(rewardInput, 0);
        asset.setRejectedRecipient(earningsRecipient, true);
        rewards.setRejectEnqueue(true);

        uint256 ownerBefore = asset.balanceOf(alice);
        vm.prank(alice);
        market.requestWithdrawal(survivor, redirectedReceiver);

        uint256 backing = survivor == 1 ? 100 ether : 200 ether;
        uint256 earningsClaim = cash + rewardInput;
        assertEq(asset.balanceOf(alice) - ownerBefore, backing);
        assertEq(collection.ownerOf(survivor), redirectedReceiver);
        assertEq(market.settlementClaims(earningsRecipient), earningsClaim);
        assertEq(rewards.queued(earningsRecipient, address(asset)), 0);

        uint256 ownerClaim = market.settlementClaims(alice);
        assertGt(ownerClaim, 0, "Crown fallback makes ownership separation adversarial");
        uint256 receiverBefore = asset.balanceOf(redirectedReceiver);
        vm.prank(alice);
        market.claimSettlement(redirectedReceiver);
        assertEq(asset.balanceOf(redirectedReceiver) - receiverBefore, ownerClaim);
        assertEq(market.settlementClaims(earningsRecipient), earningsClaim);

        receiverBefore = asset.balanceOf(redirectedReceiver);
        vm.prank(earningsRecipient);
        market.claimSettlement(redirectedReceiver);
        assertEq(asset.balanceOf(redirectedReceiver) - receiverBefore, earningsClaim);
    }

    function testQueuedDenylistedOwnerCanExitAndRedirectBacking() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        _deposit(alice, 2, 200 ether);
        uint256 price = market.currentPullPrice();
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: buyer,
            drawCount: 1,
            maxUnitPrice: SafeCast.toUint128(price),
            maxTotalPrice: SafeCast.toUint128(price),
            deadline: uint48(block.timestamp + 1),
            referralCode: bytes32(0)
        });
        vm.prank(buyer);
        coordinator.requestPull(input);
        vm.prank(alice);
        market.requestWithdrawal(1);
        coordinator.requestRandomness();
        randomness.setSeed(32);
        coordinator.provideRandomness("");
        vm.warp(block.timestamp + 2);
        coordinator.resolveEpoch(1);
        coordinator.advanceEpochBoundary(1);
        asset.setRejectedRecipient(alice, true);

        vm.prank(alice);
        market.claimWithdrawal(1, redirectedReceiver);

        assertEq(collection.ownerOf(1), redirectedReceiver);
        assertEq(market.settlementClaims(alice), 100 ether);
        assertTrue(market.solvent());
        uint256 receiverBefore = asset.balanceOf(redirectedReceiver);
        vm.prank(alice);
        market.claimSettlement(redirectedReceiver);
        assertEq(asset.balanceOf(redirectedReceiver) - receiverBefore, 100 ether);
    }

    function testRefundOwnerCanRedirectDenylistedRefund() external {
        _deployMarket(address(0), 1_000 ether, buyback);
        _deposit(alice, 1, 100 ether);
        uint256 price = market.currentPullPrice();
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: buyer,
            drawCount: 1,
            maxUnitPrice: SafeCast.toUint128(price),
            maxTotalPrice: SafeCast.toUint128(price),
            deadline: uint48(block.timestamp + 1),
            referralCode: bytes32(0)
        });
        vm.prank(buyer);
        coordinator.requestPull(input);
        coordinator.requestRandomness();
        randomness.setSeed(33);
        coordinator.provideRandomness("");
        vm.warp(block.timestamp + 2);
        coordinator.resolveEpoch(1);
        assertEq(coordinator.refundClaims(buyer), price);
        asset.setRejectedRecipient(buyer, true);

        vm.prank(buyer);
        vm.expectRevert(EpochCoordinator.InvalidRefundReceiver.selector);
        coordinator.claimRefund(address(0));
        assertEq(coordinator.refundClaims(buyer), price);

        vm.prank(governor);
        vm.expectRevert(EpochCoordinator.NothingToClaim.selector);
        coordinator.claimRefund(redirectedReceiver);

        uint256 receiverBefore = asset.balanceOf(redirectedReceiver);
        vm.prank(buyer);
        coordinator.claimRefund(redirectedReceiver);
        assertEq(asset.balanceOf(redirectedReceiver) - receiverBefore, price);
        assertEq(coordinator.refundClaims(buyer), 0);
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
        _deployMarketFromConfig(config);
    }

    function _deployMarketWithRewardController(address rewardController) private {
        ProtocolTypes.MarketConfig memory config = _config(address(0), 1_000 ether, buyback);
        config.rewardController = rewardController;
        _deployMarketFromConfig(config);
    }

    function _deployMarketWithPolicy(uint16 cashPayoutBps, uint16 keepPayoutBps) private {
        ProtocolTypes.MarketConfig memory config = _config(address(0), 1_000 ether, buyback);
        config.cashPayoutBps = cashPayoutBps;
        config.keepPayoutBps = keepPayoutBps;
        _deployMarketFromConfig(config);
    }

    function _deployMarketFromConfig(ProtocolTypes.MarketConfig memory config) private {
        _initializeFresh(config);
        bytes32 marketRole = referrals.MARKET_ROLE();
        vm.prank(governor);
        referrals.grantRole(marketRole, address(coordinator));
        asset.mint(buyer, config.maxBacking);
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
            config.decisionWindow,
            config.cashPayoutBps,
            config.keepPayoutBps
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
            markupBps: 250,
            cashPayoutBps: 9_000,
            keepPayoutBps: 9_900
        });
    }

    function _deposit(address owner, uint256 tokenId, uint128 backing) private {
        _depositFor(owner, tokenId, backing, owner);
    }

    function _depositFor(address owner, uint256 tokenId, uint128 backing, address earningsRecipient) private {
        collection.mint(owner, tokenId);
        asset.mint(owner, backing);
        vm.startPrank(owner);
        collection.approve(address(vault), tokenId);
        asset.approve(address(vault), backing);
        market.depositPosition(address(collection), tokenId, backing, earningsRecipient);
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
