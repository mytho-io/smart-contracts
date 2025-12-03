// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// OpenZeppelin
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";

// Uniswap V2
import {IUniswapV2Factory} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "lib/solmate/src/tokens/WETH.sol";

// Chainlink Mock
import {MockV3Aggregator} from "@chainlink/local/src/data-feeds/MockV3Aggregator.sol";

// Contracts
import {MeritManager as MM} from "../src/MeritManager.sol";
import {TotemFactory as TF} from "../src/TotemFactory.sol";
import {TotemTokenDistributor as TTD} from "../src/TotemTokenDistributor.sol";
import {TotemToken as TT} from "../src/TotemToken.sol";
import {Totem} from "../src/Totem.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {Treasury} from "../src/Treasury.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {Posts as P} from "../src/Posts.sol";
import {Shards} from "../src/Shards.sol";
import {BoostSystem} from "../src/BoostSystem.sol";
import {BadgeNFT} from "../src/BadgeNFT.sol";
import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";

// Deployer
import {Deployer} from "test/util/Deployer.sol";

// Mocks
import {MockVRFCoordinator} from "./mocks/MockVRFCoordinator.sol";
import {MockBadgeNFT} from "./mocks/MockBadgeNFT.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

contract Base is Test {
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

    TransparentUpgradeableProxy postsProxy;
    P postsImpl;
    P posts;

    TransparentUpgradeableProxy shardProxy;
    Shards shardsImpl;
    Shards shards;

    // BoostSystem
    TransparentUpgradeableProxy boostSystemProxy;
    BoostSystem boostSystemImpl;
    BoostSystem boostSystem;

    // BadgeNFT
    BadgeNFT badgeNFT;

    // MockVRFCoordinator
    MockVRFCoordinator mockVRFCoordinator;

    // TokenHoldersOracle
    TokenHoldersOracle holdersOracle;

    // uni
    IUniswapV2Factory uniFactory;
    IUniswapV2Pair pair;
    IUniswapV2Router02 router;
    WETH weth;

    // MockV3Aggregator
    MockV3Aggregator mockV3Aggregator;

    address deployer;
    address userA;
    address userB;
    address userC;
    address userD;

    uint256 deployerPrivateKey = 0x1;
    uint256 userAPrivateKey = 0x2;
    uint256 userBPrivateKey = 0x3;
    uint256 userCPrivateKey = 0x4;
    uint256 userDPrivateKey = 0x5;

    function setUp() public {
        deployer = vm.addr(deployerPrivateKey);
        userA = vm.addr(userAPrivateKey);
        userB = vm.addr(userBPrivateKey);
        userC = vm.addr(userCPrivateKey);
        userD = vm.addr(userDPrivateKey);

        prank(deployer);
        _deploy();

        warp(24 hours);
    }

    // HELPERS

    function createPost(
        address _creator,
        uint256 _totemId
    ) internal returns (uint256) {
        TF.TotemData memory data = factory.getTotemData(_totemId);
        prank(_creator);
        return
            posts.createPost(
                data.totemAddr,
                abi.encodePacked(keccak256("Test"))
            );
    }

    function createPostWithTotem(
        address _creator,
        address _totemAddr
    ) internal returns (uint256) {
        prank(_creator);
        return
            posts.createPost(_totemAddr, abi.encodePacked(keccak256("Test")));
    }

    function createTotem(address _creator) internal returns (uint256) {
        prank(_creator);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotem(
            abi.encodePacked(keccak256("Test")),
            "Test Totem",
            "TST",
            new address[](0)
        );

        return factory.getLastId() - 1;
    }

    function createTotemWithAddrInReturn(
        address _creator
    ) internal returns (address) {
        prank(_creator);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotem("dataHash", "TotemToken", "TT", new address[](0));
        TF.TotemData memory totemData = factory.getTotemData(
            factory.getLastId() - 1
        );
        return totemData.totemTokenAddr;
    }

    function createTotemWithNFT(address _creator) internal returns (uint256) {
        MockERC721 nftToken = new MockERC721();

        prank(deployer);
        address[] memory users = new address[](1);
        users[0] = _creator;
        factory.authorizeUsers(address(nftToken), users);

        prank(_creator);
        astrToken.approve(address(factory), factory.getCreationFee());
        address[] memory nftAddresses = new address[](1);
        nftAddresses[0] = address(nftToken);

        vm.mockCall(
            address(holdersOracle),
            abi.encodeWithSelector(
                TokenHoldersOracle.requestNFTCount.selector,
                address(nftToken)
            ),
            abi.encode(0)
        );

        factory.createTotemWithExistingToken(
            abi.encodePacked(keccak256("NFT Test")),
            address(nftToken),
            new address[](0)
        );

        return factory.getLastId() - 1;
    }

    function buyAllTotemTokens(address _totemTokenAddr) internal {
        uint256 counter = type(uint32).max;
        do {
            address user = vm.addr(
                uint256(keccak256(abi.encodePacked(counter++)))
            );
            if (user == address(distr)) continue;
            vm.deal(user, 1 ether);
            paymentToken.mint(user, 2_500_000 ether);

            prank(user);
            uint256 available = distr.getAvailableTokensForPurchase(
                user,
                _totemTokenAddr
            );
            paymentToken.approve(address(distr), available);

            distr.buy(_totemTokenAddr, available);
        } while (IERC20(_totemTokenAddr).balanceOf(address(distr)) > 0);
    }

    // Helper function to create boost signature
    function createBoostSignature(
        address _user,
        address _totemAddr,
        uint256 _timestamp
    ) internal view returns (bytes memory) {
        // Create message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(_user, _totemAddr, _timestamp)
        );

        // Create Ethereum signed message hash (with prefix)
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        // Sign with deployer's private key (frontend signer)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            deployerPrivateKey,
            ethSignedMessageHash
        );
        return abi.encodePacked(r, s, v);
    }

    // Helper function to perform boost with signature (auto-waits for interval)
    function performBoost(address _user, address _totemAddr) internal {
        // Check if we need to wait for boost interval
        (uint256 lastBoostTimestamp, , , , , , , ) = boostSystem.getBoostData(
            _user,
            _totemAddr
        );
        if (lastBoostTimestamp > 0) {
            uint256 freeBoostCooldown = boostSystem.getFreeBoostCooldown();
            if (block.timestamp < lastBoostTimestamp + freeBoostCooldown) {
                uint256 timeToWait = lastBoostTimestamp +
                    freeBoostCooldown -
                    block.timestamp;
                warp(timeToWait + 1);
            }
        }

        uint256 timestamp = block.timestamp;
        bytes memory signature = createBoostSignature(
            _user,
            _totemAddr,
            timestamp
        );
        prank(_user);
        boostSystem.boost(_totemAddr, timestamp, signature);
    }

    // Helper function to perform boost without auto-waiting (for testing reverts)
    function performBoostNoWait(address _user, address _totemAddr) internal {
        // Use a slightly different timestamp to avoid signature reuse
        uint256 timestamp = block.timestamp + 1;
        bytes memory signature = createBoostSignature(
            _user,
            _totemAddr,
            timestamp
        );
        prank(_user);
        boostSystem.boost(_totemAddr, timestamp, signature);
    }

    // Utility function to prank as a specific user
    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }

    function warp(uint256 _time) internal {
        vm.warp(block.timestamp + _time);
    }

    // Deploy all contracts
    function _deploy() internal {
        // Uni V2 deploying
        uniFactory = Deployer.deployFactory(deployer);
        // pair = IUniswapV2Pair(uniFactory.createPair(address(tokenA), address(tokenB)));
        weth = Deployer.deployWETH();
        router = Deployer.deployRouterV2(address(uniFactory), address(weth));

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
        astrToken.mint(userA, 1_000_000 ether);
        astrToken.mint(userB, 1_000_000 ether);
        astrToken.mint(userC, 1_000_000 ether);
        astrToken.mint(userD, 1_000_000 ether);

        // Set payment token
        paymentToken = astrToken;

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

        // TotemTokenDistributor
        distrImpl = new TTD();
        distrProxy = new TransparentUpgradeableProxy(
            address(distrImpl),
            deployer,
            ""
        );
        distr = TTD(payable(address(distrProxy)));
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
        distr.setUniswapV2Router(address(router));
        distr.setPaymentToken(address(paymentToken));
        paymentToken.mint(userA, 1_000_000 ether);

        mm.grantRole(mm.REGISTRATOR(), address(distr));
        mm.grantRole(mm.REGISTRATOR(), address(factory));
        
        // Set start time for merit distribution to begin immediately
        mm.setStartTime(block.timestamp + 1);

        // Deploy TokenHoldersOracle
        address routerAddress = makeAddr("chainlinkFunctionsRouter");
        holdersOracle = new TokenHoldersOracle(
            routerAddress,
            address(treasury)
        );

        // Grant roles and set configuration
        holdersOracle.grantRole(holdersOracle.CALLER_ROLE(), address(factory));
        holdersOracle.setSubscriptionId(1);
        holdersOracle.setGasLimit(300000);

        // Register in AddressRegistry
        registry.setAddress(
            bytes32("TOKEN_HOLDERS_ORACLE"),
            address(holdersOracle)
        );

        // Posts
        postsImpl = new P();
        postsProxy = new TransparentUpgradeableProxy(
            address(postsImpl),
            deployer,
            ""
        );
        posts = P(address(postsProxy));
        posts.initialize(address(registry));

        registry.setAddress(bytes32("POSTS"), address(posts));

        // Shards
        shardsImpl = new Shards();
        shardProxy = new TransparentUpgradeableProxy(
            address(shardsImpl),
            deployer,
            ""
        );
        shards = Shards(address(shardProxy));
        shards.initialize(address(registry));

        registry.setAddress(bytes32("SHARDS"), address(shards));

        posts.setShardToken();

        // BadgeNFT
        badgeNFT = new BadgeNFT();
        badgeNFT.initialize("Mytho Badges", "BADGE");

        // BoostSystem
        boostSystemImpl = new BoostSystem();
        boostSystemProxy = new TransparentUpgradeableProxy(
            address(boostSystemImpl),
            deployer,
            ""
        );
        boostSystem = BoostSystem(address(boostSystemProxy));

        // Deploy mock VRF coordinator
        mockVRFCoordinator = new MockVRFCoordinator();

        // Initialize BoostSystem with mock VRF coordinator
        boostSystem.initialize(
            address(registry),
            address(mockVRFCoordinator),
            1, // subscription ID
            keccak256("test") // key hash
        );

        registry.setAddress(bytes32("BOOST_SYSTEM"), address(boostSystem));

        // Setup BoostSystem
        boostSystem.setBadgeNFT(address(badgeNFT));
        boostSystem.setFrontendSigner(deployer); // Use deployer as frontend signer for tests

        badgeNFT.setBoostSystem(address(boostSystem));

        // MockV3Aggregator
        mockV3Aggregator = new MockV3Aggregator(8, 0.05e8);

        distr.setPriceFeed(address(paymentToken), address(mockV3Aggregator));

        mytho.toggleTransferability();
        mytho.grantRole(mytho.TRANSFEROR(), address(mm));
    }
}
