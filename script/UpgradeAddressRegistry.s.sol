// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";

/**
 * @title AddressRegistry
 * @dev Script to upgrade the AddressRegistry contract implementation
 */
contract UpgradeAddressRegistry is Script {
    // Current deployed proxy address
    address constant ADDRESS_REGISTRY_PROXY = 0x8c41642801687A4F2f6C31aB40b3Ab74c3809e5E;
    address constant ADDRESS_REGISTRY_ADMIN = 0xc6A1849eb3a305e69571D45E0D76E5C2714c6a99;
    
    ProxyAdmin proxyAdmin;
    ITransparentUpgradeableProxy proxy;
    
    // New implementation
    AddressRegistry newImplementation;
    
    // Fork ID
    uint256 minato;
    
    // Private key for deployment
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    
    // RPC URL
    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");
    
    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        proxy = ITransparentUpgradeableProxy(ADDRESS_REGISTRY_PROXY);
        proxyAdmin = ProxyAdmin(ADDRESS_REGISTRY_ADMIN);
    }
    
    function run() public {
        fork(minato);
        
        newImplementation = new AddressRegistry();        
        
        proxyAdmin.upgradeAndCall(proxy, address(newImplementation), "");

        console.log("Upgraded AddressRegistry implementation to:", address(newImplementation));
    }
    
    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// current implementation: 0x80ba92DFaaa8299dC2a557E7e9a13fF76dB2a750