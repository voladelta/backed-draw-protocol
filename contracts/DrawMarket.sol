// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { MarketVault } from "./MarketVault.sol";
import { SettlementEngine } from "./SettlementEngine.sol";
import { EpochCoordinator } from "./EpochCoordinator.sol";
import { PositionNFT } from "./tokens/PositionNFT.sol";
import { WeightedTree } from "./libraries/WeightedTree.sol";
import { ProtocolTypes } from "./types/ProtocolTypes.sol";
import { IEligibilityPolicy } from "./interfaces/IEligibilityPolicy.sol";
import { IRewardController } from "./interfaces/IRewardController.sol";
import { IProtocolRegistry } from "./interfaces/IProtocolRegistry.sol";
import { IDrawMarketCore } from "./interfaces/IDrawMarketCore.sol";

contract DrawMarket is AccessControl, ReentrancyGuard {
    using WeightedTree for WeightedTree.Tree;

    error ZeroAddress();
    error InvalidConfiguration();
    error InvalidBacking(uint256 backing);
    error InvalidPositionState(uint256 positionId, ProtocolTypes.PositionStatus status);
    error CollectionNotEnabled(address collection);
    error Ineligible(address user);
    error SolvencyInvariantBroken(uint256 assets, uint256 liabilities);
    error MarketCapacityReached();
    error IntakePaused();
    error NothingToClaim();
    error EpochBoundaryPending();
    error NotNFTClaimOwner();
    error NFTClaimAlreadyExists();

    struct WithdrawalClaim {
        address owner;
        address earningsRecipient;
        uint256 backing;
        uint256 cashEarnings;
        uint256 rewardInput;
    }

    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    uint256 public constant ACC_PRECISION = 1e27;
    uint256 public constant WEIGHT_NUMERATOR = 1e36;
    uint256 public constant BPS = 10_000;
    uint256 public constant REWARD_MARKUP_BPS = 1_000;
    uint256 public constant CROWN_REMAINDER_BPS = 500;
    uint256 public constant PROTOCOL_REMAINDER_BPS = 100;
    uint256 public constant CROWN_CHALLENGE_BPS = 11_000;
    uint32 public constant MAX_BOUNDARY_BATCH = 64;

    uint256 public marketId;
    bytes32 public collectionSetId;
    address public settlementAsset;
    IProtocolRegistry public protocolRegistry;
    address public treasury;
    address public insuranceReserve;
    uint128 public minBacking;
    uint128 public maxBacking;
    uint32 public maxActivePositions;
    uint32 public maxDrawsPerEpoch;
    uint32 public collectionWindow;
    uint32 public randomnessTimeout;
    uint32 public decisionWindow;
    uint16 public markupBps;
    uint8 public settlementDecimals;
    uint256 public normalizationFactor;

    MarketVault public vault;
    PositionNFT public positionToken;
    SettlementEngine public settlementEngine;
    EpochCoordinator public epochCoordinator;
    IEligibilityPolicy public eligibilityPolicy;
    IRewardController public rewardController;

    WeightedTree.Tree private _tree;
    mapping(uint256 node => uint256 candidate) private _crownBackingTree;
    mapping(uint256 positionId => ProtocolTypes.Position position) public positions;
    mapping(uint32 slot => uint256 positionId) public positionAtSlot;
    mapping(address collection => bool enabled) public collectionEnabled;
    mapping(address account => uint256 amount) public settlementClaims;
    mapping(uint256 positionId => WithdrawalClaim claim) public withdrawalClaims;

    uint256[] private _withdrawalQueue;
    uint256[] private _backingChangeQueue;
    uint256[] private _activationQueue;
    uint256 private _withdrawalCursor;
    uint256 private _backingChangeCursor;
    uint256 private _activationCursor;

    uint32[] private _freeSlots;
    uint32 private _nextSlot;
    uint256 public nextPositionId;
    uint32 public activePositionCount;
    bytes32 public activeSetCommitment;
    uint256 public accBasePerPosition;
    uint256 public accMarkupPerPosition;
    uint256 public accRewardInputPerPosition;
    uint256 public crownPositionId;
    uint256 public crownPot;

    uint256 public backingLiability;
    uint256 public earningsLiability;
    uint256 public rewardInputLiability;
    uint256 public settlementClaimLiability;
    uint256 public crownLiability;
    uint256 public securityLiability;
    uint256 public protocolLiability;

    uint256 private _cashRoundingDust;
    uint256 private _rewardRoundingDust;

    bool public depositsPaused;
    bool public epochLocked;
    bool public boundaryActive;
    bool private _initialized;
    mapping(address collection => mapping(uint256 tokenId => address owner)) public pendingNFTClaims;

    event CollectionStatusUpdated(address indexed collection, bool enabled);
    event DepositsPaused(bool paused);
    event PositionDeposited(
        uint256 indexed positionId,
        address indexed owner,
        address indexed collection,
        uint256 tokenId,
        uint256 backing,
        ProtocolTypes.PositionStatus status
    );
    event PositionActivated(uint256 indexed positionId, uint32 treeSlot, uint256 weight);
    event PositionWithdrawalQueued(uint256 indexed positionId);
    event PositionWithdrawalClaimable(uint256 indexed positionId, address indexed owner);
    event PositionWithdrawn(
        uint256 indexed positionId,
        address indexed owner,
        uint256 backing,
        uint256 cashEarnings,
        uint256 rewardInput
    );
    event BackingChangeQueued(uint256 indexed positionId, uint256 oldBacking, uint256 newBacking);
    event BackingChanged(uint256 indexed positionId, uint256 oldBacking, uint256 newBacking);
    event PositionSelected(
        uint256 indexed receiptId,
        uint256 indexed positionId,
        address indexed buyer,
        uint256 price,
        uint256 backing
    );
    event CrownChanged(uint256 indexed previousPositionId, uint256 indexed newPositionId, uint256 paidPot);
    event EpochBoundaryStarted(uint256 withdrawals, uint256 backingChanges, uint256 activations);
    event EpochBoundaryAdvanced(
        uint32 processed,
        uint256 withdrawalRemaining,
        uint256 backingChangeRemaining,
        uint256 activationRemaining
    );
    event EpochBoundaryCompleted();
    event RewardFundingCashFallbackAccrued(address indexed beneficiary, uint256 amount);
    event SettlementPayoutAccrued(address indexed claimOwner, uint256 amount);
    event SettlementPayoutClaimed(address indexed claimOwner, address indexed receiver, uint256 amount);
    event WithdrawalNFTDeliveryDeferred(
        address indexed collection, uint256 indexed tokenId, address indexed claimOwner
    );
    event WithdrawalNFTClaimed(
        address indexed collection, uint256 indexed tokenId, address indexed claimOwner, address receiver
    );

    constructor() {
        _initialized = true;
    }

    function initialize(
        ProtocolTypes.MarketConfig calldata config,
        address vault_,
        address positionToken_,
        address settlementEngine_,
        address epochCoordinator_,
        address[] calldata initialCollections
    ) external {
        if (_initialized) revert InvalidConfiguration();
        _initialized = true;
        if (
            config.settlementAsset == address(0) || config.protocolRegistry == address(0)
                || config.governor == address(0) || config.treasury == address(0)
                || config.insuranceReserve == address(0) || config.buybackReceiver == address(0)
                || config.randomnessAdapter == address(0) || config.referralRegistry == address(0)
                || config.rewardController == address(0) || vault_ == address(0)
                || positionToken_ == address(0) || settlementEngine_ == address(0)
                || epochCoordinator_ == address(0)
        ) revert ZeroAddress();
        if (
            config.minBacking == 0 || config.maxBacking < config.minBacking || config.maxActivePositions == 0
                || config.maxDrawsPerEpoch == 0 || config.markupBps > 5_000 || config.decisionWindow == 0
        ) revert InvalidConfiguration();

        uint8 decimals = IERC20Metadata(config.settlementAsset).decimals();
        if (decimals > 18) revert InvalidConfiguration();
        uint256 factor = 10 ** (18 - decimals);
        if (uint256(config.maxBacking) * factor > WEIGHT_NUMERATOR) revert InvalidConfiguration();

        marketId = config.marketId;
        collectionSetId = config.collectionSetId;
        settlementAsset = config.settlementAsset;
        protocolRegistry = IProtocolRegistry(config.protocolRegistry);
        treasury = config.treasury;
        insuranceReserve = config.insuranceReserve;
        minBacking = config.minBacking;
        maxBacking = config.maxBacking;
        maxActivePositions = config.maxActivePositions;
        maxDrawsPerEpoch = config.maxDrawsPerEpoch;
        collectionWindow = config.collectionWindow;
        randomnessTimeout = config.randomnessTimeout;
        decisionWindow = config.decisionWindow;
        markupBps = config.markupBps;
        settlementDecimals = decimals;
        normalizationFactor = factor;

        eligibilityPolicy = IEligibilityPolicy(config.eligibilityPolicy);
        rewardController = IRewardController(config.rewardController);
        vault = MarketVault(vault_);
        positionToken = PositionNFT(positionToken_);
        settlementEngine = SettlementEngine(settlementEngine_);
        epochCoordinator = EpochCoordinator(epochCoordinator_);
        nextPositionId = 1;
        _tree.initialize(config.maxActivePositions);
        vault.setOperators(settlementEngine_, epochCoordinator_);
        for (uint256 i; i < initialCollections.length; ++i) {
            collectionEnabled[initialCollections[i]] = true;
            emit CollectionStatusUpdated(initialCollections[i], true);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, config.governor);
        _grantRole(GOVERNOR_ROLE, config.governor);
        if (config.guardian != address(0)) _grantRole(GUARDIAN_ROLE, config.guardian);
    }

    function setCollectionEnabled(address collection, bool enabled) external onlyRole(GOVERNOR_ROLE) {
        collectionEnabled[collection] = enabled;
        emit CollectionStatusUpdated(collection, enabled);
    }

    function setEligibilityPolicy(address policy) external onlyRole(GOVERNOR_ROLE) {
        if (_treeLocked()) revert InvalidConfiguration();
        if (policy != address(0) && !protocolRegistry.eligibilityPolicyApproved(policy)) {
            revert InvalidConfiguration();
        }
        eligibilityPolicy = IEligibilityPolicy(policy);
    }

    function setDepositsPaused(bool paused) external onlyRole(GUARDIAN_ROLE) {
        depositsPaused = paused;
        emit DepositsPaused(paused);
    }

    function depositPosition(address collection, uint256 tokenId, uint128 backing, address earningsRecipient)
        external
        nonReentrant
        returns (uint256 positionId)
    {
        if (depositsPaused) revert IntakePaused();
        if (boundaryActive) revert EpochBoundaryPending();
        if (!collectionEnabled[collection]) revert CollectionNotEnabled(collection);
        if (!_canDeposit(msg.sender)) revert Ineligible(msg.sender);
        _validateBacking(backing);
        address recipient = earningsRecipient == address(0) ? msg.sender : earningsRecipient;

        positionId = _initializePosition(collection, tokenId, backing, recipient);
        ProtocolTypes.Position storage position = positions[positionId];
        backingLiability += backing;

        vault.depositSettlement(msg.sender, backing);
        vault.depositNFT(msg.sender, collection, tokenId);
        positionToken.mint(msg.sender, positionId);

        _activateOrStage(positionId, position);
        emit PositionDeposited(positionId, msg.sender, collection, tokenId, backing, position.status);
        _assertSolvent();
    }

    function activatePosition(uint256 positionId) external nonReentrant {
        if (boundaryActive) revert EpochBoundaryPending();
        if (_treeLocked()) revert InvalidConfiguration();
        ProtocolTypes.Position storage position = positions[positionId];
        if (position.status != ProtocolTypes.PositionStatus.Staged) {
            revert InvalidPositionState(positionId, position.status);
        }
        _activate(positionId, position);
    }

    function requestWithdrawal(uint256 positionId) external nonReentrant {
        _requestWithdrawal(positionId, msg.sender);
    }

    function requestWithdrawal(uint256 positionId, address nftReceiver) external nonReentrant {
        if (nftReceiver == address(0)) revert ZeroAddress();
        _requestWithdrawal(positionId, nftReceiver);
    }

    function _requestWithdrawal(uint256 positionId, address nftReceiver) private {
        if (boundaryActive) revert EpochBoundaryPending();
        if (positionToken.ownerOf(positionId) != msg.sender) revert Ineligible(msg.sender);
        ProtocolTypes.Position storage position = positions[positionId];
        if (position.status == ProtocolTypes.PositionStatus.Staged) {
            _withdraw(positionId, position, msg.sender, nftReceiver);
        } else if (position.status == ProtocolTypes.PositionStatus.Active && _treeLocked()) {
            position.status = ProtocolTypes.PositionStatus.WithdrawalQueued;
            _withdrawalQueue.push(positionId);
            emit PositionWithdrawalQueued(positionId);
        } else if (position.status == ProtocolTypes.PositionStatus.Active) {
            _withdraw(positionId, position, msg.sender, nftReceiver);
        } else if (position.status == ProtocolTypes.PositionStatus.WithdrawalQueued && !_treeLocked()) {
            _withdraw(positionId, position, msg.sender, nftReceiver);
        } else {
            revert InvalidPositionState(positionId, position.status);
        }
        _assertSolvent();
    }

    function requestBackingChange(uint256 positionId, uint128 newBacking) external nonReentrant {
        if (boundaryActive) revert EpochBoundaryPending();
        if (positionToken.ownerOf(positionId) != msg.sender) revert Ineligible(msg.sender);
        _validateBacking(newBacking);
        ProtocolTypes.Position storage position = positions[positionId];
        if (position.status != ProtocolTypes.PositionStatus.Active) {
            revert InvalidPositionState(positionId, position.status);
        }
        uint256 oldBacking = position.backing;
        if (newBacking > oldBacking) {
            uint256 addition = newBacking - oldBacking;
            vault.depositSettlement(msg.sender, addition);
            backingLiability += addition;
        }
        if (_treeLocked()) {
            position.pendingBacking = newBacking;
            position.status = ProtocolTypes.PositionStatus.BackingChangeQueued;
            _backingChangeQueue.push(positionId);
            emit BackingChangeQueued(positionId, oldBacking, newBacking);
        } else {
            uint256 reduction = _applyBackingChange(positionId, position, newBacking);
            if (reduction != 0) vault.releaseSettlement(msg.sender, reduction);
        }
        _assertSolvent();
    }

    function setEarningsRecipient(uint256 positionId, address recipient) external nonReentrant {
        if (positionToken.ownerOf(positionId) != msg.sender) revert Ineligible(msg.sender);
        if (recipient == address(0)) revert ZeroAddress();
        ProtocolTypes.PositionStatus status = positions[positionId].status;
        if (!_isTransferable(status)) revert InvalidPositionState(positionId, status);
        positions[positionId].earningsRecipient = recipient;
    }

    function finalizeSelectedPosition(uint256 positionId) external nonReentrant {
        if (msg.sender != address(settlementEngine)) revert Ineligible(msg.sender);
        ProtocolTypes.Position storage position = positions[positionId];
        if (position.status != ProtocolTypes.PositionStatus.Selected) {
            revert InvalidPositionState(positionId, position.status);
        }
        position.status = ProtocolTypes.PositionStatus.Closed;
        positionToken.setFrozen(positionId, false);
        positionToken.burn(positionId);
    }

    function relistFromSettlement(
        address payer,
        address owner,
        address collection,
        uint256 tokenId,
        uint128 backing,
        address earningsRecipient
    ) external nonReentrant returns (uint256 positionId) {
        if (msg.sender != address(settlementEngine)) revert Ineligible(msg.sender);
        if (boundaryActive) revert EpochBoundaryPending();
        _validateBacking(backing);
        if (!_canDeposit(owner)) revert Ineligible(owner);
        positionId = _initializePosition(collection, tokenId, backing, earningsRecipient);
        ProtocolTypes.Position storage position = positions[positionId];
        if (!_canReceive(owner, positionId)) revert Ineligible(owner);
        backingLiability += backing;
        vault.depositSettlement(payer, backing);
        positionToken.mint(owner, positionId);
        _activateOrStage(positionId, position);
        emit PositionDeposited(positionId, owner, collection, tokenId, backing, position.status);
        _assertSolvent();
    }

    function applyQueuedBackingChange(uint256 positionId) external nonReentrant {
        if (boundaryActive) revert EpochBoundaryPending();
        if (_treeLocked()) revert InvalidConfiguration();
        ProtocolTypes.Position storage position = positions[positionId];
        if (position.status != ProtocolTypes.PositionStatus.BackingChangeQueued) {
            revert InvalidPositionState(positionId, position.status);
        }
        address owner = positionToken.ownerOf(positionId);
        uint256 reduction = _applyBackingChange(positionId, position, position.pendingBacking);
        if (reduction != 0) vault.releaseSettlement(owner, reduction);
        _assertSolvent();
    }

    function claimWithdrawal(uint256 positionId, address nftReceiver) external nonReentrant {
        WithdrawalClaim memory claim = withdrawalClaims[positionId];
        if (claim.owner != msg.sender) revert Ineligible(msg.sender);
        if (nftReceiver == address(0)) revert ZeroAddress();

        delete withdrawalClaims[positionId];
        positions[positionId].status = ProtocolTypes.PositionStatus.Withdrawn;
        _releasePositionLiabilities(claim.backing, claim.cashEarnings, claim.rewardInput);
        _deliverSettlementOrAccrue(claim.owner, claim.owner, claim.backing);
        _deliverSettlementOrAccrue(claim.earningsRecipient, claim.earningsRecipient, claim.cashEarnings);
        _fundRewardOrAccrue(claim.earningsRecipient, claim.rewardInput);
        ProtocolTypes.Position storage position = positions[positionId];
        _deliverNFTOrDefer(claim.owner, nftReceiver, position.collection, position.tokenId);
        emit PositionWithdrawn(positionId, claim.owner, claim.backing, claim.cashEarnings, claim.rewardInput);
        _assertSolvent();
    }

    function challengeCrown(uint256 positionId) external {
        if (boundaryActive) revert EpochBoundaryPending();
        ProtocolTypes.Position storage position = positions[positionId];
        if (position.status != ProtocolTypes.PositionStatus.Active) {
            revert InvalidPositionState(positionId, position.status);
        }
        _considerCrown(positionId, position.backing);
    }

    function canPullUser(address user) external view returns (bool) {
        return _canPull(user);
    }

    function lockEpoch() external returns (uint32 count, uint256 weight, bytes32 root) {
        if (
            msg.sender != address(epochCoordinator) || epochLocked || boundaryActive || _hasBoundaryWork()
                || activePositionCount == 0
        ) {
            revert InvalidConfiguration();
        }
        epochLocked = true;
        return (activePositionCount, _tree.total(), activeSetCommitment);
    }

    function unlockEpoch() external {
        if (msg.sender != address(epochCoordinator) || !epochLocked) revert InvalidConfiguration();
        epochLocked = false;
        boundaryActive = _hasBoundaryWork();
        emit EpochBoundaryStarted(
            _withdrawalQueue.length - _withdrawalCursor,
            _backingChangeQueue.length - _backingChangeCursor,
            _activationQueue.length - _activationCursor
        );
        if (!boundaryActive) {
            _ensureCrown();
            emit EpochBoundaryCompleted();
        }
    }

    function epochBoundaryPending() external view returns (bool) {
        return boundaryActive;
    }

    function epochBoundaryState()
        external
        view
        returns (uint256 withdrawalRemaining, uint256 backingChangeRemaining, uint256 activationRemaining)
    {
        withdrawalRemaining = _withdrawalQueue.length - _withdrawalCursor;
        backingChangeRemaining = _backingChangeQueue.length - _backingChangeCursor;
        activationRemaining = _activationQueue.length - _activationCursor;
    }

    function processEpochBoundary(uint32 maxPositions)
        external
        nonReentrant
        returns (uint32 processed, bool complete)
    {
        if (
            msg.sender != address(epochCoordinator) || epochLocked || maxPositions == 0
                || maxPositions > MAX_BOUNDARY_BATCH
        ) {
            revert InvalidConfiguration();
        }

        while (processed < maxPositions && _withdrawalCursor < _withdrawalQueue.length) {
            uint256 positionId = _withdrawalQueue[_withdrawalCursor++];
            ProtocolTypes.Position storage position = positions[positionId];
            if (position.status == ProtocolTypes.PositionStatus.WithdrawalQueued) {
                _prepareWithdrawal(positionId, position);
            }
            processed++;
        }
        while (processed < maxPositions && _backingChangeCursor < _backingChangeQueue.length) {
            uint256 positionId = _backingChangeQueue[_backingChangeCursor++];
            ProtocolTypes.Position storage position = positions[positionId];
            if (position.status == ProtocolTypes.PositionStatus.BackingChangeQueued) {
                address owner = positionToken.ownerOf(positionId);
                uint256 reduction = _applyBackingChange(positionId, position, position.pendingBacking);
                if (reduction != 0) {
                    settlementClaims[owner] += reduction;
                    settlementClaimLiability += reduction;
                }
            }
            processed++;
        }
        while (processed < maxPositions && _activationCursor < _activationQueue.length) {
            uint256 positionId = _activationQueue[_activationCursor++];
            ProtocolTypes.Position storage position = positions[positionId];
            if (
                position.status == ProtocolTypes.PositionStatus.Staged
                    && activePositionCount < maxActivePositions
            ) {
                _activate(positionId, position);
            }
            processed++;
        }

        complete = !_hasBoundaryWork();
        if (complete) {
            _ensureCrown();
            boundaryActive = false;
            emit EpochBoundaryCompleted();
        }
        emit EpochBoundaryAdvanced(
            processed,
            _withdrawalQueue.length - _withdrawalCursor,
            _backingChangeQueue.length - _backingChangeCursor,
            _activationQueue.length - _activationCursor
        );
        _assertSolvent();
    }

    function resolveDraw(
        uint256 epochId,
        address buyer,
        address receiver,
        uint128 chargedPrice,
        address referrer,
        uint256 randomValue
    ) external nonReentrant returns (uint256 receiptId, uint256 positionId, uint128 backing) {
        if (msg.sender != address(epochCoordinator) || !epochLocked) revert InvalidConfiguration();
        if (chargedPrice != currentPullPrice()) revert InvalidConfiguration();
        uint32 slot = _tree.find(randomValue % _tree.total());
        positionId = positionAtSlot[slot];
        ProtocolTypes.Position storage position = positions[positionId];
        if (!_canReceive(receiver, positionId)) revert IDrawMarketCore.IneligibleReceiver(receiver);
        _allocatePullPayment(chargedPrice);
        backing = position.backing;
        receiptId = _selectPosition(epochId, positionId, position, buyer, receiver, chargedPrice, referrer);
        emit PositionSelected(receiptId, positionId, buyer, chargedPrice, backing);
        _assertSolvent();
    }

    function claimSettlement() external nonReentrant {
        _claimSettlement(msg.sender);
    }

    function claimSettlement(address receiver) external nonReentrant {
        if (receiver == address(0)) revert ZeroAddress();
        _claimSettlement(receiver);
    }

    function _claimSettlement(address receiver) private {
        uint256 amount = settlementClaims[msg.sender];
        if (amount == 0) revert NothingToClaim();
        settlementClaims[msg.sender] = 0;
        settlementClaimLiability -= amount;
        vault.releaseSettlement(receiver, amount);
        emit SettlementPayoutClaimed(msg.sender, receiver, amount);
        _assertSolvent();
    }

    function claimNFT(address collection, uint256 tokenId, address receiver) external nonReentrant {
        if (receiver == address(0)) revert ZeroAddress();
        if (pendingNFTClaims[collection][tokenId] != msg.sender) revert NotNFTClaimOwner();
        delete pendingNFTClaims[collection][tokenId];
        vault.releaseNFT(receiver, collection, tokenId);
        emit WithdrawalNFTClaimed(collection, tokenId, msg.sender, receiver);
    }

    function claimProtocolRevenue() external onlyRole(GOVERNOR_ROLE) nonReentrant {
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

    function currentExpectedValue() public view returns (uint256 rawExpectedValue) {
        uint256 treeWeight = _tree.total();
        if (activePositionCount == 0 || treeWeight == 0) return 0;
        // Configuration bounds each weight and expected value by WEIGHT_NUMERATOR; uint32 capacity
        // and the fixed BPS/WAD factors keep the direct numerators within uint256.
        uint256 normalized = uint256(activePositionCount) * WEIGHT_NUMERATOR / treeWeight;
        rawExpectedValue = Math.ceilDiv(normalized, normalizationFactor);
    }

    function currentPullPrice() public view returns (uint256) {
        uint256 expectedValue = currentExpectedValue();
        return Math.ceilDiv(expectedValue * (BPS + markupBps), BPS);
    }

    function positionProbability(uint256 positionId) external view returns (uint256 probabilityWad) {
        ProtocolTypes.Position storage position = positions[positionId];
        if (!_isTreeMember(position.status)) return 0;
        uint256 treeWeight = _tree.total();
        return treeWeight == 0 ? 0 : _tree.weightAt(position.treeSlot) * 1e18 / treeWeight;
    }

    function pendingPositionEarnings(uint256 positionId)
        external
        view
        returns (uint256 cash, uint256 rewardInput)
    {
        ProtocolTypes.Position storage position = positions[positionId];
        return _pendingEarnings(position);
    }

    function canTransferPosition(address, address to, uint256 positionId) external view returns (bool) {
        if (msg.sender != address(positionToken)) return false;
        ProtocolTypes.PositionStatus status = positions[positionId].status;
        if (!_isTransferable(status)) return false;
        return _canReceive(to, positionId);
    }

    function totalWeight() external view returns (uint256) {
        return _tree.total();
    }

    function totalLiabilities() public view returns (uint256) {
        return backingLiability + earningsLiability + rewardInputLiability + settlementClaimLiability
            + crownLiability + securityLiability + protocolLiability + settlementEngine.totalLiabilities()
            + epochCoordinator.totalLiabilities();
    }

    function solvent() external view returns (bool) {
        return IERC20Metadata(settlementAsset).balanceOf(address(vault)) >= totalLiabilities();
    }

    function _allocatePullPayment(uint256 pullPrice) private {
        uint256 expectedValue = currentExpectedValue();
        uint256 markup = pullPrice - expectedValue;
        uint256 rewardShare = markup * REWARD_MARKUP_BPS / BPS;
        uint256 remainder = markup - rewardShare;
        uint256 crownShare = remainder * CROWN_REMAINDER_BPS / BPS;
        uint256 protocolShare = remainder * PROTOCOL_REMAINDER_BPS / BPS;
        uint256 depositorMarkup = remainder - crownShare - protocolShare;

        _accrueCash(expectedValue, true);
        _accrueCash(depositorMarkup, false);
        _accrueReward(rewardShare);
        crownPot += crownShare;
        crownLiability += crownShare;
        protocolLiability += protocolShare;
    }

    function _accrueCash(uint256 amount, bool base) private {
        uint256 scaledAmount = amount * ACC_PRECISION;
        uint256 increment = scaledAmount / activePositionCount;
        if (base) accBasePerPosition += increment;
        else accMarkupPerPosition += increment;
        earningsLiability += amount;
        _recordCashDust(scaledAmount - increment * activePositionCount);
    }

    function _accrueReward(uint256 amount) private {
        uint256 scaledAmount = amount * ACC_PRECISION;
        uint256 increment = scaledAmount / activePositionCount;
        accRewardInputPerPosition += increment;
        rewardInputLiability += amount;
        _recordRewardDust(scaledAmount - increment * activePositionCount);
    }

    function _selectPosition(
        uint256 epochId,
        uint256 positionId,
        ProtocolTypes.Position storage position,
        address buyer,
        address receiver,
        uint128 chargedPrice,
        address referrer
    ) private returns (uint256 receiptId) {
        (uint256 cash, uint256 rewardInput) = _crystallizeEarnings(position);
        address previousOwner = positionToken.ownerOf(positionId);
        _removeFromTree(position);
        _releasePositionLiabilities(position.backing, cash, rewardInput);

        if (position.pendingBacking > position.backing) {
            uint256 unusedAddition = position.pendingBacking - position.backing;
            backingLiability -= unusedAddition;
            settlementClaims[previousOwner] += unusedAddition;
            settlementClaimLiability += unusedAddition;
        }
        position.pendingBacking = 0;
        _succeedRemovedCrown(positionId);
        position.status = ProtocolTypes.PositionStatus.Selected;
        positionToken.setFrozen(positionId, true);
        receiptId = settlementEngine.registerSelection(
            epochId,
            positionId,
            buyer,
            receiver,
            position.collection,
            position.tokenId,
            previousOwner,
            position.earningsRecipient,
            chargedPrice,
            position.backing,
            cash,
            rewardInput,
            referrer
        );
    }

    function _withdraw(
        uint256 positionId,
        ProtocolTypes.Position storage position,
        address owner,
        address nftReceiver
    ) private {
        (uint256 backing, uint256 cash, uint256 rewardInput) = _detachPosition(positionId, position);
        position.status = ProtocolTypes.PositionStatus.Withdrawn;
        _releasePositionLiabilities(backing, cash, rewardInput);
        positionToken.burn(positionId);
        _deliverSettlementOrAccrue(owner, owner, backing);
        _deliverSettlementOrAccrue(position.earningsRecipient, position.earningsRecipient, cash);
        _fundRewardOrAccrue(position.earningsRecipient, rewardInput);
        _deliverNFTOrDefer(owner, nftReceiver, position.collection, position.tokenId);
        emit PositionWithdrawn(positionId, owner, backing, cash, rewardInput);
    }

    function _releasePositionLiabilities(uint256 backing, uint256 cash, uint256 rewardInput) private {
        backingLiability -= backing;
        earningsLiability -= cash;
        rewardInputLiability -= rewardInput;
    }

    function _detachPosition(uint256 positionId, ProtocolTypes.Position storage position)
        private
        returns (uint256 backing, uint256 cash, uint256 rewardInput)
    {
        (cash, rewardInput) = _crystallizeEarnings(position);
        if (_isTreeMember(position.status)) _removeFromTree(position);
        _succeedRemovedCrown(positionId);
        backing = position.backing;
        if (position.pendingBacking > backing) backing = position.pendingBacking;
    }

    function _fundRewardOrAccrue(address beneficiary, uint256 amount) private {
        if (amount == 0) return;
        try settlementEngine.dispatchMarketReward(beneficiary, amount) { }
        catch {
            _accrueSettlementClaim(beneficiary, amount);
            emit RewardFundingCashFallbackAccrued(beneficiary, amount);
        }
    }

    function _deliverSettlementOrAccrue(address claimOwner, address receiver, uint256 amount) private {
        if (amount == 0) return;
        try vault.releaseSettlement(receiver, amount) { }
        catch {
            _accrueSettlementClaim(claimOwner, amount);
        }
    }

    function _accrueSettlementClaim(address claimOwner, uint256 amount) private {
        settlementClaims[claimOwner] += amount;
        settlementClaimLiability += amount;
        emit SettlementPayoutAccrued(claimOwner, amount);
    }

    function _deliverNFTOrDefer(address claimOwner, address receiver, address collection, uint256 tokenId)
        private
    {
        if (vault.tryReleaseNFT(receiver, collection, tokenId)) return;
        if (pendingNFTClaims[collection][tokenId] != address(0)) revert NFTClaimAlreadyExists();
        pendingNFTClaims[collection][tokenId] = claimOwner;
        emit WithdrawalNFTDeliveryDeferred(collection, tokenId, claimOwner);
    }

    function _initializePosition(
        address collection,
        uint256 tokenId,
        uint128 backing,
        address earningsRecipient
    ) private returns (uint256 positionId) {
        positionId = nextPositionId++;
        ProtocolTypes.Position storage position = positions[positionId];
        position.collection = collection;
        position.tokenId = tokenId;
        position.backing = backing;
        position.earningsRecipient = earningsRecipient;
    }

    function _activateOrStage(uint256 positionId, ProtocolTypes.Position storage position) private {
        if (_treeLocked()) {
            position.status = ProtocolTypes.PositionStatus.Staged;
            _activationQueue.push(positionId);
        } else {
            _activate(positionId, position);
        }
    }

    function _activate(uint256 positionId, ProtocolTypes.Position storage position) private {
        if (activePositionCount >= maxActivePositions) revert MarketCapacityReached();
        uint32 slot;
        if (_freeSlots.length != 0) {
            slot = _freeSlots[_freeSlots.length - 1];
            _freeSlots.pop();
        } else {
            slot = _nextSlot++;
            if (slot >= _tree.capacity) revert MarketCapacityReached();
        }
        uint256 weight = _weight(position.backing);
        position.treeSlot = slot;
        position.status = ProtocolTypes.PositionStatus.Active;
        position.baseDebt = accBasePerPosition;
        position.markupDebt = accMarkupPerPosition;
        position.rewardDebt = accRewardInputPerPosition;
        positionAtSlot[slot] = positionId;
        _tree.set(slot, weight, _leafCommitment(positionId, slot, weight));
        _setCrownCandidate(slot, position.backing);
        activePositionCount++;
        activeSetCommitment = _tree.root();
        _considerCrown(positionId, position.backing);
        emit PositionActivated(positionId, slot, weight);
    }

    function _removeFromTree(ProtocolTypes.Position storage position) private {
        uint32 slot = position.treeSlot;
        _tree.set(slot, 0, bytes32(0));
        _setCrownCandidate(slot, 0);
        activeSetCommitment = _tree.root();
        positionAtSlot[slot] = 0;
        _freeSlots.push(slot);
        activePositionCount--;
    }

    function _applyBackingChange(
        uint256 positionId,
        ProtocolTypes.Position storage position,
        uint128 newBacking
    ) private returns (uint256 reduction) {
        uint256 oldBacking = position.backing;
        uint32 slot = position.treeSlot;
        position.backing = newBacking;
        position.pendingBacking = 0;
        position.status = ProtocolTypes.PositionStatus.Active;
        uint256 newWeight = _weight(newBacking);
        _tree.set(slot, newWeight, _leafCommitment(positionId, slot, newWeight));
        _setCrownCandidate(slot, newBacking);
        activeSetCommitment = _tree.root();
        if (newBacking < oldBacking) {
            reduction = oldBacking - newBacking;
            backingLiability -= reduction;
        }
        if (crownPositionId == positionId && newBacking < oldBacking) {
            _recomputeCrown();
        } else {
            _considerCrown(positionId, newBacking);
        }
        emit BackingChanged(positionId, oldBacking, newBacking);
    }

    function _considerCrown(uint256 positionId, uint256 backing) private {
        uint256 incumbent = crownPositionId;
        if (incumbent == positionId) return;
        if (incumbent == 0 || backing * BPS >= uint256(positions[incumbent].backing) * CROWN_CHALLENGE_BPS) {
            _releaseCrown(incumbent, positionId);
        }
    }

    function _releaseCrown(uint256 previousPositionId, uint256 newPositionId) private {
        uint256 paidPot = crownPot;
        if (previousPositionId != 0 && paidPot != 0) {
            address owner = positionToken.ownerOf(previousPositionId);
            crownPot = 0;
            crownLiability -= paidPot;
            settlementClaims[owner] += paidPot;
            settlementClaimLiability += paidPot;
        }
        crownPositionId = newPositionId;
        emit CrownChanged(previousPositionId, newPositionId, paidPot);
    }

    function _pendingEarnings(ProtocolTypes.Position storage position)
        private
        view
        returns (uint256 cash, uint256 rewardInput)
    {
        if (!_isTreeMember(position.status)) return (0, 0);
        cash = (accBasePerPosition - position.baseDebt) / ACC_PRECISION
            + (accMarkupPerPosition - position.markupDebt) / ACC_PRECISION;
        rewardInput = (accRewardInputPerPosition - position.rewardDebt) / ACC_PRECISION;
    }

    function _crystallizeEarnings(ProtocolTypes.Position storage position)
        private
        returns (uint256 cash, uint256 rewardInput)
    {
        if (!_isTreeMember(position.status)) return (0, 0);
        uint256 baseAccrued = accBasePerPosition - position.baseDebt;
        uint256 markupAccrued = accMarkupPerPosition - position.markupDebt;
        uint256 rewardAccrued = accRewardInputPerPosition - position.rewardDebt;
        cash = baseAccrued / ACC_PRECISION + markupAccrued / ACC_PRECISION;
        rewardInput = rewardAccrued / ACC_PRECISION;
        _recordCashDust(baseAccrued % ACC_PRECISION + markupAccrued % ACC_PRECISION);
        _recordRewardDust(rewardAccrued % ACC_PRECISION);
    }

    function _recordCashDust(uint256 scaledDust) private {
        _recordRoundingDust(scaledDust, false);
    }

    function _recordRewardDust(uint256 scaledDust) private {
        _recordRoundingDust(scaledDust, true);
    }

    function _recordRoundingDust(uint256 scaledDust, bool reward) private {
        // Fractions become security revenue only after retired entitlements sum to a raw asset unit.
        uint256 totalDust = (reward ? _rewardRoundingDust : _cashRoundingDust) + scaledDust;
        uint256 wholeUnits = totalDust / ACC_PRECISION;
        uint256 remainder = totalDust % ACC_PRECISION;
        if (reward) _rewardRoundingDust = remainder;
        else _cashRoundingDust = remainder;
        if (wholeUnits == 0) return;
        if (reward) rewardInputLiability -= wholeUnits;
        else earningsLiability -= wholeUnits;
        securityLiability += wholeUnits;
    }

    function _weight(uint256 rawBacking) private view returns (uint256) {
        return WEIGHT_NUMERATOR / (rawBacking * normalizationFactor);
    }

    function _leafCommitment(uint256 positionId, uint32 slot, uint256 weight) private pure returns (bytes32) {
        return keccak256(abi.encode(positionId, slot, weight));
    }

    function _validateBacking(uint256 backing) private view {
        if (backing < minBacking || backing > maxBacking) revert InvalidBacking(backing);
    }

    function _canDeposit(address user) private view returns (bool) {
        return address(eligibilityPolicy) == address(0) || eligibilityPolicy.canDeposit(user, marketId);
    }

    function _canPull(address user) private view returns (bool) {
        return address(eligibilityPolicy) == address(0) || eligibilityPolicy.canPull(user, marketId);
    }

    function _canReceive(address user, uint256 positionId) private view returns (bool) {
        address policy = address(eligibilityPolicy);
        if (policy == address(0)) return true;
        bytes memory callData = abi.encodeCall(IEligibilityPolicy.canReceive, (user, positionId));
        bool success;
        uint256 resultSize;
        uint256 allowed;
        assembly ("memory-safe") {
            success := staticcall(gas(), policy, add(callData, 0x20), mload(callData), 0, 0)
            resultSize := returndatasize()
            if and(success, eq(resultSize, 0x20)) {
                returndatacopy(0, 0, 0x20)
                allowed := mload(0)
            }
        }
        return success && resultSize == 32 && allowed == 1;
    }

    function _treeLocked() private view returns (bool) {
        return epochLocked;
    }

    function _hasBoundaryWork() private view returns (bool) {
        return _withdrawalCursor < _withdrawalQueue.length
            || _backingChangeCursor < _backingChangeQueue.length
            || _activationCursor < _activationQueue.length;
    }

    function _ensureCrown() private {
        if (crownPositionId != 0 || activePositionCount == 0) return;
        _recomputeCrown();
    }

    function _succeedRemovedCrown(uint256 positionId) private {
        if (crownPositionId != positionId) return;
        _releaseCrown(positionId, 0);
        _ensureCrown();
    }

    function _recomputeCrown() private {
        uint256 previousPositionId = crownPositionId;
        uint256 positionId;
        if (activePositionCount != 0) positionId = _bestCrownCandidate();
        if (positionId != previousPositionId) _releaseCrown(previousPositionId, positionId);
    }

    function _bestCrownCandidate() private view returns (uint256 positionId) {
        uint256 candidate = _crownBackingTree[1];
        uint32 slot = type(uint32).max - uint32(candidate);
        positionId = positionAtSlot[slot];
    }

    function _setCrownCandidate(uint32 slot, uint256 backing) private {
        uint256 node = uint256(_tree.capacity) + slot;
        // Higher backing wins; reversed slot makes equal-backing succession deterministic.
        _crownBackingTree[node] = backing == 0 ? 0 : (backing << 32) | (uint256(type(uint32).max) - slot);
        while (node > 1) {
            node >>= 1;
            uint256 leftCandidate = _crownBackingTree[node << 1];
            uint256 rightCandidate = _crownBackingTree[node << 1 | 1];
            _crownBackingTree[node] = leftCandidate >= rightCandidate ? leftCandidate : rightCandidate;
        }
    }

    function _prepareWithdrawal(uint256 positionId, ProtocolTypes.Position storage position) private {
        address owner = positionToken.ownerOf(positionId);
        (uint256 backing, uint256 cash, uint256 rewardInput) = _detachPosition(positionId, position);
        position.pendingBacking = 0;
        position.status = ProtocolTypes.PositionStatus.WithdrawalClaimable;
        withdrawalClaims[positionId] = WithdrawalClaim({
            owner: owner,
            earningsRecipient: position.earningsRecipient,
            backing: backing,
            cashEarnings: cash,
            rewardInput: rewardInput
        });
        positionToken.burn(positionId);
        emit PositionWithdrawalClaimable(positionId, owner);
    }

    function _isTreeMember(ProtocolTypes.PositionStatus status) private pure returns (bool) {
        return status >= ProtocolTypes.PositionStatus.Active
            && status <= ProtocolTypes.PositionStatus.WithdrawalQueued;
    }

    function _isTransferable(ProtocolTypes.PositionStatus status) private pure returns (bool) {
        return status <= ProtocolTypes.PositionStatus.WithdrawalQueued;
    }

    function _assertSolvent() private view {
        uint256 assets = IERC20Metadata(settlementAsset).balanceOf(address(vault));
        uint256 liabilities = totalLiabilities();
        if (assets < liabilities) revert SolvencyInvariantBroken(assets, liabilities);
    }
}
