// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { RewardController } from "../contracts/RewardController.sol";
import { ISwapAdapter } from "../contracts/interfaces/ISwapAdapter.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

contract RewardControllerSwapAdapter is ISwapAdapter {
    uint256 public amountOut;
    uint256 public reportedAmountOut;

    function setAmountOut(uint256 amount) external {
        amountOut = amount;
        reportedAmountOut = amount;
    }

    function setReportedAmountOut(uint256 amount) external {
        reportedAmountOut = amount;
    }

    function swapExactOutput(address, address, uint256, uint256, address, bytes calldata)
        external
        pure
        returns (uint256)
    {
        revert("not implemented");
    }

    function swapExactInput(
        address inputAsset,
        address outputAsset,
        uint256 amountIn,
        uint256,
        address receiver,
        bytes calldata
    ) external returns (uint256) {
        require(IERC20(inputAsset).transferFrom(msg.sender, address(this), amountIn));
        MockERC20(outputAsset).mint(receiver, amountOut);
        return reportedAmountOut;
    }
}

contract RewardControllerTest is Test {
    MockERC20 internal input;
    MockERC20 internal draw;
    RewardControllerSwapAdapter internal adapter;
    RewardController internal controller;

    address internal beneficiary = makeAddr("reward-beneficiary");

    function setUp() external {
        input = new MockERC20("Input", "IN", 18);
        draw = new MockERC20("Draw", "DRAW", 18);
        adapter = new RewardControllerSwapAdapter();
        controller = new RewardController(address(this), address(draw), address(adapter));
        controller.grantRole(controller.MARKET_ROLE(), address(this));
    }

    function testSettlementSwapDeliversProtectedDrawOutput() external {
        input.mint(address(controller), 85 ether);
        adapter.setAmountOut(90 ether);
        vm.prank(address(controller));
        input.approve(address(adapter), 1 ether);

        uint256 drawAmount =
            controller.swapSettlement(beneficiary, address(input), 85 ether, 89 ether, hex"1234");

        assertEq(drawAmount, 90 ether);
        assertEq(draw.balanceOf(beneficiary), 90 ether);
        assertEq(input.balanceOf(address(adapter)), 85 ether);
        assertEq(input.allowance(address(controller), address(adapter)), 0);
    }

    function testProtectedSettlementSwapFailureRevertsFundingAndOutput() external {
        input.mint(address(controller), 85 ether);
        adapter.setAmountOut(80 ether);

        vm.expectRevert(
            abi.encodeWithSelector(RewardController.SlippageExceeded.selector, 80 ether, 81 ether)
        );
        controller.swapSettlement(beneficiary, address(input), 85 ether, 81 ether, hex"1234");

        assertEq(input.balanceOf(address(controller)), 85 ether);
        assertEq(input.balanceOf(address(adapter)), 0);
        assertEq(draw.balanceOf(beneficiary), 0);
    }

    function testSettlementSwapRejectsAdapterThatReportsOutputWithoutDeliveringIt() external {
        input.mint(address(controller), 85 ether);
        adapter.setAmountOut(0);
        adapter.setReportedAmountOut(100 ether);

        vm.expectRevert(abi.encodeWithSelector(RewardController.SlippageExceeded.selector, 0, 80 ether));
        controller.swapSettlement(beneficiary, address(input), 85 ether, 80 ether, "");

        assertEq(input.balanceOf(address(controller)), 85 ether);
        assertEq(input.balanceOf(address(adapter)), 0);
        assertEq(draw.balanceOf(beneficiary), 0);
    }

    function testClaimUsesActualReceiverOutputAndClearsStaleAllowance() external {
        input.mint(address(controller), 10 ether);
        controller.enqueue(beneficiary, address(input), 10 ether);
        adapter.setAmountOut(9 ether);
        adapter.setReportedAmountOut(type(uint256).max);
        vm.prank(address(controller));
        input.approve(address(adapter), 1 ether);

        vm.prank(beneficiary);
        uint256 amountOut = controller.claim(address(input), 8 ether, beneficiary, "");

        assertEq(amountOut, 9 ether);
        assertEq(draw.balanceOf(beneficiary), 9 ether);
        assertEq(input.allowance(address(controller), address(adapter)), 0);
        assertEq(controller.queuedInput(beneficiary, address(input)), 0);
        assertEq(controller.totalQueued(address(input)), 0);
    }

    function testClaimRejectsLyingNoOutputAdapterWithoutConsumingEntitlement() external {
        input.mint(address(controller), 10 ether);
        controller.enqueue(beneficiary, address(input), 10 ether);
        adapter.setAmountOut(0);
        adapter.setReportedAmountOut(10 ether);

        vm.prank(beneficiary);
        vm.expectRevert(abi.encodeWithSelector(RewardController.SlippageExceeded.selector, 0, 1 ether));
        controller.claim(address(input), 1 ether, beneficiary, "");

        assertEq(controller.queuedInput(beneficiary, address(input)), 10 ether);
        assertEq(controller.totalQueued(address(input)), 10 ether);
        assertEq(input.balanceOf(address(controller)), 10 ether);
        assertEq(input.balanceOf(address(adapter)), 0);
    }

    function testSettlementSwapCannotSpendQueuedRewardInput() external {
        input.mint(address(controller), 100 ether);
        controller.enqueue(beneficiary, address(input), 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                RewardController.UnfundedInput.selector, address(input), 100 ether, 110 ether
            )
        );
        controller.swapSettlement(beneficiary, address(input), 100 ether, 0, "");

        assertEq(controller.queuedInput(beneficiary, address(input)), 10 ether);
        assertEq(controller.totalQueued(address(input)), 10 ether);
    }
}
