// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Layers} from "../src/Layers.sol";

/**
 * @title UpgradeLayers
 * @dev Script to upgrade the Layers contract implementation
 */
contract UpgradeLayers is Script {
    // Current deployed proxy address
    address constant LAYERS_PROXY = 0xB1d122d1329dbF9a125cDf978a0b6190C93f7FFB;
    address constant LAYERS_ADMIN = 0xbEAEB957D422fD29687CCbD516f737469E146245;
    
    ProxyAdmin proxyAdmin;
    ITransparentUpgradeableProxy proxy;
    
    // New implementation
    Layers newImplementation;
    
    // Fork ID
    uint256 minato;
    
    // Private key for deployment
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    
    // RPC URL
    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");
    
    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        proxyAdmin = ProxyAdmin(LAYERS_ADMIN);
        proxy = ITransparentUpgradeableProxy(LAYERS_PROXY);
    }
    
    function run() public {
        fork(minato);
        
        newImplementation = new Layers();        
        
        proxyAdmin.upgradeAndCall(proxy, address(newImplementation), "");

        console.log("Upgraded Layers implementation to:", address(newImplementation));
    }
    
    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// current implementation: 0xb2BACdE7C499F2Dc9514afE538793072d333B0c7