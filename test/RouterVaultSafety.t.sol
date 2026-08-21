// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { SwapAndPullRouter } from "../contracts/SwapAndPullRouter.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockRewardController } from "./mocks/MockRewardController.sol";

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
            24 hours
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
}
