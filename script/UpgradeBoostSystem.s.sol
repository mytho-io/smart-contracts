// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {BoostSystem} from "../src/BoostSystem.sol";

/**
 * @dev BoostSystem upgrade
 */
contract UpgradeBoostSystem is Script {
    // Current deployed proxy address
    address constant BOOST_SYSTEM_PROXY = 0x7278eE249dD284FA04732Bc6dB339BAEca3F44ad;
    address constant BOOST_SYSTEM_ADMIN = 0xf141B85884c379a26b96A0145AbEEf698f2357E9;

    ProxyAdmin proxyAdmin;
    ITransparentUpgradeableProxy proxy;

    // New implementation
    BoostSystem newImplementation;

    uint256 minato;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");

    address deployer;

    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        proxyAdmin = ProxyAdmin(BOOST_SYSTEM_ADMIN);
        proxy = ITransparentUpgradeableProxy(BOOST_SYSTEM_PROXY);
    }

    function run() public {
        fork(minato);
        
        newImplementation = new BoostSystem();        
        
        proxyAdmin.upgradeAndCall(proxy, address(newImplementation), "");

        console.log("Upgraded BoostSystem implementation to:", address(newImplementation));
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

