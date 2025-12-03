// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract DebugTest is Base {
    function test_debug_distribution() public {
        prank(deployer);
        distr.setMaxTotemTokensPerAddress(1e36);

        deal(userA, 1000 ether);
        deal(userB, 1000 ether);
        deal(userC, 1000 ether);
        deal(userD, 1000 ether);

        paymentToken.mint(userB, 1_000_000 ether);
        paymentToken.mint(userC, 1_000_000 ether);
        paymentToken.mint(userD, 1_000_000 ether);

        // Create 4 totems
        vm.startPrank(userA);
        address[] memory myCollabs = new address[](0);
        astrToken.approve(address(factory), 20e18);
        factory.createTotem("SimpleTotem", "SIMPLE", "SMPL", myCollabs);
        factory.createTotem("SimpleTotem2", "SIMPLE2", "SMPL2", myCollabs);
        factory.createTotem("SimpleTotem3", "SIMPLE3", "SMPL3", myCollabs);
        factory.createTotem("SimpleTotem4", "SIMPLE4", "SMPL4", myCollabs);
        vm.stopPrank();

        // Get totem data
        TF.TotemData memory data = factory.getTotemData(0);
        TF.TotemData memory data2 = factory.getTotemData(1);
        TF.TotemData memory data3 = factory.getTotemData(2);
        TF.TotemData memory data4 = factory.getTotemData(3);

        address[] memory userArray = new address[](3);
        userArray[0] = userB;
        userArray[1] = userC;
        userArray[2] = userD;

        // Close all sales
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(userArray[i]);
            paymentToken.approve(address(distr), paymentToken.balanceOf(userArray[i]));
            distr.buy(data.totemTokenAddr, 233_250_000e18);
            distr.buy(data2.totemTokenAddr, 233_250_000e18);
            distr.buy(data3.totemTokenAddr, 233_250_000e18);
            distr.buy(data4.totemTokenAddr, 233_250_000e18);
            vm.stopPrank();
        }

        // Boost for 367 days
        for (uint day = 0; day < 367; day++) {
            uint consecutiveDays = block.timestamp + 1 days;
            vm.warp(block.timestamp + 1 days);

            for (uint i = 0; i < 3; i++) {
                vm.startPrank(userArray[i]);
                bytes memory signature1 = createBoostSignature(userArray[i], data.totemAddr, consecutiveDays);
                bytes memory signature2 = createBoostSignature(userArray[i], data2.totemAddr, consecutiveDays);
                bytes memory signature3 = createBoostSignature(userArray[i], data3.totemAddr, consecutiveDays);
                bytes memory signature4 = createBoostSignature(userArray[i], data4.totemAddr, consecutiveDays);

                boostSystem.boost(data.totemAddr, consecutiveDays, signature1);
                boostSystem.boost(data2.totemAddr, consecutiveDays, signature2);
                boostSystem.boost(data3.totemAddr, consecutiveDays, signature3);
                boostSystem.boost(data4.totemAddr, consecutiveDays, signature4);
                vm.stopPrank();
            }
        }

        console.log("=== BEFORE UPDATE STATE ===");
        console.log("Current period:", mm.currentPeriod());
        console.log("Last processed period:", mm.lastProcessedPeriod());
        console.log("MM MYTHO balance:", mytho.balanceOf(address(mm)));

        // Update state
        vm.startPrank(deployer);
        mm.updateState();
        vm.stopPrank();

        console.log("=== AFTER UPDATE STATE ===");
        console.log("Current period:", mm.currentPeriod());
        console.log("Last processed period:", mm.lastProcessedPeriod());
        console.log("MM MYTHO balance:", mytho.balanceOf(address(mm)));

        // Check vesting wallet allocation
        console.log("=== VESTING INFO ===");
        console.log("Year index:", mm.getYearIndex());
        
        // Check each period
        console.log("=== PERIOD ANALYSIS ===");
        for (uint i = 0; i < 15; i++) {
            uint256 totalMerit = mm.totalMeritPoints(i);
            uint256 releasedMytho = mm.releasedMytho(i);
            uint256 totem1Merit = mm.totemMerit(i, data.totemAddr);
            
            if (totalMerit > 0 || releasedMytho > 0) {
                console.log("Period", i);
                console.log("  Total merit:", totalMerit);
                console.log("  Released MYTHO:", releasedMytho);
                console.log("  Totem1 merit:", totem1Merit);
                console.log("  ---");
            }
        }
    }
}