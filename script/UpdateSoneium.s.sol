// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Posts} from "../src/Posts.sol";
import {Shards} from "../src/Shards.sol";
import {BoostSystem} from "../src/BoostSystem.sol";
import {BadgeNFT} from "../src/BadgeNFT.sol";
import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";

/**
 * @dev Soneium contract updates
 * Updates: Posts, Shards, BoostSystem, BadgeNFT, TokenHoldersOracle
 */
contract UpdateSoneium is Script {
    // Existing contracts (already deployed)
    AddressRegistry registry;
    TokenHoldersOracle oracle;

    // New contracts to deploy/update
    TransparentUpgradeableProxy postsProxy;
    Posts postsImpl;
    Posts posts;

    TransparentUpgradeableProxy shardsProxy;
    Shards shardsImpl;
    Shards shards;

    TransparentUpgradeableProxy boostSystemProxy;
    BoostSystem boostSystemImpl;
    BoostSystem boostSystem;

    TransparentUpgradeableProxy badgeNFTProxy;
    BadgeNFT badgeNFTImpl;
    BadgeNFT badgeNFT;

    uint256 soneium;
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    string SONEIUM_RPC_URL = vm.envString("SONEIUM_RPC_URL");
    address deployer;

    // Existing contract addresses on Soneium
    address constant ADDRESS_REGISTRY =
        0x3FAa053eB0B08C091f5f0746AeF127819133e0FA;
    address constant MERIT_MANAGER = 0xcaC88671A5bB03debd0B1592C1c724f9fB991b3e;
    address constant MYTHO_TOKEN = 0x6Dee78B728d5AdB869B04951692331a2C455Eef7;
    address constant TOTEM_FACTORY = 0x077dF74a067624f4506166F7dcd9Cf1465299bC7;
    address constant TOTEM_TOKEN_DISTRIBUTOR =
        0x723C0699B0273D4aE251DDE870FF70959B43c48f;
    address constant TREASURY = 0xcD32ae8C3b8a5d40CeeEcacC6e0A9Ce149182fCE;

    // VRF Configuration for Soneium
    address constant VRF_COORDINATOR =
        0xb89BB0aB64b219Ba7702f862020d879786a2BC49;
    uint256 constant VRF_SUBSCRIPTION_ID =
        20752627233091861947823349696287991151486717766529904171579935104100400785289;
    bytes32 constant VRF_KEY_HASH =
        0x7611210a5ac0abd39b581bd4ce1108aa0b9e63994daa32cc7302d98ed47747c1; // 30 gwei key hash

    // TokenHoldersOracle already deployed
    address constant TOKEN_HOLDERS_ORACLE =
        0x44935376C5371564782fd1488bC6d83dFbB15aB5;

    // Frontend signer address for signature verification
    address constant FRONTEND_SIGNER =
        0x79B71ab26496AAbFD2013965dBD1a1A2DB77921e;

    function setUp() public {
        soneium = vm.createFork(SONEIUM_RPC_URL);
        deployer = vm.addr(deployerPk);
    }

    function run() public {
        fork(soneium);

        // Get existing registry
        registry = AddressRegistry(ADDRESS_REGISTRY);

        console.log("=== Deploying new contracts ===");

        // Deploy Posts
        console.log("Deploying Posts...");
        postsImpl = new Posts();
        postsProxy = new TransparentUpgradeableProxy(
            address(postsImpl),
            deployer,
            ""
        );
        posts = Posts(payable(address(postsProxy)));
        posts.initialize(address(registry));

        // Deploy Shards (will be initialized after Posts is added to registry)
        console.log("Deploying Shards...");
        shardsImpl = new Shards();
        shardsProxy = new TransparentUpgradeableProxy(
            address(shardsImpl),
            deployer,
            ""
        );
        shards = Shards(payable(address(shardsProxy)));

        // Deploy BadgeNFT
        console.log("Deploying BadgeNFT...");
        badgeNFTImpl = new BadgeNFT();
        badgeNFTProxy = new TransparentUpgradeableProxy(
            address(badgeNFTImpl),
            deployer,
            ""
        );
        badgeNFT = BadgeNFT(payable(address(badgeNFTProxy)));
        badgeNFT.initialize("Mytho Badges", "MYTHO-BADGE");

        // Get existing TokenHoldersOracle
        console.log("Getting existing TokenHoldersOracle...");
        oracle = TokenHoldersOracle(TOKEN_HOLDERS_ORACLE);

        console.log("=== Updating AddressRegistry ===");

        // Update AddressRegistry with new contract addresses
        registry.setAddress(bytes32("POSTS"), address(posts));
        registry.setAddress(bytes32("SHARDS"), address(shards));
        registry.setAddress(bytes32("BADGE_NFT"), address(badgeNFT));

        // Now initialize Shards after Posts is in registry
        shards.initialize(address(registry));

        // Deploy BoostSystem (after BadgeNFT is in registry)
        console.log("Deploying BoostSystem...");
        boostSystemImpl = new BoostSystem();
        boostSystemProxy = new TransparentUpgradeableProxy(
            address(boostSystemImpl),
            deployer,
            ""
        );
        boostSystem = BoostSystem(payable(address(boostSystemProxy)));
        boostSystem.initialize(
            address(registry),
            VRF_COORDINATOR,
            VRF_SUBSCRIPTION_ID,
            VRF_KEY_HASH
        );

        // Add BoostSystem to registry
        registry.setAddress(bytes32("BOOST_SYSTEM"), address(boostSystem));

        console.log("=== Configuring contracts ===");

        // Configure Posts to use Shards token
        posts.setShardToken();

        // Configure BadgeNFT
        badgeNFT.setBoostSystem(address(boostSystem));

        // Configure BoostSystem
        // Note: BadgeNFT is automatically set in BoostSystem.initialize() from registry
        boostSystem.setFrontendSigner(FRONTEND_SIGNER);

        // Grant necessary roles
        boostSystem.grantRole(boostSystem.MANAGER(), deployer);
        posts.grantRole(posts.MANAGER(), deployer);
        shards.grantRole(shards.MANAGER(), deployer);
        badgeNFT.grantRole(badgeNFT.MANAGER(), deployer);
        // Oracle roles already set during initial deployment

        console.log("=== Deployment Summary ===");
        console.log("AddressRegistry:", address(registry));
        console.log("Posts:", address(posts));
        console.log("Shards:", address(shards));
        console.log("BoostSystem:", address(boostSystem));
        console.log("BadgeNFT:", address(badgeNFT));
        console.log("TokenHoldersOracle:", address(oracle));
        console.log("=== Update completed successfully! ===");

        vm.stopBroadcast();
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }

    function stopBroadcast() internal {
        vm.stopBroadcast();
    }
}
