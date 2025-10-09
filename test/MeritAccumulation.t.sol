// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./Base.t.sol";
import {MeritManager} from "../src/MeritManager.sol";

contract MeritAccumulationTest is Base {
    function test_ChangingPeriodLength() public {
        printCurrentPeriod();
        warp(40 days);
        printCurrentPeriod();
        warp(400 days);

        prank(deployer);
        printCurrentPeriod();
        console.log("period duration:", mm.periodDuration());
        mm.setPeriodDuration(5 days);
        console.log("new period duration:", mm.periodDuration());
        printCurrentPeriod();
        warp(4 days);
        printCurrentPeriod();
        warp(1 days);
        printCurrentPeriod();

        // Logs:
        // Current period: 0
        // Current period: 1
        // Current period: 14
        // period duration: 2592000
        // new period duration: 432000
        // Current period: 14
        // Current period: 14
        // Current period: 15
    }

    function test_audit_ChangingPeriodLengthProblem() public {
        deal(userA, 1000 ether);
        deal(userB, 1000 ether);
        deal(userC, 1000 ether);

        prank(deployer);
        distr.setMaxTotemTokensPerAddress(1e36);

        vm.startPrank(userA);
        address[] memory myCollabs = new address [](1);
        myCollabs[0] = userC;
        astrToken.approve(address(factory), 5e18);
        factory.createTotem("SimpleTotem", "SIMPLE", "SMPL", myCollabs);
        vm.stopPrank();

        TF.TotemData memory data = factory.getTotemData(0);

        vm.startPrank(userB);
        paymentToken.approve(address(distr), paymentToken.balanceOf(userB));
        distr.buy(data.totemTokenAddr, 699_750_000e18);

        // 3 DAYS BOOST
        for(uint i = 1; i < 3; i++){
            uint consecutiveDays = i * 86400;
            bytes memory signature1001 = createBoostSignature(userB, data.totemAddr, consecutiveDays);

            vm.warp(consecutiveDays);
            boostSystem.boost(data.totemAddr, consecutiveDays, signature1001);
        }

        vm.stopPrank();


        vm.startPrank(deployer);
        mm.creditMerit(data.totemAddr, 1000);
        vm.warp(block.timestamp + 31 days);
        printCurrentPeriod();
        console.log("last processed period", mm.lastProcessedPeriod());
        mm.setPeriodDuration(20 days);
        printCurrentPeriod();
        console.log("last processed period", mm.lastProcessedPeriod());
        printCurrentPeriod();
        mm.updateState();

        console.log("totemMerit", mm.totemMerit(0, data.totemAddr));
        console.log("totemMeritPoints", mm.totalMeritPoints(0));
        console.log("releasedMytho", mm.releasedMytho(0));

        console.log("Totem pending reward:", mm.getPendingReward(data.totemAddr, 0));
        // vm.warp(block.timestamp + (367 days));
        // mm.updateState();
        // vm.stopPrank();
        

        // vm.startPrank(userA);
        // Totem(data.totemAddr).collectMYTH(0);
    }
    
    function test_MeritAccumulationBeforeFirstPeriod() public {
        // Create a totem
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);
        
        // At this point, startTime is already set in Base.t.sol setup
        // But let's check the current period
        uint256 initialPeriod = mm.currentPeriod();
        console.log("Initial period:", initialPeriod);
        
        // Credit some merit points
        prank(deployer);
        mm.grantRegistratorRole(deployer);
        mm.register(totemData.totemAddr);
        mm.creditMerit(totemData.totemAddr, 1000);
        
        // Check that merit points are in period 0
        assertEq(mm.getTotemMeritPoints(totemData.totemAddr, 0), 1000, "Merit should be in period 0");
        assertEq(mm.currentPeriod(), 0, "Should still be period 0");
        
        // Warp to 15 days after startTime (still period 0)
        vm.warp(block.timestamp + 15 days);
        
        // Credit more merit points
        prank(deployer);
        mm.creditMerit(totemData.totemAddr, 500);
        
        // Should still be period 0
        assertEq(mm.currentPeriod(), 0, "Should still be period 0 after 15 days");
        assertEq(mm.getTotemMeritPoints(totemData.totemAddr, 0), 1500, "Merit should accumulate in period 0");
        
        // Warp to 29 days after startTime (still period 0)
        vm.warp(block.timestamp + 14 days); // Total 29 days
        
        prank(deployer);
        mm.creditMerit(totemData.totemAddr, 300);
        
        assertEq(mm.currentPeriod(), 0, "Should still be period 0 after 29 days");
        assertEq(mm.getTotemMeritPoints(totemData.totemAddr, 0), 1800, "Merit should accumulate in period 0");
        
        // Warp to 31 days after startTime (now period 1)
        vm.warp(block.timestamp + 2 days); // Total 31 days
        
        assertEq(mm.currentPeriod(), 1, "Should be period 1 after 31 days");
        
        // Credit merit points in period 1
        prank(deployer);
        mm.creditMerit(totemData.totemAddr, 200);
        
        // Check that period 0 merit is unchanged and period 1 has new merit
        assertEq(mm.getTotemMeritPoints(totemData.totemAddr, 0), 1800, "Period 0 merit should be unchanged");
        assertEq(mm.getTotemMeritPoints(totemData.totemAddr, 1), 200, "Period 1 should have new merit");
    }
    
    function test_MeritAccumulationWithDelayedStartTime() public {
        // Deploy a fresh MeritManager without setting startTime
        MeritManager freshMM = new MeritManager();
        
        // Create vesting wallets (dummy addresses for this test)
        address[4] memory vestingWallets = [
            address(0x1), address(0x2), address(0x3), address(0x4)
        ];
        uint256[4] memory vestingAllocations = [
            uint256(8_000_000 ether), uint256(6_000_000 ether), uint256(4_000_000 ether), uint256(2_000_000 ether)
        ];
        
        freshMM.initialize(address(registry), vestingWallets, vestingAllocations);
        
        // Grant roles
        freshMM.grantRole(freshMM.DEFAULT_ADMIN_ROLE(), deployer);
        freshMM.grantRole(freshMM.MANAGER(), deployer);
        
        // Register a totem
        address dummyTotem = address(0x999);
        freshMM.grantRole(freshMM.REGISTRATOR(), deployer);
        prank(deployer);
        freshMM.register(dummyTotem);
        
        // Check initial state - startTime not set
        assertEq(freshMM.currentPeriod(), 0, "Should be period 0 when startTime not set");
        assertFalse(freshMM.isStartTimeInitialized(), "StartTime should not be initialized");
        
        // Credit merit points before setting startTime
        prank(deployer);
        freshMM.creditMerit(dummyTotem, 1000);
        
        assertEq(freshMM.getTotemMeritPoints(dummyTotem, 0), 1000, "Merit should be in period 0");
        
        // Set startTime to 10 days in the future
        uint256 futureStartTime = block.timestamp + 10 days;
        prank(deployer);
        freshMM.setStartTime(futureStartTime);
        
        // Should still be period 0 (before startTime)
        assertEq(freshMM.currentPeriod(), 0, "Should still be period 0 before startTime");
        
        // Credit more merit points
        prank(deployer);
        freshMM.creditMerit(dummyTotem, 500);
        
        assertEq(freshMM.getTotemMeritPoints(dummyTotem, 0), 1500, "Merit should accumulate in period 0");
        
        // Warp to 5 days before startTime
        vm.warp(block.timestamp + 5 days);
        
        prank(deployer);
        freshMM.creditMerit(dummyTotem, 300);
        
        assertEq(freshMM.currentPeriod(), 0, "Should still be period 0 before startTime");
        assertEq(freshMM.getTotemMeritPoints(dummyTotem, 0), 1800, "Merit should accumulate in period 0");
        
        // Warp to exactly startTime
        vm.warp(futureStartTime);
        
        assertEq(freshMM.currentPeriod(), 0, "Should be period 0 at startTime");
        
        // Warp to 15 days after startTime (still period 0)
        vm.warp(futureStartTime + 15 days);
        
        prank(deployer);
        freshMM.creditMerit(dummyTotem, 200);
        
        assertEq(freshMM.currentPeriod(), 0, "Should still be period 0 within first 30 days");
        assertEq(freshMM.getTotemMeritPoints(dummyTotem, 0), 2000, "Merit should accumulate in period 0");
        
        // Warp to 31 days after startTime (now period 1)
        vm.warp(futureStartTime + 31 days);
        
        assertEq(freshMM.currentPeriod(), 1, "Should be period 1 after 31 days from startTime");
        
        // Credit merit in period 1
        prank(deployer);
        freshMM.creditMerit(dummyTotem, 100);
        
        assertEq(freshMM.getTotemMeritPoints(dummyTotem, 0), 2000, "Period 0 merit should be unchanged");
        assertEq(freshMM.getTotemMeritPoints(dummyTotem, 1), 100, "Period 1 should have new merit");
    }

    function printCurrentPeriod() public view {
        console.log("Current period:", mm.currentPeriod());
    }

    function test_setPeriodDurationProcessesPendingPeriods() public {
        // Create a totem and add merit
        uint256 totemId = createTotem(userA);
        TF.TotemData memory totemData = factory.getTotemData(totemId);
        
        vm.startPrank(deployer);
        mm.grantRegistratorRole(deployer);
        mm.register(totemData.totemAddr);
        mm.creditMerit(totemData.totemAddr, 1000);
        vm.stopPrank();
        
        // Move to period 2 (60+ days)
        vm.warp(block.timestamp + 65 days);
        
        console.log("Before setPeriodDuration:");
        console.log("Current period:", mm.currentPeriod());
        console.log("Last processed period:", mm.lastProcessedPeriod());
        console.log("Released MYTHO for period 0:", mm.releasedMytho(0));
        console.log("Released MYTHO for period 1:", mm.releasedMytho(1));
        
        // Change period duration - this should process periods 0 and 1
        vm.startPrank(deployer);
        mm.setPeriodDuration(15 days);
        vm.stopPrank();
        
        console.log("After setPeriodDuration:");
        console.log("Current period:", mm.currentPeriod());
        console.log("Last processed period:", mm.lastProcessedPeriod());
        console.log("Released MYTHO for period 0:", mm.releasedMytho(0));
        console.log("Released MYTHO for period 1:", mm.releasedMytho(1));
        
        // Verify that period 0 has MYTHO tokens available
        assert(mm.releasedMytho(0) > 0);
        
        // Verify that we can claim MYTHO for period 0
        uint256 pendingReward = mm.getPendingReward(totemData.totemAddr, 0);
        assert(pendingReward > 0);
        
        console.log("Pending reward for period 0:", pendingReward);
        
        // Claim should work
        vm.startPrank(totemData.totemAddr);
        mm.claimMytho(0);
        vm.stopPrank();
        
        console.log("Successfully claimed MYTHO for period 0!");
    }
}