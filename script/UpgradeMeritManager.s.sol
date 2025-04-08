// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {MeritManager as MM} from "../src/MeritManager.sol";

/**
 * @title UpgradeMeritManager
 * @dev Script to upgrade the MeritManager contract implementation
 */
contract UpgradeMeritManager is Script {
    // Current deployed proxy address
    address constant MERIT_MANAGER_PROXY = 0xe2629839031bea8Dd370d109969c5033DcdEb9aA;
    address constant MERIT_MANAGER_ADMIN = 0xC75564728232995B46853d5Cf201cFf83B195ee6;
    
    ProxyAdmin proxyAdmin;
    ITransparentUpgradeableProxy proxy;
    
    // New implementation
    MM newImplementation;
    
    // Fork ID
    uint256 minato;
    
    // Private key for deployment
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    
    // RPC URL
    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");
    
    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        proxyAdmin = ProxyAdmin(MERIT_MANAGER_ADMIN);
        proxy = ITransparentUpgradeableProxy(MERIT_MANAGER_PROXY);
    }
    
    function run() public {
        fork(minato);
        
        newImplementation = new MM();        
        
        proxyAdmin.upgradeAndCall(proxy, address(newImplementation), "");

        console.log("Upgraded MeritManager implementation to:", address(newImplementation));
    }
    
    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// current implementation: 0xAB68FFA52a7c3ab8247fB54632Ae075a6BA1A836