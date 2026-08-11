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
            markupBps: 1_000
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
        assertEq(market.currentPullPrice(), 188_571_430);
        assertTrue(market.solvent());
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
