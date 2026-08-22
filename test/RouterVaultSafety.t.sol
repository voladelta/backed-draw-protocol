// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { SwapAndPullRouter } from "../contracts/SwapAndPullRouter.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockRewardController } from "./mocks/MockRewardController.sol";
import { MockTaxedERC20 } from "./mocks/MockTaxedERC20.sol";

contract RouterVaultSafetyAdversarialSwapAdapter {
    uint256 public inputSpent;
    uint256 public outputDelivered;
    uint256 public amountReported;

    function configure(uint256 inputSpent_, uint256 outputDelivered_, uint256 amountReported_) external {
        inputSpent = inputSpent_;
        outputDelivered = outputDelivered_;
        amountReported = amountReported_;
    }

    function swapExactOutput(
        address inputAsset,
        address outputAsset,
        uint256,
        uint256,
        address receiver,
        bytes calldata
    ) external returns (uint256 amountIn) {
        if (inputSpent != 0) {
            if (!IERC20(inputAsset).transferFrom(msg.sender, address(this), inputSpent)) {
                revert();
            }
        }
        if (outputDelivered != 0 && !IERC20(outputAsset).transfer(receiver, outputDelivered)) revert();
        amountIn = amountReported;
    }

    function swapExactInput(
        address inputAsset,
        address outputAsset,
        uint256,
        uint256,
        address receiver,
        bytes calldata
    ) external returns (uint256 amountOut) {
        if (inputSpent != 0) {
            if (!IERC20(inputAsset).transferFrom(msg.sender, address(this), inputSpent)) {
                revert();
            }
        }
        if (outputDelivered != 0 && !IERC20(outputAsset).transfer(receiver, outputDelivered)) revert();
        amountOut = amountReported;
    }
}

contract RouterVaultSafetyStickyAllowanceERC20 is ERC20 {
    constructor() ERC20("Sticky Allowance", "STICKY") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _spendAllowance(address, address, uint256) internal override { }
}

contract RouterVaultSafetyCounterfeitMarket {
    IERC20 internal immutable _settlementAsset;
    uint256 public requestCount;

    constructor(IERC20 settlementAsset_) {
        _settlementAsset = settlementAsset_;
    }

    function settlementAsset() external view returns (address) {
        return address(_settlementAsset);
    }

    function vault() external view returns (address) {
        return address(this);
    }

    function epochCoordinator() external view returns (address) {
        return address(this);
    }

    function requestPullFor(address payer, address, ProtocolTypes.PullOrderInput calldata input)
        external
        returns (uint256 orderIndex)
    {
        requestCount++;
        if (!_settlementAsset.transferFrom(payer, address(this), input.maxTotalPrice)) revert();
        orderIndex = 42;
    }
}

contract RouterVaultSafetyNoOpERC721 is ERC721 {
    address public noOpSender;
    address public redirectReceiver;

    constructor() ERC721("No-op Collectible", "NOOP") { }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function setNoOpSender(address sender) external {
        noOpSender = sender;
    }

    function setRedirectReceiver(address receiver) external {
        redirectReceiver = receiver;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {
        if (from == noOpSender && redirectReceiver == address(0)) return;
        if (from == noOpSender) to = redirectReceiver;
        super.safeTransferFrom(from, to, tokenId, data);
    }
}

contract RouterVaultSafetyTest is Test {
    address internal governor = makeAddr("router-vault-governor");
    address internal buyer = makeAddr("router-vault-buyer");
    address internal previousOwner = makeAddr("router-vault-previous-owner");
    address internal receiver = makeAddr("router-vault-receiver");

    MockERC20 internal asset;
    ProtocolRegistry internal registry;
    SwapAndPullRouter internal router;
    RouterVaultSafetyCounterfeitMarket internal counterfeitMarket;

    uint256 internal finalizedPositionId;

    function setUp() external {
        asset = new MockERC20("Settlement", "SET", 18);
        registry = new ProtocolRegistry(governor);
        router = new SwapAndPullRouter(governor, address(asset), address(0), address(registry));
        counterfeitMarket = new RouterVaultSafetyCounterfeitMarket(asset);

        asset.mint(buyer, 100 ether);
        vm.prank(buyer);
        asset.approve(address(router), 100 ether);
    }

    function testRouterRejectsCounterfeitMarketBeforeCollectingTokensOrApprovingIt() external {
        ProtocolTypes.PullOrderInput memory order = _order(60 ether);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndPullRouter.UnregisteredMarket.selector, address(counterfeitMarket))
        );
        router.swapAndPull(address(counterfeitMarket), address(asset), 100 ether, order, "");

        assertEq(asset.balanceOf(buyer), 100 ether);
        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(counterfeitMarket)), 0);
        assertEq(asset.allowance(buyer, address(router)), 100 ether);
        assertEq(asset.allowance(address(router), address(counterfeitMarket)), 0);
        assertEq(counterfeitMarket.requestCount(), 0);
    }

    function testRouterRejectsCounterfeitMarketBeforeWrappingNativeInput() external {
        vm.deal(buyer, 100 ether);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndPullRouter.UnregisteredMarket.selector, address(counterfeitMarket))
        );
        router.swapAndPull{ value: 100 ether }(
            address(counterfeitMarket), address(0), 100 ether, _order(60 ether), ""
        );

        assertEq(buyer.balance, 100 ether);
        assertEq(address(router).balance, 0);
        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(counterfeitMarket.requestCount(), 0);
    }

    function testRouterPreservesRegisteredMarketExactOutputAndRefundPath() external {
        vm.prank(governor);
        registry.registerMarket(address(counterfeitMarket), 1, 1);

        vm.prank(buyer);
        (uint256 orderIndex, uint256 amountIn) =
            router.swapAndPull(address(counterfeitMarket), address(asset), 100 ether, _order(60 ether), "");

        assertEq(orderIndex, 42);
        assertEq(amountIn, 60 ether);
        assertEq(asset.balanceOf(buyer), 40 ether);
        assertEq(asset.balanceOf(address(router)), 0);
        assertEq(asset.balanceOf(address(counterfeitMarket)), 60 ether);
        assertEq(counterfeitMarket.requestCount(), 1);
    }

    function testRouterMeasuresExactOutputInputInsteadOfTrustingAdapterReport() external {
        (MockERC20 input, RouterVaultSafetyAdversarialSwapAdapter adapter, SwapAndPullRouter swapRouter) =
            _swapRouter();
        adapter.configure(40 ether, 60 ether, 99 ether);

        vm.prank(buyer);
        (uint256 orderIndex, uint256 amountIn) = swapRouter.swapAndPull(
            address(counterfeitMarket), address(input), 100 ether, _order(60 ether), ""
        );

        assertEq(orderIndex, 42);
        assertEq(amountIn, 40 ether);
        assertEq(input.balanceOf(buyer), 60 ether);
        assertEq(input.balanceOf(address(adapter)), 40 ether);
        assertEq(input.allowance(address(swapRouter), address(adapter)), 0);
    }

    function testRouterRejectsExactOutputUnderDeliveryWithSpecificBalanceMismatch() external {
        (MockERC20 input, RouterVaultSafetyAdversarialSwapAdapter adapter, SwapAndPullRouter swapRouter) =
            _swapRouter();
        adapter.configure(40 ether, 59 ether, 40 ether);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapAndPullRouter.OutputAmountMismatch.selector, address(asset), 60 ether, 59 ether
            )
        );
        swapRouter.swapAndPull(address(counterfeitMarket), address(input), 100 ether, _order(60 ether), "");

        assertEq(input.balanceOf(buyer), 100 ether);
        assertEq(asset.balanceOf(address(adapter)), 100 ether);
        assertEq(counterfeitMarket.requestCount(), 0);
    }

    function testConvertPayoutRejectsAdapterReportedOutputWhenReceiverIsUnderpaid() external {
        (
            MockERC20 input,
            MockERC20 output,
            RouterVaultSafetyAdversarialSwapAdapter adapter,
            SwapAndPullRouter swapRouter
        ) = _payoutRouter();
        adapter.configure(100 ether, 79 ether, 100 ether);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(SwapAndPullRouter.SlippageExceeded.selector, 79 ether, 80 ether)
        );
        swapRouter.convertPayout(address(input), address(output), 100 ether, 80 ether, receiver, "");

        assertEq(input.balanceOf(buyer), 100 ether);
        assertEq(input.balanceOf(address(adapter)), 0);
        assertEq(output.balanceOf(receiver), 0);
    }

    function testConvertPayoutRejectsPartialExactInputConsumption() external {
        (
            MockERC20 input,
            MockERC20 output,
            RouterVaultSafetyAdversarialSwapAdapter adapter,
            SwapAndPullRouter swapRouter
        ) = _payoutRouter();
        adapter.configure(40 ether, 80 ether, 80 ether);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapAndPullRouter.InputAmountMismatch.selector, address(input), 100 ether, 40 ether
            )
        );
        swapRouter.convertPayout(address(input), address(output), 100 ether, 80 ether, receiver, "");

        assertEq(input.balanceOf(buyer), 100 ether);
        assertEq(input.balanceOf(address(adapter)), 0);
        assertEq(output.balanceOf(receiver), 0);
    }

    function testConvertPayoutClearsAllowanceEvenWhenTokenDoesNotSpendIt() external {
        RouterVaultSafetyStickyAllowanceERC20 input = new RouterVaultSafetyStickyAllowanceERC20();
        MockERC20 output = new MockERC20("Output", "OUT", 18);
        RouterVaultSafetyAdversarialSwapAdapter adapter = new RouterVaultSafetyAdversarialSwapAdapter();
        SwapAndPullRouter swapRouter =
            new SwapAndPullRouter(governor, address(asset), address(adapter), address(registry));
        input.mint(buyer, 100 ether);
        output.mint(address(adapter), 80 ether);
        adapter.configure(100 ether, 80 ether, 80 ether);
        vm.prank(buyer);
        input.approve(address(swapRouter), 100 ether);

        vm.prank(buyer);
        uint256 amountOut =
            swapRouter.convertPayout(address(input), address(output), 100 ether, 80 ether, receiver, "");

        assertEq(amountOut, 80 ether);
        assertEq(output.balanceOf(receiver), 80 ether);
        assertEq(input.allowance(address(swapRouter), address(adapter)), 0);
    }

    function testReleaseNFTRevertsWhenTransferReturnsWithoutMovingOwnership() external {
        (MarketVault vault, RouterVaultSafetyNoOpERC721 collection) = _vaultWithDepositedNFT();
        collection.setNoOpSender(address(vault));

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketVault.NFTDeliveryFailed.selector, address(collection), 1, receiver, address(vault)
            )
        );
        vault.releaseNFT(receiver, address(collection), 1);

        assertEq(collection.ownerOf(1), address(vault));
    }

    function testReleaseSettlementRejectsSenderTaxAndRollsBackTransfer() external {
        MockTaxedERC20 taxedAsset = new MockTaxedERC20("Sender Tax", "STAX", 18);
        MarketVault vault = new MarketVault(address(this), address(taxedAsset));
        taxedAsset.mint(address(vault), 100 ether);
        taxedAsset.setOutboundTax(address(vault), 1_000, true);

        vm.expectRevert(
            abi.encodeWithSelector(MarketVault.UnsupportedTokenBehavior.selector, 10 ether, 11 ether)
        );
        vault.releaseSettlement(receiver, 10 ether);

        assertEq(taxedAsset.balanceOf(address(vault)), 100 ether);
        assertEq(taxedAsset.balanceOf(receiver), 0);
    }

    function testReleaseSettlementRejectsRecipientTaxAndRollsBackTransfer() external {
        MockTaxedERC20 taxedAsset = new MockTaxedERC20("Recipient Tax", "RTAX", 18);
        MarketVault vault = new MarketVault(address(this), address(taxedAsset));
        taxedAsset.mint(address(vault), 100 ether);
        taxedAsset.setOutboundTax(address(vault), 1_000, false);

        vm.expectRevert(
            abi.encodeWithSelector(MarketVault.UnsupportedTokenBehavior.selector, 10 ether, 9 ether)
        );
        vault.releaseSettlement(receiver, 10 ether);

        assertEq(taxedAsset.balanceOf(address(vault)), 100 ether);
        assertEq(taxedAsset.balanceOf(receiver), 0);
    }

    function testTryReleaseNFTRevertsAndRollsBackTransferToWrongReceiver() external {
        (MarketVault vault, RouterVaultSafetyNoOpERC721 collection) = _vaultWithDepositedNFT();
        address attacker = makeAddr("router-vault-nft-attacker");
        collection.setNoOpSender(address(vault));
        collection.setRedirectReceiver(attacker);

        vm.expectRevert(
            abi.encodeWithSelector(
                MarketVault.NFTDeliveryFailed.selector, address(collection), 1, receiver, attacker
            )
        );
        vault.tryReleaseNFT(receiver, address(collection), 1);

        assertEq(collection.ownerOf(1), address(vault));
    }

    function testNoOpNFTDeliveryIsDeferredWithCustodyAndRetryableClaimPreserved() external {
        (MarketVault vault, RouterVaultSafetyNoOpERC721 collection) = _vaultWithDepositedNFT();
        MockRewardController rewards = new MockRewardController();
        SettlementEngine engine = new SettlementEngine(
            address(this),
            1,
            address(asset),
            governor,
            makeAddr("router-vault-treasury"),
            makeAddr("router-vault-insurance"),
            makeAddr("router-vault-buyback"),
            address(vault),
            address(rewards),
            1,
            1_000 ether,
            24 hours,
            9_000,
            9_900
        );
        vault.setOperators(address(engine), makeAddr("router-vault-coordinator"));
        asset.mint(address(vault), 100 ether);
        engine.registerSelection(
            1,
            7,
            buyer,
            buyer,
            address(collection),
            1,
            previousOwner,
            previousOwner,
            100 ether,
            100 ether,
            0,
            0,
            address(0)
        );
        collection.setNoOpSender(address(vault));

        vm.prank(buyer);
        engine.settleKeep(1);

        assertEq(finalizedPositionId, 7);
        assertEq(collection.ownerOf(1), address(vault));
        assertEq(engine.pendingNFTClaims(address(collection), 1), buyer);

        collection.setNoOpSender(address(0));
        vm.prank(buyer);
        engine.claimNFT(address(collection), 1, receiver);

        assertEq(collection.ownerOf(1), receiver);
        assertEq(engine.pendingNFTClaims(address(collection), 1), address(0));
    }

    function finalizeSelectedPosition(uint256 positionId) external {
        finalizedPositionId = positionId;
    }

    function _order(uint128 totalPrice) private view returns (ProtocolTypes.PullOrderInput memory order) {
        order = ProtocolTypes.PullOrderInput({
            receiver: buyer,
            drawCount: 1,
            maxUnitPrice: totalPrice,
            maxTotalPrice: totalPrice,
            deadline: uint48(block.timestamp + 1 hours),
            referralCode: bytes32(0)
        });
    }

    function _vaultWithDepositedNFT()
        private
        returns (MarketVault vault, RouterVaultSafetyNoOpERC721 collection)
    {
        vault = new MarketVault(address(this), address(asset));
        collection = new RouterVaultSafetyNoOpERC721();
        collection.mint(address(this), 1);
        collection.approve(address(vault), 1);
        vault.depositNFT(address(this), address(collection), 1);
        assertEq(collection.ownerOf(1), address(vault));
    }

    function _swapRouter()
        private
        returns (
            MockERC20 input,
            RouterVaultSafetyAdversarialSwapAdapter adapter,
            SwapAndPullRouter swapRouter
        )
    {
        input = new MockERC20("Input", "IN", 18);
        adapter = new RouterVaultSafetyAdversarialSwapAdapter();
        swapRouter = new SwapAndPullRouter(governor, address(input), address(adapter), address(registry));
        vm.prank(governor);
        registry.registerMarket(address(counterfeitMarket), 1, 1);
        input.mint(buyer, 100 ether);
        asset.mint(address(adapter), 100 ether);
        vm.prank(buyer);
        input.approve(address(swapRouter), 100 ether);
    }

    function _payoutRouter()
        private
        returns (
            MockERC20 input,
            MockERC20 output,
            RouterVaultSafetyAdversarialSwapAdapter adapter,
            SwapAndPullRouter swapRouter
        )
    {
        input = new MockERC20("Input", "IN", 18);
        output = new MockERC20("Output", "OUT", 18);
        adapter = new RouterVaultSafetyAdversarialSwapAdapter();
        swapRouter = new SwapAndPullRouter(governor, address(asset), address(adapter), address(registry));
        input.mint(buyer, 100 ether);
        output.mint(address(adapter), 100 ether);
        vm.prank(buyer);
        input.approve(address(swapRouter), 100 ether);
    }
}
