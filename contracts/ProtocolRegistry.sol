// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract ProtocolRegistry is AccessControl {
    bytes32 public constant MARKET_CREATOR_ROLE = keccak256("MARKET_CREATOR_ROLE");
    bytes32 public constant REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");

    mapping(address asset => bool approved) public settlementAssetApproved;
    mapping(address adapter => bool approved) public randomnessAdapterApproved;
    mapping(address policy => bool approved) public eligibilityPolicyApproved;
    mapping(address registry => bool approved) public referralRegistryApproved;
    mapping(address controller => bool approved) public rewardControllerApproved;
    mapping(address router => bool approved) public routerApproved;
    mapping(address market => bool registered) public isMarket;
    mapping(uint32 version => bytes32 codeHash) public implementationCodeHash;
    bool public permissionlessCreation;

    event ModuleApprovalUpdated(bytes32 indexed moduleType, address indexed module, bool approved);
    event MarketRegistered(address indexed market, uint256 indexed marketId, uint32 indexed version);
    event PermissionlessCreationUpdated(bool enabled);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRY_MANAGER_ROLE, admin);
        _grantRole(MARKET_CREATOR_ROLE, admin);
    }

    function setSettlementAsset(address module, bool approved) external onlyRole(REGISTRY_MANAGER_ROLE) {
        settlementAssetApproved[module] = approved;
        emit ModuleApprovalUpdated("SETTLEMENT_ASSET", module, approved);
    }

    function setRandomnessAdapter(address module, bool approved) external onlyRole(REGISTRY_MANAGER_ROLE) {
        randomnessAdapterApproved[module] = approved;
        emit ModuleApprovalUpdated("RANDOMNESS_ADAPTER", module, approved);
    }

    function setEligibilityPolicy(address module, bool approved) external onlyRole(REGISTRY_MANAGER_ROLE) {
        eligibilityPolicyApproved[module] = approved;
        emit ModuleApprovalUpdated("ELIGIBILITY_POLICY", module, approved);
    }

    function setReferralRegistry(address module, bool approved) external onlyRole(REGISTRY_MANAGER_ROLE) {
        referralRegistryApproved[module] = approved;
        emit ModuleApprovalUpdated("REFERRAL_REGISTRY", module, approved);
    }

    function setRewardController(address module, bool approved) external onlyRole(REGISTRY_MANAGER_ROLE) {
        rewardControllerApproved[module] = approved;
        emit ModuleApprovalUpdated("REWARD_CONTROLLER", module, approved);
    }

    function setRouter(address module, bool approved) external onlyRole(REGISTRY_MANAGER_ROLE) {
        routerApproved[module] = approved;
        emit ModuleApprovalUpdated("ROUTER", module, approved);
    }

    function setImplementation(uint32 version, bytes32 codeHash) external onlyRole(REGISTRY_MANAGER_ROLE) {
        implementationCodeHash[version] = codeHash;
    }

    function setPermissionlessCreation(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        permissionlessCreation = enabled;
        emit PermissionlessCreationUpdated(enabled);
    }

    function registerMarket(address market, uint256 marketId, uint32 version)
        external
        onlyRole(REGISTRY_MANAGER_ROLE)
    {
        isMarket[market] = true;
        emit MarketRegistered(market, marketId, version);
    }

    function canCreateMarket(address creator) external view returns (bool) {
        return permissionlessCreation || hasRole(MARKET_CREATOR_ROLE, creator);
    }
}
