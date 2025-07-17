// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {MeritManager as MM} from "../src/MeritManager.sol";
import {TotemFactory as TF} from "../src/TotemFactory.sol";
import {TotemTokenDistributor as TTD} from "../src/TotemTokenDistributor.sol";
import {Totem} from "../src/Totem.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {Treasury} from "../src/Treasury.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {Layers} from "../src/Layers.sol";
import {Shards} from "../src/Shards.sol";
import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";

import {MockToken} from "../test/mocks/MockToken.sol";

import {WETH} from "lib/solmate/src/tokens/WETH.sol";

/**
 * @dev Minato update to layers
 */
contract MinatoUpdateToLayers is Script {
    UpgradeableBeacon totemBeaconProxy;

    TF factory;
    MM mm;
    TTD distr;
    Treasury treasury;
    AddressRegistry registry;
    MYTHO mytho;
    TokenHoldersOracle oracle;

    ProxyAdmin pfTF;
    ProxyAdmin paMM;
    ProxyAdmin paMYTHO;
    ProxyAdmin paAddressRegistry;
    ProxyAdmin paTTD;

    Layers layers;
    Shards shards;

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

        totemBeaconProxy = UpgradeableBeacon(address(0x8c0e0cEbec78D9Fb0264e557C52045E1Af6d53Ec));

        factory = TF(0xF0a09aC7a2242977566c8F8dF4F944ed7D333047);
        mm = MM(0x622A3667AA0A879EEB63011c63B6395feBe38880);
        distr = TTD(0x652F0E0F01F5a9376cA1a8704c3F849861242C91);
        treasury = Treasury(payable(0x62470fbE6768C723678886ddD574B818a4aba59e));
        registry = AddressRegistry(0x8c41642801687A4F2f6C31aB40b3Ab74c3809e5E);
        mytho = MYTHO(0x8651355f756075f26cc9568114fFe87B3Faffd4a);

        pfTF = ProxyAdmin(0x2CF33a81ddF97dA64b6ca3931B7Cc1895a747E60); 
        paMM = ProxyAdmin(0xf80450Ac97aAed1608318A6Cf6cF5B558867843b); // make update for vestingWallets
        paMYTHO = ProxyAdmin(0xE0860A352bcA29fA366b9aeC68122671869e649F);
        paAddressRegistry = ProxyAdmin(0xc6A1849eb3a305e69571D45E0D76E5C2714c6a99);
        paTTD = ProxyAdmin(0xb73EE6d7Aa6371c6210152AeE40bc960899f4698);
    }

    function run() public {
        fork(minato);

        // update of existing contracts
        pfTF.upgradeAndCall(ITransparentUpgradeableProxy(address(factory)), address(new TF()), "");
        paMM.upgradeAndCall(ITransparentUpgradeableProxy(address(mm)), address(new MM()), "");
        paMYTHO.upgradeAndCall(ITransparentUpgradeableProxy(address(mytho)), address(new MYTHO()), "");
        paAddressRegistry.upgradeAndCall(ITransparentUpgradeableProxy(address(registry)), address(new AddressRegistry()), "");
        paTTD.upgradeAndCall(ITransparentUpgradeableProxy(address(distr)), address(new TTD()), "");

        // update totem implementation
        totemBeaconProxy.upgradeTo(address(new Totem()));

        // deploy layers and shards
        Layers layersImpl = new Layers();
        Shards shardsImpl = new Shards();
        TransparentUpgradeableProxy layersProxy = new TransparentUpgradeableProxy(address(layersImpl), deployer, "");
        TransparentUpgradeableProxy shardsProxy = new TransparentUpgradeableProxy(address(shardsImpl), deployer, "");
        layers = Layers(address(layersProxy));
        layers.initialize(address(registry));

        registry.setAddress(bytes32("LAYERS"), address(layers));

        shards = Shards(address(shardsProxy));
        shards.initialize(address(registry));

        registry.setAddress(bytes32("SHARDS"), address(shards));
        layers.setShardToken();

        // deploy oracle
        oracle = new TokenHoldersOracle(
            0x3704dc1eefCDCE04C58813836AEcfdBC8e7cB3D8, // Chainlink Functions router on Minato
            address(treasury)
        );
        oracle.setGasLimit(300_000);
        oracle.setSubscriptionId(41);

        registry.setAddress(bytes32("TOKEN_HOLDERS_ORACLE"), address(oracle));

        console.log("Contracts updated successfully");
        console.log("Shards deployed at:", address(shards));
        console.log("Layers deployed at:", address(layers));
        console.log("Oracle deployed at:", address(oracle));
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// Address Registry:      0x8c41642801687A4F2f6C31aB40b3Ab74c3809e5E // 0x1149880b95e8bf4e27637151969fd4db1daee07e
// MeritManager:          0x622A3667AA0A879EEB63011c63B6395feBe38880 // 0x35927e216824d08903140511f4217d5e6037143f
// MYTHO:                 0x8651355f756075f26cc9568114fFe87B3Faffd4a // 0x0d915403101ef77cf70a867cc37710315b549fad
// Beacon:                0x8c0e0cEbec78D9Fb0264e557C52045E1Af6d53Ec // 0x23AEC98C1636110c9A56c6D4b14D839777e3f786
// TotemFactory:          0xF0a09aC7a2242977566c8F8dF4F944ed7D333047 // 0xfCE408a315d8ABf11A8a001642Ddc3Dc7C0815AB
// TotemTokenDistributor: 0x652F0E0F01F5a9376cA1a8704c3F849861242C91 // 0x824e216bb64d8e262a1f63b63215b1688e51aea5
// Treasury:              0x62470fbE6768C723678886ddD574B818a4aba59e // 0x9d399a9f4f245d1bf1636d70ef5a246395f8de87

// == Logs ==
//   Contracts updated successfully
//   Shards deployed at: 0x58A4aEE1978228201F5aDC533B72597605E9fC77 // 0xbc7ec2b1bb4b959c801ac2e4f2e7d8408791654a
//   Layers deployed at: 0xB1d122d1329dbF9a125cDf978a0b6190C93f7FFB // 0x59acf8cb844ec52337a4fa4bc4fcbd7b71e5d772
//   Oracle deployed at: 0x2B737862129a79BBF1feE6cA065C70BA54f22E29

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
