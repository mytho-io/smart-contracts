// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TotemTokenDistributor} from "../src/TotemTokenDistributor.sol";

/**
 * @title UpgradeMeritManager
 * @dev Script to upgrade the MeritManager contract implementation
 */
contract UpgradeTotemTokenDistributor is Script {
    // Current deployed proxy address
    address constant TOTEM_TOKEN_DISTR_PROXY = 0x891561D42158d12fAeCE264b1d312d1FD7EdBDF4;
    address constant TOTEM_TOKEN_DISTR_ADMIN = 0xC2CF952E708b75E03bbC627D56740741D6542D18;
    
    ProxyAdmin proxyAdmin;
    ITransparentUpgradeableProxy proxy;
    
    // New implementation
    TotemTokenDistributor newImplementation;
    
    // Fork ID
    uint256 minato;
    
    // Private key for deployment
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    
    // RPC URL
    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");
    
    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        proxyAdmin = ProxyAdmin(TOTEM_TOKEN_DISTR_ADMIN);
        proxy = ITransparentUpgradeableProxy(TOTEM_TOKEN_DISTR_PROXY);
    }
    
    function run() public {
        fork(minato);
        
        newImplementation = new TotemTokenDistributor();        
        
        proxyAdmin.upgradeAndCall(proxy, address(newImplementation), "");

        console.log("Upgraded TotemTokenDistributor implementation to:", address(newImplementation));
    }
    
    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// current implementation: 0x723C0699B0273D4aE251DDE870FF70959B43c48f