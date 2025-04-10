// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import { CCIPReceiver } from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

import { IAny2EVMMessageReceiver } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

import {MYTHO} from "../src/MYTHO.sol";

/// @notice MYTHO crosschain transfer
contract CrosschainTransfer is Script {
    MYTHO mythoSoneium;
    MYTHO mythoAstar;

    address linkAddrSoneium;
    address linkAddrEthereum;

    address ccipRouterSoneium;
    address ccipRouterAstar;

    address deployer;

    address wastrCLAddr;
    address wastrAddr;
    address wethSoneium;

    uint64 astarChainSelector;
    uint64 soneiumChainSelector;

    uint256 soneium;
    uint256 astar;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    string SONEIUM_RPC_URL = vm.envString("SONEIUM_RPC_URL");
    string ASTAR_RPC_URL = vm.envString("ASTAR_RPC_URL");

    function setUp() public {
        soneium = vm.createFork(SONEIUM_RPC_URL);
        astar = vm.createFork(ASTAR_RPC_URL);
        deployer = vm.addr(deployerPk);

        // mytho on both chains astar and soneium
        mythoSoneium = MYTHO(0x197dB89FBbad7C0D23feA80539c20F2F05Ca694F);
        mythoAstar = MYTHO(0xCFA795310bD2b2bf0E50fc50D3559B4aD591b74E);

        // astar
        wastrCLAddr = 0x37795FdD8C165CaB4D6c05771D564d80439CD093;
        wastrAddr = 0xAeaaf0e2c81Af264101B9129C00F4440cCF0F720;
        ccipRouterAstar = 0x8D5c5CB8ec58285B424C93436189fB865e437feF;

        // soneium
        linkAddrSoneium = 0x32D8F819C8080ae44375F8d383Ffd39FC642f3Ec;
        ccipRouterSoneium = 0x8C8B88d827Fe14Df2bc6392947d513C86afD6977;
        soneiumChainSelector = 12505351618335765396;
        wethSoneium = 0x4200000000000000000000000000000000000006;

        astarChainSelector = 6422105447186081193;
    }

    function run() public {
        fork(soneium);

        console.log(mythoSoneium.balanceOf(deployer));
        console.log(mythoSoneium.totalSupply());

        fork(astar);

        console.log(mythoAstar.balanceOf(deployer));
        console.log(mythoAstar.totalSupply());
    }

    function send() public {
        bytes memory data = abi.encode("");

        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](1);
        tokens[0] = Client.EVMTokenAmount(address(mythoSoneium), 10 ether);

        _ccipSend(tokens, data);
    }

    function _ccipSend(
        Client.EVMTokenAmount[] memory tokens,
        bytes memory _data
    ) internal {
        // set message data
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(deployer),
            data: _data,
            tokenAmounts: tokens,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 2_000_000})),
            feeToken: address(0)
        });

        // approve tokens for router if there is a need to send it
        if (tokens.length > 0) {
            for (uint256 i; i < tokens.length; i++) {
                IERC20(tokens[i].token).approve(ccipRouterSoneium, tokens[i].amount);
            }            
        }

        uint256 fee = IRouterClient(ccipRouterSoneium).getFee(astarChainSelector, message);

        // IERC20(wethSoneium).approve(address(ccipRouterSoneium), fee);

        IRouterClient(ccipRouterSoneium).ccipSend{value: fee}(
            astarChainSelector,
            message
        );
    }

    function fork(uint256 _forkId) internal {
        try vm.stopBroadcast() {} catch {}
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

//   Soneium pool deployed at: 0xc071B8E36B6bC20990951848Ee9997bAEFb07113
//   Soneium MYTHO deployed at: 0x197dB89FBbad7C0D23feA80539c20F2F05Ca694F
//   Astar pool deployed at: 0x893855bd21519CA7c321BEB1cdd493473dF0582e
//   Astar MYTHO deployed at: 0xCFA795310bD2b2bf0E50fc50D3559B4aD591b74E