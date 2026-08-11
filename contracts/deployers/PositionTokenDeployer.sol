// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { PositionNFT } from "../tokens/PositionNFT.sol";

contract PositionTokenDeployer {
    function deploy(address market) external returns (address) {
        return address(new PositionNFT("Backed Position", "BKPOS", market));
    }
}
