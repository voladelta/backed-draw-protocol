// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { DrawMarket } from "../contracts/DrawMarket.sol";
import { MarketFactory } from "../contracts/MarketFactory.sol";
import { ProtocolRegistry } from "../contracts/ProtocolRegistry.sol";
import { ReferralRegistry } from "../contracts/ReferralRegistry.sol";
import { RewardController } from "../contracts/RewardController.sol";
import { VaultDeployer } from "../contracts/deployers/VaultDeployer.sol";
import { PositionTokenDeployer } from "../contracts/deployers/PositionTokenDeployer.sol";
import { SettlementEngineDeployer } from "../contracts/deployers/SettlementEngineDeployer.sol";
import { EpochCoordinatorDeployer } from "../contracts/deployers/EpochCoordinatorDeployer.sol";
import { ProtocolTypes } from "../contracts/types/ProtocolTypes.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { MockRandomnessAdapter } from "./mocks/MockRandomnessAdapter.sol";

contract MarketFactoryTest is Test {
    address internal governor = makeAddr("governor");

    function testDeploysFixedVersionIsolatedMarket() external {
        MockERC20 asset = new MockERC20("USDG", "USDG", 6);
        MockERC20 drawToken = new MockERC20("Draw", "DRAW", 18);
        MockERC721 collection = new MockERC721();
        MockRandomnessAdapter randomness = new MockRandomnessAdapter();
        ProtocolRegistry registry = new ProtocolRegistry(governor);
        ReferralRegistry referrals = new ReferralRegistry(governor);
        RewardController rewards = new RewardController(governor, address(drawToken), address(0));
        DrawMarket implementation = new DrawMarket();
        MarketFactory factory = new MarketFactory(
            address(registry),
            address(implementation),
            address(new VaultDeployer()),
            address(new PositionTokenDeployer()),
            address(new SettlementEngineDeployer()),
            address(new EpochCoordinatorDeployer())
        );

        vm.startPrank(governor);
        registry.setSettlementAsset(address(asset), true);
        registry.setRandomnessAdapter(address(randomness), true);
        registry.setReferralRegistry(address(referrals), true);
        registry.setRewardController(address(rewards), true);
        registry.setImplementation(1, address(implementation).codehash);
        registry.grantRole(registry.REGISTRY_MANAGER_ROLE(), address(factory));
        referrals.grantRole(referrals.FACTORY_ROLE(), address(factory));
        rewards.grantRole(rewards.FACTORY_ROLE(), address(factory));

        ProtocolTypes.MarketConfig memory config = ProtocolTypes.MarketConfig({
            marketId: 0,
            collectionSetId: keccak256("TCG_USDG"),
            settlementAsset: address(asset),
            protocolRegistry: address(0),
            governor: governor,
            guardian: governor,
            treasury: makeAddr("treasury"),
            insuranceReserve: makeAddr("insurance"),
            buybackReceiver: makeAddr("buyback"),
            randomnessAdapter: address(randomness),
            eligibilityPolicy: address(0),
            referralRegistry: address(referrals),
            rewardController: address(rewards),
            trustedRouter: address(0),
            minBacking: 10e6,
            maxBacking: 1_000_000e6,
            maxActivePositions: 1_024,
            maxDrawsPerEpoch: 64,
            collectionWindow: 30,
            randomnessTimeout: 1 hours,
            decisionWindow: 24 hours,
            markupBps: 250,
            cashPayoutBps: 9_000,
            keepPayoutBps: 9_900
        });
        address[] memory collections = new address[](1);
        collections[0] = address(collection);
        address marketAddress = factory.createMarket(config, collections);
        vm.stopPrank();

        DrawMarket market = DrawMarket(marketAddress);
        assertTrue(registry.isMarket(marketAddress));
        assertEq(factory.marketForId(1), marketAddress);
        assertEq(market.marketId(), 1);
        assertEq(market.settlementDecimals(), 6);
        assertEq(market.normalizationFactor(), 1e12);
        assertTrue(market.collectionEnabled(address(collection)));
        assertEq(market.vault().market(), marketAddress);
        assertEq(market.vault().settlementEngine(), address(market.settlementEngine()));
        assertEq(market.vault().epochCoordinator(), address(market.epochCoordinator()));
        assertTrue(rewards.hasRole(rewards.MARKET_ROLE(), address(market)));
        assertTrue(rewards.hasRole(rewards.MARKET_ROLE(), address(market.settlementEngine())));
        assertTrue(referrals.hasRole(referrals.MARKET_ROLE(), address(market.epochCoordinator())));

        _depositUsdPosition(market, asset, collection, makeAddr("alice"), 1, 100e6);
        _depositUsdPosition(market, asset, collection, makeAddr("bob"), 2, 200e6);
        _depositUsdPosition(market, asset, collection, makeAddr("carol"), 3, 400e6);
        assertApproxEqAbs(market.currentExpectedValue(), 171_428_572, 1);
        assertEq(market.currentPullPrice(), 175_714_287);
        assertEq(market.settlementEngine().cashPayoutBps(), 9_000);
        assertEq(market.settlementEngine().keepPayoutBps(), 9_900);
        assertTrue(market.solvent());
    }

    function testRejectsInvalidEconomicPoliciesAtCreation() external {
        (MarketFactory factory, ProtocolTypes.MarketConfig memory config, address[] memory collections) =
            _factoryFixture();

        vm.startPrank(governor);
        _expectInvalidEconomicPolicy(factory, config, collections, 5_001, 9_000, 9_900);
        _expectInvalidEconomicPolicy(factory, config, collections, 250, 7_999, 9_900);
        _expectInvalidEconomicPolicy(factory, config, collections, 250, 9_501, 9_900);
        _expectInvalidEconomicPolicy(factory, config, collections, 250, 9_000, 9_499);
        _expectInvalidEconomicPolicy(factory, config, collections, 250, 9_000, 10_001);
        _expectInvalidEconomicPolicy(factory, config, collections, 250, 9_501, 9_500);
        vm.stopPrank();

        assertEq(factory.nextMarketId(), 1);
    }

    function testAcceptsInclusiveEconomicPolicyBoundaries() external {
        (MarketFactory factory, ProtocolTypes.MarketConfig memory config, address[] memory collections) =
            _factoryFixture();

        vm.startPrank(governor);
        config.markupBps = 5_000;
        config.cashPayoutBps = 8_000;
        config.keepPayoutBps = 9_500;
        DrawMarket lowerBoundary = DrawMarket(factory.createMarket(config, collections));

        config.cashPayoutBps = 9_500;
        config.keepPayoutBps = 10_000;
        DrawMarket upperBoundary = DrawMarket(factory.createMarket(config, collections));
        vm.stopPrank();

        assertEq(lowerBoundary.settlementEngine().cashPayoutBps(), 8_000);
        assertEq(lowerBoundary.settlementEngine().keepPayoutBps(), 9_500);
        assertEq(upperBoundary.settlementEngine().cashPayoutBps(), 9_500);
        assertEq(upperBoundary.settlementEngine().keepPayoutBps(), 10_000);
    }

    function _factoryFixture()
        private
        returns (
            MarketFactory factory,
            ProtocolTypes.MarketConfig memory config,
            address[] memory collections
        )
    {
        MockERC20 asset = new MockERC20("USDG", "USDG", 6);
        MockERC20 drawToken = new MockERC20("Draw", "DRAW", 18);
        MockERC721 collection = new MockERC721();
        MockRandomnessAdapter randomness = new MockRandomnessAdapter();
        ProtocolRegistry registry = new ProtocolRegistry(governor);
        ReferralRegistry referrals = new ReferralRegistry(governor);
        RewardController rewards = new RewardController(governor, address(drawToken), address(0));
        DrawMarket implementation = new DrawMarket();
        factory = new MarketFactory(
            address(registry),
            address(implementation),
            address(new VaultDeployer()),
            address(new PositionTokenDeployer()),
            address(new SettlementEngineDeployer()),
            address(new EpochCoordinatorDeployer())
        );

        vm.startPrank(governor);
        registry.setSettlementAsset(address(asset), true);
        registry.setRandomnessAdapter(address(randomness), true);
        registry.setReferralRegistry(address(referrals), true);
        registry.setRewardController(address(rewards), true);
        registry.setImplementation(1, address(implementation).codehash);
        registry.grantRole(registry.REGISTRY_MANAGER_ROLE(), address(factory));
        referrals.grantRole(referrals.FACTORY_ROLE(), address(factory));
        rewards.grantRole(rewards.FACTORY_ROLE(), address(factory));
        vm.stopPrank();

        config = ProtocolTypes.MarketConfig({
            marketId: 0,
            collectionSetId: keccak256("ECONOMIC_POLICY"),
            settlementAsset: address(asset),
            protocolRegistry: address(0),
            governor: governor,
            guardian: governor,
            treasury: makeAddr("policy-treasury"),
            insuranceReserve: makeAddr("policy-insurance"),
            buybackReceiver: makeAddr("policy-buyback"),
            randomnessAdapter: address(randomness),
            eligibilityPolicy: address(0),
            referralRegistry: address(referrals),
            rewardController: address(rewards),
            trustedRouter: address(0),
            minBacking: 10e6,
            maxBacking: 1_000_000e6,
            maxActivePositions: 1_024,
            maxDrawsPerEpoch: 64,
            collectionWindow: 30,
            randomnessTimeout: 1 hours,
            decisionWindow: 24 hours,
            markupBps: 250,
            cashPayoutBps: 9_000,
            keepPayoutBps: 9_900
        });
        collections = new address[](1);
        collections[0] = address(collection);
    }

    function _expectInvalidEconomicPolicy(
        MarketFactory factory,
        ProtocolTypes.MarketConfig memory config,
        address[] memory collections,
        uint16 markupBps,
        uint16 cashPayoutBps,
        uint16 keepPayoutBps
    ) private {
        config.markupBps = markupBps;
        config.cashPayoutBps = cashPayoutBps;
        config.keepPayoutBps = keepPayoutBps;
        vm.expectRevert(MarketFactory.InvalidEconomicPolicy.selector);
        factory.createMarket(config, collections);
    }

    function _depositUsdPosition(
        DrawMarket market,
        MockERC20 asset,
        MockERC721 collection,
        address owner,
        uint256 tokenId,
        uint128 backing
    ) private {
        collection.mint(owner, tokenId);
        asset.mint(owner, backing);
        vm.startPrank(owner);
        collection.approve(address(market.vault()), tokenId);
        asset.approve(address(market.vault()), backing);
        market.depositPosition(address(collection), tokenId, backing, owner);
        vm.stopPrank();
    }
}
