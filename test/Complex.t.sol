// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

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

import {MockToken} from "./mocks/MockToken.sol";

import { IUniswapV2Factory } from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Router02 } from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { WETH } from "lib/solmate/src/tokens/WETH.sol";

import { Deployer } from "test/util/Deployer.sol";

contract ComplexTest is Test {
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
    IUniswapV2Pair pair;
    IUniswapV2Router02 router;
    WETH weth;

    address deployer;
    address userA;
    address userB;

    function setUp() public {
        deployer = makeAddr("deployer");
        userA = makeAddr("userA");
        userB = makeAddr("userB");

        prank(deployer);
        _deploy();
    }

    // Test totem creation and initial token distribution
    function test_TotemCreating() public {
        assertEq(factory.getLastId(), 0);

        address totemTokenAddr = createTotem(userA);
        assertEq(factory.getLastId(), 1);

        TF.TotemData memory data = factory.getTotemData(0);
        assertEq(data.creator, userA);
        assertFalse(data.isCustomToken);

        TT token = TT(data.tokenAddr);
        assertEq(token.name(), "TotemToken");
        assertEq(token.symbol(), "TT");

        assertEq(token.balanceOf(userA), 250_000 ether);
        assertEq(token.balanceOf(address(distr)), 899_750_000 ether);
        assertEq(token.balanceOf(data.totemAddr), 100_000_000 ether);
    }

    // Test price conversion functions
    function test_PriceObtaining() public {
        address pToken = address(paymentToken);
        uint256 totemsToPayment = distr.totemsToPaymentToken(
            pToken,
            1_000_000_000 ether
        );
        uint256 paymentToTotems = distr.paymentTokenToTotems(
            pToken,
            100_000 ether
        );

        assertTrue(totemsToPayment > 0);
        assertTrue(paymentToTotems > 0);
        assertApproxEqRel(
            distr.paymentTokenToTotems(pToken, totemsToPayment),
            1_000_000_000 ether,
            1e16 // 1% tolerance
        );
    }

    // Test setting payment token by manager
    function test_PaymentTokensAdding() public {
        prank(deployer);
        address initialToken = distr.getPaymentToken();
        assertEq(initialToken, address(paymentToken));

        address newToken = address(new MockToken());
        distr.setPaymentToken(newToken);
        assertEq(distr.getPaymentToken(), newToken);

        // Test access control: non-manager should fail
        prank(userA);
        vm.expectRevert();
        distr.setPaymentToken(address(paymentToken));
    }

    // Test buying totem tokens
    function test_Buying() public {
        address totemTokenAddr = createTotem(userA);

        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        uint256 balanceBefore = paymentToken.balanceOf(userA);
        uint256 totemBalanceBefore = IERC20(totemTokenAddr).balanceOf(userA);

        distr.buy(totemTokenAddr, 100 ether);

        assertEq(
            paymentToken.balanceOf(userA),
            balanceBefore -
                distr.totemsToPaymentToken(address(paymentToken), 100 ether)
        );
        assertEq(
            IERC20(totemTokenAddr).balanceOf(userA),
            totemBalanceBefore + 100 ether
        );
    }

    // Test selling totem tokens
    function test_Selling() public {
        address totemTokenAddr = createTotem(userA);

        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        distr.buy(totemTokenAddr, 100 ether);

        uint256 paymentBefore = paymentToken.balanceOf(userA);
        uint256 totemBefore = IERC20(totemTokenAddr).balanceOf(userA);

        IERC20(totemTokenAddr).approve(address(distr), 50 ether);
        distr.sell(totemTokenAddr, 50 ether);

        assertEq(
            IERC20(totemTokenAddr).balanceOf(userA),
            totemBefore - 50 ether
        );
        assertApproxEqRel(
            paymentToken.balanceOf(userA),
            paymentBefore +
                distr.totemsToPaymentToken(address(paymentToken), 50 ether),
            1e16
        );
    }

    // Test burning tokens after sale period ends
    function test_BurningAfterSale() public {
        address totemTokenAddr = createTotem(userA);

        prank(userA);
        paymentToken.mint(userA, 100 ether); // Ensure enough balance
        paymentToken.approve(address(distr), 100 ether);
        distr.buy(totemTokenAddr, 100 ether);

        // End sale period by selling all tokens back
        prank(userA);
        IERC20(totemTokenAddr).approve(address(distr), 100 ether);
        distr.sell(totemTokenAddr, 100 ether);

        _buyAllTotemTokens(totemTokenAddr);

        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        prank(userA);
        IERC20(totemTokenAddr).approve(address(totem), 50 ether);
        totem.burnTotemTokens(50 ether);

        assertEq(
            IERC20(totemTokenAddr).balanceOf(userA),
            250_000 ether - 50 ether // Initial + bought - sold - burned
        );
    }

    // Test merit points allocation and MYTHO claiming
    function test_MeritAndClaim() public {
        address totemTokenAddr = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        _buyAllTotemTokens(totemTokenAddr);

        // Allocate merit points
        prank(deployer);
        mm.creditMerit(data.totemAddr, 1000);
        assertEq(
            mm.getTotemMeritPoints(data.totemAddr, mm.currentPeriod()),
            1000
        );

        // Warp time to end period and update state
        vm.warp(block.timestamp + 31 days);
        mm.updateState();

        // Claim MYTHO
        uint256 mythoBefore = mytho.balanceOf(data.totemAddr);
        prank(address(totem));
        totem.collectMYTH(0);
        assertTrue(mytho.balanceOf(data.totemAddr) > mythoBefore);
    }

    // Test transfer restrictions during sale period
    function test_SalePeriodRestrictions() public {
        address totemTokenAddr = createTotem(userA);
        TT token = TT(totemTokenAddr);

        prank(userA);
        vm.expectRevert(TT.NotAllowedInSalePeriod.selector);
        token.transfer(userB, 100 ether);
    }

    // Test creating totem with custom token
    function test_CreateTotemWithCustomToken() public {
        MockToken customToken = new MockToken();
        customToken.mint(deployer, 1_000_000 ether);

        prank(deployer);
        factory.addTokenToWhitelist(address(customToken));

        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotemWithExistingToken(
            "customDataHash",
            address(customToken)
        );

        TF.TotemData memory data = factory.getTotemData(0);
        assertTrue(data.isCustomToken);
        assertEq(data.tokenAddr, address(customToken));
        assertEq(data.creator, userA);
    }

    // Test boosting totem in Mythus period
    function test_TotemBoosting() public {
        address totemTokenAddr = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);

        uint256 available = distr.getAvailableTokensForPurchase(userA, totemTokenAddr);
        assertEq(available, 4_750_000 ether);

        // but all totem tokens and check if the distr balance eq to zero
        _buyAllTotemTokens(totemTokenAddr);
        assertEq(IERC20(totemTokenAddr).balanceOf(address(distr)), 0);

        vm.deal(userA, 1 ether); // Provide ETH for boost fee
        prank(userA);

        // try to boost not in mythus period and fail
        vm.expectRevert(MM.NotInMythumPeriod.selector);
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        // revert if boost fee too small
        vm.expectRevert(MM.InsufficientBoostFee.selector);
        mm.boostTotem{value: 0.0001 ether}(data.totemAddr);

        // revert if totem blacklisted
        prank(deployer);
        mm.grantRole(mm.BLACKLISTED(), data.totemAddr);
        prank(userA);
        vm.expectRevert(MM.TotemInBlocklist.selector);
        mm.boostTotem{value: 0.0001 ether}(data.totemAddr);

        // revoke blacklisted role from totem
        prank(deployer);
        mm.revokeRole(mm.BLACKLISTED(), data.totemAddr);

        // Warp to Mythus period (last 25% of period)
        warp(23 days);
        
        prank(userA);
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        // try to boost another time in the same period and fail
        vm.expectRevert(MM.AlreadyBoostedInPeriod.selector);
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        uint256 period = mm.currentPeriod();
        assertTrue(mm.hasUserBoostedInPeriod(userA, period));
        assertEq(mm.getTotemMeritPoints(data.totemAddr, period), 10); // Default boost value
        assertEq(address(treasury).balance, 0.001 ether);
        assertEq(mm.getUserBoostedTotem(userA, period), data.totemAddr);
        assertEq(mm.getUserBoostedTotem(userA, period + 1), address(0));

        // boost totem in the next mythum period
        warp(30 days);

        mm.boostTotem{value: 0.002 ether}(data.totemAddr);
        assertEq(address(treasury).balance, 0.002 ether);

        // check if points added correctly in the next period
        assertEq(mm.getTotemMeritPoints(data.totemAddr, period + 1), 10);
        assertEq(mm.getTotemMeritPoints(data.totemAddr, period + 2), 0);
        assertEq(mm.getUserBoostedTotem(userA, period + 1), data.totemAddr);
        assertEq(mm.getUserBoostedTotem(userA, period + 2), address(0));
    }

    // Test access control for manager functions
    function test_AccessControl() public {
        // Non-manager trying to credit merit
        prank(userA);
        vm.expectRevert();
        mm.creditMerit(address(1), 100);

        // Non-admin trying to set period duration
        prank(userA);
        vm.expectRevert();
        mm.setPeriodDuration(15 days);
    }

    // Test edge case: buying more than max tokens per address
    function test_BuyingExceedsMaxTokens() public {
        address totemTokenAddr = createTotem(userA);

        prank(userA);
        paymentToken.mint(userA, 1_000_000 ether);
        paymentToken.approve(address(distr), 1_000_000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(TTD.WrongAmount.selector, 5_000_001 ether)
        );
        distr.buy(totemTokenAddr, 5_000_001 ether); // Exceeds maxTokensPerAddress
    }

    // Test claiming MYTHO for already claimed period
    function test_ClaimAlreadyClaimedPeriod() public {
        address totemTokenAddr = createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        _buyAllTotemTokens(totemTokenAddr);
        assertTrue(mm.isRegisteredTotem(data.totemAddr));

        prank(deployer);
        mm.creditMerit(data.totemAddr, 1000);

        assertEq(mm.getTotemMeritPoints(data.totemAddr, 0), 1000);
        assertEq(mm.totalMeritPoints(0), 1000);

        warp(31 days);
        mm.updateState();

        prank(address(totem));
        totem.collectMYTH(0);

        vm.expectRevert(
            abi.encodeWithSelector(MM.AlreadyClaimed.selector, 0)
        );
        totem.collectMYTH(0); // Should revert on second attempt
    }

    // Utility function to create a totem
    function createTotem(address _totemCreator) public returns (address) {
        prank(_totemCreator);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotem("dataHash", "TotemToken", "TT");
        TF.TotemData memory totemData = factory.getTotemData(
            factory.getLastId() - 1
        );
        return totemData.tokenAddr;
    }

    function _buyAllTotemTokens(address _totemTokenAddr) internal {
        uint256 counter = type(uint32).max;
        do {
            address user = vm.addr(uint256(keccak256(abi.encodePacked(counter++))));
            if (user == address(distr)) continue;
            vm.deal(user, 1 ether);
            paymentToken.mint(user, 2_500_000 ether);

            prank(user);
            uint256 available = distr.getAvailableTokensForPurchase(user, _totemTokenAddr);
            paymentToken.approve(address(distr), available);

            distr.buy(_totemTokenAddr, available);
        } while (
            IERC20(_totemTokenAddr).balanceOf(address(distr)) > 0
        );
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
        distr.setUniswapV2Router(address(router));
        paymentToken = astrToken;
        distr.setPaymentToken(address(astrToken));
        paymentToken.mint(userA, 1_000_000 ether);

        mm.grantRole(mm.REGISTRATOR(), address(distr));
        mm.grantRole(mm.REGISTRATOR(), address(factory));
    }

    // Utility function to prank as a specific user
    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }

    function warp(uint256 _time) internal {
        vm.warp(block.timestamp + _time);
    }
}
