// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { MarketVault } from "./MarketVault.sol";
import { ProtocolTypes } from "./types/ProtocolTypes.sol";
import { IRandomnessAdapter } from "./interfaces/IRandomnessAdapter.sol";
import { IReferralRegistry } from "./interfaces/IReferralRegistry.sol";
import { IProtocolRegistry } from "./interfaces/IProtocolRegistry.sol";
import { IDrawMarketCore } from "./interfaces/IDrawMarketCore.sol";

contract EpochCoordinator is AccessControl, ReentrancyGuard {
    using SafeCast for uint256;

    error InvalidEpochState(ProtocolTypes.EpochStatus status);
    error InvalidOrder();
    error DeadlineExpired();
    error PriceLimitExceeded(uint256 price, uint256 limit);
    error Ineligible(address user);
    error BatchTooLarge();
    error IntakePaused();
    error RandomnessNotTimedOut();
    error NothingToClaim();
    error EpochBoundaryPending();
    error RouterNotApproved(address router);
    error InvalidPayer(address payer, address caller);
    error ZeroAddress();
    error InvalidRefundReceiver();
    error InsufficientResolutionGas();

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant ROUTER_ROLE = keccak256("ROUTER_ROLE");
    uint256 public constant RESOLUTION_CALL_GAS = 2_000_000;
    uint256 public constant RESOLUTION_GAS_RESERVE = 300_000;

    struct Epoch {
        uint256 id;
        ProtocolTypes.EpochStatus status;
        uint48 openedAt;
        uint48 randomnessRequestedAt;
        uint32 activeCountSnapshot;
        uint32 orderCursor;
        uint32 totalResolved;
        uint32 totalRequested;
        uint256 totalWeightSnapshot;
        bytes32 activeTreeRoot;
        bytes32 orderRoot;
        bytes32 requestId;
        uint256 randomSeed;
    }

    uint256 public immutable marketId;
    IDrawMarketCore public immutable market;
    MarketVault public immutable vault;
    IProtocolRegistry public immutable protocolRegistry;
    IReferralRegistry public immutable referralRegistry;
    uint32 public immutable maxDrawsPerEpoch;
    uint32 public immutable collectionWindow;
    uint32 public immutable randomnessTimeout;
    IRandomnessAdapter public randomnessAdapter;
    Epoch public epoch;
    mapping(uint256 epochId => ProtocolTypes.PullOrder[] orders) private _orders;
    mapping(address account => uint256 amount) public refundClaims;
    uint256 public escrowLiability;
    uint256 public refundLiability;
    bool public pullsPaused;
    mapping(address adapter => mapping(bytes32 requestId => uint256 epochId)) public randomnessRequestEpoch;

    event PullOrderSubmitted(
        uint256 indexed epochId,
        uint256 indexed orderIndex,
        address indexed buyer,
        uint32 drawCount,
        uint256 escrow
    );
    event RandomnessRequested(uint256 indexed epochId, bytes32 indexed requestId, bytes32 commitment);
    event RandomnessRequestFailed(uint256 indexed epochId, address indexed adapter);
    event RandomnessReady(uint256 indexed epochId, uint256 randomSeed);
    event DrawResolved(
        uint256 indexed epochId,
        uint256 indexed receiptId,
        uint256 indexed positionId,
        uint256 price,
        uint256 backing
    );
    event EpochFinalized(uint256 indexed epochId, uint32 resolvedDraws);
    event EpochCancelled(uint256 indexed epochId);
    event EpochRefunding(uint256 indexed epochId, ProtocolTypes.EpochStatus previousStatus);
    event EpochBoundaryAdvanced(uint256 indexed epochId, uint32 processed, bool complete);
    event PullsPaused(bool paused);
    event RefundClaimed(address indexed claimOwner, address indexed receiver, uint256 amount);

    constructor(
        uint256 marketId_,
        address market_,
        address vault_,
        address protocolRegistry_,
        address referralRegistry_,
        address randomnessAdapter_,
        address governor_,
        address guardian_,
        address trustedRouter_,
        uint32 maxDrawsPerEpoch_,
        uint32 collectionWindow_,
        uint32 randomnessTimeout_
    ) {
        marketId = marketId_;
        market = IDrawMarketCore(market_);
        vault = MarketVault(vault_);
        protocolRegistry = IProtocolRegistry(protocolRegistry_);
        referralRegistry = IReferralRegistry(referralRegistry_);
        randomnessAdapter = IRandomnessAdapter(randomnessAdapter_);
        maxDrawsPerEpoch = maxDrawsPerEpoch_;
        collectionWindow = collectionWindow_;
        randomnessTimeout = randomnessTimeout_;
        _grantRole(DEFAULT_ADMIN_ROLE, governor_);
        _grantRole(GOVERNOR_ROLE, governor_);
        if (guardian_ != address(0)) _grantRole(GUARDIAN_ROLE, guardian_);
        if (trustedRouter_ != address(0)) _grantRole(ROUTER_ROLE, trustedRouter_);
    }

    function setRandomnessAdapter(address adapter) external onlyRole(GOVERNOR_ROLE) {
        if (_inFlight()) revert InvalidEpochState(epoch.status);
        if (!protocolRegistry.randomnessAdapterApproved(adapter)) revert InvalidOrder();
        randomnessAdapter = IRandomnessAdapter(adapter);
    }

    function setPullsPaused(bool paused) external onlyRole(GUARDIAN_ROLE) {
        pullsPaused = paused;
        emit PullsPaused(paused);
    }

    function grantRole(bytes32 role, address account) public override {
        if (role == ROUTER_ROLE && !protocolRegistry.routerApproved(account)) revert InvalidOrder();
        super.grantRole(role, account);
    }

    function requestPull(ProtocolTypes.PullOrderInput calldata input)
        external
        nonReentrant
        returns (uint256 orderIndex)
    {
        return _requestPull(msg.sender, msg.sender, input);
    }

    function requestPullFor(address payer, address buyer, ProtocolTypes.PullOrderInput calldata input)
        external
        onlyRole(ROUTER_ROLE)
        nonReentrant
        returns (uint256 orderIndex)
    {
        if (!protocolRegistry.routerApproved(msg.sender)) revert RouterNotApproved(msg.sender);
        if (payer != msg.sender) revert InvalidPayer(payer, msg.sender);
        return _requestPull(payer, buyer, input);
    }

    function requestRandomness() external nonReentrant {
        if (epoch.status != ProtocolTypes.EpochStatus.Collecting) revert InvalidEpochState(epoch.status);
        if (block.timestamp < _earliestRandomnessRequestTime()) revert DeadlineExpired();
        bytes32 commitment = keccak256(
            abi.encode(
                block.chainid,
                marketId,
                epoch.id,
                epoch.activeTreeRoot,
                epoch.orderRoot,
                epoch.activeCountSnapshot,
                epoch.totalWeightSnapshot,
                block.number
            )
        );
        epoch.status = ProtocolTypes.EpochStatus.RandomnessRequested;
        epoch.randomnessRequestedAt = uint48(block.timestamp);
        IRandomnessAdapter adapter = randomnessAdapter;
        try adapter.requestRandomness(commitment, 1) returns (bytes32 requestId) {
            if (requestId == bytes32(0) || randomnessRequestEpoch[address(adapter)][requestId] != 0) {
                emit RandomnessRequestFailed(epoch.id, address(adapter));
                return;
            }
            epoch.requestId = requestId;
            randomnessRequestEpoch[address(adapter)][requestId] = epoch.id;
            emit RandomnessRequested(epoch.id, requestId, commitment);
        } catch {
            emit RandomnessRequestFailed(epoch.id, address(adapter));
        }
    }

    function provideRandomness(bytes calldata proof) external nonReentrant {
        if (epoch.status != ProtocolTypes.EpochStatus.RandomnessRequested) {
            revert InvalidEpochState(epoch.status);
        }
        if (block.timestamp > uint256(epoch.randomnessRequestedAt) + randomnessTimeout) {
            revert RandomnessNotTimedOut();
        }
        bytes32 requestId = epoch.requestId;
        IRandomnessAdapter adapter = randomnessAdapter;
        if (requestId == bytes32(0) || randomnessRequestEpoch[address(adapter)][requestId] != epoch.id) {
            revert InvalidOrder();
        }
        uint256[] memory words = adapter.verifyAndConsume(requestId, proof);
        if (words.length == 0) revert InvalidOrder();
        epoch.randomSeed = words[0];
        epoch.status = ProtocolTypes.EpochStatus.RandomnessReady;
        emit RandomnessReady(epoch.id, words[0]);
    }

    function resolveEpoch(uint32 maxDraws) external nonReentrant {
        if (maxDraws == 0 || maxDraws > maxDrawsPerEpoch) revert BatchTooLarge();
        if (
            epoch.status != ProtocolTypes.EpochStatus.RandomnessReady
                && epoch.status != ProtocolTypes.EpochStatus.Resolving
        ) {
            revert InvalidEpochState(epoch.status);
        }
        epoch.status = ProtocolTypes.EpochStatus.Resolving;
        ProtocolTypes.PullOrder[] storage epochOrders = _orders[epoch.id];
        uint32 processed;
        while (processed < maxDraws && epoch.orderCursor < epochOrders.length) {
            ProtocolTypes.PullOrder storage order = epochOrders[epoch.orderCursor];
            processed++;
            if (order.resolvedCount == order.drawCount) {
                _refundOrder(order);
                epoch.orderCursor++;
                continue;
            }
            uint256 unitPrice = market.currentPullPrice();
            if (
                block.timestamp > order.deadline || market.activePositionCount() == 0
                    || unitPrice > order.maxUnitPrice || unitPrice > order.escrowRemaining
            ) {
                _refundOrder(order);
                epoch.orderCursor++;
                continue;
            }
            uint128 quotedPrice = unitPrice.toUint128();
            if (gasleft() < RESOLUTION_CALL_GAS + RESOLUTION_GAS_RESERVE) {
                revert InsufficientResolutionGas();
            }
            order.escrowRemaining -= quotedPrice;
            escrowLiability -= unitPrice;
            uint256 randomValue = uint256(
                keccak256(abi.encode(epoch.randomSeed, epoch.id, epoch.totalResolved, epoch.orderCursor))
            );
            try market.resolveDraw{ gas: RESOLUTION_CALL_GAS }(
                epoch.id, order.buyer, order.receiver, quotedPrice, order.referrer, randomValue
            ) returns (
                uint256 receiptId, uint256 positionId, uint128 backing
            ) {
                order.resolvedCount++;
                epoch.totalResolved++;
                emit DrawResolved(epoch.id, receiptId, positionId, unitPrice, backing);
            } catch (bytes memory reason) {
                order.escrowRemaining += quotedPrice;
                escrowLiability += unitPrice;
                if (!_isIneligibleReceiver(reason, order.receiver)) {
                    ProtocolTypes.EpochStatus previousStatus = epoch.status;
                    epoch.status = ProtocolTypes.EpochStatus.Refunding;
                    emit EpochRefunding(epoch.id, previousStatus);
                    return;
                }
                _refundOrder(order);
                epoch.orderCursor++;
                continue;
            }
            if (order.resolvedCount == order.drawCount) {
                _refundOrder(order);
                epoch.orderCursor++;
            }
        }
        if (epoch.orderCursor == epochOrders.length) {
            epoch.status = ProtocolTypes.EpochStatus.Finalizing;
            market.unlockEpoch();
            _completeBoundaryIfReady();
        }
    }

    function cancelTimedOutEpoch(uint32 maxOrders) external nonReentrant {
        if (maxOrders == 0) revert BatchTooLarge();
        ProtocolTypes.EpochStatus status = epoch.status;
        if (
            status != ProtocolTypes.EpochStatus.RandomnessRequested
                && status != ProtocolTypes.EpochStatus.Refunding
        ) {
            revert InvalidEpochState(status);
        }
        if (status == ProtocolTypes.EpochStatus.RandomnessRequested) {
            if (block.timestamp <= uint256(epoch.randomnessRequestedAt) + randomnessTimeout) {
                revert RandomnessNotTimedOut();
            }
            epoch.status = ProtocolTypes.EpochStatus.Refunding;
            emit EpochRefunding(epoch.id, status);
        }
        ProtocolTypes.PullOrder[] storage epochOrders = _orders[epoch.id];
        uint32 processed;
        while (processed < maxOrders && epoch.orderCursor < epochOrders.length) {
            _refundOrder(epochOrders[epoch.orderCursor]);
            epoch.orderCursor++;
            processed++;
        }
        if (epoch.orderCursor == epochOrders.length) {
            epoch.status = ProtocolTypes.EpochStatus.Cancelling;
            market.unlockEpoch();
            _completeBoundaryIfReady();
        }
    }

    function advanceEpochBoundary(uint32 maxPositions) external nonReentrant {
        ProtocolTypes.EpochStatus status = epoch.status;
        if (status != ProtocolTypes.EpochStatus.Finalizing && status != ProtocolTypes.EpochStatus.Cancelling)
        {
            revert InvalidEpochState(status);
        }
        (uint32 processed, bool complete) = market.processEpochBoundary(maxPositions);
        emit EpochBoundaryAdvanced(epoch.id, processed, complete);
        if (complete) _finishBoundary(status);
    }

    function claimRefund() external nonReentrant {
        _claimRefund(msg.sender);
    }

    function claimRefund(address receiver) external nonReentrant {
        if (receiver == address(0)) revert InvalidRefundReceiver();
        _claimRefund(receiver);
    }

    function _claimRefund(address receiver) private {
        uint256 amount = refundClaims[msg.sender];
        if (amount == 0) revert NothingToClaim();
        refundClaims[msg.sender] = 0;
        refundLiability -= amount;
        vault.releaseSettlement(receiver, amount);
        emit RefundClaimed(msg.sender, receiver, amount);
    }

    function orderCount(uint256 epochId) external view returns (uint256) {
        return _orders[epochId].length;
    }

    function orderAt(uint256 epochId, uint256 index) external view returns (ProtocolTypes.PullOrder memory) {
        return _orders[epochId][index];
    }

    function totalLiabilities() external view returns (uint256) {
        return escrowLiability + refundLiability;
    }

    function _requestPull(address payer, address buyer, ProtocolTypes.PullOrderInput calldata input)
        private
        returns (uint256 orderIndex)
    {
        if (pullsPaused) revert IntakePaused();
        address receiver = input.receiver == address(0) ? buyer : input.receiver;
        if (buyer == address(0) || receiver == address(0)) revert ZeroAddress();
        if (
            epoch.status == ProtocolTypes.EpochStatus.Finalizing
                || epoch.status == ProtocolTypes.EpochStatus.Cancelling || market.epochBoundaryPending()
        ) revert EpochBoundaryPending();
        if (!market.canPullUser(buyer)) revert Ineligible(buyer);
        if (input.deadline < block.timestamp) revert DeadlineExpired();
        if (input.drawCount == 0 || input.drawCount > maxDrawsPerEpoch) revert BatchTooLarge();
        if (market.activePositionCount() < input.drawCount) revert InvalidOrder();
        uint256 unitPrice = market.currentPullPrice();
        if (unitPrice == 0 || unitPrice > input.maxUnitPrice) {
            revert PriceLimitExceeded(unitPrice, input.maxUnitPrice);
        }
        if (uint256(input.maxUnitPrice) * input.drawCount > input.maxTotalPrice) {
            revert PriceLimitExceeded(uint256(input.maxUnitPrice) * input.drawCount, input.maxTotalPrice);
        }
        if (!_inFlight()) _startEpoch();
        if (epoch.status != ProtocolTypes.EpochStatus.Collecting) revert InvalidEpochState(epoch.status);
        if (input.deadline < _earliestRandomnessRequestTime()) revert DeadlineExpired();
        if (uint256(epoch.totalRequested) + input.drawCount > maxDrawsPerEpoch) revert BatchTooLarge();
        vault.depositSettlement(payer, input.maxTotalPrice);
        escrowLiability += input.maxTotalPrice;
        address referrer = referralRegistry.bindFromMarket(buyer, input.referralCode);
        ProtocolTypes.PullOrder memory order = ProtocolTypes.PullOrder({
            buyer: buyer,
            receiver: receiver,
            drawCount: input.drawCount,
            resolvedCount: 0,
            maxUnitPrice: input.maxUnitPrice,
            escrowRemaining: input.maxTotalPrice,
            deadline: input.deadline,
            referralCode: input.referralCode,
            referrer: referrer
        });
        orderIndex = _orders[epoch.id].length;
        _orders[epoch.id].push(order);
        epoch.totalRequested += input.drawCount;
        epoch.orderRoot = keccak256(abi.encode(epoch.orderRoot, orderIndex, order));
        emit PullOrderSubmitted(epoch.id, orderIndex, buyer, input.drawCount, input.maxTotalPrice);
    }

    function _startEpoch() private {
        (uint32 activeCount, uint256 weight, bytes32 root) = market.lockEpoch();
        epoch = Epoch({
            id: epoch.id + 1,
            status: ProtocolTypes.EpochStatus.Collecting,
            openedAt: uint48(block.timestamp),
            randomnessRequestedAt: 0,
            activeCountSnapshot: activeCount,
            orderCursor: 0,
            totalResolved: 0,
            totalRequested: 0,
            totalWeightSnapshot: weight,
            activeTreeRoot: root,
            orderRoot: bytes32(0),
            requestId: bytes32(0),
            randomSeed: 0
        });
    }

    function _earliestRandomnessRequestTime() private view returns (uint256) {
        return uint256(epoch.openedAt) + collectionWindow;
    }

    function _refundOrder(ProtocolTypes.PullOrder storage order) private {
        uint256 refund = order.escrowRemaining;
        order.resolvedCount = order.drawCount;
        order.escrowRemaining = 0;
        if (refund != 0) {
            escrowLiability -= refund;
            refundClaims[order.buyer] += refund;
            refundLiability += refund;
        }
    }

    function _isIneligibleReceiver(bytes memory reason, address receiver) private pure returns (bool) {
        if (reason.length != 36) return false;
        bytes4 selector;
        address rejectedUser;
        assembly ("memory-safe") {
            selector := mload(add(reason, 0x20))
            rejectedUser := mload(add(reason, 0x24))
        }
        return selector == IDrawMarketCore.IneligibleReceiver.selector && rejectedUser == receiver;
    }

    function _completeBoundaryIfReady() private {
        if (!market.epochBoundaryPending()) _finishBoundary(epoch.status);
    }

    function _finishBoundary(ProtocolTypes.EpochStatus boundaryStatus) private {
        if (boundaryStatus == ProtocolTypes.EpochStatus.Finalizing) {
            epoch.status = ProtocolTypes.EpochStatus.Finalized;
            emit EpochFinalized(epoch.id, epoch.totalResolved);
        } else {
            epoch.status = ProtocolTypes.EpochStatus.Cancelled;
            emit EpochCancelled(epoch.id);
        }
    }

    function _inFlight() private view returns (bool) {
        ProtocolTypes.EpochStatus status = epoch.status;
        return status == ProtocolTypes.EpochStatus.Collecting
            || status == ProtocolTypes.EpochStatus.RandomnessRequested
            || status == ProtocolTypes.EpochStatus.RandomnessReady
            || status == ProtocolTypes.EpochStatus.Resolving || status == ProtocolTypes.EpochStatus.Finalizing
            || status == ProtocolTypes.EpochStatus.Cancelling || status == ProtocolTypes.EpochStatus.Refunding;
    }
}
