// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console, console2, StdStyle} from "forge-std/Script.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MeritManager as MM} from "../src/MeritManager.sol";
import {TotemFactory as TF} from "../src/TotemFactory.sol";
import {TotemTokenDistributor as TTD} from "../src/TotemTokenDistributor.sol";
import {TotemToken as TT} from "../src/TotemToken.sol";
import {Totem} from "../src/Totem.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {Treasury} from "../src/Treasury.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {MockToken} from "../test/mocks/MockToken.sol";

import {IUniswapV2Factory} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "lib/solmate/src/tokens/WETH.sol";

import {Deployer} from "test/util/Deployer.sol";

/**
 * @dev Minato deployment
 */
contract Do is Script {
    UpgradeableBeacon beacon;

    TransparentUpgradeableProxy factoryProxy;
    TF factoryImpl;
    TF factory;

    TransparentUpgradeableProxy mmProxy;
    MM mmImpl;
    MM mm;

    TransparentUpgradeableProxy distrProxy;
    TTD distrImpl;
    TTD distr;

    TransparentUpgradeableProxy treasuryProxy;
    Treasury treasuryImpl;
    Treasury treasury;

    TransparentUpgradeableProxy registryProxy;
    AddressRegistry registryImpl;
    AddressRegistry registry;

    MYTHO mytho;
    MockToken paymentToken;

    // uni
    IUniswapV2Factory uniFactory;
    IUniswapV2Router02 uniRouter;
    WETH weth;

    uint256 minato;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");

    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");

    address deployer;
    address user;

    address astrToken;

    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        deployer = vm.addr(deployerPk);
        user = 0xf9B9068276163f47cd5599750496c48BeEba7B44;

        // Deployed contracts
        beacon = UpgradeableBeacon(0x8c0e0cEbec78D9Fb0264e557C52045E1Af6d53Ec);
        factory = TF(0xF0a09aC7a2242977566c8F8dF4F944ed7D333047);
        mm = MM(0x622A3667AA0A879EEB63011c63B6395feBe38880);
        distr = TTD(0x652F0E0F01F5a9376cA1a8704c3F849861242C91);
        treasury = Treasury(payable(0x62470fbE6768C723678886ddD574B818a4aba59e));
        registry = AddressRegistry(0x8c41642801687A4F2f6C31aB40b3Ab74c3809e5E);
        mytho = MYTHO(0x8651355f756075f26cc9568114fFe87B3Faffd4a);

        astrToken = 0x26e6f7c7047252DdE3dcBF26AA492e6a264Db655;
    }

    function run() public {
        fork(minato);

        console.log("merit vesting 1:", mytho.meritVestingYear1());
        console.log("merit vesting 2:", mytho.meritVestingYear2());
        console.log("merit vesting 3:", mytho.meritVestingYear3());
        console.log("merit vesting 4:", mytho.meritVestingYear4());
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

//   Address Registry:      0x8c41642801687A4F2f6C31aB40b3Ab74c3809e5E
//   MeritManager:          0x622A3667AA0A879EEB63011c63B6395feBe38880
//   MYTHO:                 0x8651355f756075f26cc9568114fFe87B3Faffd4a
//   Beacon:                0x8c0e0cEbec78D9Fb0264e557C52045E1Af6d53Ec
//   TotemFactory:          0xF0a09aC7a2242977566c8F8dF4F944ed7D333047
//   TotemTokenDistributor: 0x652F0E0F01F5a9376cA1a8704c3F849861242C91
//   Treasury:              0x62470fbE6768C723678886ddD574B818a4aba59e

// Chainlink Minato price feeds
// ASTR/USD 0x1e13086Ca715865e4d89b280e3BB6371dD48DabA
// BTC/USD 0x7B783a093eE5Fe07E49b5bd913a1b4AD1e90B23F
// ETH/USD 0xCA50964d2Cf6366456a607E5e1DBCE381A8BA807
// LINK/ETH 0x0538646F40d4Bd4DdA8c3d4A0C013EAE7ACE4F92
// LINK/USD 0x40dC8B228db7554D3e5d7ee1632f2a64ec63DaF4
// USDC/USD 0x87307a6c8f7b66653F7Cd1C8703064D1e369E8B6