// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// First iteration
import {MeritManager} from "../src/MeritManager.sol";
import {TotemFactory} from "../src/TotemFactory.sol";
import {TotemTokenDistributor} from "../src/TotemTokenDistributor.sol";
import {Totem} from "../src/Totem.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {Treasury} from "../src/Treasury.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";

// Second iteration
import {Posts} from "../src/Posts.sol";
import {Shards} from "../src/Shards.sol";
import {BoostSystem} from "../src/BoostSystem.sol";
import {BadgeNFT} from "../src/BadgeNFT.sol";

import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {WETH} from "lib/solmate/src/tokens/WETH.sol";

/**
 * @dev BNB deployment
 */
contract DeployBNB is Script {
    UpgradeableBeacon beacon;

    TotemFactory factory;
    MeritManager mm;
    TotemTokenDistributor distr;
    Treasury treasury;
    AddressRegistry registry;
    MYTHO mytho;
    Posts posts;
    BoostSystem bs;
    Shards shards;
    BadgeNFT badges;
    TokenHoldersOracle holdersOracle;

    // uni
    IUniswapV2Router02 uniRouter;
    WETH weth;

    uint256 bnb;
    uint256 deployerPk = vm.envUint("PRIVATE_KEY");
    string BNB_RPC_URL = vm.envString("BNB_RPC_URL");

    address deployer;
    address admin;

    function setUp() public {
        // bnb = vm.createFork(BNB_RPC_URL);
        deployer = vm.addr(deployerPk);
        admin = 0xf9B9068276163f47cd5599750496c48BeEba7B44;
    }

    function run() public {
        vm.startBroadcast(deployerPk);

        // Uni V2 deploying
        weth = WETH(payable(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c)); // wbnb
        uniRouter = IUniswapV2Router02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        ); // BNB PancakeRouter V2

        // Deploy Treasury
        treasury = Treasury(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new Treasury()),
                        deployer,
                        ""
                    )
                )
            )
        );
        treasury.initialize();

        // Deploy AddressRegistry
        registry = AddressRegistry(
            address(
                new TransparentUpgradeableProxy(
                    address(new AddressRegistry()),
                    deployer,
                    ""
                )
            )
        );
        registry.initialize();

        // Deploy Totem Beacon
        beacon = new UpgradeableBeacon(address(new Totem()), deployer);

        // Deploy MeritManager
        mm = MeritManager(
            address(
                new TransparentUpgradeableProxy(
                    address(new MeritManager()),
                    deployer,
                    ""
                )
            )
        );

        // Deploy MYTHO
        mytho = MYTHO(
            address(
                new TransparentUpgradeableProxy(
                    address(new MYTHO()),
                    deployer,
                    ""
                )
            )
        );
        mytho.initialize(address(mm), address(registry));

        address[4] memory vestingAddresses = [
            mytho.meritVestingYear1(),
            mytho.meritVestingYear2(),
            mytho.meritVestingYear3(),
            mytho.meritVestingYear4()
        ];

        registry.setAddress(bytes32("MERIT_MANAGER"), address(mm));
        registry.setAddress(bytes32("MYTHO_TOKEN"), address(mytho));
        registry.setAddress(bytes32("MYTHO_TREASURY"), address(treasury));
        registry.setAddress(bytes32("WBNB"), address(weth));

        uint256[4] memory vestingAllocations;
        vestingAllocations[0] = 40_000_000 ether;
        vestingAllocations[1] = 30_000_000 ether;
        vestingAllocations[2] = 20_000_000 ether;
        vestingAllocations[3] = 10_000_000 ether;

        mm.initialize(address(registry), vestingAddresses, vestingAllocations);

        // Deploy TotemTokenDistributor
        distr = TotemTokenDistributor(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new TotemTokenDistributor()),
                        deployer,
                        ""
                    )
                )
            )
        );
        distr.initialize(address(registry));

        registry.setAddress(bytes32("TOTEM_TOKEN_DISTRIBUTOR"), address(distr));

        // Deploy TotemFactory
        factory = TotemFactory(
            address(
                new TransparentUpgradeableProxy(
                    address(new TotemFactory()),
                    deployer,
                    ""
                )
            )
        );
        factory.initialize(address(registry), address(beacon), address(weth));

        registry.setAddress(bytes32("TOTEM_FACTORY"), address(factory));

        distr.setTotemFactory(address(registry));
        distr.setUniswapV2Router(address(uniRouter));
        distr.setPaymentToken(address(weth));

        mm.grantRole(mm.REGISTRATOR(), address(distr));
        mm.grantRole(mm.REGISTRATOR(), address(factory));

        // Set up Chainlink price feeds
        distr.setPriceFeed(
            address(weth),
            0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE // BNB/USD Chainlink price feed
        );

        // Configure slippage percentage (default is 50 = 5%)
        // distr.setSlippagePercentage(50); // Uncomment to explicitly set slippage

        // SKIPPING TokenHoldersOracle deploy

        // Deploy Posts
        posts = Posts(
            address(
                new TransparentUpgradeableProxy(
                    address(new Posts()),
                    deployer,
                    ""
                )
            )
        );
        posts.initialize(address(registry));

        registry.setAddress(bytes32("POSTS"), address(posts));

        // Deploy Shards
        shards = Shards(
            address(
                new TransparentUpgradeableProxy(
                    address(new Shards()),
                    deployer,
                    ""
                )
            )
        );
        shards.initialize(address(registry));

        registry.setAddress(bytes32("SHARDS"), address(shards));

        posts.setShardToken();

        // Deploy BadgeNFT
        badges = BadgeNFT(
            address(
                new TransparentUpgradeableProxy(
                    address(new BadgeNFT()),
                    deployer,
                    ""
                )
            )
        );
        badges.initialize("Mytho Merit Boost Streak Badge", "BADGE");

        // Deploy BoostSystem
        bs = BoostSystem(
            address(
                new TransparentUpgradeableProxy(
                    address(new BoostSystem()),
                    deployer,
                    ""
                )
            )
        );

        // Initialize BoostSystem with BNB VRF coordinator
        bs.initialize(
            address(registry),
            0xd691f04bc0C9a24Edb78af9E005Cf85768F694C9, // VRF BNB Coordinator
            58739616670969550414069311962789324059467971557888165933761401711821656040946, // subscription ID
            0xb94a4fdb12830e15846df59b27d7c5d92c9c24c10cf6ae49655681ba560848dd // key hash
        );

        registry.setAddress(bytes32("BOOST_SYSTEM"), address(bs));

        // Setup BoostSystem
        bs.setBadgeNFT(address(badges));
        bs.setFrontendSigner(0x79B71ab26496AAbFD2013965dBD1a1A2DB77921e);

        badges.setBoostSystem(address(bs));

        mytho.toggleTransferability();
        mytho.grantRole(mytho.TRANSFEROR(), address(mm));

        console.log("Address Registry:", address(registry));
        console.log("MeritManager:", address(mm));
        console.log("MYTHO:", address(mytho));
        console.log("Beacon:", address(beacon));
        console.log("TotemFactory:", address(factory));
        console.log("TotemTokenDistributor:", address(distr));
        console.log("Treasury:", address(treasury));
        console.log("Posts:", address(posts));
        console.log("BoostSystem:", address(bs));
        console.log("Shards:", address(shards));
        console.log("BadgeNFT:", address(badges));
    }

    function fork(uint256 _forkId) internal {
        vm.selectFork(_forkId);
        vm.startBroadcast(deployerPk);
    }
}

//   Address Registry:      0x857BB63C6bb93a01Dc81bf29217A538b7fa8D933 0x0f819eac29d87ff2d8609818dbdf3895176ce7e6
//   MeritManager:          0x658Cdb366C15c42dfc099227ACbC7cda8bca61ce 0x91f32be2cb91d97099fc2a374c9a578250606446
//   MYTHO:                 0x7C2ab056a6870b1913cC6BE346a70366390F4300 0xfc03dace0c898bff840882a8338f8f5f4ad49fe7
//   Beacon:                0x96314bA48419A79cB2b77DA2F9E9B8f61a7d1a1a 0xFC4CEe56d336Aa99F7e70AB2A214D9Fc16eB4386
//   TotemFactory:          0x488f268aef2ec6a8054737be4e056d6b729493f3 0x8817e0677ac171d575662c522e714356efb151ec
//   TotemTokenDistributor: 0x7BB815fC8f774F2c2e1015BEa6b1393238622602 0x3146f807405db92ba52ff2efd92dd219700439f8
//   Treasury:              0x44c7DD4e1a1CB91199Ad6af8bAC11652260268a9 0xe02c2c3d8eb73b7673d7d8dd560f7048822dc9c7
//   Posts:                 0x69a227fEFe7d3D6f154af6A9bD84AB832b10580F 0x7c35c0b10318310480d2eb13e2ad0b686ae656ac
//   BoostSystem:           0xF94e9c5cd1191Ee4e81d8ffDD0a02234B137C4b1 0x97685bad28f5b44a4c0db0c04c3d615d9d3b89c8
//   Shards:                0x5c2C2918b1fCAcc58aB89Fb4606b437266472CdE 0x8bfc21ea07e90e0007db4152df690fc848824f9d
//   BadgeNFT:              0x0C169920684959A7D45207C6990f1c4d0225D177 0x120f5cb712ed94dec1daffce7e4f8171b3f73ca8

//   MeritVestingYear1:     0x1F99B3Fa28337e96bA1fA0fFCe4f0421eEEEa312
//   MeritVestingYear2:     0xaba540632f98a83A12d2731Ea831c131F3243A6a
//   MeritVestingYear3:     0x7f220fC7F68C19d890eeae78Ab11B70eCB1afE4E
//   MeritVestingYear4:     0x94b080f1954b3879bDc58f9C9CB2b968Bc419571

// Chainlink BNB Chain price feeds
// BNB/USD 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE

// bnb before: 0.0317