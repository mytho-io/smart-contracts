// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";

contract DoHolderOracle is Script {
    TokenHoldersOracle holdersOracle;
    address functionsRouter;
    address treasury;
    uint256 soneium;
    bytes32 soneiumDonId;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    string SONEIUM_RPC_URL = vm.envString("SONEIUM_RPC_URL");

    function setUp() public {
        soneium = vm.createFork(SONEIUM_RPC_URL);
        functionsRouter = 0x20fef1B12FA78fAc8CFB8a7ac1bf032Bd8DcAdDa;
        soneiumDonId = 0x66756e2d736f6e6569756d2d6d61696e6e65742d310000000000000000000000;

        // deployer address initially
        treasury = 0x7ECD92b9835E0096880bF6bA778d9eA40d1338B5;

        // deployed oracle
        holdersOracle = TokenHoldersOracle(0x9391e8110d1Ca8BD9D8F24c6d25a4a6464D7ea69);
    }

    function run() public {
        fork(soneium);

        address tokenAddress = 0x2877Da93f3b2824eEF206b3B313d4A61E01e5698;

        // SEND REQUEST
        // holdersOracle.requestHoldersCount(tokenAddress);

        // DEPLOY
        // holdersOracle = new TokenHoldersOracle(functionsRouter, treasury);
        // holdersOracle.setGasLimit(300_000);
        // holdersOracle.setSubscriptionId(4);

        // console.log("TokenHoldersOracle deployed at:", address(holdersOracle));

        // CHECK INFO
        (uint256 number, ) = holdersOracle.getNFTCount(tokenAddress);
        console.log("Nubmer of holders:", number);
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// == Logs ==
//   TokenHoldersOracle deployed at: 0x9391e8110d1Ca8BD9D8F24c6d25a4a6464D7ea69

// Costs: ~3 cent in LINK tokens per one request