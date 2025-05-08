// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";

import {MeritManager as MM} from "../src/MeritManager.sol";
import {TotemFactory as TF} from "../src/TotemFactory.sol";
import {TotemTokenDistributor as TTD} from "../src/TotemTokenDistributor.sol";
import {TotemToken as TT} from "../src/TotemToken.sol";
import {Totem} from "../src/Totem.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {Treasury} from "../src/Treasury.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {Layers as L} from "../src/Layers.sol";
import {Shards} from "../src/Shards.sol";

import {MockToken} from "./mocks/MockToken.sol";

import {IUniswapV2Factory} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "lib/solmate/src/tokens/WETH.sol";

import {Deployer} from "test/util/Deployer.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LayersTest is Test {
    UpgradeableBeacon beacon;

    TransparentUpgradeableProxy factoryProxy;
    TF factoryImpl;
    TF factory;

    TransparentUpgradeableProxy mmProxy;
    MM mmImpl;
    MM mm;

    TransparentUpgradeableProxy distrProxy;
    TTD distrImpl;
    TTD distr;

    TransparentUpgradeableProxy treasuryProxy;
    Treasury treasuryImpl;
    Treasury treasury;

    TransparentUpgradeableProxy registryProxy;
    AddressRegistry registryImpl;
    AddressRegistry registry;

    TransparentUpgradeableProxy mythoProxy;
    MYTHO mythoImpl;
    MYTHO mytho;
    MockToken paymentToken;
    MockToken astrToken;

    TransparentUpgradeableProxy layerProxy;
    L layersImpl;
    L layers;

    TransparentUpgradeableProxy shardProxy;
    Shards shardsImpl;
    Shards shards;

    // uni
    IUniswapV2Factory uniFactory;
    IUniswapV2Pair pair;
    IUniswapV2Router02 router;
    WETH weth;

    address deployer;
    address userA;
    address userB;
    address userC;
    address userD;

    function setUp() public {
        deployer = makeAddr("deployer");
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");
        userD = makeAddr("userD");

        prank(deployer);
        _deploy();
    }

    function test_Free() public {
        uint256 totemId = createTotem(userA);

        TF.TotemData memory data = factory.getTotemData(totemId);
        assertEq(data.creator, userA);
        assertTrue(data.totemAddr != address(0));
        assertFalse(uint8(data.tokenType) != uint8(TF.TokenType.STANDARD));

        // Buy totem tokens by userB
        prank(userB);
        astrToken.approve(address(distr), 250_000 ether);
        distr.buy(data.totemTokenAddr, 5_000_000 ether);

        buyAllTotemTokens(data.totemTokenAddr);

        TT token = TT(data.totemTokenAddr);
        assertEq(token.balanceOf(userB), 5_000_000 ether);
        assertEq(token.balanceOf(userA), 250_000 ether);
        assertEq(token.balanceOf(address(distr)), 0);
        assertEq(token.balanceOf(data.totemAddr), 100_000_000 ether);
        assertTrue(mm.isRegisteredTotem(data.totemAddr));
        assertFalse(mm.isBlacklisted(data.totemAddr));

        // check who is owner
        assertTrue(Totem(data.totemAddr).getOwner() == userA);
        assertFalse(Totem(data.totemAddr).getOwner() == userB);

        // now userA has 250_000 totem tokens
        // now userB has 5_000_000 totem tokens

        assertEq(layers.layerCounter(), 1);
        assertEq(layers.pendingLayerCounter(), 1);

        uint256 layerId = createLayer(userA, totemId);
        
        // check royalty info
        (address royaltyReceiver, uint256 royaltyAmount) = layers.royaltyInfo(layerId, 100_000 ether);
        assertEq(royaltyReceiver, userA);
        assertEq(royaltyAmount, 100_000 ether * 1000 / 10000); // 10% of 100_000 ether = 10_000 ether

        // check layer info
        L.Layer memory layer = layers.getLayer(layerId);
        assertEq(layer.creator, userA);
        assertEq(layer.totemAddr, data.totemAddr);
        assertEq(layer.createdAt, uint32(block.timestamp));
        assertEq(layer.totalBoostedTokens, 0);

        // Test boosting layer
        // Approve totem tokens for boosting
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 1_000_000 ether);
        layers.boostLayer(layerId, 1_000_000 ether);

        // Check boost was recorded correctly
        assertEq(layers.getBoostAmount(layerId, userB), 1_000_000 ether);

        // totalBoostedTokens should be 0 while boost window is active
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 0);

        // Try boosting with userC who has no tokens - should revert
        prank(userC);
        TT(data.totemTokenAddr).approve(address(layers), 2_000_000 ether);
        vm.expectRevert(L.InsufficientBalance.selector);
        layers.boostLayer(layerId, 2_000_000 ether);

        // Verify no changes occurred after failed boost
        assertEq(layers.getBoostAmount(layerId, userB), 1_000_000 ether);
        assertEq(layers.getBoostAmount(layerId, userC), 0);
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 0); // Still 0 as boost window is active

        // Test that userB can boost more tokens
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 2_000_000 ether);
        layers.boostLayer(layerId, 2_000_000 ether);
        assertEq(layers.getBoostAmount(layerId, userB), 3_000_000 ether);
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 0); // Still 0 as boost window is active

        // Warp time to after boost window
        warp(25 hours); // Boost window is 24 hours

        // Now check totalBoostedTokens after boost window
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 3_000_000 ether);

        uint256 pendingLayerId = createLayer(userB, totemId);
        assertEq(pendingLayerId, 1);

        // check pending layer info
        L.Layer memory pendingLayer = layers.getPendingLayer(pendingLayerId);
        assertEq(pendingLayer.creator, userB);
        assertEq(pendingLayer.totemAddr, data.totemAddr);
        assertEq(pendingLayer.createdAt, uint32(block.timestamp));
        assertEq(pendingLayer.totalBoostedTokens, 0);
        assertEq(layers.userPendingLayer(userB), 1);

        assertEq(layers.layerCounter(), 2);
        assertEq(layers.pendingLayerCounter(), 2);

        // verify layer by creator
        prank(userA);
        uint256 newLayerId = layers.verifyLayer(1, true);
        assertEq(layers.layerCounter(), 3);
        assertEq(newLayerId, 2);
        assertEq(layers.userPendingLayer(userB), 0);

        layer = layers.getLayer(2);
        assertEq(layer.creator, userB);
        assertEq(layer.totemAddr, data.totemAddr);
        assertEq(layers.ownerOf(newLayerId), userB);
        assertEq(layers.userPendingLayer(userB), 0); // Pending layer cleared

        // Verify royalty settings
        (address receiver, uint256 amount) = layers.royaltyInfo(newLayerId, 100 ether);
        assertEq(receiver, userB);
        assertEq(amount, 10 ether); // 10% of 100 ether
    }

    function test_LayerCreation() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);

        // Test auto-approved layer creation (userA has enough tokens)
        uint256 layerId = createLayer(userA, totemId);
        L.Layer memory layer = layers.getLayer(layerId);
        assertEq(layer.creator, userA);
        assertEq(layer.totemAddr, data.totemAddr);
        assertEq(layer.createdAt, uint32(block.timestamp));
        assertEq(layer.totalBoostedTokens, 0);
        assertEq(layers.ownerOf(layerId), userA);

        // Test pending layer creation (userD has no tokens)
        prank(userD);
        vm.expectRevert(L.NotEnoughTotemTokens.selector);
        layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));

        // Test invalid totem
        prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(TF.TotemNotFound.selector, 0)
        );
        layers.createLayer(address(999), abi.encodePacked(keccak256("Test")));
    }

    function test_LayerVerification() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);

        // Give userB some totem tokens to meet minimum balance requirement
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 250_000 ether);

        // Create pending layer - it will be pending since userB is not owner or collaborator
        uint256 pendingLayerId = createLayer(userB, totemId);
        
        // Verify layer info
        L.Layer memory pendingLayer = layers.getPendingLayer(pendingLayerId);
        assertEq(pendingLayer.creator, userB);
        assertEq(pendingLayer.totemAddr, data.totemAddr);
        assertEq(pendingLayer.createdAt, uint32(block.timestamp));
        assertEq(pendingLayer.totalBoostedTokens, 0);
        assertEq(layers.userPendingLayer(userB), pendingLayerId);

        // Test verification by non-owner/collaborator
        prank(userC);
        vm.expectRevert(L.NotAuthorized.selector);
        layers.verifyLayer(pendingLayerId, true);

        // Test verification by owner when totem is not registered in Merit Manager
        assertFalse(mm.isRegisteredTotem(data.totemAddr), "Totem should not be registered yet");
        prank(userA);
        uint256 newLayerId = layers.verifyLayer(pendingLayerId, true);

        // Check layer was created properly
        L.Layer memory layer = layers.getLayer(newLayerId);
        assertEq(layer.creator, userB);
        assertEq(layer.totemAddr, data.totemAddr);
        assertEq(layers.ownerOf(newLayerId), userB);
        assertEq(layers.userPendingLayer(userB), 0); // Pending layer cleared

        // Verify royalty settings
        (address receiver, uint256 amount) = layers.royaltyInfo(newLayerId, 100 ether);
        assertEq(receiver, userB);
        assertEq(amount, 10 ether); // 10% of 100 ether

        // Complete token sale to register totem in Merit Manager
        buyAllTotemTokens(data.totemTokenAddr);
        assertTrue(mm.isRegisteredTotem(data.totemAddr), "Totem should be registered after token sale");

        // Create and verify another layer - this time Merit Manager reward should be given
        uint256 pendingLayerId2 = createLayer(userB, totemId);
        prank(userA);
        uint256 newLayerId2 = layers.verifyLayer(pendingLayerId2, true);
        assertEq(layers.ownerOf(newLayerId2), userB);

        // Test rejecting a layer
        uint256 pendingLayerId3 = createLayer(userB, totemId);
        prank(userA);
        layers.verifyLayer(pendingLayerId3, false);
        assertEq(layers.userPendingLayer(userB), 0);
    }

    function test_LayerBoosting() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Buy enough totem tokens for boosting
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        // Create layer as owner so it's auto-approved
        uint256 layerId = createLayer(userA, totemId);
        
        // Test boosting with insufficient balance
        prank(userC);
        vm.expectRevert(L.InsufficientBalance.selector);
        layers.boostLayer(layerId, 1_000_000 ether);
        
        // Test boosting non-existent layer
        prank(userB);
        vm.expectRevert(L.LayerNotFound.selector);
        layers.boostLayer(999, 1_000_000 ether);
        
        // Test successful boost
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 1_000_000 ether);
        layers.boostLayer(layerId, 1_000_000 ether);
        
        // Verify boost data
        assertEq(layers.getBoostAmount(layerId, userB), 1_000_000 ether);
        L.Layer memory layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 0); // Should be 0 during boost window
        
        // Test additional boost from same user
        prank(userB);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        layers.boostLayer(layerId, 500_000 ether);
        assertEq(layers.getBoostAmount(layerId, userB), 1_500_000 ether);
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 0); // Should be 0 during boost window
        
        // Test boosting after window ends
        warp(25 hours);
        prank(userB);
        vm.expectRevert(L.BoostWindowClosed.selector);
        layers.boostLayer(layerId, 1_000_000 ether);
        
        // Verify total boosted tokens after window
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 1_500_000 ether); // Now should show actual value
    }

    function test_LayerUnboosting() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Buy enough totem tokens for boosting
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        // Create layer and boost it
        uint256 layerId = createLayer(userA, totemId);
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 1_000_000 ether);
        layers.boostLayer(layerId, 1_000_000 ether);
        assertEq(layers.getBoostAmount(layerId, userB), 1_000_000 ether);
        
        // Test unboosting before boost window ends
        prank(userB);
        vm.expectRevert(L.BoostLocked.selector);
        layers.unboostLayer(layerId);
        
        // Test unboosting after boost window
        warp(25 hours);
        uint256 initialBoosterBalance = shards.balanceOf(userB);
        uint256 initialCreatorBalance = shards.balanceOf(userA);
        
        prank(userB);
        layers.unboostLayer(layerId);
        
        // Verify unboost results
        assertEq(layers.getBoostAmount(layerId, userB), 0);
        uint256 boosterShards = shards.balanceOf(userB) - initialBoosterBalance;
        uint256 creatorShards = shards.balanceOf(userA) - initialCreatorBalance;
        
        assertGt(boosterShards, 0); // Booster received shards
        assertGt(creatorShards, 0); // Creator received shards
        assertApproxEqRel(creatorShards * 9, boosterShards, 1.5e17);
        
        L.Layer memory layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 1_000_000 ether);
        
        // Test unboosting again
        prank(userB);
        vm.expectRevert(L.BoostNotFound.selector);
        layers.unboostLayer(layerId);
        
        // Test unboosting non-existent layer
        prank(userB);
        vm.expectRevert(L.LayerNotFound.selector);
        layers.unboostLayer(999);
    }

    function test_LayerDonations() public {
        uint256 totemId = createTotem(userA);
        uint256 layerId = createLayer(userA, totemId);

        // Test donation below minimum fee
        vm.deal(userB, 1000 ether);
        prank(userB);
        vm.expectRevert(L.FeeTooLow.selector);
        layers.donateToLayer{value: 0.0009 ether}(layerId);

        // Test successful donation
        uint256 donationAmount = 1 ether;
        uint256 expectedFee = (donationAmount * layers.donationFeePercentage()) / 10000;
        uint256 initialBalance = address(userA).balance;

        prank(userB);
        layers.donateToLayer{value: donationAmount}(layerId);

        // Verify donation was processed correctly
        assertEq(address(userA).balance, initialBalance + donationAmount - expectedFee);
        assertEq(layers.totalDonations(layerId), donationAmount);

        // Test donation to non-existent layer
        prank(userB);
        vm.expectRevert(L.LayerNotFound.selector);
        layers.donateToLayer{value: 1 ether}(999);
    }

    function test_AdminFunctions() public {
        // Test setting base shard reward
        prank(deployer);
        layers.setBaseShardReward(1000);
        assertEq(layers.baseShardReward(), 1000);

        // Test setting minimum author shard reward
        prank(deployer);
        layers.setMinAuthorShardReward(100);
        assertEq(layers.minAuthorShardReward(), 100);

        // Test setting author shard percentage
        prank(deployer);
        layers.setAuthorShardPercentage(2000); // 20%
        assertEq(layers.authorShardPercentage(), 2000);

        // Test setting royalty percentage
        prank(deployer);
        layers.setRoyaltyPercentage(500); // 5%
        assertEq(layers.royaltyPercentage(), 500);

        // Test setting boost window
        prank(deployer);
        layers.setBoostWindow(48 hours);
        assertEq(layers.boostWindow(), 48 hours);

        // Test setting minimum totem token balance
        prank(deployer);
        layers.setMinTotemTokenBalance(300_000 ether);
        assertEq(layers.minTotemTokenBalance(), 300_000 ether);

        // Test setting donation fee percentage
        prank(deployer);
        vm.expectRevert(L.InvalidFeePercentage.selector);
        layers.setDonationFee(10001); // Over 100%

        layers.setDonationFee(500); // 5%
        assertEq(layers.donationFeePercentage(), 500);

        // Test setting minimum donation fee
        prank(deployer);
        layers.setMinDonationFee(0.005 ether);
        assertEq(layers.minDonationFee(), 0.005 ether);

        // Test unauthorized access
        prank(userA);
        vm.expectRevert();
        layers.setBaseShardReward(2000);
    }

    function test_PauseAndUnpause() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);

        // Test pausing by non-manager
        prank(userA);
        vm.expectRevert();
        layers.pause();

        // Test pausing by manager
        prank(deployer);
        layers.pause();

        // Test operations while paused
        prank(userA);
        vm.expectRevert();
        layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));

        // Test unpausing by manager
        prank(deployer);
        layers.unpause();

        // Verify operations work after unpause
        prank(userA);
        uint256 layerId = createLayer(userA, totemId);
        assertEq(layers.ownerOf(layerId), userA);
    }

    function test_MinimumTotemTokenBalance() public {
        // Create a totem
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Complete token sale first
        buyAllTotemTokens(data.totemTokenAddr);
        
        // Check minimum token requirement
        uint256 minRequired = layers.minTotemTokenBalance();
        
        // Verify userA has enough tokens (creator automatically gets tokens)
        assertGe(TT(data.totemTokenAddr).balanceOf(userA), minRequired);
        
        // Give userB less than minimum tokens
        prank(userA);
        TT(data.totemTokenAddr).transfer(userB, minRequired / 2);
        
        // Verify userB has less than minimum
        assertLt(TT(data.totemTokenAddr).balanceOf(userB), minRequired);
        
        // Attempt to create layer with insufficient tokens should fail
        prank(userB);
        vm.expectRevert(L.NotEnoughTotemTokens.selector);
        layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Give userB enough tokens
        prank(userA);
        TT(data.totemTokenAddr).transfer(userB, minRequired);
        
        // Verify userB now has enough tokens
        assertGe(TT(data.totemTokenAddr).balanceOf(userB), minRequired);
        
        // Should now be able to create layer
        prank(userB);
        uint256 layerId = layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Verify layer was created
        assertEq(layers.userPendingLayer(userB), layerId);
    }

    function test_MeritManagerRewards() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Complete token sale to register totem in Merit Manager
        buyAllTotemTokens(data.totemTokenAddr);
        
        // Verify totem is registered in Merit Manager
        assertTrue(mm.isRegisteredTotem(data.totemAddr));
        
        // Create layer and verify it's successful
        prank(userA);
        uint256 layerId = layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        assertEq(layers.ownerOf(layerId), userA);
        
        // Test donation reward
        vm.deal(userB, 5 ether);
        prank(userB);
        uint256 initialBalance = address(userA).balance;
        layers.donateToLayer{value: 1 ether}(layerId);
        
        // Verify donation was processed
        uint256 expectedFee = (1 ether * layers.donationFeePercentage()) / 10000;
        assertEq(address(userA).balance, initialBalance + 1 ether - expectedFee);
        assertEq(layers.totalDonations(layerId), 1 ether);
    }
    
    function test_NoMeritManagerRewardsForUnregisteredTotem() public {
        // Create totem but don't complete token sale (not registered in Merit Manager)
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Verify totem is NOT registered in Merit Manager
        assertFalse(mm.isRegisteredTotem(data.totemAddr));
        
        // Create layer and verify it's successful even without Merit Manager registration
        prank(userA);
        uint256 layerId = layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        assertEq(layers.ownerOf(layerId), userA);
        
        // Test donation still works for unregistered totems
        vm.deal(userB, 5 ether);
        prank(userB);
        uint256 initialBalance = address(userA).balance;
        layers.donateToLayer{value: 1 ether}(layerId);
        
        // Verify donation was processed
        uint256 expectedFee = (1 ether * layers.donationFeePercentage()) / 10000;
        assertEq(address(userA).balance, initialBalance + 1 ether - expectedFee);
        assertEq(layers.totalDonations(layerId), 1 ether);
    }
    
    function test_MetadataHashFunctionality() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        bytes memory metadataHash = abi.encodePacked(keccak256("Custom Metadata"));
        
        // Create layer with custom metadata
        prank(userA);
        uint256 layerId = layers.createLayer(data.totemAddr, metadataHash);
        
        // Verify metadata hash is stored correctly
        bytes memory storedHash = layers.getMetadataHash(layerId);
        assertEq(keccak256(storedHash), keccak256(metadataHash));
        
        // Test getting metadata for non-existent layer
        prank(userA);
        vm.expectRevert(L.LayerNotFound.selector);
        layers.getMetadataHash(999);
    }
    
    function test_MeritManagerLayerRewards() public {
        // Create a totem
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Complete token sale to register totem in Merit Manager
        buyAllTotemTokens(data.totemTokenAddr);
        
        // Verify totem is registered in Merit Manager
        assertTrue(mm.isRegisteredTotem(data.totemAddr));
        
        // Create layer and verify it's successful
        prank(userA);
        uint256 layerId = layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        assertEq(layers.ownerOf(layerId), userA);
        
        // Verify the layer exists
        L.Layer memory layer = layers.getLayer(layerId);
        assertEq(layer.creator, userA);
        assertEq(layer.totemAddr, data.totemAddr);
    }
    
    function test_CreatorRewardOnlyOncePerLayer() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Create layer
        uint256 layerId = createLayer(userA, totemId);
        
        // Multiple users boost the layer
        // UserB boosts
        prank(userB);
        astrToken.approve(address(distr), 500_000 ether);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        layers.boostLayer(layerId, 500_000 ether);
        
        // UserC boosts
        prank(userC);
        astrToken.approve(address(distr), 500_000 ether);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        layers.boostLayer(layerId, 500_000 ether);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // First unboost should trigger creator reward
        uint256 initialCreatorShards = shards.balanceOf(userA);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 creatorRewardAmount = shards.balanceOf(userA) - initialCreatorShards;
        assertGt(creatorRewardAmount, 0);
        
        // Second unboost should not give additional creator reward
        initialCreatorShards = shards.balanceOf(userA);
        prank(userC);
        layers.unboostLayer(layerId);
        assertEq(shards.balanceOf(userA), initialCreatorShards);
    }
    
    function test_BoostingAfterWindowEnds() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Create layer
        uint256 layerId = createLayer(userA, totemId);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Try to boost after window ends
        prank(userB);
        astrToken.approve(address(distr), 500_000 ether);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        
        // Should NOT be able to boost after window (expect revert)
        vm.expectRevert(L.BoostWindowClosed.selector);
        layers.boostLayer(layerId, 500_000 ether);
    }
    
    function test_EcosystemPause() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Pause the ecosystem
        prank(deployer);
        registry.setEcosystemPaused(true);
        
        // Try to create layer while ecosystem is paused
        prank(userA);
        vm.expectRevert(L.EcosystemPaused.selector);
        layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Unpause the ecosystem
        prank(deployer);
        registry.setEcosystemPaused(false);
        
        // Should be able to create layer now
        prank(userA);
        uint256 layerId = layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        assertEq(layers.ownerOf(layerId), userA);
    }

    // HELPERS

    function createLayer(
        address _creator,
        uint256 _totemId
    ) internal returns (uint256) {
        TF.TotemData memory data = factory.getTotemData(_totemId);
        prank(_creator);
        return
            layers.createLayer(
                data.totemAddr,
                abi.encodePacked(keccak256("Test"))
            );
    }

    function createTotem(address _creator) internal returns (uint256) {
        prank(_creator);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotem(
            abi.encodePacked(keccak256("Test")),
            "Test Totem",
            "TST",
            new address[](0)
        );

        return factory.getLastId() - 1;
    }

    function buyAllTotemTokens(address _totemTokenAddr) internal {
        uint256 counter = type(uint32).max;
        do {
            address user = vm.addr(
                uint256(keccak256(abi.encodePacked(counter++)))
            );
            if (user == address(distr)) continue;
            vm.deal(user, 1 ether);
            paymentToken.mint(user, 2_500_000 ether);

            prank(user);
            uint256 available = distr.getAvailableTokensForPurchase(
                user,
                _totemTokenAddr
            );
            paymentToken.approve(address(distr), available);

            distr.buy(_totemTokenAddr, available);
        } while (IERC20(_totemTokenAddr).balanceOf(address(distr)) > 0);
    }

    // Deploy all contracts
    function _deploy() internal {
        // Uni V2 deploying
        uniFactory = Deployer.deployFactory(deployer);
        // pair = IUniswapV2Pair(uniFactory.createPair(address(tokenA), address(tokenB)));
        weth = Deployer.deployWETH();
        router = Deployer.deployRouterV2(address(uniFactory), address(weth));

        treasuryImpl = new Treasury();
        treasuryProxy = new TransparentUpgradeableProxy(
            address(treasuryImpl),
            deployer,
            ""
        );
        treasury = Treasury(payable(address(treasuryProxy)));
        treasury.initialize();

        registryImpl = new AddressRegistry();
        registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            deployer,
            ""
        );
        registry = AddressRegistry(address(registryProxy));
        registry.initialize();

        Totem totemImplementation = new Totem();
        beacon = new UpgradeableBeacon(address(totemImplementation), deployer);

        astrToken = new MockToken();
        astrToken.mint(userA, 1_000_000 ether);
        astrToken.mint(userB, 1_000_000 ether);
        astrToken.mint(userC, 1_000_000 ether);
        astrToken.mint(userD, 1_000_000 ether);

        // Set payment token
        paymentToken = astrToken;

        // MeritManager
        mmImpl = new MM();
        mmProxy = new TransparentUpgradeableProxy(
            address(mmImpl),
            deployer,
            ""
        );
        mm = MM(address(mmProxy));

        // MYTHO - Upgradeable implementation
        mythoImpl = new MYTHO();
        mythoProxy = new TransparentUpgradeableProxy(
            address(mythoImpl),
            deployer,
            ""
        );
        mytho = MYTHO(address(mythoProxy));
        mytho.initialize(
            address(mm),
            deployer,
            deployer,
            deployer,
            address(registry)
        );

        address[4] memory vestingAddresses = [
            mytho.meritVestingYear1(),
            mytho.meritVestingYear2(),
            mytho.meritVestingYear3(),
            mytho.meritVestingYear4()
        ];

        registry.setAddress(bytes32("MERIT_MANAGER"), address(mm));
        registry.setAddress(bytes32("MYTHO_TOKEN"), address(mytho));
        registry.setAddress(bytes32("MYTHO_TREASURY"), address(treasury));

        mm.initialize(address(registry), vestingAddresses);

        // TotemTokenDistributor
        distrImpl = new TTD();
        distrProxy = new TransparentUpgradeableProxy(
            address(distrImpl),
            deployer,
            ""
        );
        distr = TTD(address(distrProxy));
        distr.initialize(address(registry));

        registry.setAddress(bytes32("TOTEM_TOKEN_DISTRIBUTOR"), address(distr));

        // TotemFactory
        factoryImpl = new TF();
        factoryProxy = new TransparentUpgradeableProxy(
            address(factoryImpl),
            deployer,
            ""
        );
        factory = TF(address(factoryProxy));
        factory.initialize(
            address(registry),
            address(beacon),
            address(astrToken)
        );

        registry.setAddress(bytes32("TOTEM_FACTORY"), address(factory));

        distr.setTotemFactory(address(registry));
        distr.setUniswapV2Router(address(router));
        distr.setPaymentToken(address(paymentToken));

        mm.grantRole(mm.REGISTRATOR(), address(distr));
        mm.grantRole(mm.REGISTRATOR(), address(factory));

        // Layers
        layersImpl = new L();
        layerProxy = new TransparentUpgradeableProxy(
            address(layersImpl),
            deployer,
            ""
        );
        layers = L(address(layerProxy));
        layers.initialize(address(registry));

        registry.setAddress(bytes32("LAYERS"), address(layers));

        // Shards
        shardsImpl = new Shards();
        shardProxy = new TransparentUpgradeableProxy(
            address(shardsImpl),
            deployer,
            ""
        );
        shards = Shards(address(shardProxy));
        shards.initialize(address(registry));
        
        registry.setAddress(bytes32("SHARDS"), address(shards));

        layers.setShardToken();
    }

    // Utility function to prank as a specific user
    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }

    function warp(uint256 _time) internal {
        vm.warp(block.timestamp + _time);
    }
}
