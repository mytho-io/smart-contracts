// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {AddressRegistry} from "../src/AddressRegistry.sol";
import {BoostSystem} from "../src/BoostSystem.sol";
import {MeritManager} from "../src/MeritManager.sol";
import {BadgeNFT} from "../src/BadgeNFT.sol";

/**
 * @dev Minato deployment
 */
contract DeployBoostSystem is Script {
    AddressRegistry registry;

    ProxyAdmin adminMM;
    ITransparentUpgradeableProxy proxyMM;

    TransparentUpgradeableProxy bsProxy;
    BoostSystem bsImplementation;
    BoostSystem bs;

    TransparentUpgradeableProxy badgeProxy;
    BadgeNFT badgeImplementation;
    BadgeNFT badge;

    address vrfCoordinator;
    uint256 vrfSubscriptionId;
    bytes32 vrfKeyHash;

    uint256 minato;

    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    address frontendSigner = vm.envAddress("FRONTEND_SIGNER"); // Add this to your .env

    string MINATO_RPC_URL = vm.envString("MINATO_RPC_URL");

    address deployer;

    function setUp() public {
        minato = vm.createFork(MINATO_RPC_URL);
        deployer = vm.addr(deployerPk);

        vrfCoordinator = 0x3Fa01AB73beB4EA09e78FC0849FCe31d0b035b47;
        vrfSubscriptionId = 110586606629607351084397527862915980192448378269538304305737515090960183799576;
        vrfKeyHash = 0x8077df514608a09f83e4e8d300645594e5d7234665448ba83f51a50f842bd3d9;

        registry = AddressRegistry(0x8c41642801687A4F2f6C31aB40b3Ab74c3809e5E);
        adminMM = ProxyAdmin(0xf80450Ac97aAed1608318A6Cf6cF5B558867843b);
        proxyMM = ITransparentUpgradeableProxy(0x622A3667AA0A879EEB63011c63B6395feBe38880);
    }

    function run() public {
        fork(minato);

        // Deploy BadgeNFT first
        badgeImplementation = new BadgeNFT();
        badgeProxy = new TransparentUpgradeableProxy(
            address(badgeImplementation),
            deployer,
            ""
        );
        badge = BadgeNFT(address(badgeProxy));
        badge.initialize("Mytho Boost Badges", "MBB");

        // Deploy BoostSystem
        bsImplementation = new BoostSystem();
        bsProxy = new TransparentUpgradeableProxy(
            address(bsImplementation),
            deployer,
            ""
        );
        bs = BoostSystem(address(bsProxy));
        bs.initialize(
            address(registry),
            vrfCoordinator,
            vrfSubscriptionId,
            vrfKeyHash
        );

        // Configure BoostSystem
        bs.setFrontendSigner(frontendSigner);
        
        // Grant BoostSystem the MINTER role on BadgeNFT
        badge.setBoostSystem(address(bs));

        // Register in AddressRegistry
        registry.setAddress(bytes32("BOOST_SYSTEM"), address(bs));
        registry.setAddress(bytes32("BADGE_NFT"), address(badge));

        address newImplMMAddr = _updateMM();

        console.log("New MeritManager implementation:", newImplMMAddr);
        console.log("BoostSystem proxy:", address(bs));
        console.log("BoostSystem implementation:", address(bsImplementation));
        console.log("BadgeNFT proxy:", address(badge));
        console.log("BadgeNFT implementation:", address(badgeImplementation));
        console.log("Frontend signer:", frontendSigner);
    }

    function _updateMM() internal returns(address) {
        MeritManager newImpl = new MeritManager();
        adminMM.upgradeAndCall(
            proxyMM,
            address(newImpl),
            ""
        );
        return address(newImpl);
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

// == Logs ==
//   New MeritManager implementation: 0xe2e8c446966326Bb17d3eeD8edBE1Ede131F4144
//   BoostSystem proxy: 0x7278eE249dD284FA04732Bc6dB339BAEca3F44ad
//   BoostSystem implementation: 0x3F79F2d957923485d5A2218b60255427565c845F
//   BadgeNFT proxy: 0xe425fe4598AFfff82Da4CF6Ad09715C8a6127aaa
//   BadgeNFT implementation: 0xb53E8684294884C18C2DCa89E6a2204b2266373d
//   Frontend signer: 0x79B71ab26496AAbFD2013965dBD1a1A2DB77921e