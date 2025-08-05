// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract BoostSystemTest is Base {

    function test_Mix() public {
        // Scenario: user creates a totem, then performs a regular boost, 
        // then a day passes and they boost again. We verify that exactly 
        // 2 times the base merit reward was awarded. Then another day passes, 
        // user boosts again and we verify that merit was awarded with streak bonus.

        // Step 1: User creates a totem
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Step 2: Buy totem tokens for userB (so they can boost)
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Buy all remaining tokens to register the totem
        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 meritBefore;
        uint256 meritAfter;

        // Step 3: Day 1 - First regular totem boost (base reward = 100 points)
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        assertEq(meritAfter - meritBefore, 100, "First boost should give base reward of 100 merit points");

        // Step 4: Day passes, Day 2 - Second regular totem boost 
        // (already with streak bonus: 105% of base = 105 points)
        warp(1 days);
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        assertEq(meritAfter - meritBefore, 105, "Second boost should give 105 merit points (5% streak bonus)");

        // Step 5: Another day passes, Day 3 - Third boost with even bigger streak bonus 
        // (110% of base = 110 points)
        warp(1 days);
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        assertEq(meritAfter - meritBefore, 110, "Third boost should give 110 merit points (10% streak bonus)");

        // Additional verification: ensure streak is actually working
        (uint256 streakDays, uint256 streakMultiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streakDays, 3, "Should have 3-day streak");
        assertEq(streakMultiplier, 110, "Should have 110% multiplier (10% bonus)");
    }

    function test_PremiumBoostExtendsStreak() public {
        // Scenario: user creates a totem, performs a regular boost, then a premium boost,
        // and we verify that premium boost extends streak just like regular boost

        // Step 1: Create totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 meritBefore;
        uint256 meritAfter;

        // Step 2: Day 1 - Regular boost (base reward = 100 points)
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        assertEq(meritAfter - meritBefore, 100, "First daily boost should give base reward of 100 merit points");

        // Check streak after first boost
        (uint256 streakDays, uint256 streakMultiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streakDays, 1, "Should have 1-day streak after first boost");
        assertEq(streakMultiplier, 100, "Should have 100% multiplier (no bonus yet)");

        // Step 3: Day 2 - Premium boost instead of regular (should extend streak)
        warp(1 days);
        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 1 ether);
        
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        // Execute VRF request to get reward
        mockVRFCoordinator.fulfillRandomWords(1);
        
        meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        
        // Premium boost should give reward with streak consideration (105% of base for premium boost)
        // Minimum premium boost reward 500 points * 1.05 = 525 points
        assertGe(meritAfter - meritBefore, 525, "Premium boost should give at least 525 merit points with streak bonus");

        // Check that streak continued
        (streakDays, streakMultiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streakDays, 2, "Should have 2-day streak after premium boost");
        assertEq(streakMultiplier, 105, "Should have 105% multiplier (5% bonus)");

        // Step 4: Day 3 - Regular boost again (should extend streak further)
        warp(1 days);
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        
        // Regular boost with 3-day streak: 100 * 1.10 = 110 points
        assertEq(meritAfter - meritBefore, 110, "Third boost should give 110 merit points (10% streak bonus)");

        // Final streak verification
        (streakDays, streakMultiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streakDays, 3, "Should have 3-day streak after mixing daily and premium boosts");
        assertEq(streakMultiplier, 110, "Should have 110% multiplier (10% bonus)");
    }

    function test_BadgeMintingForStreakMilestones() public {
        // Scenario: Test NFT badge minting for streak milestones (7, 14, 30 days)
        // Also test that badges are earned per totem separately

        // Step 1: Create first totem and buy tokens
        uint256 totemId1 = createTotem(userA);
        TF.TotemData memory totemData1 = factory.getTotemData(totemId1);

        prank(userB);
        uint256 available1 = distr.getAvailableTokensForPurchase(
            userB,
            totemData1.totemTokenAddr
        );
        paymentToken.approve(address(distr), available1);
        distr.buy(totemData1.totemTokenAddr, available1);
        buyAllTotemTokens(totemData1.totemTokenAddr);

        // Step 2: Create second totem for parallel streak testing
        uint256 totemId2 = createTotem(userC);
        TF.TotemData memory totemData2 = factory.getTotemData(totemId2);

        prank(userB);
        uint256 available2 = distr.getAvailableTokensForPurchase(
            userB,
            totemData2.totemTokenAddr
        );
        paymentToken.approve(address(distr), available2);
        distr.buy(totemData2.totemTokenAddr, available2);
        buyAllTotemTokens(totemData2.totemTokenAddr);

        // Step 3: Build 6-day streak on first totem (not yet 7 days)
        for (uint256 i = 0; i < 6; i++) {
            performBoost(userB, totemData1.totemAddr);
            if (i < 5) warp(1 days);
        }

        // Step 4: Check that user cannot mint 7-day badge yet
        assertEq(boostSystem.getAvailableBadges(userB, 7), 0, "Should not have 7-day badge available before 7th boost");
        
        // Try to mint - should fail
        vm.expectRevert(BoostSystem.MilestoneNotAchieved.selector);
        prank(userB);
        boostSystem.mintBadge(7);

        // Step 5: Day 7 - Perform 7th boost to achieve 7-day milestone
        warp(1 days);
        performBoost(userB, totemData1.totemAddr);

        // Check that 7-day badge is now available
        assertEq(boostSystem.getAvailableBadges(userB, 7), 1, "Should have 1 available 7-day badge after 7th boost");

        // Mint the 7-day badge
        prank(userB);
        boostSystem.mintBadge(7);

        // Check that badge is no longer available after minting
        assertEq(boostSystem.getAvailableBadges(userB, 7), 0, "Should have 0 available 7-day badges after minting");

        // Try to mint again - should fail
        vm.expectRevert(BoostSystem.MilestoneNotAchieved.selector);
        prank(userB);
        boostSystem.mintBadge(7);

        // Step 6: Continue streak for 6 more days (total 13 days, not yet 14)
        for (uint256 i = 0; i < 6; i++) {
            warp(1 days);
            performBoost(userB, totemData1.totemAddr);
        }

        // Check that 14-day badge is not available yet
        assertEq(boostSystem.getAvailableBadges(userB, 14), 0, "Should not have 14-day badge available at day 13");

        // Try to mint 14-day badge - should fail
        vm.expectRevert(BoostSystem.MilestoneNotAchieved.selector);
        prank(userB);
        boostSystem.mintBadge(14);

        // Step 7: Day 14 - Perform 14th boost to achieve 14-day milestone
        warp(1 days);
        performBoost(userB, totemData1.totemAddr);

        // Check that 14-day badge is now available
        assertEq(boostSystem.getAvailableBadges(userB, 14), 1, "Should have 1 available 14-day badge after 14th boost");

        // Mint the 14-day badge
        prank(userB);
        boostSystem.mintBadge(14);

        // Check that badge is no longer available after minting
        assertEq(boostSystem.getAvailableBadges(userB, 14), 0, "Should have 0 available 14-day badges after minting");

        // Step 8: Continue streak to 30 days
        for (uint256 i = 0; i < 16; i++) {
            warp(1 days);
            performBoost(userB, totemData1.totemAddr);
        }

        // Check that 30-day badge is now available
        assertEq(boostSystem.getAvailableBadges(userB, 30), 1, "Should have 1 available 30-day badge after 30th boost");

        // Mint the 30-day badge
        prank(userB);
        boostSystem.mintBadge(30);

        // Check that badge is no longer available after minting
        assertEq(boostSystem.getAvailableBadges(userB, 30), 0, "Should have 0 available 30-day badges after minting");

        // Step 9: Test parallel streak on second totem (7 days)
        for (uint256 i = 0; i < 7; i++) {
            performBoost(userB, totemData2.totemAddr);
            if (i < 6) warp(1 days);
        }

        // Check that another 7-day badge is available (separate totem)
        assertEq(boostSystem.getAvailableBadges(userB, 7), 1, "Should have 1 available 7-day badge from second totem");

        // Mint the second 7-day badge
        prank(userB);
        boostSystem.mintBadge(7);

        // Verify final state
        assertEq(boostSystem.getAvailableBadges(userB, 7), 0, "Should have 0 available 7-day badges after minting second one");
        assertEq(boostSystem.getAvailableBadges(userB, 14), 0, "Should have 0 available 14-day badges");
        assertEq(boostSystem.getAvailableBadges(userB, 30), 0, "Should have 0 available 30-day badges");

        // Verify streak info for both totems
        (uint256 streakDays1, , ) = boostSystem.getStreakInfo(userB, totemData1.totemAddr);
        (uint256 streakDays2, , ) = boostSystem.getStreakInfo(userB, totemData2.totemAddr);
        
        assertEq(streakDays1, 30, "First totem should have 30-day streak");
        assertEq(streakDays2, 7, "Second totem should have 7-day streak");
    }

    function test_ComplexGraceDayScenarios() public {
        // Test grace day functionality with premium boosts
        
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);
        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriodNum = mm.currentPeriod();
        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 10 ether);

        // Step 1: Do premium boost to earn grace day
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(1);

        // Check grace day earned
        (, , , , uint256 graceDaysEarned, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned, 1, "Should have 1 grace day from premium boost");

        // Step 2: Build a short streak with daily boosts
        for (uint256 i = 0; i < 3; i++) {
            warp(1 days);
            performBoost(userB, totemData.totemAddr);
        }

        // Step 3: Skip more than 2 days to require grace day usage
        warp(2 days);
        uint256 meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        uint256 meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        
        // Should maintain streak and increment to 5th day (20% bonus = 120 points)
        assertEq(meritAfter - meritBefore, 120, "Should maintain streak bonus with grace day");

        // Check grace day was used
        (, , , , uint256 graceDaysEarnedB, uint256 graceDaysWasted, , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysWasted, 1, "Should have used 1 grace day");
        assertEq(graceDaysEarnedB, 1, "Should have earned 1 grace day");

        // warp(3 days);

        // meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        // performBoost(userB, totemData.totemAddr);
        // meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        // console.log(meritAfter - meritBefore);

        // Step 4: Skip another day without grace days - streak should break
        warp(2 days);
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        
        // Should be back to base reward (streak broken)
        assertEq(meritAfter - meritBefore, 100, "Streak should be broken without grace days");

        // Verify streak reset
        (uint256 streakDays, uint256 streakMultiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streakDays, 1, "Should have new 1-day streak");
        assertEq(streakMultiplier, 100, "Should have base multiplier");
    }

    function test_GraceDayEdgeCases() public {
        // Test edge cases for grace day system
        
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);
        buyAllTotemTokens(totemData.totemTokenAddr);

        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 5 ether);

        // Edge Case 1: Premium boost exactly at 24-hour boundary
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        // Wait exactly 24 hours
        warp(24 hours);
        
        // Should earn another grace day
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        (, , , , uint256 graceDaysEarned, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned, 2, "Should earn grace day at exactly 24-hour boundary");

        // Edge Case 2: Premium boost just before 24-hour boundary
        warp(23 hours + 59 minutes);
        
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        (, , , , graceDaysEarned, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned, 2, "Should not earn grace day before 24-hour boundary");

        // Edge Case 3: Multiple premium boosts in same day
        for (uint256 i = 0; i < 5; i++) {
            prank(userB);
            boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        }
        
        (, , , , graceDaysEarned, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned, 2, "Multiple premium boosts in same day should not earn additional grace days");
    }

    function test_dailyBoost_basicFunctionality() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Buy all remaining tokens to register totem
        buyAllTotemTokens(totemData.totemTokenAddr);

        // Test boost once per 24 hours
        performBoost(userB, totemData.totemAddr);
        
        // Try to boost again immediately - should fail
        vm.expectRevert(BoostSystem.NotEnoughTimePassedForFreeBoost.selector);
        performBoostNoWait(userB, totemData.totemAddr);

        // Wait 24 hours and boost again - should succeed
        warp(1 days);
        performBoost(userB, totemData.totemAddr);
    }

    function test_dailyBoost_meritPointsReward() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 initialMerit = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );

        performBoost(userB, totemData.totemAddr);

        uint256 finalMerit = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );

        // Should receive base reward (100 merit points by default)
        assertEq(finalMerit - initialMerit, 100, "Should receive base merit points");
    }

    function test_dailyBoost_requiresTokens() public {
        // Create a totem but don't buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Try to boost without tokens - should fail
        vm.expectRevert(BoostSystem.NotEnoughTokens.selector);
        performBoostNoWait(userB, totemData.totemAddr);
    }

    function test_dailyBoost_separateWindowPerTotem() public {
        // Create two totems
        uint256 totemId1 = createTotem(userA);
        uint256 totemId2 = createTotem(userC);
        TF.TotemData memory totemData1 = factory.getTotemData(totemId1);
        TF.TotemData memory totemData2 = factory.getTotemData(totemId2);

        // Buy tokens for both totems
        prank(userB);
        uint256 available1 = distr.getAvailableTokensForPurchase(
            userB,
            totemData1.totemTokenAddr
        );
        paymentToken.approve(address(distr), available1);
        distr.buy(totemData1.totemTokenAddr, available1);

        uint256 available2 = distr.getAvailableTokensForPurchase(
            userB,
            totemData2.totemTokenAddr
        );
        paymentToken.approve(address(distr), available2);
        distr.buy(totemData2.totemTokenAddr, available2);

        buyAllTotemTokens(totemData1.totemTokenAddr);
        buyAllTotemTokens(totemData2.totemTokenAddr);

        // Boost first totem
        performBoost(userB, totemData1.totemAddr);

        // Should be able to boost second totem immediately (separate windows)
        performBoost(userB, totemData2.totemAddr);

        // Should not be able to boost first totem again
        vm.expectRevert(BoostSystem.NotEnoughTimePassedForFreeBoost.selector);
        performBoostNoWait(userB, totemData1.totemAddr);

        // Should not be able to boost second totem again
        vm.expectRevert(BoostSystem.NotEnoughTimePassedForFreeBoost.selector);
        performBoostNoWait(userB, totemData2.totemAddr);
    }

    function test_dailyBoost_streakGrowth() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriodNum = mm.currentPeriod();

        // Day 1: Base reward (100 points)
        uint256 merit1 = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        uint256 reward1 = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum) - merit1;
        assertEq(reward1, 100, "Day 1 should have base reward");

        // Day 2: 105% of base (105 points)
        warp(1 days);
        uint256 merit2 = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        uint256 reward2 = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum) - merit2;
        assertEq(reward2, 105, "Day 2 should have 105% of base reward");

        // Day 3: 110% of base (110 points)
        warp(1 days);
        uint256 merit3 = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        uint256 reward3 = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum) - merit3;
        assertEq(reward3, 110, "Day 3 should have 110% of base reward");
    }



    function test_dailyBoost_streakMaxBonus() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Boost for 30 days to reach maximum bonus
        for (uint256 i = 0; i < 30; i++) {
            performBoost(userB, totemData.totemAddr);
            if (i < 29) warp(1 days);
        }

        // Day 30: Should have 245% of base (245 points), but may have Mythum multiplier applied
        // Get the current period after all the time warping
        uint256 finalPeriodNum = mm.currentPeriod();
        uint256 meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, finalPeriodNum);
        warp(1 days);
        performBoost(userB, totemData.totemAddr);
        uint256 finalPeriodAfterBoost = mm.currentPeriod();
        uint256 reward = mm.getTotemMeritPoints(totemData.totemAddr, finalPeriodAfterBoost) - meritBefore;
        
        // Check if we're in Mythum period (which applies 1.5x multiplier)
        if (mm.isMythum()) {
            // During Mythum: 245 * 1.5 = 367.5 (rounded to 367)
            assertEq(reward, 367, "Day 31+ should have maximum 245% of base reward with Mythum multiplier");
        } else {
            // Normal period: just the streak multiplier
            assertEq(reward, 245, "Day 31+ should have maximum 245% of base reward");
        }
    }

    function test_dailyBoost_streakReset() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriodNum = mm.currentPeriod();

        // Build a 3-day streak
        performBoost(userB, totemData.totemAddr);
        warp(1 days);
        performBoost(userB, totemData.totemAddr);
        warp(1 days);
        performBoost(userB, totemData.totemAddr);

        // Wait more than 48 hours (2 boost intervals) to break streak
        warp(3 days);

        // Next boost should reset to base reward
        uint256 meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        uint256 reward = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum) - meritBefore;
        assertEq(reward, 100, "After streak break, should return to base reward");
    }

    function test_dailyBoost_graceDaysFrom30DayStreak() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Build a 30-day streak
        for (uint256 i = 0; i < 30; i++) {
            performBoost(userB, totemData.totemAddr);
            if (i < 29) warp(1 days);
        }

        // Skip one day to trigger grace day calculation (this will calculate grace days from the 30-day streak)
        warp(2 days);
        performBoost(userB, totemData.totemAddr);

        // Check grace days earned (should be 1 from the 30-day streak)
        (, , , , uint256 graceDaysEarned, uint256 graceDaysWasted, , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned, 1, "Should earn 1 grace day after 30-day streak");
        assertEq(graceDaysWasted, 1, "Should have used 1 grace day");

        // Skip another day - streak should break now (no more grace days)
        warp(2 days);
        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        uint256 reward = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum) - meritBefore;
        assertEq(reward, 100, "After using all grace days, streak should reset");
    }

    function test_dailyBoost_graceDaysFrom60DayStreak() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Build a 60-day streak
        for (uint256 i = 0; i < 60; i++) {
            performBoost(userB, totemData.totemAddr);
            if (i < 59) warp(1 days);
        }

        // Skip one day to trigger grace day calculation (this will calculate grace days from the 60-day streak)
        warp(2 days);
        performBoost(userB, totemData.totemAddr);

        // Check grace days earned (should be 2: one at 30 days, one at 60 days)
        (, , , , uint256 graceDaysEarned, uint256 graceDaysWasted, , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned, 2, "Should earn 2 grace days after 60-day streak");
        assertEq(graceDaysWasted, 1, "Should have used 1 grace day");

        // Skip another day (use second grace day)
        warp(2 days);
        performBoost(userB, totemData.totemAddr);

        // Check grace days wasted
        (, , , , , graceDaysWasted, , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysWasted, 2, "Should have used 2 grace days");

        // Skip another day - streak should break now (no more grace days)
        warp(2 days);
        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        performBoost(userB, totemData.totemAddr);
        uint256 reward = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum) - meritBefore;
        assertEq(reward, 100, "After using all grace days, streak should reset");
    }

    // PREMIUM BOOST TESTS

    function test_premiumBoost_basicFunctionality() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Get premium boost price
        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        
        // Use the stored MockVRFCoordinator instance
        
        // Perform premium boost
        vm.deal(userB, 1 ether);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        // Manually fulfill the VRF request
        mockVRFCoordinator.fulfillRandomWords(1);

        // Should be able to do another premium boost immediately
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        // Manually fulfill the second VRF request
        mockVRFCoordinator.fulfillRandomWords(2);
    }

    function test_premiumBoost_requiresPayment() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Try premium boost without payment - should fail
        prank(userB);
        vm.expectRevert(BoostSystem.InsufficientPayment.selector);
        boostSystem.premiumBoost{value: 0}(totemData.totemAddr);
    }

    function test_premiumBoost_requiresTokens() public {
        // Create a totem but don't buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        
        // Try premium boost without tokens - should fail
        vm.deal(userB, 1 ether);
        prank(userB);
        vm.expectRevert(BoostSystem.NotEnoughTokens.selector);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
    }

    function test_premiumBoost_paymentToTreasury() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        (uint256 price, address treasuryAddr) = boostSystem.getPremiumBoostConfig();
        uint256 treasuryBalanceBefore = treasuryAddr.balance;

        // Perform premium boost
        vm.deal(userB, 1 ether);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);

        uint256 treasuryBalanceAfter = treasuryAddr.balance;
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, price, "Treasury should receive payment");
    }

    function test_premiumBoost_excessPaymentReturned() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        uint256 overpayment = price + 0.1 ether;
        
        vm.deal(userB, 1 ether);
        uint256 userBalanceBefore = userB.balance;
        
        prank(userB);
        boostSystem.premiumBoost{value: overpayment}(totemData.totemAddr);

        uint256 userBalanceAfter = userB.balance;
        assertEq(userBalanceBefore - userBalanceAfter, price, "User should only pay the required price");
    }

    function test_premiumBoost_extendsStreak() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Start with daily boost
        performBoost(userB, totemData.totemAddr);
        
        // Next day, use premium boost instead of daily boost
        warp(1 days);
        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 1 ether);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        // Execute VRF callback to complete the premium boost
        mockVRFCoordinator.fulfillRandomWords(1);

        // Check that streak continues (should be day 2)
        (uint256 streakDays, uint256 streakMultiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streakDays, 2, "Premium boost should extend streak");
        assertEq(streakMultiplier, 105, "Should have day 2 multiplier");
    }

    function test_premiumBoost_graceDayOnFirstUsePerDay() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 2 ether);

        // First premium boost - should earn grace day
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        (, , , , uint256 graceDaysEarned1, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned1, 1, "Should earn 1 grace day on first premium boost");

        // Second premium boost immediately - should not earn another grace day
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        (, , , , uint256 graceDaysEarned2, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned2, 1, "Should not earn additional grace day on same day");

        // Wait 24 hours and do another premium boost - should earn another grace day
        warp(1 days);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        (, , , , uint256 graceDaysEarned3, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDaysEarned3, 2, "Should earn grace day after 24 hours");
    }

    function test_premiumBoost_allowsEveryOtherDayVisits() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 10 ether);

        uint256 currentPeriodNum = mm.currentPeriod();

        // Day 1: Premium boost
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(1);

        // Day 3: Premium boost (skip day 2)
        warp(2 days);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(2);

        // Should still have streak (grace day should cover the gap)
        uint256 meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        
        // Day 5: Premium boost (skip day 4)
        warp(2 days);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(3);
        
        uint256 meritAfter = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        
        // Should have streak bonus (not base reward)
        assertGt(meritAfter - meritBefore, 500, "Should have streak bonus from premium boost");
    }

    // NFT TOTEM TESTS

    function test_dailyBoost_withNFTTotem_Basic() public {
        uint256 totemId = createTotemWithNFT(userA);

        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Mint NFT to userB
        MockERC721(totemData.totemTokenAddr).mint(userB, 1);

        // Should be able to boost with NFT
        performBoost(userB, totemData.totemAddr);

        // Check merit points increased
        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 finalMerit = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );
        assertGt(finalMerit, 0, "Should receive merit points with NFT");
    }

    function test_dailyBoost_withNFTTotem_requiresNFT() public {
        uint256 totemId = createTotemWithNFT(userA);

        TF.TotemData memory totemData = factory.getTotemData(totemId);

        uint256 timestamp = block.timestamp;
        bytes memory signature = createBoostSignature(
            userB,
            totemData.totemAddr,
            timestamp
        );
        prank(userB);
        // Don't mint NFT to userB - should fail
        vm.expectRevert(BoostSystem.NotEnoughTokens.selector);
        boostSystem.boost(totemData.totemAddr, timestamp, signature);
    }

    // MILESTONE BADGE TESTS

    function test_milestones_7DayBadge() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Boost for 7 days
        for (uint256 i = 0; i < 7; i++) {
            performBoost(userB, totemData.totemAddr);
            if (i < 6) warp(1 days);
        }

        // Check 7-day badge is available
        uint256 availableBadges = boostSystem.getAvailableBadges(userB, 7);
        assertEq(availableBadges, 1, "Should have 1 seven-day badge available");

        // Mint the badge
        prank(userB);
        boostSystem.mintBadge(7);

        // Check badge was minted
        availableBadges = boostSystem.getAvailableBadges(userB, 7);
        assertEq(availableBadges, 0, "Should have 0 seven-day badges after minting");
    }

    function test_milestones_multipleBadges() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Boost for 30 days to get multiple milestones
        for (uint256 i = 0; i < 30; i++) {
            performBoost(userB, totemData.totemAddr);
            if (i < 29) warp(1 days);
        }

        // Check multiple badges are available
        assertEq(boostSystem.getAvailableBadges(userB, 7), 1, "Should have 7-day badge");
        assertEq(boostSystem.getAvailableBadges(userB, 14), 1, "Should have 14-day badge");
        assertEq(boostSystem.getAvailableBadges(userB, 30), 1, "Should have 30-day badge");
        assertEq(boostSystem.getAvailableBadges(userB, 100), 0, "Should not have 100-day badge");
    }

    function test_milestones_cannotMintWithoutAchievement() public {
        // Try to mint badge without achievement
        prank(userB);
        vm.expectRevert(BoostSystem.MilestoneNotAchieved.selector);
        boostSystem.mintBadge(7);
    }

    function test_milestones_invalidMilestone() public {
        // Try to mint badge for invalid milestone
        prank(userB);
        vm.expectRevert(BoostSystem.MilestoneNotAchieved.selector);
        boostSystem.mintBadge(5); // 5 is not a valid milestone
    }

    // MANAGER CONFIGURATION TESTS

    function test_manager_setBoostRewardPoints() public {
        uint256 newReward = 200;
        
        prank(deployer);
        boostSystem.setBoostRewardPoints(newReward);

        // Create a totem and test new reward
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 initialMerit = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );

        performBoost(userB, totemData.totemAddr);

        uint256 finalMerit = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );

        assertEq(finalMerit - initialMerit, newReward, "Should use new reward amount");
    }

    function test_manager_setPremiumBoostPrice() public {
        uint256 newPrice = 0.1 ether;
        
        prank(deployer);
        boostSystem.setPremiumBoostPrice(newPrice);

        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        assertEq(price, newPrice, "Should update premium boost price");
    }

    function test_manager_setFreeBoostCooldown() public {
        uint256 newCooldown = 12 hours;
        
        prank(deployer);
        boostSystem.setFreeBoostCooldown(newCooldown);

        assertEq(boostSystem.getFreeBoostCooldown(), newCooldown, "Should update free boost cooldown");
    }

    // SIGNATURE VERIFICATION TESTS

    function test_signature_expiredTimestamp() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Create signature with old timestamp
        uint256 oldTimestamp = block.timestamp - 10 minutes;
        bytes memory signature = createBoostSignature(
            userB,
            totemData.totemAddr,
            oldTimestamp
        );

        prank(userB);
        vm.expectRevert(BoostSystem.SignatureExpired.selector);
        boostSystem.boost(totemData.totemAddr, oldTimestamp, signature);
    }

    function test_signature_futureTimestamp() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Create signature with future timestamp
        uint256 futureTimestamp = block.timestamp + 10 minutes;
        bytes memory signature = createBoostSignature(
            userB,
            totemData.totemAddr,
            futureTimestamp
        );

        prank(userB);
        vm.expectRevert(BoostSystem.SignatureExpired.selector);
        boostSystem.boost(totemData.totemAddr, futureTimestamp, signature);
    }

    function test_signature_wrongSigner() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Create signature with wrong signer
        uint256 timestamp = block.timestamp;
        bytes32 messageHash = keccak256(
            abi.encodePacked(userB, totemData.totemAddr, timestamp)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        // Sign with wrong private key (userA instead of deployer)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            userAPrivateKey,
            ethSignedMessageHash
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        prank(userB);
        vm.expectRevert(BoostSystem.InvalidSignature.selector);
        boostSystem.boost(totemData.totemAddr, timestamp, signature);
    }

    // EDGE CASE TESTS

    function test_streakReset_afterLongBreak() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Build a streak
        performBoost(userB, totemData.totemAddr);
        warp(1 days);
        performBoost(userB, totemData.totemAddr);

        // Take a very long break (1 week)
        warp(7 days);

        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum);
        
        performBoost(userB, totemData.totemAddr);
        
        uint256 reward = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriodNum) - meritBefore;
        assertEq(reward, 100, "Should reset to base reward after long break");
    }

    function test_multipleUsers_separateStreaks() public {
        // Create a totem
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Both users buy tokens
        prank(userB);
        uint256 availableB = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), availableB);
        distr.buy(totemData.totemTokenAddr, availableB);

        prank(userC);
        uint256 availableC = distr.getAvailableTokensForPurchase(
            userC,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), availableC);
        distr.buy(totemData.totemTokenAddr, availableC);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // UserB builds a 3-day streak
        performBoost(userB, totemData.totemAddr);
        warp(1 days);
        performBoost(userB, totemData.totemAddr);
        warp(1 days);
        performBoost(userB, totemData.totemAddr);

        // UserC starts their streak
        performBoost(userC, totemData.totemAddr);

        // Check separate streak info
        (uint256 streakDaysB, uint256 streakMultiplierB, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        (uint256 streakDaysC, uint256 streakMultiplierC, ) = boostSystem.getStreakInfo(userC, totemData.totemAddr);

        assertEq(streakDaysB, 3, "UserB should have 3-day streak");
        assertEq(streakMultiplierB, 110, "UserB should have 110% multiplier");
        assertEq(streakDaysC, 1, "UserC should have 1-day streak");
        assertEq(streakMultiplierC, 100, "UserC should have 100% multiplier");
    }

    function test_premiumBoost_withStreakMultiplier() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        buyAllTotemTokens(totemData.totemTokenAddr);

        // Build a 2-day streak with daily boosts
        performBoost(userB, totemData.totemAddr);
        warp(1 days);
        performBoost(userB, totemData.totemAddr);

        // Use premium boost on day 3 - should get streak multiplier
        warp(1 days);
        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 1 ether);
        
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        
        // Execute VRF callback to complete the premium boost
        mockVRFCoordinator.fulfillRandomWords(1);

        // Note: Premium boost uses VRF so we can't test exact merit points
        // But we can verify the streak continues
        (uint256 streakDays, uint256 streakMultiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streakDays, 3, "Premium boost should continue streak");
        assertEq(streakMultiplier, 110, "Should have day 3 multiplier");
    }

    // BOOST FUNCTION TESTS

    function test_boost_success() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Buy all remaining tokens to register totem
        buyAllTotemTokens(totemData.totemTokenAddr);

        // Get initial merit points for current period
        uint256 currentPeriodNum = mm.currentPeriod();
        uint256 initialMerit = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );

        // Perform boost using helper function
        performBoost(userB, totemData.totemAddr);

        // Check merit points increased
        uint256 finalMerit = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );

        // console.log("final merit:", finalMerit);

        assertGt(
            finalMerit,
            initialMerit,
            "Merit points should increase after boost"
        );

        // Check boost data
        (uint256 lastBoostTimestamp, , , , , , , ) = boostSystem.getBoostData(
            userB,
            totemData.totemAddr
        );
        assertEq(
            lastBoostTimestamp,
            block.timestamp,
            "Last boost timestamp should be updated"
        );
    }

    function test_boost_revert_noTokens() public {
        // Create a totem but don't buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Create signature for boost
        uint256 timestamp = block.timestamp;
        bytes memory signature = createBoostSignature(
            userB,
            totemData.totemAddr,
            timestamp
        );

        // Try to boost without tokens - should revert
        prank(userB);
        vm.expectRevert(BoostSystem.NotEnoughTokens.selector);
        boostSystem.boost(totemData.totemAddr, timestamp, signature);
    }

    function test_boost_revert_invalidSignature() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Create invalid signature (wrong timestamp)
        uint256 timestamp = block.timestamp;
        bytes memory signature = createBoostSignature(
            userB,
            totemData.totemAddr,
            timestamp + 1
        );

        // Try to boost with invalid signature - should revert
        prank(userB);
        vm.expectRevert(BoostSystem.InvalidSignature.selector);
        boostSystem.boost(totemData.totemAddr, timestamp, signature);
    }

    function test_boost_revert_expiredSignature() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Move forward in time first, then create old timestamp
        warp(1 hours); // Move forward 1 hour
        uint256 timestamp = block.timestamp - 10 minutes; // Now this is safe
        bytes memory signature = createBoostSignature(
            userB,
            totemData.totemAddr,
            timestamp
        );

        // Try to boost with expired signature - should revert
        prank(userB);
        vm.expectRevert(BoostSystem.SignatureExpired.selector);
        boostSystem.boost(totemData.totemAddr, timestamp, signature);
    }

    function test_boost_revert_tooSoon() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Buy all remaining tokens to register totem
        buyAllTotemTokens(totemData.totemTokenAddr);

        // First boost
        performBoost(userB, totemData.totemAddr);

        // Try to boost again immediately - should revert
        warp(1 hours);
        uint256 timestamp2 = block.timestamp;
        bytes memory signature2 = createBoostSignature(
            userB,
            totemData.totemAddr,
            timestamp2
        );

        prank(userB);
        vm.expectRevert(BoostSystem.NotEnoughTimePassedForFreeBoost.selector);
        boostSystem.boost(totemData.totemAddr, timestamp2, signature2);
    }

    function test_boost_revert_signatureReuse() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Buy all remaining tokens to register totem
        buyAllTotemTokens(totemData.totemTokenAddr);

        // First boost
        uint256 timestamp = block.timestamp;
        bytes memory signature = createBoostSignature(
            userB,
            totemData.totemAddr,
            timestamp
        );
        prank(userB);
        boostSystem.boost(totemData.totemAddr, timestamp, signature);

        // Try to reuse the same signature - should revert
        vm.expectRevert(BoostSystem.SignatureAlreadyUsed.selector);
        boostSystem.boost(totemData.totemAddr, timestamp, signature);

        // Wait for boost interval
        warp(1 days);
        vm.expectRevert(BoostSystem.SignatureExpired.selector);
        boostSystem.boost(totemData.totemAddr, timestamp, signature);
    }

    function test_boost_streakMultiplier() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Buy all remaining tokens to register totem
        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriodNum = mm.currentPeriod();

        // First boost (day 1)
        uint256 initialMerit = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );
        performBoost(userB, totemData.totemAddr);
        uint256 firstBoostReward = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        ) - initialMerit;

        // Second boost (day 2)
        warp(1 days);
        uint256 meritBeforeSecond = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );
        performBoost(userB, totemData.totemAddr);
        uint256 secondBoostReward = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        ) - meritBeforeSecond;

        // Second boost should have 5% more reward (105% of base)
        uint256 expectedSecondReward = (firstBoostReward * 105) / 100;
        assertEq(
            secondBoostReward,
            expectedSecondReward,
            "Day 2 should have 105% of base reward"
        );

        // Third boost (day 3)
        warp(1 days);
        uint256 meritBeforeThird = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        );
        performBoost(userB, totemData.totemAddr);
        uint256 thirdBoostReward = mm.getTotemMeritPoints(
            totemData.totemAddr,
            currentPeriodNum
        ) - meritBeforeThird;

        // Third boost should have 10% more reward (110% of base)
        uint256 expectedThirdReward = (firstBoostReward * 110) / 100;
        assertEq(
            thirdBoostReward,
            expectedThirdReward,
            "Day 3 should have 110% of base reward"
        );
    }

    function test_boost_milestoneAchievement() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // Buy all remaining tokens to register totem
        buyAllTotemTokens(totemData.totemTokenAddr);

        // Boost for 7 days to achieve first milestone
        for (uint256 i = 0; i < 7; i++) {
            performBoost(userB, totemData.totemAddr);

            if (i < 6) {
                warp(1 days);
            }
        }

        // Check that milestone badge is available
        (bool canMint, uint256 reason) = boostSystem.canMintBadge(userB, 7);
        assertTrue(canMint, "Should be able to mint 7-day milestone badge");
        assertEq(reason, 0, "Should have no reason preventing mint");

        // Check boost data to verify streak
        (, , , uint256 streakStartPoint, , , , ) = boostSystem.getBoostData(
            userB,
            totemData.totemAddr
        );
        assertGt(streakStartPoint, 0, "Should have streak start point set");
    }

    function test_boost_badgeResetAfterStreakBreak() public {
        // Create a totem and buy tokens
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        // Buy totem tokens for userB
        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(
            userB,
            totemData.totemTokenAddr
        );
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);

        // make totem registered
        buyAllTotemTokens(totemData.totemTokenAddr);

        prank(userB);

        // First streak: boost for 7 days to achieve first milestone
        for (uint256 i = 0; i < 7; i++) {
            performBoost(userB, totemData.totemAddr);
            if (i < 6) {
                warp(1 days);
            }
        }

        // Check that 7-day milestone badge is available
        (bool canMint7, ) = boostSystem.canMintBadge(userB, 7);
        assertTrue(
            canMint7,
            "Should be able to mint 7-day milestone badge after first streak"
        );

        // Continue to 14 days
        for (uint256 i = 7; i < 14; i++) {
            warp(1 days);
            performBoost(userB, totemData.totemAddr);
        }

        // Check that 14-day milestone badge is available
        (bool canMint14, ) = boostSystem.canMintBadge(userB, 14);
        assertTrue(
            canMint14,
            "Should be able to mint 14-day milestone badge after first streak"
        );

        // Break the streak by waiting more than 2 boost intervals (48 hours)
        warp(3 days);

        // Start new streak - boost again
        performBoost(userB, totemData.totemAddr);

        // Check boost data - streak should be reset
        (, , , , , , uint256 releasedBadges, ) = boostSystem
            .getBoostData(userB, totemData.totemAddr);
        assertEq(
            releasedBadges,
            0,
            "Released badges should be reset to 0 after streak break"
        );

        // Continue new streak for 7 days
        for (uint256 i = 1; i < 7; i++) {
            warp(1 days);
            performBoost(userB, totemData.totemAddr);
        }

        // Check that 7-day milestone badge is available again (should be earned again)
        uint256 availableBadges7 = boostSystem.getAvailableBadges(userB, 7);
        assertGt(
            availableBadges7,
            0,
            "Should have 7-day badges available after new streak"
        );

        // Continue to 14 days in new streak
        for (uint256 i = 7; i < 14; i++) {
            warp(1 days);
            performBoost(userB, totemData.totemAddr);
        }

        // Check that 14-day milestone badge is available again
        uint256 availableBadges14 = boostSystem.getAvailableBadges(userB, 14);
        assertGt(
            availableBadges14,
            0,
            "Should have 14-day badges available after new streak"
        );

        // Verify that user now has multiple badges of each type
        assertGe(
            availableBadges7,
            2,
            "Should have at least 2 seven-day badges (from both streaks)"
        );
        assertGe(
            availableBadges14,
            2,
            "Should have at least 2 fourteen-day badges (from both streaks)"
        );
    }

    function test_PremiumBoostGraceDayComplexScenario() public {
        // Сценарий: юзер делает премиум буст, проходит 2 часа, после этого он делает еще один премиум буст,
        // мы проверяем что кол-во мерит увеличилось на правильное кол-во. Также мы проверяем что добавилось 1 грейс день.
        // Проходит 22 часа, юзер делает еще один премиум буст, мы проверяем что теперь у нас 2 грейс дня.
        // Проходит час, после этого пользователь успешно делает дейли буст, мы проверяем что стрик уже равен 4 
        // и пользователь получил 115 мерита.

        // Подготовка: создаем тотем и покупаем токены
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(userB, totemData.totemTokenAddr);
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);
        buyAllTotemTokens(totemData.totemTokenAddr);

        uint256 currentPeriod = mm.currentPeriod();
        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 10 ether);

        // Шаг 1: Первый премиум буст
        uint256 meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(1);
        
        // Проверяем мерит и грейс день
        assertGe(mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod) - meritBefore, 500, "First premium boost should give at least 500 merit points");
        (, , , , uint256 graceDays, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDays, 1, "Should have 1 grace day after first premium boost");
        (uint256 streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 1, "Should have 1-day streak after first premium boost");

        // Шаг 2: Проходит 2 часа, делаем второй премиум буст
        warp(2 hours);
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(2);

        // Проверяем мерит и грейс день (не должен добавиться)
        assertGe(mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod) - meritBefore, 500, "Second premium boost should give at least 500 merit points (no streak bonus yet)");
        (, , , , graceDays, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDays, 1, "Should still have only 1 grace day (less than 24 hours passed since first grace day)");
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 1, "Should still have 1-day streak (less than 24 hours passed since first boost)");

        // Шаг 3: Проходит 22 часа (итого 24 часа с момента первого буста), делаем третий премиум буст
        warp(22 hours);
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(3);

        // Проверяем мерит и грейс день (должен добавиться второй, стрик увеличится до 2)
        assertGe(mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod) - meritBefore, 525, "Third premium boost should give at least 525 merit points with streak bonus");
        (, , , , graceDays, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDays, 2, "Should have 2 grace days after third premium boost (24+ hours passed since first grace day)");
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 2, "Should have 2-day streak after third premium boost (24+ hours passed since first boost)");

        // Шаг 4: Проходит 1 час, делаем дейли буст
        warp(1 hours);
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod);
        performBoost(userB, totemData.totemAddr);

        // Проверяем финальный результат (стрик все еще 2, так как не прошло 24 часа с момента последнего увеличения стрика)
        assertEq(mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod) - meritBefore, 105, "Daily boost should give 105 merit points with 2-day streak bonus");
        uint256 multiplier;
        (streak, multiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 2, "Should still have 2-day streak after daily boost (less than 24 hours since last streak increment)");
        assertEq(multiplier, 105, "Should have 105% multiplier (5% bonus)");
        
        // Шаг 5: Проходит еще 23 часа (итого 48 часов с момента первого буста), делаем премиум буст
        warp(23 hours);
        meritBefore = mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(4);

        // Теперь стрик должен увеличиться до 3 (прошло 48 часов с момента первого буста)
        assertGe(mm.getTotemMeritPoints(totemData.totemAddr, currentPeriod) - meritBefore, 550, "Premium boost should give at least 550 merit points with 3-day streak bonus");
        (streak, multiplier, ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 3, "Should have 3-day streak after premium boost (48+ hours passed since first boost)");
        assertEq(multiplier, 110, "Should have 110% multiplier (10% bonus)");
        
        // Финальная проверка грейс дней
        (, , , , graceDays, , , ) = boostSystem.getBoostData(userB, totemData.totemAddr);
        assertEq(graceDays, 3, "Should have 3 grace days after premium boost (earned from 3 premium boosts with 24+ hour gaps)");
    }

    function test_StreakLogicAsDescribed() public {
        // Test exactly as described:
        // Premium boost, 2 hours later another premium boost (streak still 1),
        // 3 hours later another premium boost, 1 hour later daily boost (streak still 1),
        // 18 hours later daily boost (24 hours passed, streak becomes 2),
        // premium boost (streak still 2), 23 hours later premium boost (streak still 2),
        // 1 hour later (48 hours total) premium boost (streak becomes 3)

        // Setup
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);

        prank(userB);
        uint256 available = distr.getAvailableTokensForPurchase(userB, totemData.totemTokenAddr);
        paymentToken.approve(address(distr), available);
        distr.buy(totemData.totemTokenAddr, available);
        buyAllTotemTokens(totemData.totemTokenAddr);

        (uint256 price, ) = boostSystem.getPremiumBoostConfig();
        vm.deal(userB, 10 ether);

        // 1. First premium boost
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(1);
        
        (uint256 streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 1, "After first premium boost streak should be 1");

        // 2. 2 hours later another premium boost, streak still 1
        warp(2 hours);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(2);
        
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 1, "After second premium boost (2 hours later) streak should still be 1");

        // 3. 3 hours later another premium boost
        warp(3 hours);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(3);
        
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 1, "After third premium boost (3 hours later) streak should still be 1");

        // 4. 1 hour later daily boost, streak still 1
        warp(1 hours);
        performBoost(userB, totemData.totemAddr);
        
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 1, "After daily boost (1 hour later) streak should still be 1");

        // 5. 18 hours later daily boost (24 hours passed), streak becomes 2
        warp(18 hours);
        performBoost(userB, totemData.totemAddr);
        
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 2, "After daily boost (24 hours since last streak increment) streak should be 2");

        // 6. Premium boost - streak still 2
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(4);
        
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 2, "After premium boost streak should still be 2");

        // 7. 23 hours later premium boost, streak still 2
        warp(23 hours);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(5);
        
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 2, "After premium boost (23 hours later) streak should still be 2");

        // 8. 1 hour later (48 hours total) premium boost, streak becomes 3
        warp(1 hours);
        prank(userB);
        boostSystem.premiumBoost{value: price}(totemData.totemAddr);
        mockVRFCoordinator.fulfillRandomWords(6);
        
        (streak, , ) = boostSystem.getStreakInfo(userB, totemData.totemAddr);
        assertEq(streak, 3, "After premium boost (48 hours since last streak increment) streak should be 3");
    }
}