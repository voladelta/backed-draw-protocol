// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { EpochCoordinator } from "../EpochCoordinator.sol";
import { ProtocolTypes } from "../types/ProtocolTypes.sol";

contract EpochCoordinatorDeployer {
    function deploy(address market, address vault, ProtocolTypes.MarketConfig calldata config)
        external
        returns (address)
    {
        return address(
            new EpochCoordinator(
                config.marketId,
                market,
                vault,
                config.protocolRegistry,
                config.referralRegistry,
                config.randomnessAdapter,
                config.governor,
                config.guardian,
                config.trustedRouter,
                config.maxDrawsPerEpoch,
                config.collectionWindow,
                config.randomnessTimeout
            )
        );
    }
}
