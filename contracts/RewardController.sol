// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapAdapter } from "./interfaces/ISwapAdapter.sol";

contract RewardController is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAmount();
    error SlippageExceeded(uint256 actual, uint256 minimum);
    error UnfundedInput(address asset, uint256 assets, uint256 liabilities);

    bytes32 public constant MARKET_ROLE = keccak256("MARKET_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    bytes32 public constant ADAPTER_ADMIN_ROLE = keccak256("ADAPTER_ADMIN_ROLE");

    address public immutable drawToken;
    ISwapAdapter public swapAdapter;
    mapping(address beneficiary => mapping(address inputAsset => uint256 amount)) public queuedInput;
    mapping(address asset => uint256 amount) public totalQueued;

    event RewardEnqueued(address indexed beneficiary, address indexed inputAsset, uint256 amount);
    event RewardClaimed(
        address indexed beneficiary,
        address indexed receiver,
        address indexed inputAsset,
        uint256 inputAmount,
        uint256 drawAmount
    );
    event SettlementRewardPurchased(
        address indexed beneficiary, address indexed inputAsset, uint256 inputAmount, uint256 drawAmount
    );
    event SwapAdapterUpdated(address indexed adapter);

    constructor(address admin, address drawToken_, address swapAdapter_) {
        drawToken = drawToken_;
        swapAdapter = ISwapAdapter(swapAdapter_);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADAPTER_ADMIN_ROLE, admin);
    }

    function setSwapAdapter(address adapter) external onlyRole(ADAPTER_ADMIN_ROLE) {
        swapAdapter = ISwapAdapter(adapter);
        emit SwapAdapterUpdated(adapter);
    }

    function authorizeMarket(address market) external onlyRole(FACTORY_ROLE) {
        _grantRole(MARKET_ROLE, market);
    }

    function enqueue(address beneficiary, address inputAsset, uint256 inputAmount)
        external
        onlyRole(MARKET_ROLE)
    {
        if (inputAmount == 0) revert ZeroAmount();
        queuedInput[beneficiary][inputAsset] += inputAmount;
        totalQueued[inputAsset] += inputAmount;
        uint256 assets = IERC20(inputAsset).balanceOf(address(this));
        if (assets < totalQueued[inputAsset]) {
            revert UnfundedInput(inputAsset, assets, totalQueued[inputAsset]);
        }
        emit RewardEnqueued(beneficiary, inputAsset, inputAmount);
    }

    function swapSettlement(
        address beneficiary,
        address inputAsset,
        uint256 inputAmount,
        uint256 minDrawOut,
        bytes calldata routeData
    ) external onlyRole(MARKET_ROLE) nonReentrant returns (uint256 drawAmount) {
        if (inputAmount == 0) revert ZeroAmount();
        uint256 assets = IERC20(inputAsset).balanceOf(address(this));
        uint256 requiredAssets = totalQueued[inputAsset] + inputAmount;
        if (assets < requiredAssets) {
            revert UnfundedInput(inputAsset, assets, requiredAssets);
        }
        IERC20(inputAsset).forceApprove(address(swapAdapter), inputAmount);
        drawAmount = swapAdapter.swapExactInput(
            inputAsset, drawToken, inputAmount, minDrawOut, beneficiary, routeData
        );
        IERC20(inputAsset).forceApprove(address(swapAdapter), 0);
        if (drawAmount < minDrawOut) revert SlippageExceeded(drawAmount, minDrawOut);
        emit SettlementRewardPurchased(beneficiary, inputAsset, inputAmount, drawAmount);
    }

    function claim(address inputAsset, uint256 minDrawOut, address receiver, bytes calldata routeData)
        external
        nonReentrant
        returns (uint256 drawAmount)
    {
        uint256 inputAmount = queuedInput[msg.sender][inputAsset];
        if (inputAmount == 0) revert ZeroAmount();
        queuedInput[msg.sender][inputAsset] = 0;
        totalQueued[inputAsset] -= inputAmount;
        IERC20(inputAsset).forceApprove(address(swapAdapter), inputAmount);
        drawAmount =
            swapAdapter.swapExactInput(inputAsset, drawToken, inputAmount, minDrawOut, receiver, routeData);
        if (drawAmount < minDrawOut) revert SlippageExceeded(drawAmount, minDrawOut);
        emit RewardClaimed(msg.sender, receiver, inputAsset, inputAmount, drawAmount);
    }
}
