// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IProtocolRegistry {
    function settlementAssetApproved(address asset) external view returns (bool);
    function randomnessAdapterApproved(address adapter) external view returns (bool);
    function eligibilityPolicyApproved(address policy) external view returns (bool);
    function referralRegistryApproved(address registry) external view returns (bool);
    function rewardControllerApproved(address controller) external view returns (bool);
    function routerApproved(address router) external view returns (bool);
    function canCreateMarket(address creator) external view returns (bool);
    function implementationCodeHash(uint32 version) external view returns (bytes32);
}
