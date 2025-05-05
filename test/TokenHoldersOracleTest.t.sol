// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";

contract TokenHoldersOracleTest is Test {
    TokenHoldersOracle holdersOracle;

    address owner;

    function setUp() public {
        uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(ownerPk);

        // get deployed contract
        holdersOracle = TokenHoldersOracle(0xFa35acb38c09Cd416956F7593ac57E669fd9EDF1);
    }

    // function test_getHoldersCount() public {
        // vm.startPrank(owner);

        // address tokenAddress = 0x2877Da93f3b2824eEF206b3B313d4A61E01e5698;
        // holdersOracle.requestHoldersCount(tokenAddress);

        // (uint256 count, uint256 lastUpdate) = holdersOracle.getHoldersCount(tokenAddress);

        // console.log("Holders count:", count);
        // console.log("Last update:", lastUpdate);
    // }
}