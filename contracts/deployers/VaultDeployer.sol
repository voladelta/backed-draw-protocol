// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { MarketVault } from "../MarketVault.sol";

contract VaultDeployer {
    function deploy(address market, address settlementAsset) external returns (address) {
        return address(new MarketVault(market, settlementAsset));
    }
}
