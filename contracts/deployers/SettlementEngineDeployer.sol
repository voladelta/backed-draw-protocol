// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { SettlementEngine } from "../SettlementEngine.sol";
import { ProtocolTypes } from "../types/ProtocolTypes.sol";

contract SettlementEngineDeployer {
    function deploy(address market, address vault, ProtocolTypes.MarketConfig calldata config)
        external
        returns (address)
    {
        return address(
            new SettlementEngine(
                market,
                config.marketId,
                config.settlementAsset,
                config.governor,
                config.treasury,
                config.insuranceReserve,
                config.buybackReceiver,
                vault,
                config.rewardController,
                config.minBacking,
                config.maxBacking,
                config.decisionWindow
            )
        );
    }
}
