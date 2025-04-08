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
        beacon = UpgradeableBeacon(0x6b240c09059A5DAE4ce8716F10726A06c82eED63);
        factory = TF(0x6a89EdDE5D7a3C8Ec5103f7dB4Be2587660420D6);
        mm = MM(0xe2629839031bea8Dd370d109969c5033DcdEb9aA);
        distr = TTD(0x891561D42158d12fAeCE264b1d312d1FD7EdBDF4);
        treasury = Treasury(payable(0x8006aa62c46Fc731f3B1389AA0fF0d3f07d4d7f5));
        registry = AddressRegistry(0x5FFA0E0302E28f937B705D5e3CF7FbA453CD3eC0);
        mytho = MYTHO(0x3e75e4991E4DeEcC2338577A125A560c490d6Da7);

        astrToken = 0x26e6f7c7047252DdE3dcBF26AA492e6a264Db655;
    }

    function run() public {
        fork(minato);

        MockToken customToken = MockToken(0xA43E037B79bED682Ce48eEF6e969EE5a7F39cf51);
        // ERC20 kyoLP = ERC20(0x572634d00EddaD9ee693b513ef53260456B3B24e);
        address totem = 0x5f97611B1d6A08571727F16aa27FdE021f36dEfF;

        console.log("-- Deployer --");
        console.log("totemTokens:", customToken.balanceOf(deployer));
        console.log("astrTokens:", ERC20(astrToken).balanceOf(deployer));
        console.log("mythoTokens:", mytho.balanceOf(deployer));
        console.log("-- Totem --");
        console.log("totemTokens:", customToken.balanceOf(totem));
        console.log("astrTokens:", ERC20(astrToken).balanceOf(totem));
        console.log("mythoTokens:", mytho.balanceOf(totem));
        console.log("-- Treasury --");
        console.log("totemTokens:", customToken.balanceOf(address(treasury)));
        console.log("astrTokens:", ERC20(astrToken).balanceOf(address(treasury)));
        console.log("mythoTokens:", mytho.balanceOf(address(treasury)));
        console.log("native balance:", address(treasury).balance);
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// == Logs ==
//   Address Registry: 0x5FFA0E0302E28f937B705D5e3CF7FbA453CD3eC0
//   MeritManager: 0xe2629839031bea8Dd370d109969c5033DcdEb9aA
//   MYTHO: 0x3e75e4991E4DeEcC2338577A125A560c490d6Da7
//   Beacon: 0x6b240c09059A5DAE4ce8716F10726A06c82eED63
//   TotemFactory: 0x6a89EdDE5D7a3C8Ec5103f7dB4Be2587660420D6
//   TotemTokenDistributor: 0x891561D42158d12fAeCE264b1d312d1FD7EdBDF4
//   Treasury: 0x8006aa62c46Fc731f3B1389AA0fF0d3f07d4d7f5

// Chainlink Minato price feeds
// ASTR/USD 0x1e13086Ca715865e4d89b280e3BB6371dD48DabA
// BTC/USD 0x7B783a093eE5Fe07E49b5bd913a1b4AD1e90B23F
// ETH/USD 0xCA50964d2Cf6366456a607E5e1DBCE381A8BA807
// LINK/ETH 0x0538646F40d4Bd4DdA8c3d4A0C013EAE7ACE4F92
// LINK/USD 0x40dC8B228db7554D3e5d7ee1632f2a64ec63DaF4
// USDC/USD 0x87307a6c8f7b66653F7Cd1C8703064D1e369E8B6