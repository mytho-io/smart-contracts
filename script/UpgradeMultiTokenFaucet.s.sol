// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {MultiTokenFaucet} from "../src/MultiTokenFaucet.sol";

contract UpgradeMultiTokenFaucet is Script {
    // New implementation
    MultiTokenFaucet newImplementation;

    // Fork ID
    uint256 minato;

    // Private key for deployment
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    // RPC URL
    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");

    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
    }

    function run() public {
        fork(minato);

        newImplementation = new MultiTokenFaucet();

        ProxyAdmin proxyAdmin = ProxyAdmin(0x9b7365330b73d76f5314fb7a4f3b0103bE55D68A);
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(0x927B5e06476807626130D6FC0d33a8a7ed77c4c3);

        proxyAdmin.upgradeAndCall(proxy, address(newImplementation), "");

        console.log("MultiTokenFaucet upgraded, new implementation:", address(newImplementation));

        vm.stopBroadcast();
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// == Logs ==
//   MultiTokenFaucet implementation deployed to: 0xA6473FFd28b21C821a1b4e96aeAbFd1413989d9c
//   MultiTokenFaucet proxy deployed to: 0x927B5e06476807626130D6FC0d33a8a7ed77c4c3
//   ProxyAdmin deployed to: 0xCF42226c03eAB7FB43B6Bc286f8554A63BBAB52f

// Mytho - новый токен (5 токенов за минт, 1 раз в день)
// AD - 0x191A03E5A0C4873ABb1bD848Fc5F4225e362958A (300 000 токенов за минт, 1 раз в день - для всех остальных токенов ниже тоже самое)
// ARCAS - 0x0F5c8DF30180BdadC44e700BE26F53894bB6a457
// SoneX - 0x1589759fFF5AdEcA706B572f346D9a15A75D8E6a
// AiWeb3 - 0x31Fca7F542698E25Cf8fBe31b907f81D2ea98422
// INTERN - 0xc0665577e2F24C6ecde98c1759F556904F72B45a
// ALGM - 0x2Ce6b85a6CEC17071738A16f6BBB276daA056289
