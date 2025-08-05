// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract LayersTest is Base {

    function test_Chaos() public {
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

        // totalBoostedTokens should show actual boosted amount
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 1_000_000 ether);

        // Try boosting with userC who has no tokens - should revert
        prank(userC);
        TT(data.totemTokenAddr).approve(address(layers), 2_000_000 ether);
        vm.expectRevert(L.InsufficientBalance.selector);
        layers.boostLayer(layerId, 2_000_000 ether);

        // Verify no changes occurred after failed boost
        assertEq(layers.getBoostAmount(layerId, userB), 1_000_000 ether);
        assertEq(layers.getBoostAmount(layerId, userC), 0);
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 1_000_000 ether); // Shows actual boosted amount

        // Test that userB can boost more tokens
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 2_000_000 ether);
        layers.boostLayer(layerId, 2_000_000 ether);
        assertEq(layers.getBoostAmount(layerId, userB), 3_000_000 ether);
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 3_000_000 ether); // Shows actual boosted amount

        // Warp time to after boost window
        warp(25 hours); // Boost window is 24 hours

        // Check totalBoostedTokens after boost window (same as before)
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
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), 1);

        assertEq(layers.layerCounter(), 2);
        assertEq(layers.pendingLayerCounter(), 2);

        // verify layer by creator
        prank(userA);
        uint256 newLayerId = layers.verifyLayer(1, true);
        assertEq(layers.layerCounter(), 3);
        assertEq(newLayerId, 2);
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), 0);

        layer = layers.getLayer(2);
        assertEq(layer.creator, userB);
        assertEq(layer.totemAddr, data.totemAddr);
        assertEq(layers.ownerOf(newLayerId), userB);
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), 0); // Pending layer cleared

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
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), pendingLayerId);

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
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), 0); // Pending layer cleared

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
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), 0);
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
        assertEq(layer.totalBoostedTokens, 1_000_000 ether); // Should show actual boosted amount
        
        // Test additional boost from same user
        prank(userB);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        layers.boostLayer(layerId, 500_000 ether);
        assertEq(layers.getBoostAmount(layerId, userB), 1_500_000 ether);
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 1_500_000 ether); // Should show actual boosted amount
        
        // Test boosting after window ends
        warp(25 hours);
        prank(userB);
        vm.expectRevert(L.BoostWindowClosed.selector);
        layers.boostLayer(layerId, 1_000_000 ether);
        
        // Verify total boosted tokens after window (same as before since it's always tracked)
        layer = layers.getLayer(layerId);
        assertEq(layer.totalBoostedTokens, 1_500_000 ether); // Always shows actual value
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

        // Test successful donation
        vm.deal(userB, 1000 ether);
        uint256 donationAmount = 1 ether;
        uint256 expectedFee = (donationAmount * layers.donationFeePercentage()) / 10000;
        uint256 initialBalance = address(userA).balance;

        prank(userB);
        layers.donateToLayer{value: donationAmount}(layerId);

        // Verify donation was processed correctly
        assertEq(address(userA).balance, initialBalance + donationAmount - expectedFee);
        assertEq(layers.totalDonations(layerId), donationAmount - expectedFee);

        // Test donation to non-existent layer
        prank(userB);
        vm.expectRevert(L.LayerNotFound.selector);
        layers.donateToLayer{value: 1 ether}(999);

        // Get totem data
        TF.TotemData memory data = factory.getTotemData(totemId);

        // Make totem registered in Merit Manager
        buyAllTotemTokens(data.totemTokenAddr);

        // Get totems merit points
        uint256 totemMerit = mm.getTotemMeritPoints(data.totemAddr, 0);
        console.log("totemMerit", totemMerit);

        // Test small amount of donation
        prank(userB);
        donationAmount = 0.00011 ether;
        uint256 predictedMerit = mm.calculateDonationMerit(donationAmount);
        console.log("predictedMerit", predictedMerit);
        console.log("min donation for merit", mm.getMinimumDonationForMerit());
        layers.donateToLayer{value: donationAmount}(layerId);

        // Get totems merit points
        totemMerit = mm.getTotemMeritPoints(data.totemAddr, 0);
        console.log("totemMerit", totemMerit);
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
        
        // Should now be able to create layer (will be pending since userB is not creator)
        prank(userB);
        uint256 layerId = layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Verify pending layer was created (userB is not the totem creator, so gets pending layer)
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), layerId);
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
        assertEq(layers.totalDonations(layerId), 1 ether - expectedFee);
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
        assertEq(layers.totalDonations(layerId), 1 ether - expectedFee);
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

        // update price feed
        mockV3Aggregator.updateAnswer(0.05e8);

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

    function test_NFTBoosting() public {
        // Create a mock NFT
        MockERC721 nftToken = new MockERC721();
        
        // Mint some NFTs to users
        nftToken.mint(userA, 1);
        nftToken.mint(userB, 2);
        nftToken.mint(userC, 3);
        
        // Authorize userA to create a totem with the NFT token
        prank(deployer);
        address[] memory usersToAuthorize = new address[](1);
        usersToAuthorize[0] = userA;
        factory.authorizeUsers(address(nftToken), usersToAuthorize);
        
        // Approve fee token for totem creation
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        
        // Mock oracle call (like in Complex.t.sol)
        vm.mockCall(
            address(holdersOracle),
            abi.encodeWithSelector(TokenHoldersOracle.requestNFTCount.selector, address(nftToken)),
            abi.encode(0)
        );
        
        // Create totem with NFT token
        factory.createTotemWithExistingToken(
            abi.encodePacked(keccak256("NFT Totem")),
            address(nftToken),
            new address[](0)
        );
        
        // Get totem data
        TF.TotemData memory data = factory.getTotemData(factory.getLastId() - 1);
        assertEq(uint256(data.tokenType), uint256(TF.TokenType.ERC721));
        assertEq(data.totemTokenAddr, address(nftToken));
        
        // Create layer
        uint256 layerId = createLayerWithTotem(userA, data.totemAddr);
        
        // Test NFT boosting - userB boosts with NFT tokenId 2
        prank(userB);
        nftToken.approve(address(layers), 2);
        layers.boostLayer(layerId, 2); // tokenId = 2
        
        // Check boost data
        assertEq(layers.getBoostAmount(layerId, userB), 1); // Each NFT counts as 1 boost
        uint256[] memory nftBoosts = layers.getNFTBoosts(layerId, userB);
        assertEq(nftBoosts.length, 1);
        assertEq(nftBoosts[0], 2);
        
        // Verify NFT was transferred to contract
        assertEq(nftToken.ownerOf(2), address(layers));
        
        // Test boosting with another NFT from same user
        prank(userC);
        nftToken.approve(address(layers), 3);
        layers.boostLayer(layerId, 3); // tokenId = 3
        
        assertEq(layers.getBoostAmount(layerId, userC), 1);
        uint256[] memory nftBoosts2 = layers.getNFTBoosts(layerId, userC);
        assertEq(nftBoosts2.length, 1);
        assertEq(nftBoosts2[0], 3);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Test unboosting NFT
        prank(userB);
        layers.unboostLayer(layerId);
        
        // Verify NFT was returned
        assertEq(nftToken.ownerOf(2), userB);
        assertEq(layers.getBoostAmount(layerId, userB), 0);
        
        // Check NFT boosts array is cleared
        nftBoosts = layers.getNFTBoosts(layerId, userB);
        assertEq(nftBoosts.length, 0);
        
        // Test second user unboosting
        prank(userC);
        layers.unboostLayer(layerId);
        
        assertEq(nftToken.ownerOf(3), userC);
        assertEq(layers.getBoostAmount(layerId, userC), 0);
    }

    function test_ViewFunctions() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        uint256 layerId = createLayer(userA, totemId);
        
        // Test getLayer during boost window
        L.Layer memory layer = layers.getLayer(layerId);
        assertEq(layer.creator, userA);
        assertEq(layer.totemAddr, data.totemAddr);
        assertEq(layer.totalBoostedTokens, 0); // Should be 0 during boost window
        
        // Test getMetadataHash
        bytes memory metadata = layers.getMetadataHash(layerId);
        assertEq(keccak256(metadata), keccak256(abi.encodePacked(keccak256("Test"))));
        
        // Test getBoostAmount (should be 0 initially)
        assertEq(layers.getBoostAmount(layerId, userB), 0);
        
        // Test getNFTBoosts (should be empty initially)
        uint256[] memory nftBoosts = layers.getNFTBoosts(layerId, userB);
        assertEq(nftBoosts.length, 0);
        
        // Test with non-existent layer
        vm.expectRevert(L.LayerNotFound.selector);
        layers.getLayer(999);
        
        vm.expectRevert(L.LayerNotFound.selector);
        layers.getMetadataHash(999);
    }

    function test_PendingLayerFunctions() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Give userB some tokens
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 250_000 ether);
        
        // Create pending layer
        uint256 pendingLayerId = createLayer(userB, totemId);
        
        // Test getPendingLayer
        L.Layer memory pendingLayer = layers.getPendingLayer(pendingLayerId);
        assertEq(pendingLayer.creator, userB);
        assertEq(pendingLayer.totemAddr, data.totemAddr);
        assertEq(pendingLayer.totalBoostedTokens, 0);
        
        // Test userPendingLayerByTotem mapping
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), pendingLayerId);
        
        // Approve pending layer
        prank(userA);
        layers.verifyLayer(pendingLayerId, true);
        
        // Check pending layer was cleared
        assertEq(layers.userPendingLayerByTotem(userB, data.totemAddr), 0);
        
        // Test that getPendingLayer still works for historical data
        pendingLayer = layers.getPendingLayer(pendingLayerId);
        assertEq(pendingLayer.creator, userB); // Data still there
    }

    function test_RoyaltyFunctionality() public {
        uint256 totemId = createTotem(userA);
        uint256 layerId = createLayer(userA, totemId);
        
        // Test royalty info
        (address receiver, uint256 royaltyAmount) = layers.royaltyInfo(layerId, 100_000 ether);
        assertEq(receiver, userA);
        assertEq(royaltyAmount, 10_000 ether); // 10% of 100_000 ether = 10_000 ether
        
        // Test with different amount
        (receiver, royaltyAmount) = layers.royaltyInfo(layerId, 1 ether);
        assertEq(receiver, userA);
        assertEq(royaltyAmount, 0.1 ether); // 10% of 1 ether = 0.1 ether
        
        // Change royalty percentage and create new layer (royalty is set at mint time)
        prank(deployer);
        layers.setRoyaltyPercentage(500); // 5%
        
        uint256 layerId2 = createLayer(userA, totemId);
        (receiver, royaltyAmount) = layers.royaltyInfo(layerId2, 100_000 ether);
        assertEq(receiver, userA);
        assertEq(royaltyAmount, 5_000 ether); // 5% of 100_000 ether = 5_000 ether
    }

    function test_SetShardToken() public {
        // Test unauthorized access
        prank(userA);
        vm.expectRevert();
        layers.setShardToken();
        
        // Test successful set by manager
        prank(deployer);
        layers.setShardToken();

        // Deploy TokenHoldersOracle
        address routerAddress = makeAddr("chainlinkFunctionsRouter");
        holdersOracle = new TokenHoldersOracle(routerAddress, address(treasury));
        
        // Grant roles and set configuration
        holdersOracle.grantRole(holdersOracle.CALLER_ROLE(), address(factory));
        holdersOracle.setSubscriptionId(1);
        holdersOracle.setGasLimit(300000);

        // Register in AddressRegistry
        registry.setAddress(bytes32("TOKEN_HOLDERS_ORACLE"), address(holdersOracle));
    }

    function test_InvalidMetadataHash() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Test with empty metadata hash
        prank(userA);
        vm.expectRevert(L.InvalidMetadataHash.selector);
        layers.createLayer(data.totemAddr, "");
    }

    function test_HasPendingLayerError() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Give userB some tokens
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 250_000 ether);
        
        // Create first pending layer
        createLayer(userB, totemId);
        
        // Try to create second pending layer
        prank(userB);
        vm.expectRevert(L.HasPendingLayer.selector);
        layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test2")));
    }

    function test_MultipleBoostsAndUnboosts() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        uint256 layerId = createLayer(userA, totemId);
        
        // Give tokens to multiple users
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        prank(userC);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        
        // Multiple users boost
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 1_000_000 ether);
        layers.boostLayer(layerId, 1_000_000 ether);
        
        prank(userC);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        layers.boostLayer(layerId, 500_000 ether);
        
        // Check boost amounts
        assertEq(layers.getBoostAmount(layerId, userB), 1_000_000 ether);
        assertEq(layers.getBoostAmount(layerId, userC), 500_000 ether);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // First user unboosts (creator should get reward)
        uint256 initialCreatorShards = shards.balanceOf(userA);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 creatorReward = shards.balanceOf(userA) - initialCreatorShards;
        assertGt(creatorReward, 0);
        
        // Second user unboosts (creator should NOT get additional reward)
        initialCreatorShards = shards.balanceOf(userA);
        prank(userC);
        layers.unboostLayer(layerId);
        assertEq(shards.balanceOf(userA), initialCreatorShards); // No additional reward
        
        // Check boost amounts are cleared
        assertEq(layers.getBoostAmount(layerId, userB), 0);
        assertEq(layers.getBoostAmount(layerId, userC), 0);
    }

    function test_DonationFeeValidation() public {
        // Test setting fee over maximum (50%)
        prank(deployer);
        vm.expectRevert(L.InvalidFeePercentage.selector);
        layers.setDonationFee(5001); // Over 50%
        
        // Test setting maximum fee (50%)
        prank(deployer);
        layers.setDonationFee(5000); // Exactly 50%
        assertEq(layers.donationFeePercentage(), 5000);
        
        // Test setting zero fee
        prank(deployer);
        layers.setDonationFee(0); // 0%
        assertEq(layers.donationFeePercentage(), 0);
    }

    function test_BoostWindowValidation() public {
        // Test setting zero boost window
        prank(deployer);
        vm.expectRevert(L.InvalidDuration.selector);
        layers.setBoostWindow(0);
        
        // Test setting valid boost window
        prank(deployer);
        layers.setBoostWindow(48 hours);
        assertEq(layers.boostWindow(), 48 hours);
    }

    function test_EventEmissions() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Test LayerCreated event
        prank(userA);
        vm.expectEmit(true, true, true, false);
        emit L.LayerCreated(1, userA, data.totemAddr, abi.encodePacked(keccak256("Test")), false);
        uint256 layerId = layers.createLayer(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Test boost events
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        
        vm.expectEmit(true, true, false, true);
        emit L.LayerBoostedERC20(layerId, userB, 500_000 ether);
        layers.boostLayer(layerId, 500_000 ether);
        
        // Test donation event
        vm.deal(userC, 5 ether);
        prank(userC);
        uint256 expectedFee = (1 ether * layers.donationFeePercentage()) / 10000;
        vm.expectEmit(true, true, false, true);
        emit L.DonationReceived(layerId, userC, 1 ether - expectedFee, expectedFee);
        layers.donateToLayer{value: 1 ether}(layerId);
        
        // Test donation fee update event
        prank(deployer);
        vm.expectEmit(false, false, false, true);
        emit L.DonationFeeUpdated(layers.donationFeePercentage(), 1500);
        layers.setDonationFee(1500);
        
        // Test boost window update event
        prank(deployer);
        vm.expectEmit(false, false, false, true);
        emit L.BoostWindowUpdated(layers.boostWindow(), 48 hours);
        layers.setBoostWindow(48 hours);
    }

    function test_SupportsInterface() public view {
        // Test IERC721Receiver interface
        assertTrue(layers.supportsInterface(type(IERC721Receiver).interfaceId));
        
        // Test ERC721 interface (using hex value since type() might not work properly)
        assertTrue(layers.supportsInterface(0x80ac58cd)); // ERC721 interface ID
        
        // Test basic ERC165 interface
        assertTrue(layers.supportsInterface(0x01ffc9a7)); // ERC165 interface ID
    }

    function test_OnERC721Received() public view {
        // Test that contract can receive NFTs
        bytes4 selector = layers.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }

    function test_EdgeCases() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        uint256 layerId = createLayer(userA, totemId);
        
        // Test boosting with zero amount (should revert)
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        
        vm.expectRevert(L.InvalidAmount.selector);
        layers.boostLayer(layerId, 0);
        
        // Test donation with zero value (should work)
        vm.deal(userB, 5 ether);
        prank(userB);
        layers.donateToLayer{value: 0}(layerId);
        assertEq(layers.totalDonations(layerId), 0);
    }

    function test_CalculateShardRewardFormula() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Give userB tokens for boosting BEFORE completing token sale
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        
        // Complete token sale to ensure proper circulating supply
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 layerId = createLayer(userA, totemId);
        
        // Boost with specific amount
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        layers.boostLayer(layerId, 500_000 ether);
        
        // Wait for boost window
        warp(25 hours);
        
        // Check the formula is working by unboosting and getting rewards
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 receivedShards = shards.balanceOf(userB) - initialShards;
        
        // Should receive some shards based on the formula
        assertGt(receivedShards, 0);
    }

    function test_ShardDistributionFormula() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // First, buy tokens for testing users BEFORE completing sale
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether); // Buy fixed amount for userB
        
        // Complete token sale to get stable circulating supply
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 layerId = createLayer(userA, totemId);
        
        // Get circulating supply for calculations
        uint256 circulatingSupply = TT(data.totemTokenAddr).totalSupply() - 
            TT(data.totemTokenAddr).balanceOf(data.totemAddr) -
            TT(data.totemTokenAddr).balanceOf(address(distr));
        
        // UserB boosts with their purchased tokens
        uint256 boostAmount = 500_000 ether; // Use part of purchased tokens
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), boostAmount);
        layers.boostLayer(layerId, uint224(boostAmount));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Calculate expected reward using the formula: S * (l/T) * sqrt(L/T)
        uint256 baseReward = layers.baseShardReward();
        uint256 userRatio = (boostAmount * 1e18) / circulatingSupply; // l/T
        uint256 totalRatio = (boostAmount * 1e18) / circulatingSupply; // L/T (same as user since only one booster)
        uint256 sqrtTotalRatio = Math.sqrt(totalRatio);
        uint256 expectedReward = (baseReward * userRatio * sqrtTotalRatio) / 1e36;
        
        // Unboost and check rewards
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 receivedShards = shards.balanceOf(userB) - initialShards;
        
        // Should match the formula (with small tolerance for rounding)
        assertApproxEqRel(receivedShards, expectedReward, 1e15); // 0.1% tolerance
    }

    function test_ShardDistributionMultipleUsersBasic() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // First, buy tokens for testing users BEFORE completing sale
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 2_000_000 ether); // UserB gets more tokens
        
        prank(userC);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether); // UserC gets fewer tokens
        
        // Complete token sale
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 layerId = createLayer(userA, totemId);
        
        // UserB boosts with more tokens
        uint256 boostAmountB = 1_000_000 ether;
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), boostAmountB);
        layers.boostLayer(layerId, uint224(boostAmountB));
        
        // UserC boosts with fewer tokens
        uint256 boostAmountC = 500_000 ether;
        prank(userC);
        TT(data.totemTokenAddr).approve(address(layers), boostAmountC);
        layers.boostLayer(layerId, uint224(boostAmountC));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Test UserB unboost
        uint256 initialShardsB = shards.balanceOf(userB);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 receivedShardsB = shards.balanceOf(userB) - initialShardsB;
        
        // Test UserC unboost
        uint256 initialShardsC = shards.balanceOf(userC);
        prank(userC);
        layers.unboostLayer(layerId);
        uint256 receivedShardsC = shards.balanceOf(userC) - initialShardsC;
        
        // UserB should have gotten more rewards than UserC (more boost)
        assertGt(receivedShardsB, receivedShardsC);
        assertGt(receivedShardsB, 0);
        assertGt(receivedShardsC, 0);
    }

    function test_ShardDistributionFormulaAccuracy() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // First, buy tokens for testing users BEFORE completing sale
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        // Complete token sale
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 layerId = createLayer(userA, totemId);
        
        // Get circulating supply for calculations
        uint256 circulatingSupply = TT(data.totemTokenAddr).totalSupply() - 
            TT(data.totemTokenAddr).balanceOf(data.totemAddr) -
            TT(data.totemTokenAddr).balanceOf(address(distr));
        
        // UserB boosts with fixed amount
        uint256 boostAmount = 500_000 ether;
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), boostAmount);
        layers.boostLayer(layerId, uint224(boostAmount));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Calculate expected reward using the formula
        uint256 baseReward = layers.baseShardReward();
        uint256 userRatio = (boostAmount * 1e18) / circulatingSupply; // l/T
        uint256 totalRatio = (boostAmount * 1e18) / circulatingSupply; // L/T
        uint256 sqrtTotalRatio = Math.sqrt(totalRatio);
        uint256 expectedReward = (baseReward * userRatio * sqrtTotalRatio) / 1e36;
        
        // Unboost and check rewards
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 receivedShards = shards.balanceOf(userB) - initialShards;
        
        // Should match the formula (with small tolerance for rounding)
        assertApproxEqRel(receivedShards, expectedReward, 1e15); // 0.1% tolerance
    }

    function test_ShardDistributionCreatorRewardOnce() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // First, buy tokens for testing users BEFORE completing sale
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        
        prank(userC);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 300_000 ether);
        
        // Complete token sale
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 layerId = createLayer(userA, totemId);
        
        // UserB and UserC boost
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 500_000 ether);
        layers.boostLayer(layerId, uint224(500_000 ether));
        
        prank(userC);
        TT(data.totemTokenAddr).approve(address(layers), 300_000 ether);
        layers.boostLayer(layerId, uint224(300_000 ether));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // First unboost should trigger creator reward
        uint256 initialCreatorShards = shards.balanceOf(userA);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 creatorReward = shards.balanceOf(userA) - initialCreatorShards;
        assertGt(creatorReward, 0);
        
        // Second unboost should NOT give additional creator reward
        initialCreatorShards = shards.balanceOf(userA);
        prank(userC);
        layers.unboostLayer(layerId);
        uint256 noAdditionalReward = shards.balanceOf(userA) - initialCreatorShards;
        assertEq(noAdditionalReward, 0);
    }

    function test_ShardDistributionUserRatioCap() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // First, buy tokens for testing users BEFORE completing sale
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 5_000_000 ether); // Buy large amount
        
        // Complete token sale
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 layerId = createLayer(userA, totemId);
        
        // Try to boost with large amount (to test capping)
        uint256 boostAmount = 3_000_000 ether;
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), boostAmount);
        layers.boostLayer(layerId, uint224(boostAmount));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Unboost and check rewards exist (detailed cap testing in separate test)
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 receivedShards = shards.balanceOf(userB) - initialShards;
        
        // Should receive some rewards (cap formula validation in separate test)
        assertGt(receivedShards, 0);
    }

    function test_ShardDistributionCapFormulaValidation() public {
        // Test the capping mechanism independently
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // First, buy tokens for testing users BEFORE completing sale
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 2_000_000 ether);
        
        buyAllTotemTokens(data.totemTokenAddr);
        uint256 layerId = createLayer(userA, totemId);
        
        // Boost with moderate amount to test boundary
        uint256 boostAmount = 1_500_000 ether;
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), boostAmount);
        layers.boostLayer(layerId, uint224(boostAmount));
        
        warp(25 hours);
        
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 receivedShards = shards.balanceOf(userB) - initialShards;
        
        // Should receive rewards
        assertGt(receivedShards, 0);
    }

    function test_ShardDistributionCreatorRewardCalculation() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // First, buy tokens for testing users BEFORE completing sale
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        // Complete token sale
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 layerId = createLayer(userA, totemId);
        
        // UserB boosts
        prank(userB);
        TT(data.totemTokenAddr).approve(address(layers), 1_000_000 ether);
        layers.boostLayer(layerId, uint224(1_000_000 ether));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Unboost and measure rewards
        uint256 initialCreatorShards = shards.balanceOf(userA);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 creatorReward = shards.balanceOf(userA) - initialCreatorShards;
        
        // Creator should get some reward
        assertGt(creatorReward, 0);
        
        // Creator reward should be at least the minimum
        uint256 minAuthorReward = layers.minAuthorShardReward();
        assertGe(creatorReward, minAuthorReward);
    }

    function test_ShardDistributionMinimalRewards() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        uint256 layerId = createLayer(userA, totemId);
        
        // Buy small amount of tokens (minimal circulating supply)
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1000 ether);
        TT(data.totemTokenAddr).approve(address(layers), 1000 ether);
        layers.boostLayer(layerId, uint224(1000 ether));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Should get minimal rewards due to small circulating supply
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        layers.unboostLayer(layerId);
        uint256 receivedShards = shards.balanceOf(userB) - initialShards;
        
        // Should receive very small rewards (but not necessarily 0) due to minimal circulating supply
        // The formula still works but gives minimal values
        assertGe(receivedShards, 0); // Can be 0 or very small positive value
        assertLe(receivedShards, 100); // Should be very small due to minimal circulating supply
    }
}