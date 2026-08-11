// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ISwapAdapter {
    function swapExactOutput(
        address inputAsset,
        address outputAsset,
        uint256 amountOut,
        uint256 maxAmountIn,
        address receiver,
        bytes calldata routeData
    ) external returns (uint256 amountIn);

    function swapExactInput(
        address inputAsset,
        address outputAsset,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bytes calldata routeData
    ) external returns (uint256 amountOut);
}
