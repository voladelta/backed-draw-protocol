// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { MockERC20 } from "./MockERC20.sol";

contract MockDenylistERC20 is MockERC20 {
    error RejectedRecipient(address recipient);

    mapping(address recipient => bool rejected) public rejectedRecipient;

    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        MockERC20(name_, symbol_, decimals_)
    { }

    function setRejectedRecipient(address recipient, bool rejected) external {
        rejectedRecipient[recipient] = rejected;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (rejectedRecipient[to]) revert RejectedRecipient(to);
        super._update(from, to, value);
    }
}
