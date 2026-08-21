// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ProtocolTypes } from "./types/ProtocolTypes.sol";
import { IDrawMarket, IEpochCoordinator } from "./interfaces/IDrawMarket.sol";
import { IProtocolRegistry } from "./interfaces/IProtocolRegistry.sol";
import { ISwapAdapter } from "./interfaces/ISwapAdapter.sol";
import { IWETH } from "./interfaces/IWETH.sol";

contract SwapAndPullRouter is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidNativeValue();
    error UnregisteredMarket(address market);
    error DeadlineExpired();
    error ExcessiveInput(uint256 actual, uint256 maximum);
    error NativeRefundFailed();

    bytes32 public constant ADAPTER_ADMIN_ROLE = keccak256("ADAPTER_ADMIN_ROLE");

    IProtocolRegistry public immutable registry;
    address public immutable weth;
    ISwapAdapter public swapAdapter;

    event SwapAdapterUpdated(address indexed adapter);
    event PullRouted(
        address indexed buyer,
        address indexed market,
        address indexed inputAsset,
        uint256 inputAmount,
        uint256 settlementAmount,
        uint256 orderIndex
    );
    event PayoutConverted(
        address indexed user,
        address indexed inputAsset,
        address indexed outputAsset,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address admin, address weth_, address swapAdapter_, address registry_) {
        registry = IProtocolRegistry(registry_);
        weth = weth_;
        swapAdapter = ISwapAdapter(swapAdapter_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADAPTER_ADMIN_ROLE, admin);
    }

    receive() external payable {
        if (msg.sender != weth) revert InvalidNativeValue();
    }

    function setSwapAdapter(address adapter) external onlyRole(ADAPTER_ADMIN_ROLE) {
        swapAdapter = ISwapAdapter(adapter);
        emit SwapAdapterUpdated(adapter);
    }

    function swapAndPull(
        address marketAddress,
        address inputAsset,
        uint256 maxAmountIn,
        ProtocolTypes.PullOrderInput calldata order,
        bytes calldata routeData
    ) external payable nonReentrant returns (uint256 orderIndex, uint256 amountIn) {
        if (order.deadline < block.timestamp) revert DeadlineExpired();
        if (!registry.isMarket(marketAddress)) revert UnregisteredMarket(marketAddress);
        IDrawMarket market = IDrawMarket(marketAddress);
        address settlement = market.settlementAsset();
        bool nativeInput = inputAsset == address(0);
        address routedInput = nativeInput ? weth : inputAsset;

        if (nativeInput) {
            if (msg.value != maxAmountIn) revert InvalidNativeValue();
            IWETH(weth).deposit{ value: maxAmountIn }();
        } else {
            if (msg.value != 0) revert InvalidNativeValue();
            IERC20(inputAsset).safeTransferFrom(msg.sender, address(this), maxAmountIn);
        }

        if (routedInput == settlement) {
            amountIn = order.maxTotalPrice;
        } else {
            IERC20(routedInput).forceApprove(address(swapAdapter), maxAmountIn);
            amountIn = swapAdapter.swapExactOutput(
                routedInput, settlement, order.maxTotalPrice, maxAmountIn, address(this), routeData
            );
        }
        if (amountIn > maxAmountIn) revert ExcessiveInput(amountIn, maxAmountIn);

        IERC20(settlement).forceApprove(market.vault(), order.maxTotalPrice);
        orderIndex =
            IEpochCoordinator(market.epochCoordinator()).requestPullFor(address(this), msg.sender, order);
        _refundInput(routedInput, nativeInput, maxAmountIn - amountIn, msg.sender);
        emit PullRouted(msg.sender, marketAddress, routedInput, amountIn, order.maxTotalPrice, orderIndex);
    }

    function convertPayout(
        address inputAsset,
        address outputAsset,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        bytes calldata routeData
    ) external nonReentrant returns (uint256 amountOut) {
        IERC20(inputAsset).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(inputAsset).forceApprove(address(swapAdapter), amountIn);
        amountOut = swapAdapter.swapExactInput(
            inputAsset, outputAsset, amountIn, minAmountOut, receiver, routeData
        );
        emit PayoutConverted(msg.sender, inputAsset, outputAsset, amountIn, amountOut);
    }

    function _refundInput(address inputAsset, bool nativeInput, uint256 amount, address receiver) private {
        if (amount == 0) return;
        if (!nativeInput) {
            IERC20(inputAsset).safeTransfer(receiver, amount);
            return;
        }
        IWETH(weth).withdraw(amount);
        (bool sent,) = receiver.call{ value: amount }("");
        if (!sent) {
            IWETH(weth).deposit{ value: amount }();
            if (!IWETH(weth).transfer(receiver, amount)) revert NativeRefundFailed();
        }
    }
}
