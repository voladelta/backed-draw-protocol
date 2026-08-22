// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DrawMarket } from "../contracts/DrawMarket.sol";
import { EpochCoordinator } from "../contracts/EpochCoordinator.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { IRewardController } from "../contracts/interfaces/IRewardController.sol";
import { PositionNFT } from "../contracts/tokens/PositionNFT.sol";
import { PullReceipt } from "../contracts/tokens/PullReceipt.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { MockRandomnessAdapter } from "./mocks/MockRandomnessAdapter.sol";

contract InvariantRewardController is IRewardController {
    error EnqueueRejected();
    error SettlementSwapRejected();
    error NothingToClaim();

    mapping(address beneficiary => mapping(address asset => uint256 amount)) public queued;
    mapping(address beneficiary => mapping(address asset => uint256 amount)) public settlementInput;
    mapping(address asset => uint256 amount) public totalQueued;
    mapping(address asset => uint256 amount) public totalSettlementInput;
    bool public rejectEnqueue;
    bool public ignoreEnqueue;
    bool public rejectSettlementSwap;

    function setFailures(bool rejectEnqueue_, bool ignoreEnqueue_, bool rejectSettlementSwap_) external {
        rejectEnqueue = rejectEnqueue_;
        ignoreEnqueue = ignoreEnqueue_;
        rejectSettlementSwap = rejectSettlementSwap_;
    }

    function enqueue(address beneficiary, address inputAsset, uint256 inputAmount) external {
        if (rejectEnqueue) revert EnqueueRejected();
        if (ignoreEnqueue) return;
        queued[beneficiary][inputAsset] += inputAmount;
        totalQueued[inputAsset] += inputAmount;
    }

    function queuedInput(address beneficiary, address inputAsset) external view returns (uint256) {
        return queued[beneficiary][inputAsset];
    }

    function swapSettlement(
        address beneficiary,
        address inputAsset,
        uint256 inputAmount,
        uint256,
        bytes calldata
    ) external returns (uint256 drawAmount) {
        if (rejectSettlementSwap) revert SettlementSwapRejected();
        settlementInput[beneficiary][inputAsset] += inputAmount;
        totalSettlementInput[inputAsset] += inputAmount;
        return inputAmount;
    }

    function claim(address inputAsset, address receiver) external returns (uint256 amount) {
        amount = queued[msg.sender][inputAsset];
        if (amount == 0) revert NothingToClaim();
        queued[msg.sender][inputAsset] = 0;
        totalQueued[inputAsset] -= amount;
        require(IERC20(inputAsset).transfer(receiver, amount));
    }
}

contract InvariantRejectingReceiver is IERC721Receiver {
    bool public rejects;

    function setRejects(bool rejects_) external {
        rejects = rejects_;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (rejects) revert("receiver rejected NFT");
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract ProtocolHandler is Test {
    using SafeCast for uint256;

    uint256 internal constant MIN_BACKING = 10 ether;
    uint256 internal constant MAX_BACKING = 100 ether;
    uint256 internal constant MAX_POSITIONS = 18;
    bytes32 internal constant REFERRAL_CODE = keccak256("INVARIANT_REFERRAL");

    MockERC20 public immutable asset;
    MockERC721 public immutable collection;
    MockRandomnessAdapter public immutable randomness;
    InvariantRewardController public immutable rewards;
    InvariantRejectingReceiver public immutable rejectingReceiver;
    DrawMarket public immutable market;
    MarketVault public immutable vault;
    SettlementEngine public immutable engine;
    EpochCoordinator public immutable coordinator;
    PullReceipt public immutable pullReceipt;
    PositionNFT public immutable positionToken;
    address public immutable governor;
    address public immutable treasury;
    address public immutable insurance;
    address public immutable buyback;

    address[4] internal _actors;
    uint256 public nextTokenId = 1;

    uint256 public depositCalls;
    uint256 public backingChangeCalls;
    uint256 public withdrawalRequestCalls;
    uint256 public withdrawalClaimCalls;
    uint256 public pullRequestCalls;
    uint256 public resolutionCalls;
    uint256 public cancellationCalls;
    uint256 public settlementCalls;
    uint256 public forceKeepCalls;
    uint256 public rewardFailureCalls;
    uint256 public receiverFailureCalls;
    uint256 public rewardClaimCalls;
    uint256 public revenueClaimCalls;
    uint256 public crownChallengeCalls;
    uint256 public healthySeedCancellationRejections;
    uint256 public resolutionFailureCalls;
    uint256 public recoveryStepCalls;
    uint256 public marketNFTDeferralCalls;
    uint256 public nftClaimCalls;
    uint256 public expectedReverts;

    constructor(
        MockERC20 asset_,
        MockERC721 collection_,
        MockRandomnessAdapter randomness_,
        InvariantRewardController rewards_,
        InvariantRejectingReceiver rejectingReceiver_,
        DrawMarket market_,
        SettlementEngine engine_,
        EpochCoordinator coordinator_,
        address governor_,
        address treasury_,
        address insurance_,
        address buyback_,
        address[4] memory actors_
    ) {
        asset = asset_;
        collection = collection_;
        randomness = randomness_;
        rewards = rewards_;
        rejectingReceiver = rejectingReceiver_;
        market = market_;
        vault = market_.vault();
        engine = engine_;
        coordinator = coordinator_;
        pullReceipt = PullReceipt(address(engine_.pullReceipt()));
        positionToken = market_.positionToken();
        governor = governor_;
        treasury = treasury_;
        insurance = insurance_;
        buyback = buyback_;
        _actors = actors_;

        for (uint256 i; i < actors_.length; ++i) {
            asset.mint(actors_[i], 1_000_000 ether);
            vm.prank(actors_[i]);
            asset.approve(address(vault), type(uint256).max);
        }
        asset.mint(address(rejectingReceiver_), 1_000_000 ether);
        vm.prank(address(rejectingReceiver_));
        asset.approve(address(vault), type(uint256).max);
    }

    function bootstrap() external {
        deposit(0, 20 ether);
        deposit(1, 35 ether);
        deposit(2, 60 ether);
        changeBacking(0, 45 ether);
        challengeCrown(0);
        requestWithdrawal(0);
        deposit(3, 75 ether);

        requestPull(0, false);
        requestWithdrawal(1);
        requestWithdrawal(2);
        changeBacking(2, 80 ether);
        progressEpoch(17, false);
        progressEpoch(17, false);
        progressEpoch(17, false);
        progressEpoch(17, false);
        claimWithdrawal(0, false);

        rewards.setFailures(true, false, false);
        rewardFailureCalls++;
        rejectingReceiver.setRejects(true);
        settleReceipt(0, 0);
        claimDeferredNFT(0);
        claimClaims(0);
        claimClaims(3);
        rewards.setFailures(false, false, false);

        deposit(0, 30 ether);
        requestPull(1, false);
        progressEpoch(31, true);
        progressEpoch(31, true);
        claimClaims(1);

        requestPull(2, true);
        progressEpoch(41, false);
        progressEpoch(41, false);
        progressEpoch(41, true);
        rewards.setFailures(false, false, true);
        attemptDrawFailure(0);
        rewards.setFailures(false, false, false);
        forceExpiredKeep(0);
        claimDeferredNFT(0);
        for (uint256 i; i < 10; ++i) {
            claimRewards(i);
        }
        claimRevenues();

        deposit(0, 50 ether);
        requestPull(0, false);
        requestPull(1, false);
        progressEpoch(53, false);
        progressEpoch(53, false);
        triggerUnexpectedResolutionFailure();
        progressEpoch(53, false);
        progressEpoch(53, false);
        progressEpoch(53, false);

        deferWithdrawalNFT(55 ether);
        claimDeferredNFT(0);
        deferWithdrawalNFT(65 ether);
    }

    function deposit(uint256 actorSeed, uint256 backingSeed) public {
        if (market.nextPositionId() > MAX_POSITIONS || market.boundaryActive()) return;
        if (!market.epochLocked() && market.activePositionCount() >= market.maxActivePositions()) return;
        address actor = _actors[actorSeed % _actors.length];
        uint128 backing = (MIN_BACKING + backingSeed % (MAX_BACKING - MIN_BACKING + 1)).toUint128();
        uint256 tokenId = nextTokenId++;
        collection.mint(actor, tokenId);
        vm.startPrank(actor);
        collection.approve(address(vault), tokenId);
        market.depositPosition(address(collection), tokenId, backing, actor);
        vm.stopPrank();
        depositCalls++;
    }

    function changeBacking(uint256 positionSeed, uint256 backingSeed) public {
        uint256 positionId = _positionWithStatus(
            positionSeed, ProtocolTypes.PositionStatus.Active, ProtocolTypes.PositionStatus.Active
        );
        if (positionId == 0 || market.boundaryActive()) return;
        address owner = positionToken.ownerOf(positionId);
        uint128 backing = (MIN_BACKING + backingSeed % (MAX_BACKING - MIN_BACKING + 1)).toUint128();
        vm.prank(owner);
        market.requestBackingChange(positionId, backing);
        backingChangeCalls++;
    }

    function requestWithdrawal(uint256 positionSeed) public {
        uint256 positionId = _withdrawablePosition(positionSeed);
        if (positionId == 0 || market.boundaryActive()) return;
        address owner = positionToken.ownerOf(positionId);
        vm.prank(owner);
        market.requestWithdrawal(positionId, owner);
        withdrawalRequestCalls++;
    }

    function claimWithdrawal(uint256 positionSeed, bool redirect) public {
        uint256 positionId = _positionWithStatus(
            positionSeed,
            ProtocolTypes.PositionStatus.WithdrawalClaimable,
            ProtocolTypes.PositionStatus.WithdrawalClaimable
        );
        if (positionId == 0) return;
        (address owner,,,,) = market.withdrawalClaims(positionId);
        if (owner == address(0)) return;
        vm.prank(owner);
        market.claimWithdrawal(positionId, redirect ? _actors[3] : owner);
        (address remainingOwner,,,,) = market.withdrawalClaims(positionId);
        assertEq(remainingOwner, address(0));
        withdrawalClaimCalls++;
    }

    function requestPull(uint256 actorSeed, bool useRejectingReceiver) public {
        if (!_canRequestPull()) return;
        address buyer = _actors[actorSeed % _actors.length];
        address receiver = useRejectingReceiver ? address(rejectingReceiver) : buyer;
        uint256 price = market.currentPullPrice();
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: receiver,
            drawCount: 1,
            maxUnitPrice: price.toUint128(),
            maxTotalPrice: price.toUint128(),
            deadline: uint48(block.timestamp + 1 days),
            referralCode: buyer == _actors[3] ? bytes32(0) : REFERRAL_CODE
        });
        vm.prank(buyer);
        coordinator.requestPull(input);
        pullRequestCalls++;
    }

    function progressEpoch(uint256 seed, bool cancel) public {
        (, ProtocolTypes.EpochStatus status,,,,,,,,,,,) = coordinator.epoch();
        if (status == ProtocolTypes.EpochStatus.Collecting) {
            coordinator.requestRandomness();
            return;
        }
        if (status == ProtocolTypes.EpochStatus.RandomnessRequested) {
            if (cancel) {
                vm.warp(block.timestamp + coordinator.randomnessTimeout() + 1);
                coordinator.cancelTimedOutEpoch(type(uint32).max);
                cancellationCalls++;
            } else {
                randomness.setSeed(seed);
                coordinator.provideRandomness("");
            }
            return;
        }
        if (
            status == ProtocolTypes.EpochStatus.RandomnessReady
                || status == ProtocolTypes.EpochStatus.Resolving
        ) {
            if (cancel) {
                vm.warp(block.timestamp + coordinator.randomnessTimeout() + 1);
                (bool ok, bytes memory reason) = address(coordinator)
                    .call(abi.encodeCall(EpochCoordinator.cancelTimedOutEpoch, (uint32(1))));
                assertFalse(ok, "healthy seeded epoch was cancellable");
                assertEq(reason, abi.encodeWithSelector(EpochCoordinator.InvalidEpochState.selector, status));
                healthySeedCancellationRejections++;
                expectedReverts++;
            }
            coordinator.resolveEpoch(1);
            resolutionCalls++;
            return;
        }
        if (status == ProtocolTypes.EpochStatus.Refunding) {
            coordinator.cancelTimedOutEpoch(1);
            recoveryStepCalls++;
            return;
        }
        if (status == ProtocolTypes.EpochStatus.Finalizing || status == ProtocolTypes.EpochStatus.Cancelling)
        {
            coordinator.advanceEpochBoundary(market.MAX_BOUNDARY_BATCH());
        }
    }

    function triggerUnexpectedResolutionFailure() public {
        (uint256 epochId, ProtocolTypes.EpochStatus status,,,, uint32 orderCursor,,,,,,,) =
            coordinator.epoch();
        if (
            (status != ProtocolTypes.EpochStatus.RandomnessReady
                    && status != ProtocolTypes.EpochStatus.Resolving) || market.activePositionCount() == 0
        ) return;
        ProtocolTypes.PullOrder memory order = coordinator.orderAt(epochId, orderCursor);
        uint256 price = market.currentPullPrice();
        if (
            order.resolvedCount == order.drawCount || block.timestamp > order.deadline
                || price > order.maxUnitPrice || price > order.escrowRemaining
        ) return;

        uint256 escrowBefore = coordinator.escrowLiability();
        uint256 refundBefore = coordinator.refundLiability();
        uint32 marketCountBefore = market.activePositionCount();
        vm.mockCallRevert(
            address(market),
            abi.encodeWithSelector(DrawMarket.resolveDraw.selector),
            abi.encodeWithSignature("InvariantResolveFailure()")
        );
        coordinator.resolveEpoch(1);
        vm.clearMockedCalls();

        (, ProtocolTypes.EpochStatus afterStatus,,,,,,,,,,,) = coordinator.epoch();
        assertEq(uint8(afterStatus), uint8(ProtocolTypes.EpochStatus.Refunding));
        assertEq(coordinator.escrowLiability(), escrowBefore);
        assertEq(coordinator.refundLiability(), refundBefore);
        assertEq(market.activePositionCount(), marketCountBefore);
        resolutionFailureCalls++;
    }

    function settleReceipt(uint256 receiptSeed, uint256 choiceSeed) public {
        uint256 receiptId = _revealedReceipt(receiptSeed, false);
        if (receiptId == 0) return;
        address owner = pullReceipt.ownerOf(receiptId);
        uint256 choice = choiceSeed % 4;
        if (
            choice == 2
                && (market.activePositionCount() >= market.maxActivePositions()
                    || market.boundaryActive()
                    || (owner == address(rejectingReceiver) && rejectingReceiver.rejects()))
        ) choice = 0;
        if (choice == 3 && rewards.rejectSettlementSwap()) choice = 0;
        vm.prank(owner);
        if (choice == 0) {
            engine.settleKeep(receiptId);
        } else if (choice == 1) {
            engine.settleCash(receiptId);
        } else if (choice == 2) {
            uint128 backing = (MIN_BACKING + (receiptSeed % (MAX_BACKING - MIN_BACKING + 1))).toUint128();
            engine.settleRelist(receiptId, backing);
        } else {
            engine.settleDraw(receiptId, 0, "");
        }
        settlementCalls++;
    }

    function attemptDrawFailure(uint256 receiptSeed) public {
        uint256 receiptId = _revealedReceipt(receiptSeed, false);
        if (receiptId == 0 || !rewards.rejectSettlementSwap()) return;
        address owner = pullReceipt.ownerOf(receiptId);
        ProtocolTypes.PullReceiptData memory beforeData = pullReceipt.receiptData(receiptId);
        uint256 liabilitiesBefore = engine.totalLiabilities();
        uint256 vaultBefore = asset.balanceOf(address(vault));
        vm.prank(owner);
        (bool ok,) = address(engine)
            .call(abi.encodeCall(SettlementEngine.settleDraw, (receiptId, uint256(0), bytes(""))));
        assertFalse(ok, "configured reward failure unexpectedly succeeded");
        assertEq(uint8(pullReceipt.receiptData(receiptId).status), uint8(beforeData.status));
        assertEq(engine.totalLiabilities(), liabilitiesBefore);
        assertEq(asset.balanceOf(address(vault)), vaultBefore);
        expectedReverts++;
        rewardFailureCalls++;
    }

    function forceExpiredKeep(uint256 receiptSeed) public {
        uint256 receiptId = _revealedReceipt(receiptSeed, true);
        if (receiptId == 0) return;
        ProtocolTypes.PullReceiptData memory data = pullReceipt.receiptData(receiptId);
        if (block.timestamp <= data.decisionDeadline) vm.warp(uint256(data.decisionDeadline) + 1);
        engine.forceKeep(receiptId);
        forceKeepCalls++;
    }

    function toggleRewardFailures(uint256 seed) public {
        bool rejectEnqueue = seed & 1 != 0;
        bool ignoreEnqueue = seed & 2 != 0;
        bool rejectSwap = seed & 4 != 0;
        rewards.setFailures(rejectEnqueue, ignoreEnqueue, rejectSwap);
        rewardFailureCalls++;
    }

    function toggleReceiverFailure(bool rejects) public {
        rejectingReceiver.setRejects(rejects);
        receiverFailureCalls++;
    }

    function claimDeferredNFT(uint256 tokenSeed) public {
        (uint256 tokenId, bool marketClaim) = _pendingNFTToken(tokenSeed);
        if (tokenId == 0) return;
        address owner = marketClaim
            ? market.pendingNFTClaims(address(collection), tokenId)
            : engine.pendingNFTClaims(address(collection), tokenId);
        if (owner == address(0)) return;
        rejectingReceiver.setRejects(false);
        vm.prank(owner);
        if (marketClaim) {
            market.claimNFT(address(collection), tokenId, _actors[3]);
            assertEq(market.pendingNFTClaims(address(collection), tokenId), address(0));
        } else {
            engine.claimNFT(address(collection), tokenId, _actors[3]);
            assertEq(engine.pendingNFTClaims(address(collection), tokenId), address(0));
        }
        receiverFailureCalls++;
        nftClaimCalls++;
    }

    function deferWithdrawalNFT(uint256 backingSeed) public {
        if (market.nextPositionId() > MAX_POSITIONS || market.boundaryActive()) return;
        if (!market.epochLocked() && market.activePositionCount() >= market.maxActivePositions()) return;
        uint128 backing = (MIN_BACKING + backingSeed % (MAX_BACKING - MIN_BACKING + 1)).toUint128();
        uint256 tokenId = nextTokenId++;
        collection.mint(address(rejectingReceiver), tokenId);
        vm.startPrank(address(rejectingReceiver));
        collection.approve(address(vault), tokenId);
        market.depositPosition(address(collection), tokenId, backing, address(rejectingReceiver));
        rejectingReceiver.setRejects(true);
        uint256 positionId = market.nextPositionId() - 1;
        market.requestWithdrawal(positionId, address(rejectingReceiver));
        vm.stopPrank();
        assertEq(market.pendingNFTClaims(address(collection), tokenId), address(rejectingReceiver));
        depositCalls++;
        withdrawalRequestCalls++;
        receiverFailureCalls++;
        marketNFTDeferralCalls++;
    }

    function claimClaims(uint256 actorSeed) public {
        address actor = _claimActor(actorSeed);
        uint256 amount = coordinator.refundClaims(actor);
        if (amount != 0) {
            vm.prank(actor);
            coordinator.claimRefund();
            assertEq(coordinator.refundClaims(actor), 0);
            return;
        }
        amount = market.settlementClaims(actor);
        if (amount != 0) {
            vm.prank(actor);
            market.claimSettlement();
            assertEq(market.settlementClaims(actor), 0);
            return;
        }
        amount = engine.settlementClaims(actor);
        if (amount != 0) {
            vm.prank(actor);
            engine.claimSettlement(actor);
            assertEq(engine.settlementClaims(actor), 0);
            return;
        }
        amount = engine.referralClaims(actor);
        if (amount != 0) {
            vm.prank(actor);
            engine.claimReferral();
            assertEq(engine.referralClaims(actor), 0);
        }
    }

    function claimRewards(uint256 actorSeed) public {
        address actor = _claimActor(actorSeed);
        uint256 amount = rewards.queued(actor, address(asset));
        if (amount == 0) return;
        vm.prank(actor);
        rewards.claim(address(asset), actor);
        assertEq(rewards.queued(actor, address(asset)), 0);
        rewardClaimCalls++;
    }

    function claimRevenues() public {
        if (market.protocolLiability() != 0) {
            vm.prank(governor);
            market.claimProtocolRevenue();
            assertEq(market.protocolLiability(), 0);
            revenueClaimCalls++;
            return;
        }
        if (market.securityLiability() != 0) {
            market.claimSecurityRevenue();
            assertEq(market.securityLiability(), 0);
            revenueClaimCalls++;
            return;
        }
        if (engine.protocolLiability() != 0) {
            vm.prank(governor);
            engine.claimProtocolRevenue();
            assertEq(engine.protocolLiability(), 0);
            revenueClaimCalls++;
            return;
        }
        if (engine.securityLiability() != 0) {
            engine.claimSecurityRevenue();
            assertEq(engine.securityLiability(), 0);
            revenueClaimCalls++;
            return;
        }
        if (engine.buybackLiability() != 0) {
            engine.claimBuybackRevenue();
            assertEq(engine.buybackLiability(), 0);
            revenueClaimCalls++;
        }
    }

    function challengeCrown(uint256 positionSeed) public {
        uint256 positionId = _positionWithStatus(
            positionSeed, ProtocolTypes.PositionStatus.Active, ProtocolTypes.PositionStatus.Active
        );
        if (positionId == 0 || market.boundaryActive()) return;
        market.challengeCrown(positionId);
        crownChallengeCalls++;
    }

    function actorCount() external pure returns (uint256) {
        return 4;
    }

    function actorAt(uint256 index) external view returns (address) {
        return _actors[index];
    }

    function claimActorCount() external pure returns (uint256) {
        return 10;
    }

    function claimActorAt(uint256 index) external view returns (address) {
        return _claimActor(index);
    }

    function _canRequestPull() private view returns (bool) {
        (, ProtocolTypes.EpochStatus status,,,,,,,,,,,) = coordinator.epoch();
        if (
            status != ProtocolTypes.EpochStatus.Idle && status != ProtocolTypes.EpochStatus.Finalized
                && status != ProtocolTypes.EpochStatus.Cancelled
                && status != ProtocolTypes.EpochStatus.Collecting
        ) return false;
        if (market.boundaryActive() || market.activePositionCount() == 0) return false;
        if (status == ProtocolTypes.EpochStatus.Collecting) {
            (,,,,,,, uint32 totalRequested,,,,,) = coordinator.epoch();
            return totalRequested < coordinator.maxDrawsPerEpoch();
        }
        return true;
    }

    function _withdrawablePosition(uint256 seed) private view returns (uint256 positionId) {
        uint256 count;
        uint256 limit = market.nextPositionId();
        for (uint256 i = 1; i < limit; ++i) {
            (,,,,, ProtocolTypes.PositionStatus status,,,,,,) = market.positions(i);
            bool valid = status == ProtocolTypes.PositionStatus.Staged
                || status == ProtocolTypes.PositionStatus.Active
                || (status == ProtocolTypes.PositionStatus.WithdrawalQueued && !market.epochLocked());
            if (!valid) continue;
            if (count++ == seed % _countWithdrawable()) return i;
        }
    }

    function _countWithdrawable() private view returns (uint256 count) {
        uint256 limit = market.nextPositionId();
        for (uint256 i = 1; i < limit; ++i) {
            (,,,,, ProtocolTypes.PositionStatus status,,,,,,) = market.positions(i);
            if (
                status == ProtocolTypes.PositionStatus.Staged || status == ProtocolTypes.PositionStatus.Active
                    || (status == ProtocolTypes.PositionStatus.WithdrawalQueued && !market.epochLocked())
            ) count++;
        }
    }

    function _positionWithStatus(
        uint256 seed,
        ProtocolTypes.PositionStatus wantedA,
        ProtocolTypes.PositionStatus wantedB
    ) private view returns (uint256 positionId) {
        uint256 count;
        uint256 limit = market.nextPositionId();
        for (uint256 i = 1; i < limit; ++i) {
            (,,,,, ProtocolTypes.PositionStatus status,,,,,,) = market.positions(i);
            if (status == wantedA || status == wantedB) count++;
        }
        if (count == 0) return 0;
        uint256 target = seed % count;
        for (uint256 i = 1; i < limit; ++i) {
            (,,,,, ProtocolTypes.PositionStatus status,,,,,,) = market.positions(i);
            if (status != wantedA && status != wantedB) continue;
            if (target == 0) return i;
            target--;
        }
    }

    function _revealedReceipt(uint256 seed, bool includeExpired) private view returns (uint256 receiptId) {
        uint256 count;
        uint256 limit = engine.nextReceiptId();
        for (uint256 i = 1; i < limit; ++i) {
            ProtocolTypes.PullReceiptData memory data = pullReceipt.receiptData(i);
            if (
                data.status == ProtocolTypes.PullStatus.Revealed
                    && (includeExpired || block.timestamp <= data.decisionDeadline)
            ) count++;
        }
        if (count == 0) return 0;
        uint256 target = seed % count;
        for (uint256 i = 1; i < limit; ++i) {
            ProtocolTypes.PullReceiptData memory data = pullReceipt.receiptData(i);
            if (
                data.status != ProtocolTypes.PullStatus.Revealed
                    || (!includeExpired && block.timestamp > data.decisionDeadline)
            ) continue;
            if (target == 0) return i;
            target--;
        }
    }

    function _pendingNFTToken(uint256 seed) private view returns (uint256 tokenId, bool marketClaim) {
        uint256 count;
        for (uint256 i = 1; i < nextTokenId; ++i) {
            if (engine.pendingNFTClaims(address(collection), i) != address(0)) count++;
            if (market.pendingNFTClaims(address(collection), i) != address(0)) count++;
        }
        if (count == 0) return (0, false);
        uint256 target = seed % count;
        for (uint256 i = 1; i < nextTokenId; ++i) {
            if (engine.pendingNFTClaims(address(collection), i) != address(0)) {
                if (target == 0) return (i, false);
                target--;
            }
            if (market.pendingNFTClaims(address(collection), i) != address(0)) {
                if (target == 0) return (i, true);
                target--;
            }
        }
    }

    function _claimActor(uint256 seed) private view returns (address) {
        uint256 index = seed % 10;
        if (index < 4) return _actors[index];
        if (index == 4) return address(rejectingReceiver);
        if (index == 5) return treasury;
        if (index == 6) return insurance;
        if (index == 7) return buyback;
        if (index == 8) return governor;
        return address(this);
    }
}

contract ProtocolInvariantTest is StdInvariant, Test {
    uint256 internal constant WEIGHT_NUMERATOR = 1e36;

    MockERC20 internal asset;
    MockERC721 internal collection;
    MockRandomnessAdapter internal randomness;
    InvariantRewardController internal rewards;
    InvariantRejectingReceiver internal rejectingReceiver;
    DrawMarket internal market;
    MarketVault internal vault;
    SettlementEngine internal engine;
    EpochCoordinator internal coordinator;
    PullReceipt internal pullReceipt;
    PositionNFT internal positionToken;
    ProtocolHandler internal handler;

    address internal governor = makeAddr("invariant-governor");
    address internal guardian = makeAddr("invariant-guardian");
    address internal treasury = makeAddr("invariant-treasury");
    address internal insurance = makeAddr("invariant-insurance");
    address internal buyback = makeAddr("invariant-buyback");

    function setUp() external {
        asset = new MockERC20("Invariant Settlement", "INV", 18);
        collection = new MockERC721();
        randomness = new MockRandomnessAdapter();
        rewards = new InvariantRewardController();
        rejectingReceiver = new InvariantRejectingReceiver();
        ProtocolRegistry registry = new ProtocolRegistry(governor);
        ReferralRegistry referrals = new ReferralRegistry(governor);

        ProtocolTypes.MarketConfig memory config = ProtocolTypes.MarketConfig({
            marketId: 77,
            collectionSetId: keccak256("INVARIANT_COLLECTION"),
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
            minBacking: 10 ether,
            maxBacking: 100 ether,
            maxActivePositions: 8,
            maxDrawsPerEpoch: 3,
            collectionWindow: 0,
            randomnessTimeout: 10,
            decisionWindow: 1 hours,
            markupBps: 1_000
        });
        DrawMarket implementation = new DrawMarket();
        address marketAddress = Clones.clone(address(implementation));
        vault = new MarketVault(marketAddress, address(asset));
        positionToken = new PositionNFT("Invariant Position", "INVP", marketAddress);
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
        address[] memory collections = new address[](1);
        collections[0] = address(collection);
        market = DrawMarket(marketAddress);
        market.initialize(
            config, address(vault), address(positionToken), address(engine), address(coordinator), collections
        );
        address[4] memory actors = [
            makeAddr("invariant-alice"),
            makeAddr("invariant-bob"),
            makeAddr("invariant-carol"),
            makeAddr("invariant-dave")
        ];
        bytes32 referralMarketRole = referrals.MARKET_ROLE();
        vm.prank(governor);
        referrals.registerCode(keccak256("INVARIANT_REFERRAL"), actors[3]);
        vm.prank(governor);
        referrals.grantRole(referralMarketRole, address(coordinator));
        pullReceipt = PullReceipt(address(engine.pullReceipt()));

        handler = new ProtocolHandler(
            asset,
            collection,
            randomness,
            rewards,
            rejectingReceiver,
            market,
            engine,
            coordinator,
            governor,
            treasury,
            insurance,
            buyback,
            actors
        );
        handler.bootstrap();

        bytes4[] memory selectors = new bytes4[](18);
        selectors[0] = ProtocolHandler.deposit.selector;
        selectors[1] = ProtocolHandler.changeBacking.selector;
        selectors[2] = ProtocolHandler.requestWithdrawal.selector;
        selectors[3] = ProtocolHandler.claimWithdrawal.selector;
        selectors[4] = ProtocolHandler.requestPull.selector;
        selectors[5] = ProtocolHandler.progressEpoch.selector;
        selectors[6] = ProtocolHandler.settleReceipt.selector;
        selectors[7] = ProtocolHandler.attemptDrawFailure.selector;
        selectors[8] = ProtocolHandler.forceExpiredKeep.selector;
        selectors[9] = ProtocolHandler.toggleRewardFailures.selector;
        selectors[10] = ProtocolHandler.toggleReceiverFailure.selector;
        selectors[11] = ProtocolHandler.claimDeferredNFT.selector;
        selectors[12] = ProtocolHandler.claimClaims.selector;
        selectors[13] = ProtocolHandler.claimRewards.selector;
        selectors[14] = ProtocolHandler.claimRevenues.selector;
        selectors[15] = ProtocolHandler.challengeCrown.selector;
        selectors[16] = ProtocolHandler.triggerUnexpectedResolutionFailure.selector;
        selectors[17] = ProtocolHandler.deferWithdrawalNFT.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
    }

    function invariant_vaultAssetsEqualIndependentLiabilitySum() external view {
        uint256 marketOwned = market.backingLiability() + market.earningsLiability()
            + market.rewardInputLiability() + market.settlementClaimLiability() + market.crownLiability()
            + market.securityLiability() + market.protocolLiability();
        uint256 engineOwned = engine.selectedBackingLiability() + engine.earningsLiability()
            + engine.rewardInputLiability() + engine.referralLiability() + engine.securityLiability()
            + engine.buybackLiability() + engine.protocolLiability() + engine.settlementClaimLiability();
        uint256 epochOwned = coordinator.escrowLiability() + coordinator.refundLiability();
        uint256 independentlySummed = marketOwned + engineOwned + epochOwned;
        assertEq(
            asset.balanceOf(address(vault)), independentlySummed, "vault has deficit or unattributed assets"
        );
        assertEq(market.totalLiabilities(), independentlySummed, "aggregate liability getter disagrees");
        assertTrue(market.solvent());
    }

    function invariant_activeCountSlotsAndWeightMatchPositions() external view {
        uint256 expectedCount;
        uint256 expectedWeight;
        uint256 seenSlots;
        uint256 limit = market.nextPositionId();
        for (uint256 positionId = 1; positionId < limit; ++positionId) {
            (,, uint128 backing,, uint32 slot, ProtocolTypes.PositionStatus status,,,,,,) =
                market.positions(positionId);
            if (!_isTreeMember(status)) continue;
            expectedCount++;
            expectedWeight += WEIGHT_NUMERATOR / backing;
            assertLt(slot, market.maxActivePositions());
            uint256 bit = uint256(1) << slot;
            assertEq(seenSlots & bit, 0, "two active positions share a slot");
            seenSlots |= bit;
            assertEq(market.positionAtSlot(slot), positionId, "slot does not point back to position");
        }
        assertEq(market.activePositionCount(), expectedCount);
        assertEq(market.totalWeight(), expectedWeight);
    }

    function invariant_crownIsLiveAndUnchallengeable() external view {
        uint256 crownId = market.crownPositionId();
        uint256 activeCount = market.activePositionCount();
        assertEq(crownId == 0, activeCount == 0, "Crown zero-state disagrees with active set");
        if (crownId == 0) return;
        (,, uint128 crownBacking,,, ProtocolTypes.PositionStatus crownStatus,,,,,,) =
            market.positions(crownId);
        assertTrue(_isTreeMember(crownStatus), "Crown is not in weighted tree");
        uint256 limit = market.nextPositionId();
        for (uint256 positionId = 1; positionId < limit; ++positionId) {
            if (positionId == crownId) continue;
            (,, uint128 backing,,, ProtocolTypes.PositionStatus status,,,,,,) = market.positions(positionId);
            if (!_isTreeMember(status)) continue;
            assertLt(
                uint256(backing) * market.BPS(),
                uint256(crownBacking) * market.CROWN_CHALLENGE_BPS(),
                "active challenger already meets takeover threshold"
            );
        }
    }

    function invariant_selectionSettlementAndCustodyStayAttributable() external view {
        uint256 positionLimit = market.nextPositionId();
        uint256 receiptLimit = engine.nextReceiptId();
        bool[] memory selectedOnce = new bool[](positionLimit);
        uint256[] memory liveCustodyPosition = new uint256[](handler.nextTokenId());

        for (uint256 receiptId = 1; receiptId < receiptLimit; ++receiptId) {
            ProtocolTypes.PullReceiptData memory data = pullReceipt.receiptData(receiptId);
            assertGt(data.positionId, 0);
            assertLt(data.positionId, positionLimit);
            assertFalse(selectedOnce[data.positionId], "position selected twice");
            selectedOnce[data.positionId] = true;
            (address selectedCollection, uint256 tokenId,,,,,) = engine.selectedPositions(receiptId);
            if (data.status == ProtocolTypes.PullStatus.Revealed) {
                assertEq(selectedCollection, address(collection));
                assertEq(collection.ownerOf(tokenId), address(vault));
                (,,,,, ProtocolTypes.PositionStatus status,,,,,,) = market.positions(data.positionId);
                assertEq(uint8(status), uint8(ProtocolTypes.PositionStatus.Selected));
                assertTrue(positionToken.isFrozen(data.positionId));
            } else {
                assertEq(uint256(uint160(selectedCollection)), 0, "settled receipt retained selection");
            }
        }

        for (uint256 positionId = 1; positionId < positionLimit; ++positionId) {
            (address selectedCollection, uint256 tokenId,,,, ProtocolTypes.PositionStatus status,,,,,,) =
                market.positions(positionId);
            bool positionNFTExpected = status == ProtocolTypes.PositionStatus.Staged || _isTreeMember(status)
                || status == ProtocolTypes.PositionStatus.Selected;
            if (positionNFTExpected) {
                assertTrue(positionToken.ownerOf(positionId) != address(0));
            }
            if (
                status == ProtocolTypes.PositionStatus.Staged || _isTreeMember(status)
                    || status == ProtocolTypes.PositionStatus.Selected
                    || status == ProtocolTypes.PositionStatus.WithdrawalClaimable
            ) {
                assertEq(selectedCollection, address(collection));
                assertEq(collection.ownerOf(tokenId), address(vault));
                assertEq(liveCustodyPosition[tokenId], 0, "underlying backs two live positions");
                liveCustodyPosition[tokenId] = positionId;
            }
        }

        for (uint256 tokenId = 1; tokenId < handler.nextTokenId(); ++tokenId) {
            address engineClaimOwner = engine.pendingNFTClaims(address(collection), tokenId);
            address marketClaimOwner = market.pendingNFTClaims(address(collection), tokenId);
            assertTrue(
                engineClaimOwner == address(0) || marketClaimOwner == address(0),
                "NFT credited in both claim systems"
            );
            bool hasClaim = engineClaimOwner != address(0) || marketClaimOwner != address(0);
            if (hasClaim) {
                assertEq(collection.ownerOf(tokenId), address(vault));
                assertEq(liveCustodyPosition[tokenId], 0, "NFT both claimable and backing a live position");
            }
            bool vaultOwned = collection.ownerOf(tokenId) == address(vault);
            assertEq(
                vaultOwned,
                liveCustodyPosition[tokenId] != 0 || hasClaim,
                "vault-owned NFT has no live position or claim owner"
            );
        }
    }

    function invariant_claimBucketsAndRewardInputsAreFullyAttributed() external view {
        uint256 marketClaims;
        uint256 engineClaims;
        uint256 refundClaims;
        uint256 referralClaims;
        uint256 queuedRewards;
        for (uint256 i; i < handler.claimActorCount(); ++i) {
            address actor = handler.claimActorAt(i);
            marketClaims += market.settlementClaims(actor);
            engineClaims += engine.settlementClaims(actor);
            refundClaims += coordinator.refundClaims(actor);
            referralClaims += engine.referralClaims(actor);
            queuedRewards += rewards.queued(actor, address(asset));
        }
        assertEq(marketClaims, market.settlementClaimLiability());
        assertEq(engineClaims, engine.settlementClaimLiability());
        assertEq(refundClaims, coordinator.refundLiability());
        assertEq(referralClaims, engine.referralLiability());
        assertEq(queuedRewards, rewards.totalQueued(address(asset)));
        assertEq(
            asset.balanceOf(address(rewards)),
            rewards.totalQueued(address(asset)) + rewards.totalSettlementInput(address(asset)),
            "reward controller assets are not attributed"
        );
    }

    function invariant_componentLiabilitiesMatchUnderlyingEntitlements() external view {
        uint256 expectedMarketBacking;
        uint256 minimumMarketEarnings;
        uint256 minimumMarketRewardInput;
        uint256 positionLimit = market.nextPositionId();
        for (uint256 positionId = 1; positionId < positionLimit; ++positionId) {
            (,, uint128 backing, uint128 pendingBacking,, ProtocolTypes.PositionStatus status,,,,,,) =
                market.positions(positionId);
            if (
                status == ProtocolTypes.PositionStatus.Staged || _isTreeMember(status)
                    || status == ProtocolTypes.PositionStatus.WithdrawalClaimable
            ) {
                expectedMarketBacking += pendingBacking > backing ? pendingBacking : backing;
            }
            (uint256 cash, uint256 rewardInput) = market.pendingPositionEarnings(positionId);
            minimumMarketEarnings += cash;
            minimumMarketRewardInput += rewardInput;
            if (status == ProtocolTypes.PositionStatus.WithdrawalClaimable) {
                (,,, uint256 claimedCash, uint256 claimedRewardInput) = market.withdrawalClaims(positionId);
                minimumMarketEarnings += claimedCash;
                minimumMarketRewardInput += claimedRewardInput;
            }
        }
        assertEq(market.backingLiability(), expectedMarketBacking);
        assertGe(market.earningsLiability(), minimumMarketEarnings);
        assertGe(market.rewardInputLiability(), minimumMarketRewardInput);
        assertEq(market.crownPot(), market.crownLiability());

        uint256 selectedBacking;
        uint256 selectedEarnings;
        uint256 selectedRewardInput;
        for (uint256 receiptId = 1; receiptId < engine.nextReceiptId(); ++receiptId) {
            (,,,, uint128 backing, uint256 cash, uint256 rewardInput) = engine.selectedPositions(receiptId);
            selectedBacking += backing;
            selectedEarnings += cash;
            selectedRewardInput += rewardInput;
        }
        assertEq(engine.selectedBackingLiability(), selectedBacking);
        assertEq(engine.earningsLiability(), selectedEarnings);
        assertEq(engine.rewardInputLiability(), selectedRewardInput);

        (uint256 currentEpoch,,,,,,,,,,,,) = coordinator.epoch();
        uint256 expectedEscrow;
        for (uint256 epochId = 1; epochId <= currentEpoch; ++epochId) {
            uint256 orderCount = coordinator.orderCount(epochId);
            for (uint256 orderIndex; orderIndex < orderCount; ++orderIndex) {
                expectedEscrow += coordinator.orderAt(epochId, orderIndex).escrowRemaining;
            }
        }
        assertEq(coordinator.escrowLiability(), expectedEscrow);
    }

    function invariant_failureRecoveryAndActionCoverageAreNonVacuous() external view {
        assertGt(handler.depositCalls(), 0, "deposit");
        assertGt(handler.backingChangeCalls(), 0, "backing change");
        assertGt(handler.withdrawalRequestCalls(), 0, "withdrawal request");
        assertGt(handler.withdrawalClaimCalls(), 0, "withdrawal claim");
        assertGt(handler.pullRequestCalls(), 0, "pull request");
        assertGt(handler.resolutionCalls(), 0, "resolution");
        assertGt(handler.cancellationCalls(), 0, "cancellation");
        assertGt(handler.settlementCalls(), 0, "settlement");
        assertGt(handler.forceKeepCalls(), 0, "force keep");
        assertGt(handler.rewardFailureCalls(), 0, "reward failure");
        assertGt(handler.receiverFailureCalls(), 0, "receiver failure");
        assertGt(handler.rewardClaimCalls(), 0, "reward claim");
        assertGt(handler.revenueClaimCalls(), 0, "revenue claim");
        assertGt(handler.crownChallengeCalls(), 0, "Crown challenge");
        assertGt(handler.healthySeedCancellationRejections(), 0, "healthy seeded cancellation rejection");
        assertGt(handler.resolutionFailureCalls(), 0, "resolution failure");
        assertGt(handler.recoveryStepCalls(), 0, "incremental recovery");
        assertGt(handler.marketNFTDeferralCalls(), 0, "market NFT deferral");
        assertGt(handler.nftClaimCalls(), 0, "NFT claim");
        assertGt(handler.expectedReverts(), 0, "modeled revert");
    }

    function test_bootstrapExercisesEveryActionClass() external view {
        this.invariant_failureRecoveryAndActionCoverageAreNonVacuous();
    }

    function _isTreeMember(ProtocolTypes.PositionStatus status) private pure returns (bool) {
        return status == ProtocolTypes.PositionStatus.Active
            || status == ProtocolTypes.PositionStatus.BackingChangeQueued
            || status == ProtocolTypes.PositionStatus.WithdrawalQueued;
    }
}
