// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Totem} from "../src/Totem.sol";

import {MeritManager} from "../src/MeritManager.sol";

contract MythoTest is Test {
    UpgradeableBeacon totemBeacon;

    MeritManager meritManager;
    MeritManager meritManagerImpl;
    TransparentUpgradeableProxy proxy;

    Token token;

    address deployer;

    function setUp() public {
        deployer = makeAddr("deployer");

        prank(deployer); 
        deploy();

        token = new Token("MYTH", "MYTH");
    }    

    function test() public {
        string memory phrase = token.getPhrase();
        console.log(phrase);

        //567008
        //567110
        //185922
    }

    function deploy() internal {
        /* 
        DEPLOY ORDER
        1. MYTH token
        2. TotemDistributor
        3. TotemFactory
        4. MeritManager
        5. MYTHVesting
        */
        totemBeacon = new UpgradeableBeacon(address(new Totem()), deployer);

        meritManagerImpl = new MeritManager();
        proxy = new TransparentUpgradeableProxy(address(meritManagerImpl), address(new ProxyAdmin(deployer)), "");
        meritManager = MeritManager(address(proxy));
    }

    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }
}

contract Token is ERC20 {
    string private phrase = "Hello there";
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
    function getPhrase() public view returns (string memory) {
        return phrase;
    }
}

