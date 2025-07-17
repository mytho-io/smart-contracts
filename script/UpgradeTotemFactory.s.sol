// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TotemFactory} from "../src/TotemFactory.sol";

/**
 * @title UpgradeTotemFactory
 * @dev Script to upgrade the TotemFactory contract implementation
 */
contract UpgradeTotemFactory is Script {
    // Current deployed proxy address
    address constant TOTEM_FACTORY_PROXY = 0xF0a09aC7a2242977566c8F8dF4F944ed7D333047;
    address constant TOTEM_FACTORY_ADMIN = 0x2CF33a81ddF97dA64b6ca3931B7Cc1895a747E60;
    
    ProxyAdmin proxyAdmin;
    ITransparentUpgradeableProxy proxy;
    
    // New implementation
    TotemFactory newImplementation;
    
    // Fork ID
    uint256 minato;
    
    // Private key for deployment
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    
    // RPC URL
    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");
    
    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        proxyAdmin = ProxyAdmin(TOTEM_FACTORY_ADMIN);
        proxy = ITransparentUpgradeableProxy(TOTEM_FACTORY_PROXY);
    }
    
    function run() public {
        fork(minato);
        
        newImplementation = new TotemFactory();        
        
        proxyAdmin.upgradeAndCall(proxy, address(newImplementation), "");

        console.log("Upgraded TotemFactory implementation to:", address(newImplementation));
    }
    
    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// current implementation: 