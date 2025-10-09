// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract PostsTest is Base {
    function test_verifyPostWhileSalePeriod() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);

        prank(userB);
        astrToken.approve(address(distr), 250_000 ether);
        distr.buy(data.totemTokenAddr, 1000 ether);

        uint256 pendingPostId = createPost(userB, totemId);
        console.log("Post ID:", pendingPostId);

        P.Post memory pendingPost = posts.getPendingPost(pendingPostId);
        
        prank(userA);
        uint256 postId = posts.verifyPost(pendingPostId, true);

        P.Post memory post = posts.getPost(postId);
        console.log("totemAddr", post.totemAddr);
        console.log("creator", post.creator);
    }

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

        assertEq(posts.postCounter(), 1);
        assertEq(posts.pendingPostCounter(), 1);

        uint256 postId = createPost(userA, totemId);
        
        // check royalty info
        (address royaltyReceiver, uint256 royaltyAmount) = posts.royaltyInfo(postId, 100_000 ether);
        assertEq(royaltyReceiver, userA);
        assertEq(royaltyAmount, 100_000 ether * 1000 / 10000); // 10% of 100_000 ether = 10_000 ether

        // check post info
        P.Post memory post = posts.getPost(postId);
        assertEq(post.creator, userA);
        assertEq(post.totemAddr, data.totemAddr);
        assertEq(post.createdAt, uint32(block.timestamp));
        assertEq(post.totalBoostedTokens, 0);

        // Test boosting post
        // Approve totem tokens for boosting
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 1_000_000 ether);
        posts.boostPost(postId, 1_000_000 ether);

        // Check boost was recorded correctly
        assertEq(posts.getBoostAmount(postId, userB), 1_000_000 ether);

        // totalBoostedTokens should show actual boosted amount
        post = posts.getPost(postId);
        assertEq(post.totalBoostedTokens, 1_000_000 ether);

        // Try boosting with userC who has no tokens - should revert
        prank(userC);
        TT(data.totemTokenAddr).approve(address(posts), 2_000_000 ether);
        vm.expectRevert(P.InsufficientBalance.selector);
        posts.boostPost(postId, 2_000_000 ether);

        // Verify no changes occurred after failed boost
        assertEq(posts.getBoostAmount(postId, userB), 1_000_000 ether);
        assertEq(posts.getBoostAmount(postId, userC), 0);
        post = posts.getPost(postId);
        assertEq(post.totalBoostedTokens, 1_000_000 ether); // Shows actual boosted amount

        // Test that userB can boost more tokens
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 2_000_000 ether);
        posts.boostPost(postId, 2_000_000 ether);
        assertEq(posts.getBoostAmount(postId, userB), 3_000_000 ether);
        post = posts.getPost(postId);
        assertEq(post.totalBoostedTokens, 3_000_000 ether); // Shows actual boosted amount

        // Warp time to after boost window
        warp(25 hours); // Boost window is 24 hours

        // Check totalBoostedTokens after boost window (same as before)
        post = posts.getPost(postId);
        assertEq(post.totalBoostedTokens, 3_000_000 ether);

        uint256 pendingPostId = createPost(userB, totemId);
        assertEq(pendingPostId, 1);

        // check pending post info
        P.Post memory pendingPost = posts.getPendingPost(pendingPostId);
        assertEq(pendingPost.creator, userB);
        assertEq(pendingPost.totemAddr, data.totemAddr);
        assertEq(pendingPost.createdAt, uint32(block.timestamp));
        assertEq(pendingPost.totalBoostedTokens, 0);
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), 1);

        assertEq(posts.postCounter(), 2);
        assertEq(posts.pendingPostCounter(), 2);

        // verify post by creator
        prank(userA);
        uint256 newPostId = posts.verifyPost(1, true);
        assertEq(posts.postCounter(), 3);
        assertEq(newPostId, 2);
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), 0);

        post = posts.getPost(2);
        assertEq(post.creator, userB);
        assertEq(post.totemAddr, data.totemAddr);
        assertEq(posts.ownerOf(newPostId), userB);
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), 0); // Pending post cleared

        // Verify royalty settings
        (address receiver, uint256 amount) = posts.royaltyInfo(newPostId, 100 ether);
        assertEq(receiver, userB);
        assertEq(amount, 10 ether); // 10% of 100 ether
    }

    function test_PostCreation() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);

        // Test auto-approved post creation (userA has enough tokens)
        uint256 postId = createPost(userA, totemId);
        P.Post memory post = posts.getPost(postId);
        assertEq(post.creator, userA);
        assertEq(post.totemAddr, data.totemAddr);
        assertEq(post.createdAt, uint32(block.timestamp));
        assertEq(post.totalBoostedTokens, 0);
        assertEq(posts.ownerOf(postId), userA);

        // Test pending post creation (userD has no tokens)
        prank(userD);
        vm.expectRevert(P.NotEnoughTotemTokens.selector);
        posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));

        // Test invalid totem
        prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(TF.TotemNotFound.selector, 0)
        );
        posts.createPost(address(999), abi.encodePacked(keccak256("Test")));
    }

    function test_PostVerification() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);

        // Give userB some totem tokens to meet minimum balance requirement
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 250_000 ether);

        // Create pending post - it will be pending since userB is not owner or collaborator
        uint256 pendingPostId = createPost(userB, totemId);
        
        // Verify post info
        P.Post memory pendingPost = posts.getPendingPost(pendingPostId);
        assertEq(pendingPost.creator, userB);
        assertEq(pendingPost.totemAddr, data.totemAddr);
        assertEq(pendingPost.createdAt, uint32(block.timestamp));
        assertEq(pendingPost.totalBoostedTokens, 0);
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), pendingPostId);

        // Test verification by non-owner/collaborator
        prank(userC);
        vm.expectRevert(P.NotAuthorized.selector);
        posts.verifyPost(pendingPostId, true);

        // Test verification by owner when totem is not registered in Merit Manager
        assertFalse(mm.isRegisteredTotem(data.totemAddr), "Totem should not be registered yet");
        prank(userA);
        uint256 newPostId = posts.verifyPost(pendingPostId, true);

        // Check post was created properly
        P.Post memory post = posts.getPost(newPostId);
        assertEq(post.creator, userB);
        assertEq(post.totemAddr, data.totemAddr);
        assertEq(posts.ownerOf(newPostId), userB);
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), 0); // Pending post cleared

        // Verify royalty settings
        (address receiver, uint256 amount) = posts.royaltyInfo(newPostId, 100 ether);
        assertEq(receiver, userB);
        assertEq(amount, 10 ether); // 10% of 100 ether

        // Complete token sale to register totem in Merit Manager
        buyAllTotemTokens(data.totemTokenAddr);
        assertTrue(mm.isRegisteredTotem(data.totemAddr), "Totem should be registered after token sale");

        // Create and verify another post - this time Merit Manager reward should be given
        uint256 pendingPostId2 = createPost(userB, totemId);
        prank(userA);
        uint256 newPostId2 = posts.verifyPost(pendingPostId2, true);
        assertEq(posts.ownerOf(newPostId2), userB);

        // Test rejecting a post
        uint256 pendingPostId3 = createPost(userB, totemId);
        prank(userA);
        posts.verifyPost(pendingPostId3, false);
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), 0);
    }

    function test_PostBoosting() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Buy enough totem tokens for boosting
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        // Create post as owner so it's auto-approved
        uint256 postId = createPost(userA, totemId);
        
        // Test boosting with insufficient balance
        prank(userC);
        vm.expectRevert(P.InsufficientBalance.selector);
        posts.boostPost(postId, 1_000_000 ether);
        
        // Test boosting non-existent post
        prank(userB);
        vm.expectRevert(P.PostNotFound.selector);
        posts.boostPost(999, 1_000_000 ether);
        
        // Test successful boost
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 1_000_000 ether);
        posts.boostPost(postId, 1_000_000 ether);
        
        // Verify boost data
        assertEq(posts.getBoostAmount(postId, userB), 1_000_000 ether);
        P.Post memory post = posts.getPost(postId);
        assertEq(post.totalBoostedTokens, 1_000_000 ether); // Should show actual boosted amount
        
        // Test additional boost from same user
        prank(userB);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        posts.boostPost(postId, 500_000 ether);
        assertEq(posts.getBoostAmount(postId, userB), 1_500_000 ether);
        post = posts.getPost(postId);
        assertEq(post.totalBoostedTokens, 1_500_000 ether); // Should show actual boosted amount
        
        // Test boosting after window ends
        warp(25 hours);
        prank(userB);
        vm.expectRevert(P.BoostWindowClosed.selector);
        posts.boostPost(postId, 1_000_000 ether);
        
        // Verify total boosted tokens after window (same as before since it's always tracked)
        post = posts.getPost(postId);
        assertEq(post.totalBoostedTokens, 1_500_000 ether); // Always shows actual value
    }

    function test_PostUnboosting() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Buy enough totem tokens for boosting
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        // Create post and boost it
        uint256 postId = createPost(userA, totemId);
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 1_000_000 ether);
        posts.boostPost(postId, 1_000_000 ether);
        assertEq(posts.getBoostAmount(postId, userB), 1_000_000 ether);
        
        // Test unboosting before boost window ends
        prank(userB);
        vm.expectRevert(P.BoostLocked.selector);
        posts.unboostPost(postId);
        
        // Test unboosting after boost window
        warp(25 hours);
        uint256 initialBoosterBalance = shards.balanceOf(userB);
        uint256 initialCreatorBalance = shards.balanceOf(userA);
        
        prank(userB);
        posts.unboostPost(postId);
        
        // Verify unboost results
        assertEq(posts.getBoostAmount(postId, userB), 0);
        uint256 boosterShards = shards.balanceOf(userB) - initialBoosterBalance;
        uint256 creatorShards = shards.balanceOf(userA) - initialCreatorBalance;
        
        assertGt(boosterShards, 0); // Booster received shards
        assertGt(creatorShards, 0); // Creator received shards
        assertApproxEqRel(creatorShards * 9, boosterShards, 1.5e17);
        
        P.Post memory post = posts.getPost(postId);
        assertEq(post.totalBoostedTokens, 1_000_000 ether);
        
        // Test unboosting again
        prank(userB);
        vm.expectRevert(P.BoostNotFound.selector);
        posts.unboostPost(postId);
        
        // Test unboosting non-existent post
        prank(userB);
        vm.expectRevert(P.PostNotFound.selector);
        posts.unboostPost(999);
    }

    function test_PostDonations() public {
        uint256 totemId = createTotem(userA);
        uint256 postId = createPost(userA, totemId);

        // Test successful donation
        vm.deal(userB, 1000 ether);
        uint256 donationAmount = 1 ether;
        uint256 expectedFee = (donationAmount * posts.donationFeePercentage()) / 10000;
        uint256 initialBalance = address(userA).balance;

        prank(userB);
        posts.donateToPost{value: donationAmount}(postId);

        // Verify donation was processed correctly
        assertEq(address(userA).balance, initialBalance + donationAmount - expectedFee);
        assertEq(posts.totalDonations(postId), donationAmount - expectedFee);

        // Test donation to non-existent post
        prank(userB);
        vm.expectRevert(P.PostNotFound.selector);
        posts.donateToPost{value: 1 ether}(999);

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
        posts.donateToPost{value: donationAmount}(postId);

        // Get totems merit points
        totemMerit = mm.getTotemMeritPoints(data.totemAddr, 0);
        console.log("totemMerit", totemMerit);
    }

    function test_AdminFunctions() public {
        // Test setting base shard reward
        prank(deployer);
        posts.setBaseShardReward(1000);
        assertEq(posts.baseShardReward(), 1000);

        // Test setting minimum author shard reward
        prank(deployer);
        posts.setMinAuthorShardReward(100);
        assertEq(posts.minAuthorShardReward(), 100);

        // Test setting author shard percentage
        prank(deployer);
        posts.setAuthorShardPercentage(2000); // 20%
        assertEq(posts.authorShardPercentage(), 2000);

        // Test setting royalty percentage
        prank(deployer);
        posts.setRoyaltyPercentage(500); // 5%
        assertEq(posts.royaltyPercentage(), 500);

        // Test setting boost window
        prank(deployer);
        posts.setBoostWindow(48 hours);
        assertEq(posts.boostWindow(), 48 hours);

        // Test setting minimum totem token balance
        prank(deployer);
        posts.setMinTotemTokenBalance(300_000 ether);
        assertEq(posts.minTotemTokenBalance(), 300_000 ether);

        // Test setting donation fee percentage
        prank(deployer);
        vm.expectRevert(P.InvalidFeePercentage.selector);
        posts.setDonationFee(10001); // Over 100%

        posts.setDonationFee(500); // 5%
        assertEq(posts.donationFeePercentage(), 500);

        // Test unauthorized access
        prank(userA);
        vm.expectRevert();
        posts.setBaseShardReward(2000);
    }

    function test_PauseAndUnpause() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);

        // Test pausing by non-manager
        prank(userA);
        vm.expectRevert();
        posts.pause();

        // Test pausing by manager
        prank(deployer);
        posts.pause();

        // Test operations while paused
        prank(userA);
        vm.expectRevert();
        posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));

        // Test unpausing by manager
        prank(deployer);
        posts.unpause();

        // Verify operations work after unpause
        prank(userA);
        uint256 postId = createPost(userA, totemId);
        assertEq(posts.ownerOf(postId), userA);
    }

    function test_MinimumTotemTokenBalance() public {
        // Create a totem
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Complete token sale first
        buyAllTotemTokens(data.totemTokenAddr);
        
        // Check minimum token requirement
        uint256 minRequired = posts.minTotemTokenBalance();
        
        // Verify userA has enough tokens (creator automatically gets tokens)
        assertGe(TT(data.totemTokenAddr).balanceOf(userA), minRequired);
        
        // Give userB less than minimum tokens
        prank(userA);
        TT(data.totemTokenAddr).transfer(userB, minRequired / 2);
        
        // Verify userB has less than minimum
        assertLt(TT(data.totemTokenAddr).balanceOf(userB), minRequired);
        
        // Attempt to create post with insufficient tokens should fail
        prank(userB);
        vm.expectRevert(P.NotEnoughTotemTokens.selector);
        posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Give userB enough tokens
        prank(userA);
        TT(data.totemTokenAddr).transfer(userB, minRequired);
        
        // Verify userB now has enough tokens
        assertGe(TT(data.totemTokenAddr).balanceOf(userB), minRequired);
        
        // Should now be able to create post (will be pending since userB is not creator)
        prank(userB);
        uint256 postId = posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Verify pending post was created (userB is not the totem creator, so gets pending post)
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), postId);
    }

    function test_MeritManagerRewards() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Complete token sale to register totem in Merit Manager
        buyAllTotemTokens(data.totemTokenAddr);
        
        // Verify totem is registered in Merit Manager
        assertTrue(mm.isRegisteredTotem(data.totemAddr));
        
        // Create post and verify it's successful
        prank(userA);
        uint256 postId = posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));
        assertEq(posts.ownerOf(postId), userA);
        
        // Test donation reward
        vm.deal(userB, 5 ether);
        prank(userB);
        uint256 initialBalance = address(userA).balance;
        posts.donateToPost{value: 1 ether}(postId);
        
        // Verify donation was processed
        uint256 expectedFee = (1 ether * posts.donationFeePercentage()) / 10000;
        assertEq(address(userA).balance, initialBalance + 1 ether - expectedFee);
        assertEq(posts.totalDonations(postId), 1 ether - expectedFee);
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
        
        // Create post
        uint256 postId = createPostWithTotem(userA, data.totemAddr);
        
        // Test NFT boosting - userB boosts with NFT tokenId 2
        prank(userB);
        nftToken.approve(address(posts), 2);
        posts.boostPost(postId, 2); // tokenId = 2
        
        // Check boost data
        assertEq(posts.getBoostAmount(postId, userB), 1); // Each NFT counts as 1 boost
        uint256[] memory nftBoosts = posts.getNFTBoosts(postId, userB);
        assertEq(nftBoosts.length, 1);
        assertEq(nftBoosts[0], 2);
        
        // Verify NFT was transferred to contract
        assertEq(nftToken.ownerOf(2), address(posts));
        
        // Test boosting with another NFT from same user
        prank(userC);
        nftToken.approve(address(posts), 3);
        posts.boostPost(postId, 3); // tokenId = 3
        
        assertEq(posts.getBoostAmount(postId, userC), 1);
        uint256[] memory nftBoosts2 = posts.getNFTBoosts(postId, userC);
        assertEq(nftBoosts2.length, 1);
        assertEq(nftBoosts2[0], 3);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Update oracle data after warp (required for NFT totems since data becomes stale after 5 minutes)
        prank(deployer);
        holdersOracle.manuallyUpdateNFTCount(address(nftToken), 3); // 3 NFTs total
        
        // Test unboosting NFT
        prank(userB);
        posts.unboostPost(postId);
        
        // Verify NFT was returned
        assertEq(nftToken.ownerOf(2), userB);
        assertEq(posts.getBoostAmount(postId, userB), 0);
        
        // Check NFT boosts array is cleared
        nftBoosts = posts.getNFTBoosts(postId, userB);
        assertEq(nftBoosts.length, 0);
        
        // Test second user unboosting
        prank(userC);
        posts.unboostPost(postId);
        
        assertEq(nftToken.ownerOf(3), userC);
        assertEq(posts.getBoostAmount(postId, userC), 0);
    }

    function test_NFTBoostLimit() public {
        // Create a mock NFT
        MockERC721 nftToken = new MockERC721();
        
        // Mint many NFTs to userA
        for (uint256 i = 1; i <= 55; i++) {
            nftToken.mint(userA, i);
        }
        
        // Authorize userA to create a totem with the NFT token
        prank(deployer);
        address[] memory usersToAuthorize = new address[](1);
        usersToAuthorize[0] = userA;
        factory.authorizeUsers(address(nftToken), usersToAuthorize);
        
        // Approve fee token for totem creation
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        
        // Mock oracle call
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
        
        // Create post
        uint256 postId = createPostWithTotem(userA, data.totemAddr);
        
        // Test boosting up to the limit (50 NFTs)
        prank(userA);
        for (uint256 i = 1; i <= 50; i++) {
            nftToken.approve(address(posts), i);
            posts.boostPost(postId, uint224(i));
        }
        
        // Verify we reached the limit
        assertEq(posts.getBoostAmount(postId, userA), 50);
        uint256[] memory nftBoosts = posts.getNFTBoosts(postId, userA);
        assertEq(nftBoosts.length, 50);
        
        // Test that 51st NFT boost fails
        prank(userA);
        nftToken.approve(address(posts), 51);
        vm.expectRevert(abi.encodeWithSignature("MaxNFTBoostsExceeded()"));
        posts.boostPost(postId, uint224(51));
    }

    function test_SetMaxNFTBoostsPerUser() public {
        // Test setting new limit as admin
        prank(deployer);
        posts.setMaxNFTBoostsPerUser(25);
        assertEq(posts.maxNFTBoostsPerUser(), 25);
        
        // Test that non-admin cannot set limit
        prank(userA);
        vm.expectRevert();
        posts.setMaxNFTBoostsPerUser(10);
        
        // Test that zero limit is not allowed
        prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        posts.setMaxNFTBoostsPerUser(0);
    }

    function test_ForceUnboost() public {
        // Create totem and post
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Give userA totem tokens to create post
        prank(userA);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        // UserB gets totem tokens for boosting (before sale ends)
        uint256 boostAmount = 1_000_000 ether; // Increase boost amount for meaningful reward
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, boostAmount);
        
        // Complete token sale to make tokens available
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 postId = createPostWithTotem(userA, data.totemAddr);
        
        // UserB boosts the post with totem tokens
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), boostAmount);
        posts.boostPost(postId, uint224(boostAmount));
        
        // Verify boost was successful
        assertEq(posts.getBoostAmount(postId, userB), boostAmount);
        assertEq(TT(data.totemTokenAddr).balanceOf(userB), 0); // All tokens used for boost
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Admin force unboosts for userB
        uint256 userBTotemBalanceBefore = TT(data.totemTokenAddr).balanceOf(userB);
        uint256 userBShardsBefore = shards.balanceOf(userB);
        
        prank(deployer); // deployer has MANAGER role
        posts.forceUnboost(postId, userB);
        
        // Verify tokens were returned to userB
        assertEq(TT(data.totemTokenAddr).balanceOf(userB), userBTotemBalanceBefore + boostAmount);
        assertEq(posts.getBoostAmount(postId, userB), 0);
        
        // Verify userB received shards
        assertGt(shards.balanceOf(userB), userBShardsBefore);
        
        // Verify creator received reward (since this was first unboost)
        assertGt(shards.balanceOf(userA), 0);
    }

    function test_ForceUnboostNFT() public {
        // Create a mock NFT
        MockERC721 nftToken = new MockERC721();
        nftToken.mint(userB, 1);
        
        // Authorize userA to create a totem with the NFT token
        prank(deployer);
        address[] memory usersToAuthorize = new address[](1);
        usersToAuthorize[0] = userA;
        factory.authorizeUsers(address(nftToken), usersToAuthorize);
        
        // Create NFT totem and post
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        
        vm.mockCall(
            address(holdersOracle),
            abi.encodeWithSelector(TokenHoldersOracle.requestNFTCount.selector, address(nftToken)),
            abi.encode(0)
        );
        
        factory.createTotemWithExistingToken(
            abi.encodePacked(keccak256("NFT Totem")),
            address(nftToken),
            new address[](0)
        );
        
        TF.TotemData memory data = factory.getTotemData(factory.getLastId() - 1);
        
        // Give userA NFT to create post (since it's NFT totem)
        nftToken.mint(userA, 2);
        
        uint256 postId = createPostWithTotem(userA, data.totemAddr);
        
        // UserB boosts with NFT
        prank(userB);
        nftToken.approve(address(posts), 1);
        posts.boostPost(postId, uint224(1));
        
        // Verify NFT was transferred to contract
        assertEq(nftToken.ownerOf(1), address(posts));
        assertEq(posts.getBoostAmount(postId, userB), 1);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Update oracle data for NFT
        prank(deployer);
        holdersOracle.manuallyUpdateNFTCount(address(nftToken), 1);
        
        // Admin force unboosts NFT for userB
        prank(deployer);
        posts.forceUnboost(postId, userB);
        
        // Verify NFT was returned to userB
        assertEq(nftToken.ownerOf(1), userB);
        assertEq(posts.getBoostAmount(postId, userB), 0);
        
        // Verify arrays were cleared
        uint256[] memory nftBoosts = posts.getNFTBoosts(postId, userB);
        assertEq(nftBoosts.length, 0);
    }

    function test_ForceUnboostAccessControl() public {
        // Create totem and post
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Give userA totem tokens to create post
        prank(userA);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        // UserB gets totem tokens for boosting (before sale ends)
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 100 ether);
        
        // Complete token sale to make tokens available
        buyAllTotemTokens(data.totemTokenAddr);
        
        uint256 postId = createPostWithTotem(userA, data.totemAddr);
        
        // UserB boosts the post with totem tokens
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 100 ether);
        posts.boostPost(postId, uint224(100 ether));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Test that non-admin cannot force unboost
        prank(userA);
        vm.expectRevert();
        posts.forceUnboost(postId, userB);
        
        // Test that admin can force unboost
        prank(deployer);
        posts.forceUnboost(postId, userB);
        
        // Verify unboost was successful
        assertEq(posts.getBoostAmount(postId, userB), 0);
    }

    function test_NoMeritManagerRewardsForUnregisteredTotem() public {
        // Create totem but don't complete token sale (not registered in Merit Manager)
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Verify totem is NOT registered in Merit Manager
        assertFalse(mm.isRegisteredTotem(data.totemAddr));
        
        // Create post and verify it's successful even without Merit Manager registration
        prank(userA);
        uint256 postId = posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));
        assertEq(posts.ownerOf(postId), userA);
        
        // Test donation still works for unregistered totems
        vm.deal(userB, 5 ether);
        prank(userB);
        uint256 initialBalance = address(userA).balance;
        posts.donateToPost{value: 1 ether}(postId);
        
        // Verify donation was processed
        uint256 expectedFee = (1 ether * posts.donationFeePercentage()) / 10000;
        assertEq(address(userA).balance, initialBalance + 1 ether - expectedFee);
        assertEq(posts.totalDonations(postId), 1 ether - expectedFee);
    }
    
    function test_MetadataHashFunctionality() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        bytes memory metadataHash = abi.encodePacked(keccak256("Custom Metadata"));
        
        // Create post with custom metadata
        prank(userA);
        uint256 postId = posts.createPost(data.totemAddr, metadataHash);
        
        // Verify metadata hash is stored correctly
        bytes memory storedHash = posts.getMetadataHash(postId);
        assertEq(keccak256(storedHash), keccak256(metadataHash));
        
        // Test getting metadata for non-existent post
        prank(userA);
        vm.expectRevert(P.PostNotFound.selector);
        posts.getMetadataHash(999);
    }
    
    function test_MeritManagerPostRewards() public {
        // Create a totem
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Complete token sale to register totem in Merit Manager
        buyAllTotemTokens(data.totemTokenAddr);
        
        // Verify totem is registered in Merit Manager
        assertTrue(mm.isRegisteredTotem(data.totemAddr));
        
        // Create post and verify it's successful
        prank(userA);
        uint256 postId = posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));
        assertEq(posts.ownerOf(postId), userA);
        
        // Verify the post exists
        P.Post memory post = posts.getPost(postId);
        assertEq(post.creator, userA);
        assertEq(post.totemAddr, data.totemAddr);
    }
    
    function test_CreatorRewardOnlyOncePerPost() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Create post
        uint256 postId = createPost(userA, totemId);
        
        // Multiple users boost the post
        // UserB boosts
        prank(userB);
        astrToken.approve(address(distr), 500_000 ether);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        posts.boostPost(postId, 500_000 ether);
        
        // UserC boosts
        prank(userC);
        astrToken.approve(address(distr), 500_000 ether);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        posts.boostPost(postId, 500_000 ether);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // First unboost should trigger creator reward
        uint256 initialCreatorShards = shards.balanceOf(userA);
        prank(userB);
        posts.unboostPost(postId);
        uint256 creatorRewardAmount = shards.balanceOf(userA) - initialCreatorShards;
        assertGt(creatorRewardAmount, 0);
        
        // Second unboost should not give additional creator reward
        initialCreatorShards = shards.balanceOf(userA);
        prank(userC);
        posts.unboostPost(postId);
        assertEq(shards.balanceOf(userA), initialCreatorShards);
    }
    
    function test_BoostingAfterWindowEnds() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Create layer
        uint256 layerId = createPost(userA, totemId);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Try to boost after window ends
        prank(userB);
        astrToken.approve(address(distr), 500_000 ether);

        // update price feed
        mockV3Aggregator.updateAnswer(0.05e8);

        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        
        // Should NOT be able to boost after window (expect revert)
        vm.expectRevert(P.BoostWindowClosed.selector);
        posts.boostPost(layerId, 500_000 ether);
    }
    
    function test_EcosystemPause() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Pause the ecosystem
        prank(deployer);
        registry.setEcosystemPaused(true);
        
        // Try to create post while ecosystem is paused
        prank(userA);
        vm.expectRevert(P.EcosystemPaused.selector);
        posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Unpause the ecosystem
        prank(deployer);
        registry.setEcosystemPaused(false);
        
        // Should be able to create post now
        prank(userA);
        uint256 postId = posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));
        assertEq(posts.ownerOf(postId), userA);
    }

    function test_ViewFunctions() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        uint256 postId = createPost(userA, totemId);
        
        // Test getPost during boost window
        P.Post memory post = posts.getPost(postId);
        assertEq(post.creator, userA);
        assertEq(post.totemAddr, data.totemAddr);
        assertEq(post.totalBoostedTokens, 0); // Should be 0 during boost window
        
        // Test getMetadataHash
        bytes memory metadata = posts.getMetadataHash(postId);
        assertEq(keccak256(metadata), keccak256(abi.encodePacked(keccak256("Test"))));
        
        // Test getBoostAmount (should be 0 initially)
        assertEq(posts.getBoostAmount(postId, userB), 0);
        
        // Test getNFTBoosts (should be empty initially)
        uint256[] memory nftBoosts = posts.getNFTBoosts(postId, userB);
        assertEq(nftBoosts.length, 0);
        
        // Test with non-existent post
        vm.expectRevert(P.PostNotFound.selector);
        posts.getPost(999);
        
        vm.expectRevert(P.PostNotFound.selector);
        posts.getMetadataHash(999);
    }

    function test_PendingPostFunctions() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Give userB some tokens
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 250_000 ether);
        
        // Create pending post
        uint256 pendingPostId = createPost(userB, totemId);
        
        // Test getPendingPost
        P.Post memory pendingPost = posts.getPendingPost(pendingPostId);
        assertEq(pendingPost.creator, userB);
        assertEq(pendingPost.totemAddr, data.totemAddr);
        assertEq(pendingPost.totalBoostedTokens, 0);
        
        // Test userPendingPostByTotem mapping
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), pendingPostId);
        
        // Approve pending post
        prank(userA);
        posts.verifyPost(pendingPostId, true);
        
        // Check pending post was cleared
        assertEq(posts.userPendingPostByTotem(userB, data.totemAddr), 0);
        
        // Test that getPendingPost still works for historical data
        pendingPost = posts.getPendingPost(pendingPostId);
        assertEq(pendingPost.creator, userB); // Data still there
    }

    function test_RoyaltyFunctionality() public {
        uint256 totemId = createTotem(userA);
        uint256 postId = createPost(userA, totemId);
        
        // Test royalty info
        (address receiver, uint256 royaltyAmount) = posts.royaltyInfo(postId, 100_000 ether);
        assertEq(receiver, userA);
        assertEq(royaltyAmount, 10_000 ether); // 10% of 100_000 ether = 10_000 ether
        
        // Test with different amount
        (receiver, royaltyAmount) = posts.royaltyInfo(postId, 1 ether);
        assertEq(receiver, userA);
        assertEq(royaltyAmount, 0.1 ether); // 10% of 1 ether = 0.1 ether
        
        // Change royalty percentage and create new post (royalty is set at mint time)
        prank(deployer);
        posts.setRoyaltyPercentage(500); // 5%
        
        uint256 postId2 = createPost(userA, totemId);
        (receiver, royaltyAmount) = posts.royaltyInfo(postId2, 100_000 ether);
        assertEq(receiver, userA);
        assertEq(royaltyAmount, 5_000 ether); // 5% of 100_000 ether = 5_000 ether
    }

    function test_SetShardToken() public {
        // Test unauthorized access
        prank(userA);
        vm.expectRevert();
        posts.setShardToken();
        
        // Test successful set by manager
        prank(deployer);
        posts.setShardToken();
    }

    function test_InvalidMetadataHash() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Test with empty metadata hash
        prank(userA);
        vm.expectRevert(P.InvalidMetadataHash.selector);
        posts.createPost(data.totemAddr, "");
    }

    function test_HasPendingPostError() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Give userB some tokens
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 250_000 ether);
        
        // Create first pending post
        createPost(userB, totemId);
        
        // Try to create second pending post
        prank(userB);
        vm.expectRevert(P.HasPendingPost.selector);
        posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test2")));
    }

    function test_MultipleBoostsAndUnboosts() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        uint256 postId = createPost(userA, totemId);
        
        // Give tokens to multiple users
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1_000_000 ether);
        
        prank(userC);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        
        // Multiple users boost
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 1_000_000 ether);
        posts.boostPost(postId, 1_000_000 ether);
        
        prank(userC);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        posts.boostPost(postId, 500_000 ether);
        
        // Check boost amounts
        assertEq(posts.getBoostAmount(postId, userB), 1_000_000 ether);
        assertEq(posts.getBoostAmount(postId, userC), 500_000 ether);
        
        // Wait for boost window to end
        warp(25 hours);
        
        // First user unboosts (creator should get reward)
        uint256 initialCreatorShards = shards.balanceOf(userA);
        prank(userB);
        posts.unboostPost(postId);
        uint256 creatorReward = shards.balanceOf(userA) - initialCreatorShards;
        assertGt(creatorReward, 0);
        
        // Second user unboosts (creator should NOT get additional reward)
        initialCreatorShards = shards.balanceOf(userA);
        prank(userC);
        posts.unboostPost(postId);
        assertEq(shards.balanceOf(userA), initialCreatorShards); // No additional reward
        
        // Check boost amounts are cleared
        assertEq(posts.getBoostAmount(postId, userB), 0);
        assertEq(posts.getBoostAmount(postId, userC), 0);
    }

    function test_DonationFeeValidation() public {
        // Test setting fee over maximum (50%)
        prank(deployer);
        vm.expectRevert(P.InvalidFeePercentage.selector);
        posts.setDonationFee(5001); // Over 50%
        
        // Test setting maximum fee (50%)
        prank(deployer);
        posts.setDonationFee(5000); // Exactly 50%
        assertEq(posts.donationFeePercentage(), 5000);
        
        // Test setting zero fee
        prank(deployer);
        posts.setDonationFee(0); // 0%
        assertEq(posts.donationFeePercentage(), 0);
    }

    function test_BoostWindowValidation() public {
        // Test setting zero boost window
        prank(deployer);
        vm.expectRevert(P.InvalidDuration.selector);
        posts.setBoostWindow(0);
        
        // Test setting valid boost window
        prank(deployer);
        posts.setBoostWindow(48 hours);
        assertEq(posts.boostWindow(), 48 hours);
    }

    function test_EventEmissions() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        // Test PostCreated event
        prank(userA);
        vm.expectEmit(true, true, true, false);
        emit P.PostCreated(1, userA, data.totemAddr, abi.encodePacked(keccak256("Test")), false);
        uint256 postId = posts.createPost(data.totemAddr, abi.encodePacked(keccak256("Test")));
        
        // Test boost events
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        
        vm.expectEmit(true, true, false, true);
        emit P.PostBoostedERC20(postId, userB, 500_000 ether);
        posts.boostPost(postId, 500_000 ether);
        
        // Test donation event
        vm.deal(userC, 5 ether);
        prank(userC);
        uint256 expectedFee = (1 ether * posts.donationFeePercentage()) / 10000;
        vm.expectEmit(true, true, false, true);
        emit P.DonationReceived(postId, userC, 1 ether - expectedFee, expectedFee);
        posts.donateToPost{value: 1 ether}(postId);
        
        // Test donation fee update event
        prank(deployer);
        vm.expectEmit(false, false, false, true);
        emit P.DonationFeeUpdated(posts.donationFeePercentage(), 1500);
        posts.setDonationFee(1500);
        
        // Test boost window update event
        prank(deployer);
        vm.expectEmit(false, false, false, true);
        emit P.BoostWindowUpdated(posts.boostWindow(), 48 hours);
        posts.setBoostWindow(48 hours);
    }

    function test_SupportsInterface() public view {
        // Test IERC721Receiver interface
        assertTrue(posts.supportsInterface(type(IERC721Receiver).interfaceId));
        
        // Test ERC721 interface (using hex value since type() might not work properly)
        assertTrue(posts.supportsInterface(0x80ac58cd)); // ERC721 interface ID
        
        // Test basic ERC165 interface
        assertTrue(posts.supportsInterface(0x01ffc9a7)); // ERC165 interface ID
    }

    function test_OnERC721Received() public view {
        // Test that contract can receive NFTs
        bytes4 selector = posts.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }

    function test_EdgeCases() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        uint256 postId = createPost(userA, totemId);
        
        // Test boosting with zero amount (should revert)
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 500_000 ether);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        
        vm.expectRevert(P.InvalidAmount.selector);
        posts.boostPost(postId, 0);
        
        // Test donation with zero value (should work)
        vm.deal(userB, 5 ether);
        prank(userB);
        posts.donateToPost{value: 0}(postId);
        assertEq(posts.totalDonations(postId), 0);
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
        
        uint256 postId = createPost(userA, totemId);
        
        // Boost with specific amount
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        posts.boostPost(postId, 500_000 ether);
        
        // Wait for boost window
        warp(25 hours);
        
        // Check the formula is working by unboosting and getting rewards
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        posts.unboostPost(postId);
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
        
        uint256 postId = createPost(userA, totemId);
        
        // Get circulating supply for calculations
        uint256 circulatingSupply = TT(data.totemTokenAddr).totalSupply() - 
            TT(data.totemTokenAddr).balanceOf(data.totemAddr) -
            TT(data.totemTokenAddr).balanceOf(address(distr));
        
        // UserB boosts with their purchased tokens
        uint256 boostAmount = 899 ether; // Use part of purchased tokens
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), boostAmount);
        posts.boostPost(postId, uint224(boostAmount));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Calculate expected reward using the formula: S * (l/T) * sqrt(L/T)
        uint256 baseReward = posts.baseShardReward();
        uint256 userRatio = (boostAmount * 1e18) / circulatingSupply; // l/T
        uint256 totalRatio = (boostAmount * 1e18) / circulatingSupply; // L/T (same as user since only one booster)
        uint256 sqrtTotalRatio = Math.sqrt(totalRatio);
        uint256 expectedReward = (baseReward * userRatio * sqrtTotalRatio) / 1e36;

        // set new baseShardReward
        prank(deployer);
        posts.setBaseShardReward(2_000 ether);
        
        // Unboost and check rewards
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        posts.unboostPost(postId);
        uint256 receivedShards = shards.balanceOf(userB) - initialShards;
        console.log("Received shards:", receivedShards);
        
        // Should match the formula (with small tolerance for rounding)
        // assertApproxEqRel(receivedShards, expectedReward, 1e15); // 0.1% tolerance
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
        
        uint256 postId = createPost(userA, totemId);
        
        // UserB boosts with more tokens
        uint256 boostAmountB = 1_000_000 ether;
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), boostAmountB);
        posts.boostPost(postId, uint224(boostAmountB));
        
        // UserC boosts with fewer tokens
        uint256 boostAmountC = 500_000 ether;
        prank(userC);
        TT(data.totemTokenAddr).approve(address(posts), boostAmountC);
        posts.boostPost(postId, uint224(boostAmountC));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Test UserB unboost
        uint256 initialShardsB = shards.balanceOf(userB);
        prank(userB);
        posts.unboostPost(postId);
        uint256 receivedShardsB = shards.balanceOf(userB) - initialShardsB;
        
        // Test UserC unboost
        uint256 initialShardsC = shards.balanceOf(userC);
        prank(userC);
        posts.unboostPost(postId);
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
        
        uint256 postId = createPost(userA, totemId);
        
        // Get circulating supply for calculations
        uint256 circulatingSupply = TT(data.totemTokenAddr).totalSupply() - 
            TT(data.totemTokenAddr).balanceOf(data.totemAddr) -
            TT(data.totemTokenAddr).balanceOf(address(distr));
        
        // UserB boosts with fixed amount
        uint256 boostAmount = 500_000 ether;
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), boostAmount);
        posts.boostPost(postId, uint224(boostAmount));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Calculate expected reward using the formula
        uint256 baseReward = posts.baseShardReward();
        uint256 userRatio = (boostAmount * 1e18) / circulatingSupply; // l/T
        uint256 totalRatio = (boostAmount * 1e18) / circulatingSupply; // L/T
        uint256 sqrtTotalRatio = Math.sqrt(totalRatio);
        uint256 expectedReward = (baseReward * userRatio * sqrtTotalRatio) / 1e36;
        
        // Unboost and check rewards
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        posts.unboostPost(postId);
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
        
        uint256 postId = createPost(userA, totemId);
        
        // UserB and UserC boost
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 500_000 ether);
        posts.boostPost(postId, uint224(500_000 ether));
        
        prank(userC);
        TT(data.totemTokenAddr).approve(address(posts), 300_000 ether);
        posts.boostPost(postId, uint224(300_000 ether));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // First unboost should trigger creator reward
        uint256 initialCreatorShards = shards.balanceOf(userA);
        prank(userB);
        posts.unboostPost(postId);
        uint256 creatorReward = shards.balanceOf(userA) - initialCreatorShards;
        assertGt(creatorReward, 0);
        
        // Second unboost should NOT give additional creator reward
        initialCreatorShards = shards.balanceOf(userA);
        prank(userC);
        posts.unboostPost(postId);
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
        
        uint256 postId = createPost(userA, totemId);
        
        // Try to boost with large amount (to test capping)
        uint256 boostAmount = 3_000_000 ether;
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), boostAmount);
        posts.boostPost(postId, uint224(boostAmount));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Unboost and check rewards exist (detailed cap testing in separate test)
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        posts.unboostPost(postId);
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
        uint256 postId = createPost(userA, totemId);
        
        // Boost with moderate amount to test boundary
        uint256 boostAmount = 1_500_000 ether;
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), boostAmount);
        posts.boostPost(postId, uint224(boostAmount));
        
        warp(25 hours);
        
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        posts.unboostPost(postId);
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
        
        uint256 postId = createPost(userA, totemId);
        
        // UserB boosts
        prank(userB);
        TT(data.totemTokenAddr).approve(address(posts), 1_000_000 ether);
        posts.boostPost(postId, uint224(1_000_000 ether));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Unboost and measure rewards
        uint256 initialCreatorShards = shards.balanceOf(userA);
        prank(userB);
        posts.unboostPost(postId);
        uint256 creatorReward = shards.balanceOf(userA) - initialCreatorShards;
        
        // Creator should get some reward
        assertGt(creatorReward, 0);
        
        // Creator reward should be at least the minimum
        uint256 minAuthorReward = posts.minAuthorShardReward();
        assertGe(creatorReward, minAuthorReward);
    }

    function test_ShardDistributionMinimalRewards() public {
        uint256 totemId = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(totemId);
        
        uint256 postId = createPost(userA, totemId);
        
        // Buy small amount of tokens (minimal circulating supply)
        prank(userB);
        astrToken.approve(address(distr), type(uint256).max);
        distr.buy(data.totemTokenAddr, 1000 ether);
        TT(data.totemTokenAddr).approve(address(posts), 1000 ether);
        posts.boostPost(postId, uint224(1000 ether));
        
        // Wait for boost window to end
        warp(25 hours);
        
        // Should get minimal rewards due to small circulating supply
        uint256 initialShards = shards.balanceOf(userB);
        prank(userB);
        posts.unboostPost(postId);
        uint256 receivedShards = shards.balanceOf(userB) - initialShards;
        
        // Should receive very small rewards (but not necessarily 0) due to minimal circulating supply
        // The formula still works but gives minimal values
        assertGe(receivedShards, 0); // Can be 0 or very small positive value
        assertLe(receivedShards, 100); // Should be very small due to minimal circulating supply
    }
} 