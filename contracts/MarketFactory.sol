// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { DrawMarket } from "./DrawMarket.sol";
import { ProtocolRegistry } from "./ProtocolRegistry.sol";
import { ReferralRegistry } from "./ReferralRegistry.sol";
import { RewardController } from "./RewardController.sol";
import { ProtocolTypes } from "./types/ProtocolTypes.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { VaultDeployer } from "./deployers/VaultDeployer.sol";
import { PositionTokenDeployer } from "./deployers/PositionTokenDeployer.sol";
import { SettlementEngineDeployer } from "./deployers/SettlementEngineDeployer.sol";
import { EpochCoordinatorDeployer } from "./deployers/EpochCoordinatorDeployer.sol";

contract MarketFactory {
    error ModuleNotApproved(address module);
    error CreationNotAllowed(address creator);
    error InvalidCollectionSet();
    error InvalidEconomicPolicy();
    error ImplementationNotApproved(uint32 version);

    uint32 public constant IMPLEMENTATION_VERSION = 1;
    ProtocolRegistry public immutable registry;
    address public immutable implementation;
    VaultDeployer public immutable vaultDeployer;
    PositionTokenDeployer public immutable positionTokenDeployer;
    SettlementEngineDeployer public immutable settlementEngineDeployer;
    EpochCoordinatorDeployer public immutable epochCoordinatorDeployer;
    uint256 public nextMarketId = 1;
    mapping(uint256 marketId => address market) public marketForId;

    event MarketCreated(
        uint256 indexed marketId,
        address indexed market,
        address indexed creator,
        address settlementAsset,
        bytes32 collectionSetId,
        uint32 version
    );

    constructor(
        address registry_,
        address implementation_,
        address vaultDeployer_,
        address positionTokenDeployer_,
        address settlementEngineDeployer_,
        address epochCoordinatorDeployer_
    ) {
        registry = ProtocolRegistry(registry_);
        implementation = implementation_;
        vaultDeployer = VaultDeployer(vaultDeployer_);
        positionTokenDeployer = PositionTokenDeployer(positionTokenDeployer_);
        settlementEngineDeployer = SettlementEngineDeployer(settlementEngineDeployer_);
        epochCoordinatorDeployer = EpochCoordinatorDeployer(epochCoordinatorDeployer_);
    }

    function createMarket(ProtocolTypes.MarketConfig calldata input, address[] calldata initialCollections)
        external
        returns (address marketAddress)
    {
        if (!registry.canCreateMarket(msg.sender)) revert CreationNotAllowed(msg.sender);
        if (registry.implementationCodeHash(IMPLEMENTATION_VERSION) != implementation.codehash) {
            revert ImplementationNotApproved(IMPLEMENTATION_VERSION);
        }
        if (!registry.settlementAssetApproved(input.settlementAsset)) {
            revert ModuleNotApproved(input.settlementAsset);
        }
        if (!registry.randomnessAdapterApproved(input.randomnessAdapter)) {
            revert ModuleNotApproved(input.randomnessAdapter);
        }
        if (
            input.eligibilityPolicy != address(0)
                && !registry.eligibilityPolicyApproved(input.eligibilityPolicy)
        ) {
            revert ModuleNotApproved(input.eligibilityPolicy);
        }
        if (!registry.referralRegistryApproved(input.referralRegistry)) {
            revert ModuleNotApproved(input.referralRegistry);
        }
        if (!registry.rewardControllerApproved(input.rewardController)) {
            revert ModuleNotApproved(input.rewardController);
        }
        if (input.trustedRouter != address(0) && !registry.routerApproved(input.trustedRouter)) {
            revert ModuleNotApproved(input.trustedRouter);
        }
        if (input.collectionSetId == bytes32(0) || initialCollections.length == 0) {
            revert InvalidCollectionSet();
        }
        if (!ProtocolTypes.isValidEconomicPolicy(input.markupBps, input.cashPayoutBps, input.keepPayoutBps)) {
            revert InvalidEconomicPolicy();
        }

        uint256 marketId = nextMarketId++;
        ProtocolTypes.MarketConfig memory config = input;
        config.marketId = marketId;
        config.protocolRegistry = address(registry);
        marketAddress = Clones.clone(implementation);
        DrawMarket market = DrawMarket(marketAddress);
        address vault = vaultDeployer.deploy(marketAddress, config.settlementAsset);
        address positionToken = positionTokenDeployer.deploy(marketAddress);
        address settlementEngine = settlementEngineDeployer.deploy(marketAddress, vault, config);
        address epochCoordinator = epochCoordinatorDeployer.deploy(marketAddress, vault, config);
        market.initialize(
            config, vault, positionToken, settlementEngine, epochCoordinator, initialCollections
        );
        marketForId[marketId] = marketAddress;
        ReferralRegistry(config.referralRegistry).authorizeMarket(epochCoordinator);
        RewardController(config.rewardController).authorizeMarket(marketAddress);
        RewardController(config.rewardController).authorizeMarket(settlementEngine);
        registry.registerMarket(marketAddress, marketId, IMPLEMENTATION_VERSION);
        emit MarketCreated(
            marketId,
            marketAddress,
            msg.sender,
            config.settlementAsset,
            config.collectionSetId,
            IMPLEMENTATION_VERSION
        );
    }
}
