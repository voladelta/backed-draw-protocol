// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockTaxedERC20 is ERC20 {
    uint8 private immutable _tokenDecimals;

    address public taxedSender;
    uint256 public taxBps;
    bool public senderPaysExtra;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setOutboundTax(address sender, uint256 taxBps_, bool senderPaysExtra_) external {
        taxedSender = sender;
        taxBps = taxBps_;
        senderPaysExtra = senderPaysExtra_;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == taxedSender && from != address(0) && to != address(0)) {
            uint256 fee = value * taxBps / 10_000;
            super._update(from, address(0), fee);
            if (!senderPaysExtra) value -= fee;
        }
        super._update(from, to, value);
    }
}
