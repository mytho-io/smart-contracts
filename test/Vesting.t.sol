// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MYTHO} from "../src/MYTHO.sol";

contract VestingTest is Test {
    MYTHO mytho;

    VestingWallet vestingWallet;

    address beneficiaryA;
    address deployer;

    function setUp() public {
        deployer = makeAddr("deployer");
        beneficiaryA = makeAddr("beneficiaryA");

        prank(deployer);
        mytho = new MYTHO(deployer, deployer, deployer, deployer);
        vestingWallet = new VestingWallet(beneficiaryA, 100, 1000);
        deal(address(mytho), address(vestingWallet), 100e18);
    }

    function test() public {
        // set initial time to zero
        vm.warp(0);

        prank(beneficiaryA);

        assertEq(released(), 0);
        assertEq(releasable(), 0);

        pass(200);

        assertEq(released(), 0);
        assertEq(releasable(), 10e18);

        pass(100);

        assertEq(released(), 0);
        assertEq(releasable(), 20e18);

        vestingWallet.release(address(mytho));

        assertEq(released(), 20e18);
        assertEq(releasable(), 0);

        pass(200);

        assertEq(released(), 20e18);
        assertEq(releasable(), 20e18);

        pass(100);

        vestingWallet.release(address(mytho));

        assertEq(released(), 50e18);
        assertEq(releasable(), 0);

        pass(500);

        assertEq(vestingWallet.end(), block.timestamp);
        assertEq(released(), 50e18);
        assertEq(releasable(), 50e18);
        assertEq(vestingWallet.vestedAmount(address(mytho), uint64(block.timestamp)), 100e18);
    }

    function released() internal view returns (uint256) {
        return vestingWallet.released(address(mytho));
    }

    function releasable() internal view returns (uint256) {
        return vestingWallet.releasable(address(mytho));
    }

    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }

    function pass(uint256 secondsToAdd) internal {
        vm.warp(block.timestamp + secondsToAdd);
    }
}