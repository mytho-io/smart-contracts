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
    uint256 soneium;
    bytes32 soneiumDonId;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    string SONEIUM_RPC_URL = vm.envString("SONEIUM_RPC_URL");

    function setUp() public {
        soneium = vm.createFork(SONEIUM_RPC_URL);
        functionsRouter = 0x20fef1B12FA78fAc8CFB8a7ac1bf032Bd8DcAdDa;
        soneiumDonId = 0x66756e2d736f6e6569756d2d6d61696e6e65742d310000000000000000000000;
        holdersOracle = TokenHoldersOracle(0xFa35acb38c09Cd416956F7593ac57E669fd9EDF1);
    }

    function run() public {
        fork(soneium);

        address contractAddr = 0x2877Da93f3b2824eEF206b3B313d4A61E01e5698;
        address xnastrAddr = 0xea1e08A176528e2d7250a6F7001F18EDF0CaeCF0;

        // holdersOracle.requestHoldersCount(contractAddr);
        // holdersOracle.requestHoldersCount(xnastrAddr);

        (uint256 count, uint256 lastUpdate) = holdersOracle.getNFTCount(xnastrAddr);

        console.log("Holders count:", count);
        console.log("Last update:", lastUpdate);
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// == Logs ==
//   TokenHoldersOracle deployed at: 0xFa35acb38c09Cd416956F7593ac57E669fd9EDF1

// Costs: ~3 cent in LINK tokens per one request