// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MeritManager as MM} from "../src/MeritManager.sol";
import {TotemFactory as TF} from "../src/TotemFactory.sol";
import {TotemTokenDistributor as TTD} from "../src/TotemTokenDistributor.sol";
import {Totem} from "../src/Totem.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {Treasury} from "../src/Treasury.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {MockToken} from "../test/mocks/MockToken.sol";

import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "lib/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import {WETH} from "lib/solmate/src/tokens/WETH.sol";

/**
 * @dev Minato update to layers
 */
contract MinatoUpdateToLayers is Script {
    UpgradeableBeacon beacon;

    TF factory;
    MM mm;
    TTD distr;
    Treasury treasury;
    AddressRegistry registry;
    MYTHO mytho;

    MockToken paymentToken;
    MockToken astrToken;

    uint256 minato;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");

    address deployer;
    address user;

    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        deployer = vm.addr(deployerPk);
        user = 0xf9B9068276163f47cd5599750496c48BeEba7B44;
    }

    function run() public {
        fork(minato);

        
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// Address Registry:      0x8c41642801687A4F2f6C31aB40b3Ab74c3809e5E // 0x7a4029E104a9588Bf991ADF0F1dfb99eC86F8754
// MeritManager:          0x622A3667AA0A879EEB63011c63B6395feBe38880 // 0x704fa083f24ac13358f5399f3e6071be37baeaad
// MYTHO:                 0x8651355f756075f26cc9568114fFe87B3Faffd4a // 0x0f4866b88482a60923f865272c83651758bcd214
// Beacon:                0x8c0e0cEbec78D9Fb0264e557C52045E1Af6d53Ec // 0xf34755260d8465478cA019f4104d0B664FC253FB
// TotemFactory:          0xF0a09aC7a2242977566c8F8dF4F944ed7D333047 // 0xabe0620afdd162e18ab8a4f1e4d2c4414c86dff0
// TotemTokenDistributor: 0x652F0E0F01F5a9376cA1a8704c3F849861242C91 // 0x0505102352f0952480481e06b786f39300495c83
// Treasury:              0x62470fbE6768C723678886ddD574B818a4aba59e // 0x9d399a9f4f245d1bf1636d70ef5a246395f8de87

// MeritVestingYear1: 0x880a6FFFD420905A12cCa67937F1fdc273458B55
// MeritVestingYear2: 0x262D7BC9E964EeDe9a5aC6B85De97eF014d4B82d
// MeritVestingYear3: 0xCe75B56B8FdE25d6408c2c1A7BfCB1f3ff11789d
// MeritVestingYear4: 0x8Af1DE4b06F88831fef4E63BB7F78A566bF42c4a

// Chainlink Minato price feeds
// ASTR/USD 0x1e13086Ca715865e4d89b280e3BB6371dD48DabA
// BTC/USD  0x7B783a093eE5Fe07E49b5bd913a1b4AD1e90B23F
// ETH/USD  0xCA50964d2Cf6366456a607E5e1DBCE381A8BA807
// LINK/ETH 0x0538646F40d4Bd4DdA8c3d4A0C013EAE7ACE4F92
// LINK/USD 0x40dC8B228db7554D3e5d7ee1632f2a64ec63DaF4
// USDC/USD 0x87307a6c8f7b66653F7Cd1C8703064D1e369E8B6
