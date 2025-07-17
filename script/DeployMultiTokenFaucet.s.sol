// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {MultiTokenFaucet} from "../src/MultiTokenFaucet.sol";

contract DeployMultiTokenFaucet is Script {
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

        // Deploy implementation
        newImplementation = new MultiTokenFaucet();

        // Token addresses (from comments in the contract)
        address mythoToken = 0x8651355f756075f26cc9568114fFe87B3Faffd4a;
        address adToken = 0x191A03E5A0C4873ABb1bD848Fc5F4225e362958A;
        address arcasToken = 0x0F5c8DF30180BdadC44e700BE26F53894bB6a457;
        address sonexToken = 0x1589759fFF5AdEcA706B572f346D9a15A75D8E6a;
        address aiweb3Token = 0x31Fca7F542698E25Cf8fBe31b907f81D2ea98422;
        address internToken = 0xc0665577e2F24C6ecde98c1759F556904F72B45a;
        address algmToken = 0x2Ce6b85a6CEC17071738A16f6BBB276daA056289;

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            MultiTokenFaucet.initialize.selector,
            mythoToken,
            adToken,
            arcasToken,
            sonexToken,
            aiweb3Token,
            internToken,
            algmToken
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(newImplementation),
            vm.addr(deployerPk),
            initData
        );

        console.log("MultiTokenFaucet implementation deployed to:", address(newImplementation));
        console.log("MultiTokenFaucet proxy deployed to:", address(proxy));
        
        vm.stopBroadcast();
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// == Logs ==
//   MultiTokenFaucet implementation deployed to: 0xC3F2dc912480ef25be7EC8c2cEaF43518eaA8A48
//   MultiTokenFaucet proxy deployed to: 0x563Dba42775f403F5c9d008447c8ca2F7B4CF73F

// Mytho - новый токен (5 токенов за минт, 1 раз в день)
// AD - 0x191A03E5A0C4873ABb1bD848Fc5F4225e362958A (300 000 токенов за минт, 1 раз в день - для всех остальных токенов ниже тоже самое)
// ARCAS - 0x0F5c8DF30180BdadC44e700BE26F53894bB6a457
// SoneX - 0x1589759fFF5AdEcA706B572f346D9a15A75D8E6a
// AiWeb3 - 0x31Fca7F542698E25Cf8fBe31b907f81D2ea98422
// INTERN - 0xc0665577e2F24C6ecde98c1759F556904F72B45a
// ALGM - 0x2Ce6b85a6CEC17071738A16f6BBB276daA056289
