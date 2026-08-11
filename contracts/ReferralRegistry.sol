// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract ReferralRegistry is AccessControl {
    error AlreadyBound();
    error UnknownCode(bytes32 code);
    error SelfReferral();

    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    mapping(bytes32 code => address referrer) public referrerForCode;
    mapping(address user => address referrer) public boundReferrer;

    event ReferralCodeRegistered(bytes32 indexed code, address indexed referrer);
    event ReferralBound(address indexed user, address indexed referrer, bytes32 indexed code);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function registerCode(bytes32 code, address referrer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (code == bytes32(0) || referrer == address(0)) revert UnknownCode(code);
        referrerForCode[code] = referrer;
        emit ReferralCodeRegistered(code, referrer);
    }

    function authorizeMarket(address market) external onlyRole(FACTORY_ROLE) {
        _grantRole(MARKET_ROLE, market);
    }

    function bindReferral(bytes32 code) external {
        _bind(msg.sender, code);
    }

    function bindFromMarket(address user, bytes32 code)
        external
        onlyRole(MARKET_ROLE)
        returns (address referrer)
    {
        if (boundReferrer[user] != address(0)) return boundReferrer[user];
        if (code == bytes32(0)) return address(0);
        return _bind(user, code);
    }

    function resolve(address user, bytes32 suppliedCode) external view returns (address referrer) {
        referrer = boundReferrer[user];
        if (referrer == address(0)) referrer = referrerForCode[suppliedCode];
        if (referrer == user) return address(0);
    }

    function _bind(address user, bytes32 code) private returns (address referrer) {
        if (boundReferrer[user] != address(0)) revert AlreadyBound();
        referrer = referrerForCode[code];
        if (referrer == address(0)) revert UnknownCode(code);
        if (referrer == user) revert SelfReferral();
        boundReferrer[user] = referrer;
        emit ReferralBound(user, referrer, code);
    }
}
