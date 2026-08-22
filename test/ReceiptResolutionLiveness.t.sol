// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { DrawMarket } from "../contracts/DrawMarket.sol";
import { EpochCoordinator } from "../contracts/EpochCoordinator.sol";
import { MarketVault } from "../contracts/MarketVault.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { SettlementEngine } from "../contracts/SettlementEngine.sol";
import { PositionNFT } from "../contracts/tokens/PositionNFT.sol";
import { PullReceipt } from "../contracts/tokens/PullReceipt.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { MockRandomnessAdapter } from "./mocks/MockRandomnessAdapter.sol";
import { MockRewardController } from "./mocks/MockRewardController.sol";

contract NonReceiptReceiver { }

contract RevertingReceiptReceiver is IERC721Receiver {
    error ReceiptRejected();

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        revert ReceiptRejected();
    }
}

contract ReceiptResolutionLivenessTest is Test {
    MockERC20 internal asset;
    MockERC721 internal collection;
    MockRandomnessAdapter internal randomness;
    DrawMarket internal market;
    SettlementEngine internal engine;
    EpochCoordinator internal coordinator;
    PullReceipt internal receipt;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal treasury = makeAddr("treasury");
    address internal insurance = makeAddr("insurance");
    address internal buyback = makeAddr("buyback");
    address internal depositor = makeAddr("depositor");
    address internal buyer = makeAddr("buyer");

    function setUp() external {
        asset = new MockERC20("Wrapped Ether", "WETH", 18);
        collection = new MockERC721();
        randomness = new MockRandomnessAdapter();
        MockRewardController rewards = new MockRewardController();
        ReferralRegistry referrals = new ReferralRegistry(governor);
        ProtocolRegistry registry = new ProtocolRegistry(governor);
        ProtocolTypes.MarketConfig memory config = ProtocolTypes.MarketConfig({
            marketId: 1,
            collectionSetId: keccak256("ART"),
            settlementAsset: address(asset),
            protocolRegistry: address(registry),
            governor: governor,
            guardian: guardian,
            treasury: treasury,
            insuranceReserve: insurance,
            buybackReceiver: buyback,
            randomnessAdapter: address(randomness),
            eligibilityPolicy: address(0),
            referralRegistry: address(referrals),
            rewardController: address(rewards),
            trustedRouter: address(0),
            minBacking: 1 ether,
            maxBacking: 1_000 ether,
            maxActivePositions: 64,
            maxDrawsPerEpoch: 1,
            collectionWindow: 0,
            randomnessTimeout: 1 hours,
            decisionWindow: 24 hours,
            markupBps: 250,
            cashPayoutBps: 9_000,
            keepPayoutBps: 9_900
        });

        DrawMarket implementation = new DrawMarket();
        address marketAddress = Clones.clone(address(implementation));
        MarketVault vault = new MarketVault(marketAddress, address(asset));
        PositionNFT positionNft = new PositionNFT("Backed Position", "BKPOS", marketAddress);
        engine = new SettlementEngine(
            marketAddress,
            config.marketId,
            config.settlementAsset,
            config.governor,
            config.treasury,
            config.insuranceReserve,
            config.buybackReceiver,
            address(vault),
            config.rewardController,
            config.minBacking,
            config.maxBacking,
            config.decisionWindow,
            config.cashPayoutBps,
            config.keepPayoutBps
        );
        coordinator = new EpochCoordinator(
            config.marketId,
            marketAddress,
            address(vault),
            config.protocolRegistry,
            config.referralRegistry,
            config.randomnessAdapter,
            config.governor,
            config.guardian,
            config.trustedRouter,
            config.maxDrawsPerEpoch,
            config.collectionWindow,
            config.randomnessTimeout
        );
        address[] memory initialCollections = new address[](1);
        initialCollections[0] = address(collection);
        market = DrawMarket(marketAddress);
        market.initialize(
            config,
            address(vault),
            address(positionNft),
            address(engine),
            address(coordinator),
            initialCollections
        );
        bytes32 marketRole = referrals.MARKET_ROLE();
        vm.prank(governor);
        referrals.grantRole(marketRole, address(coordinator));
        receipt = engine.pullReceipt();

        collection.mint(depositor, 1);
        asset.mint(depositor, 100 ether);
        vm.startPrank(depositor);
        collection.approve(address(vault), 1);
        asset.approve(address(vault), 100 ether);
        market.depositPosition(address(collection), 1, 100 ether, depositor);
        vm.stopPrank();

        asset.mint(buyer, 1_000 ether);
        vm.prank(buyer);
        asset.approve(address(vault), type(uint256).max);
    }

    function testNonReceiverContractCannotBlockResolutionOrFinalization() external {
        _resolveOne(address(new NonReceiptReceiver()));
    }

    function testRevertingReceiverCannotBlockResolutionOrFinalization() external {
        _resolveOne(address(new RevertingReceiptReceiver()));
    }

    function _resolveOne(address receiver) private {
        uint128 price = uint128(market.currentPullPrice());
        ProtocolTypes.PullOrderInput memory input = ProtocolTypes.PullOrderInput({
            receiver: receiver,
            drawCount: 1,
            maxUnitPrice: price,
            maxTotalPrice: price,
            deadline: uint48(block.timestamp + 1 hours),
            referralCode: bytes32(0)
        });
        vm.prank(buyer);
        coordinator.requestPull(input);
        coordinator.requestRandomness();
        randomness.setSeed(7);
        coordinator.provideRandomness("");

        coordinator.resolveEpoch(1);

        (uint256 epochId, ProtocolTypes.EpochStatus status,,,,, uint32 totalResolved,,,,,,) =
            coordinator.epoch();
        assertEq(epochId, 1);
        assertEq(uint8(status), uint8(ProtocolTypes.EpochStatus.Finalized));
        assertEq(totalResolved, 1);
        assertFalse(market.epochLocked());
        assertEq(receipt.ownerOf(1), receiver);
        assertTrue(receipt.isFrozen(1));

        ProtocolTypes.PullReceiptData memory data = receipt.receiptData(1);
        assertEq(data.marketId, 1);
        assertEq(data.epochId, 1);
        assertEq(data.positionId, 1);
        assertEq(data.originalBuyer, buyer);
        assertEq(data.receiver, receiver);
        assertEq(data.chargedPrice, price);
        assertEq(data.selectedBacking, 100 ether);
        assertEq(data.revealedAt, block.timestamp);
        assertEq(data.decisionDeadline, block.timestamp + 24 hours);
        assertEq(uint8(data.status), uint8(ProtocolTypes.PullStatus.Revealed));
    }
}
