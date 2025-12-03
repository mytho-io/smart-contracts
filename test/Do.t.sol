// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { Posts } from "../src/Posts.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Totem } from "../src/Totem.sol";

interface ICoordinator {
    function owner() external view returns (address);
    function cancelSubscription(uint256 subId, address to) external;
}

contract DoTest is Test {
    Posts posts;
    Totem totem;

    address deployer;

    uint256 bnb;

    string BNB_RPC_URL = vm.envString("BNB_RPC_URL");
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    
    function setUp() public {
        // deployer = vm.addr(deployerPk);
        // bnb = vm.createFork(BNB_RPC_URL);
        posts = Posts(0xB1d122d1329dbF9a125cDf978a0b6190C93f7FFB);
        totem = Totem(payable(0xF67949FDd8B25E12390568174A73D0270fEf5a7f));
    }

    function test() public {
        address user = 0x29367D8F3E349E97aD2221242208dF92CF4E2186;

        prank(user);

        totem.redeemTotemTokens(10e18);
    }

    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }
}