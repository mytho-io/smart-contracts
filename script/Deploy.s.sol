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
contract Deploy is Script {
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
    MockToken astrToken;

    // uni
    IUniswapV2Factory uniFactory;
    IUniswapV2Router02 uniRouter;
    WETH weth;

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

        // Uni V2 deploying
        uniFactory = IUniswapV2Factory(0xA251B28B5f2325D0c7d4988d5fB5B817E96ea242);
        weth = WETH(payable(0x4200000000000000000000000000000000000006));
        uniRouter = IUniswapV2Router02(0xD0f568db3aeD46CE3F7B8833fd2aa1F1CfA71063);

        treasuryImpl = new Treasury();
        treasuryProxy = new TransparentUpgradeableProxy(
            address(treasuryImpl),
            deployer,
            ""
        );
        treasury = Treasury(payable(address(treasuryProxy)));
        treasury.initialize();

        registryImpl = new AddressRegistry();
        registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            deployer,
            ""
        );
        registry = AddressRegistry(address(registryProxy));
        registry.initialize();

        Totem totemImplementation = new Totem();
        beacon = new UpgradeableBeacon(address(totemImplementation), deployer);

        astrToken = new MockToken();

        // MeritManager
        mmImpl = new MM();
        mmProxy = new TransparentUpgradeableProxy(
            address(mmImpl),
            deployer,
            ""
        );
        mm = MM(address(mmProxy));

        // MYTHO
        mytho = new MYTHO(address(mm), deployer, deployer, deployer);

        address[4] memory vestingAddresses = [
            mytho.meritVestingYear1(),
            mytho.meritVestingYear2(),
            mytho.meritVestingYear3(),
            mytho.meritVestingYear4()
        ];

        registry.setAddress(bytes32("MERIT_MANAGER"), address(mm));
        registry.setAddress(bytes32("MYTHO_TOKEN"), address(mytho));
        registry.setAddress(bytes32("MYTHO_TREASURY"), address(treasury));

        mm.initialize(address(registry), vestingAddresses);

        // TotemTokenDistributor
        distrImpl = new TTD();
        distrProxy = new TransparentUpgradeableProxy(
            address(distrImpl),
            deployer,
            ""
        );
        distr = TTD(address(distrProxy));
        distr.initialize(address(registry));

        registry.setAddress(bytes32("TOTEM_TOKEN_DISTRIBUTOR"), address(distr));

        // TotemFactory
        factoryImpl = new TF();
        factoryProxy = new TransparentUpgradeableProxy(
            address(factoryImpl),
            deployer,
            ""
        );
        factory = TF(address(factoryProxy));
        factory.initialize(
            address(registry),
            address(beacon),
            address(astrToken)
        );

        registry.setAddress(bytes32("TOTEM_FACTORY"), address(factory));

        distr.setTotemFactory(address(registry));
        distr.setUniswapV2Router(address(uniRouter));
        paymentToken = astrToken;
        distr.setPaymentToken(address(astrToken));

        paymentToken.mint(deployer, 1_000_000 ether);

        mm.grantRole(mm.REGISTRATOR(), address(distr));
        mm.grantRole(mm.REGISTRATOR(), address(factory));

        console.log("Address Registry:", address(registry));
        console.log("MeritManager:", address(mm));
        console.log("MYTHO:", address(mytho));
        console.log("Beacon:", address(beacon));
        console.log("TotemFactory:", address(factory));
        console.log("TotemTokenDistributor:", address(distr));
        console.log("Treasury:", address(treasury));
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