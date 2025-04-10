// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {Totem} from "../src/Totem.sol";

/**
 * @title UpgradeTotem
 * @dev Script to upgrade the Totem contract implementation
 */
contract UpgradeTotem is Script {
    address constant TOTEM_BEACON = 0x6b240c09059A5DAE4ce8716F10726A06c82eED63;

    UpgradeableBeacon beacon;
    Totem newImplementation;

    // Fork ID
    uint256 minato;

    // Private key for deployment
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    // RPC URL
    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");

    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        beacon = UpgradeableBeacon(TOTEM_BEACON);
    }

    function run() public {
        fork(minato);

        newImplementation = new Totem();

        beacon.upgradeTo((address(newImplementation)));
        console.log("Beacon upgraded to new implementation at:", address(newImplementation));
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// current implementation: 0x662B0B9cDd2aeAa5AB80b640488248891F07B553
