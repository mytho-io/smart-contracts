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
 * @dev Minato deployment
 */
contract DeployMinato is Script {
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

    TransparentUpgradeableProxy mythoProxy;
    MYTHO mythoImpl;
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

        // MYTHO - Upgradeable implementation
        mythoImpl = new MYTHO();
        mythoProxy = new TransparentUpgradeableProxy(
            address(mythoImpl),
            deployer,
            ""
        );
        mytho = MYTHO(address(mythoProxy));
        mytho.initialize(address(mm), deployer, deployer, deployer, address(registry));

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

        // Set up Chainlink price feeds
        distr.setPriceFeed(address(astrToken), 0x1e13086Ca715865e4d89b280e3BB6371dD48DabA); // ASTR/USD
        
        // Configure slippage percentage (default is 50 = 5%)
        // distr.setSlippagePercentage(50); // Uncomment to explicitly set slippage

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
