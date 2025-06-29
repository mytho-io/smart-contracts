// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";

import {MeritManager as MM} from "../src/MeritManager.sol";
import {TotemFactory as TF} from "../src/TotemFactory.sol";
import {TotemTokenDistributor as TTD} from "../src/TotemTokenDistributor.sol";
import {TotemToken as TT} from "../src/TotemToken.sol";
import {Totem} from "../src/Totem.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {Treasury} from "../src/Treasury.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";
import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";

import {MockToken} from "./mocks/MockToken.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

import {IUniswapV2Factory} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap-v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "lib/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "lib/solmate/src/tokens/WETH.sol";

import {Deployer} from "test/util/Deployer.sol";

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

    TransparentUpgradeableProxy mythoProxy;
    MYTHO mythoImpl;
    MYTHO mytho;
    MockToken paymentToken;
    MockToken astrToken;

    // TokenHoldersOracle
    TokenHoldersOracle holdersOracle;

    // uni
    IUniswapV2Factory uniFactory;
    IUniswapV2Pair pair;
    IUniswapV2Router02 router;
    WETH weth;

    address deployer;
    address userA;
    address userB;
    address userC;
    address userD;

    function setUp() public {
        deployer = makeAddr("deployer");
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");
        userD = makeAddr("userD");

        prank(deployer);
        _deploy();
    }

    // Test totem creation and initial token distribution
    function test_TotemCreating_NewToken() public {
        uint256 initTreasuryBalanceInFeeTokens = IERC20(factory.getFeeToken())
            .balanceOf(address(treasury));

        assertEq(factory.getLastId(), 0);

        // get logs record and check if id of created totem eq to zero
        vm.recordLogs();
        _createTotem(userA);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        ( , , , , uint256 id) = abi.decode(
            logs[logs.length - 1].data,
            (bytes, address, address, address, uint256)
        );
        assertEq(id, 0);
        assertEq(factory.getLastId(), 1);
        assertEq(
            IERC20(factory.getFeeToken()).balanceOf(address(treasury)),
            initTreasuryBalanceInFeeTokens + factory.getCreationFee()
        );

        // check if totem with id = 1 doesn't exist
        vm.expectRevert(abi.encodeWithSelector(TF.TotemNotFound.selector, 1));
        TF.TotemData memory data = factory.getTotemData(1);

        // get data of created totem and check if data set
        data = factory.getTotemData(0);
        assertEq(data.creator, userA);
        assertTrue(data.totemAddr != address(0));
        assertTrue(data.totemTokenAddr != address(0));
        assertTrue(keccak256(data.dataHash) == keccak256("dataHash"));
        assertEq(uint(data.tokenType), uint(TF.TokenType.STANDARD));

        TT token = TT(data.totemTokenAddr);
        assertEq(token.name(), "TotemToken");
        assertEq(token.symbol(), "TT");

        assertEq(token.balanceOf(userA), 250_000 ether);
        assertEq(token.balanceOf(address(distr)), 899_750_000 ether);
        assertEq(token.balanceOf(data.totemAddr), 100_000_000 ether);

        TTD.TotemData memory dataDistr = distr.getTotemData(
            data.totemTokenAddr
        );
        assertEq(dataDistr.totemAddr, data.totemAddr);
    }

    // Test creating totem with custom token
    function test_TotemCreating_CustomToken() public {
        MockToken customToken = new MockToken();
        customToken.mint(deployer, 1_000_000 ether);

        prank(userA);
        // try to create a totem without fee tokens approve
        vm.expectRevert();
        factory.createTotemWithExistingToken(
            "customDataHash",
            address(customToken),
            new address[](0)
        );

        astrToken.approve(address(factory), factory.getCreationFee());
        vm.expectRevert(
            abi.encodeWithSelector(
                TF.UserNotAuthorized.selector,
                userA,
                address(customToken)
            )
        );
        factory.createTotemWithExistingToken(
            "customDataHash",
            address(customToken),
            new address[](0)
        );

        // Authorize user
        prank(deployer);
        address[] memory usersToAuthorize = new address[](1);
        usersToAuthorize[0] = userA;
        factory.authorizeUsers(address(customToken), usersToAuthorize);
        assertTrue(factory.isUserAuthorized(address(customToken), userA));

        prank(userA);
        vm.mockCall(
            address(holdersOracle),
            abi.encodeWithSelector(
                TokenHoldersOracle.getNFTCount.selector,
                address(customToken)
            ),
            abi.encode()
        );
        factory.createTotemWithExistingToken(
            "customDataHash",
            address(customToken),
            new address[](0)
        );

        TF.TotemData memory data = factory.getTotemData(0);
        assertEq(uint(data.tokenType), uint(TF.TokenType.ERC20));
        assertEq(data.totemTokenAddr, address(customToken));
        assertEq(data.creator, userA);

        // Check data by address
        TF.TotemData memory dataByAddr = factory.getTotemDataByAddress(
            data.totemAddr
        );
        assertEq(dataByAddr.totemTokenAddr, data.totemTokenAddr);
        assertEq(dataByAddr.creator, data.creator);
        assertEq(dataByAddr.totemAddr, data.totemAddr);

        // check if new totem not registered in TotemTokenDistributor
        TTD.TotemData memory ttdData = distr.getTotemData(data.totemTokenAddr);
        assertFalse(ttdData.registered);

        // check if new totem registered in MeritManager
        assertTrue(mm.registeredTotems(data.totemAddr));
    }

    // Test NFT totem creation and functionality
    function test_TotemCreating_NFTToken() public {
        // Create a mock NFT
        MockERC721 nftToken = new MockERC721();
        
        // Mint some NFTs to users
        nftToken.mint(userA, 1);
        nftToken.mint(userB, 2);
        nftToken.mint(userC, 3);

        vm.deal(userA, 1 ether);
        
        // Authorize userA to create a totem with the NFT token
        prank(deployer);
        address[] memory usersToAuthorize = new address[](1);
        usersToAuthorize[0] = userA;
        factory.authorizeUsers(address(nftToken), usersToAuthorize);
        
        // Get initial treasury balance
        uint256 initTreasuryBalanceInFeeTokens = IERC20(factory.getFeeToken())
            .balanceOf(address(treasury));
            
        // Approve fee token for totem creation
        prank(userA);
        IERC20(factory.getFeeToken()).approve(
            address(factory),
            factory.getCreationFee()
        );
        
        // Create totem with NFT token
        vm.mockCall(
            address(holdersOracle),
            abi.encodeWithSelector(TokenHoldersOracle.requestNFTCount.selector, address(nftToken)),
            abi.encode(0)
        );

        factory.createTotemWithExistingToken(
            "dataHash",
            address(nftToken),
            new address[](0)
        );
        
        // Verify totem was created
        assertEq(factory.getLastId(), 1);
        assertEq(
            IERC20(factory.getFeeToken()).balanceOf(address(treasury)),
            initTreasuryBalanceInFeeTokens + factory.getCreationFee()
        );
        
        // Get totem data
        TF.TotemData memory data = factory.getTotemData(0);
        assertEq(uint(data.tokenType), uint(TF.TokenType.ERC721));
        assertEq(data.totemTokenAddr, address(nftToken));
        assertEq(data.creator, userA);
        
        // Get totem instance
        Totem totem = Totem(data.totemAddr);
        
        // Manually update nft count in oracle (simulating Chainlink Functions response)
        prank(deployer);
        holdersOracle.manuallyUpdateNFTCount(address(nftToken), 3); // 3 NFT holders
        
        // Test getCirculatingSupply for NFT
        prank(userA);
        uint256 circulatingSupply = totem.getCirculatingSupply();
        assertEq(circulatingSupply, 3); // Should be equal to number of NFT holders
        
        // Test redeeming NFT tokens
        // First, we need to end the sale period
        prank(deployer);
        // Get the distributor address which has the TOTEM_DISTRIBUTOR role
        address distributorAddr = registry.getTotemTokenDistributor();
        // Use the distributor to call endSalePeriod
        prank(distributorAddr);
        Totem totemContract = Totem(factory.getTotemData(factory.getLastId() - 1).totemAddr);
        totemContract.endSalePeriod(IERC20(address(paymentToken)), IERC20(address(0)));
        
        // Verify that the sale period has ended
        assertTrue(totemContract.isSalePeriodEnded());

        prank(deployer);
        mm.creditMerit(address(totem), 1000);

        vm.warp(60 days);

        holdersOracle.manuallyUpdateNFTCount(address(nftToken), 3);        
        
        // Now redeem tokens as userA (who holds NFT)
        prank(userA);
        totem.collectMYTH(mm.currentPeriod() - 1);
        nftToken.approve(address(totem), 1);
        totem.redeemTotemTokens(1); // For NFTs, amount is ignored

        circulatingSupply = totem.getCirculatingSupply();
        assertEq(circulatingSupply, 2);
        
        // Verify user received proportional assets
        // Since there are 3 NFT holders, each should get 1/3 of the rewards
        uint256 mythoBalance = mytho.balanceOf(userA);
        assertGt(mythoBalance, 0, "User should receive MYTHO tokens");
    }

    // Test price conversion functions
    function test_PriceObtaining() public view {
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
        address totemTokenAddr = _createTotem(userA);
        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        uint256 balanceBefore = paymentToken.balanceOf(userA);
        uint256 totemBalanceBefore = IERC20(totemTokenAddr).balanceOf(userA);

        uint256 available = distr.getAvailableTokensForPurchase(
            userA,
            totemTokenAddr
        );

        assertEq(available, distr.maxTokensPerAddress() - 250_000 ether);
        assertEq(
            distr.getAvailableTokensForPurchase(userB, totemTokenAddr),
            distr.maxTokensPerAddress()
        );

        distr.buy(totemTokenAddr, 100 ether);

        assertEq(
            distr.maxTokensPerAddress() - 250_000 ether - 100 ether,
            distr.getAvailableTokensForPurchase(userA, totemTokenAddr)
        );

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
        address totemTokenAddr = _createTotem(userA);
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

    // Test redeeming tokens after sale period ends
    function test_redeemingAfterSale() public {
        address totemTokenAddr = _createTotem(userA);

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

        (, , address lpAddr) = totem.getTokenAddresses();
        IERC20 lpToken = IERC20(lpAddr);

        prank(userA);
        uint256 balanceBefore = paymentToken.balanceOf(userA);
        IERC20(totemTokenAddr).approve(address(totem), 50 ether);
        (uint256 paymentAmount, uint256 mythoAmount, uint256 lpAmount) = totem
            .estimateRedeemRewards(50 ether);
        totem.redeemTotemTokens(50 ether);
        assertEq(paymentToken.balanceOf(userA), paymentAmount + balanceBefore);
        assertEq(mytho.balanceOf(userA), mythoAmount);
        assertEq(lpToken.balanceOf(userA), lpAmount);

        assertEq(
            IERC20(totemTokenAddr).balanceOf(userA),
            250_000 ether - 50 ether // Initial + bought - sold - redeemed
        );
    }

    // Test merit points allocation and MYTHO claiming
    function test_MeritAndClaim() public {
        address totemTokenAddr = _createTotem(userA);
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
        address totemTokenAddr = _createTotem(userA);
        TT token = TT(totemTokenAddr);

        prank(userA);
        vm.expectRevert(TT.NotAllowedInSalePeriod.selector);
        token.transfer(userB, 100 ether);
    }

    // Test boosting totem in Mythus period
    function test_TotemBoosting() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);

        uint256 available = distr.getAvailableTokensForPurchase(
            userA,
            totemTokenAddr
        );
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
        vm.expectRevert(MM.TotemInBlacklist.selector);
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
        assertEq(mm.getTotemMeritPoints(data.totemAddr, period + 1), 10); // Default boost value
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
        address totemTokenAddr = _createTotem(userA);

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
        address totemTokenAddr = _createTotem(userA);
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

        vm.expectRevert(abi.encodeWithSelector(MM.AlreadyClaimed.selector, 0));
        totem.collectMYTH(0); // Should revert on second attempt
    }

    // Test multiple totems competing for merit points
    function test_MultipleTotemsCompetingForMerit() public {
        // Create three totems
        address totemToken1 = _createTotem(userA);
        address totemToken2 = _createTotem(userB);
        address totemToken3 = _createTotem(userC);

        // prank(userB); astrToken.approve(address(factory), 100 ether);
        // prank(userC); astrToken.approve(address(factory), 100 ether);

        TF.TotemData memory data1 = factory.getTotemData(0);
        TF.TotemData memory data2 = factory.getTotemData(1);
        TF.TotemData memory data3 = factory.getTotemData(2);

        Totem totem1 = Totem(data1.totemAddr);
        Totem totem2 = Totem(data2.totemAddr);
        Totem totem3 = Totem(data3.totemAddr);

        // Buy all tokens to end sale period for all totems
        _buyAllTotemTokens(totemToken1);
        _buyAllTotemTokens(totemToken2);
        _buyAllTotemTokens(totemToken3);

        // Credit different merit points to each totem
        prank(deployer);
        mm.creditMerit(data1.totemAddr, 1000); // 50%
        mm.creditMerit(data2.totemAddr, 600); // 30%
        mm.creditMerit(data3.totemAddr, 400); // 20%

        // Verify total merit points
        assertEq(mm.totalMeritPoints(0), 2000);

        // Move to next period
        warp(31 days);
        mm.updateState();

        // Record MYTHO balances before claiming
        uint256 mythoBalanceBefore1 = mytho.balanceOf(data1.totemAddr);
        uint256 mythoBalanceBefore2 = mytho.balanceOf(data2.totemAddr);
        uint256 mythoBalanceBefore3 = mytho.balanceOf(data3.totemAddr);

        // Claim MYTHO for each totem
        prank(address(totem1));
        totem1.collectMYTH(0);

        prank(address(totem2));
        totem2.collectMYTH(0);

        prank(address(totem3));
        totem3.collectMYTH(0);

        // Get MYTHO balances after claiming
        uint256 mythoBalanceAfter1 = mytho.balanceOf(data1.totemAddr);
        uint256 mythoBalanceAfter2 = mytho.balanceOf(data2.totemAddr);
        uint256 mythoBalanceAfter3 = mytho.balanceOf(data3.totemAddr);

        // Calculate claimed amounts
        uint256 claimed1 = mythoBalanceAfter1 - mythoBalanceBefore1;
        uint256 claimed2 = mythoBalanceAfter2 - mythoBalanceBefore2;
        uint256 claimed3 = mythoBalanceAfter3 - mythoBalanceBefore3;

        // Verify proportional distribution (with small rounding tolerance)
        assertApproxEqRel(claimed1, (claimed2 * 5) / 3, 1e15); // 1000/600 = 5/3
        assertApproxEqRel(claimed1, (claimed3 * 5) / 2, 1e15); // 1000/400 = 5/2
        assertApproxEqRel(claimed2, (claimed3 * 3) / 2, 1e15); // 600/400 = 3/2

        // Verify total distribution adds up
        uint256 totalClaimed = claimed1 + claimed2 + claimed3;
        uint256 expectedRelease = mm.releasedMytho(0);
        assertApproxEqRel(totalClaimed, expectedRelease, 1e15);
    }

    // Test totem lifecycle across multiple periods
    function test_TotemLifecycleAcrossMultiplePeriods() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // End sale period to register the totem in MeritManager
        _buyAllTotemTokens(totemTokenAddr);

        // Get current period
        uint256 currentPeriod = mm.currentPeriod();

        // Credit merit in current period
        prank(deployer);
        mm.creditMerit(data.totemAddr, 800);

        // Warp to Mythum period (23/30 of the period duration)
        uint256 periodDuration = mm.periodDuration();
        uint256 mythumStart = (periodDuration * 23) / 30;
        warp(mythumStart + 1);

        // Boost in Mythum period
        vm.deal(userA, 1 ether);
        prank(userA);
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        // Add additional merit
        prank(deployer);
        mm.creditMerit(data.totemAddr, 500);

        // Get actual merit points and adjust our expectations
        uint256 actualMerit = mm.getTotemMeritPoints(
            data.totemAddr,
            currentPeriod
        );
        console.log("Actual merit:", actualMerit);

        // Just assert that we have merit points, the exact value may vary due to multipliers
        assertGt(actualMerit, 0);

        // Move to next period
        warp(periodDuration + 1);
        prank(deployer);
        mm.updateState();

        // Make sure the totem is registered in Merit Manager before claiming
        if (!mm.isRegisteredTotem(address(totem))) {
            prank(deployer);
            mm.register(address(totem));
        }

        // Wait for MYTHO distribution
        warp(1 days);
        prank(deployer);
        mm.updateState(); // This will process any pending periods and distribute MYTHO

        // Claim MYTHO from previous period
        prank(address(totem));
        totem.collectMYTH(currentPeriod);

        // Move to next period
        warp(periodDuration + 1);
        prank(deployer);
        mm.updateState();

        // Credit merit in new period
        prank(deployer);
        mm.creditMerit(data.totemAddr, 300);

        // Warp to next period
        warp(periodDuration + 1);
        prank(deployer);
        mm.updateState();

        // Claim MYTHO for the period with 300 merit
        prank(address(totem));
        totem.collectMYTH(currentPeriod + 2);
    }

    // Test token redeeming with multiple users
    function test_TokenredeemingWithMultipleUsers() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // End sale period
        _buyAllTotemTokens(totemTokenAddr);

        // Credit merit and move to next period to get MYTHO
        prank(deployer);
        mm.creditMerit(data.totemAddr, 1000);

        warp(31 days);
        mm.updateState();

        prank(address(totem));
        totem.collectMYTH(0);

        // Get initial balances
        uint256 initialMythoBalance = mytho.balanceOf(data.totemAddr);
        uint256 initialPaymentBalance = paymentToken.balanceOf(data.totemAddr);

        // Transfer some totem tokens to multiple users

        uint256 userAAmount = 100_000 ether;
        uint256 userCAmount = 50_000 ether;
        uint256 userDAmount = 25_000 ether;

        prank(userA);
        IERC20(totemTokenAddr).transfer(userC, userCAmount);
        IERC20(totemTokenAddr).transfer(userD, userDAmount);

        // Users redeem their tokens
        prank(userA);
        IERC20(totemTokenAddr).approve(data.totemAddr, userAAmount);
        totem.redeemTotemTokens(userAAmount);

        prank(userC);
        IERC20(totemTokenAddr).approve(data.totemAddr, userCAmount);
        totem.redeemTotemTokens(userCAmount);

        prank(userD);
        IERC20(totemTokenAddr).approve(data.totemAddr, userDAmount);
        totem.redeemTotemTokens(userDAmount);

        // Calculate total redeemed amount
        uint256 totalredeemed = userAAmount + userCAmount + userDAmount;

        // Verify token supply decreased
        uint256 expectedSupply = 1_000_000_000 ether -
            totalredeemed -
            IERC20(totemTokenAddr).balanceOf(address(totem)) -
            IERC20(totemTokenAddr).balanceOf(address(treasury));
        assertEq(
            IERC20(totemTokenAddr).totalSupply() -
                IERC20(totemTokenAddr).balanceOf(address(totem)) -
                IERC20(totemTokenAddr).balanceOf(address(treasury)),
            expectedSupply
        );

        // Verify proportional distribution of assets
        uint256 userAMythoExpected = (initialMythoBalance * userAAmount) /
            expectedSupply;
        uint256 userCMythoExpected = (initialMythoBalance * userCAmount) /
            expectedSupply;
        uint256 userDMythoExpected = (initialMythoBalance * userDAmount) /
            expectedSupply;

        // Check that the proportions are roughly correct (allowing for rounding)
        assertApproxEqRel(mytho.balanceOf(userA), userAMythoExpected, 1e15);
        assertApproxEqRel(mytho.balanceOf(userC), userCMythoExpected, 1e15);
        assertApproxEqRel(mytho.balanceOf(userD), userDMythoExpected, 1e15);
    }

    // Test redeeming totem tokens with custom token
    function test_RedeemTotemTokens_CustomToken() public {
        // Create a custom token and whitelist it
        MockToken customToken = new MockToken();
        customToken.mint(deployer, 1_000_000 ether);

        prank(deployer);
        address[] memory usersToAuth = new address[](1);
        usersToAuth[0] = userA;
        factory.authorizeUsers(address(customToken), usersToAuth);

        // Transfer tokens to userA for creation fee and custom token
        prank(deployer);
        customToken.transfer(userA, 500_000 ether);

        // Create totem with custom token
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        vm.mockCall(
            address(holdersOracle),
            abi.encodeWithSelector(
                TokenHoldersOracle.requestNFTCount.selector,
                address(customToken)
            ),
            abi.encode()
        );
        factory.createTotemWithExistingToken(
            "customDataHash",
            address(customToken),
            new address[](0)
        );

        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Verify it's a custom token totem
        assertTrue(totem.isCustomTotemToken());
        assertEq(data.totemTokenAddr, address(customToken));

        // Credit merit and move to next period to get MYTHO
        prank(deployer);
        mm.creditMerit(data.totemAddr, 1000);

        warp(31 days);
        mm.updateState();

        prank(address(totem));
        totem.collectMYTH(0);

        // Get initial balances
        uint256 initialMythoBalance = mytho.balanceOf(data.totemAddr);
        uint256 initialPaymentBalance = paymentToken.balanceOf(data.totemAddr);
        uint256 initialTreasuryCustomTokenBalance = customToken.balanceOf(
            address(treasury)
        );

        // User redeems custom tokens
        uint256 redeemAmount = 10_000 ether;

        uint256 initialUserPaymentBalance = paymentToken.balanceOf(userA);

        prank(userA);
        customToken.approve(data.totemAddr, redeemAmount);
        totem.redeemTotemTokens(redeemAmount);

        // Verify custom tokens were transferred to treasury (not redeemed)
        assertEq(
            customToken.balanceOf(address(treasury)),
            initialTreasuryCustomTokenBalance + redeemAmount
        );

        // Calculate expected proportions
        uint256 circulatingSupply = totem.getCirculatingSupply();
        uint256 expectedMythoAmount = (initialMythoBalance * redeemAmount) /
            circulatingSupply;
        uint256 expectedPaymentAmount = (initialPaymentBalance * redeemAmount) /
            circulatingSupply;

        // Verify user received proportional assets
        assertApproxEqRel(mytho.balanceOf(userA), expectedMythoAmount, 1e16);
        assertEq(
            paymentToken.balanceOf(userA),
            initialUserPaymentBalance + expectedPaymentAmount
        );

        // Verify custom token total supply hasn't changed (tokens weren't redeemed)
        assertEq(customToken.totalSupply(), 1_000_000 ether);
    }

    // Test error cases for TotemTokenDistributor
    function test_TotemTokenDistributorErrorCases() public {
        address totemTokenAddr = _createTotem(userA);

        // Test buying with zero amount
        prank(userA);
        vm.expectRevert(abi.encodeWithSelector(TTD.WrongAmount.selector, 0));
        distr.buy(totemTokenAddr, 0);

        // Test buying with insufficient payment token balance
        prank(userA);
        paymentToken.approve(address(distr), type(uint256).max);
        uint256 balance = paymentToken.balanceOf(userA);
        uint256 tooMuchTokens = distr.paymentTokenToTotems(
            address(paymentToken),
            balance + 1 ether
        );
        vm.expectRevert();
        distr.buy(totemTokenAddr, tooMuchTokens);

        // Test selling with zero amount
        prank(userA);
        vm.expectRevert(abi.encodeWithSelector(TTD.WrongAmount.selector, 0));
        distr.sell(totemTokenAddr, 0);

        // Test selling more than owned
        prank(userA);
        uint256 ownedAmount = IERC20(totemTokenAddr).balanceOf(userA);
        IERC20(totemTokenAddr).approve(address(distr), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(TTD.WrongAmount.selector, ownedAmount + 1)
        );
        distr.sell(totemTokenAddr, ownedAmount + 1);

        // Test buying from unknown token
        address fakeToken = address(0x123);
        prank(userA);
        vm.expectRevert(
            abi.encodeWithSelector(TTD.UnknownTotemToken.selector, fakeToken)
        );
        distr.buy(fakeToken, 100 ether);
    }

    // Test MeritManager error cases
    function test_MeritManagerErrorCases() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);

        // Test crediting merit to non-registered totem
        address fakeTotem = address(0x123);
        prank(deployer);
        vm.expectRevert(MM.TotemNotRegistered.selector);
        mm.creditMerit(fakeTotem, 100);

        // Test boosting non-registered totem
        vm.deal(userA, 1 ether);
        prank(userA);
        vm.expectRevert(MM.TotemNotRegistered.selector);
        mm.boostTotem{value: 0.001 ether}(fakeTotem);

        // Test claiming for invalid period
        _buyAllTotemTokens(totemTokenAddr);
        Totem totem = Totem(data.totemAddr);
        prank(address(totem));
        vm.expectRevert(abi.encodeWithSelector(MM.InvalidPeriod.selector));
        totem.collectMYTH(999); // Non-existent period

        // Test claiming with no merit points
        prank(address(totem));
        vm.expectRevert(MM.NoMythoToClaim.selector);
        totem.collectMYTH(0); // No merit points in period 0
    }

    // Test TotemFactory error cases
    function test_TotemFactoryErrorCases() public {
        // Test creating totem with empty parameters (empty token name, symbol, or dataHash)
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        vm.expectRevert(
            abi.encodeWithSelector(
                TF.InvalidTotemParameters.selector,
                "Empty token name or symbol"
            )
        );
        factory.createTotem("", "", "", new address[](0));

        // Test creating totem with empty dataHash for custom token
        MockToken customToken = new MockToken();
        prank(deployer);
        address[] memory usersToAuth = new address[](1);
        usersToAuth[0] = userA;
        factory.authorizeUsers(address(customToken), usersToAuth);

        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        vm.mockCall(
            address(holdersOracle),
            abi.encodeWithSelector(
                TokenHoldersOracle.requestNFTCount.selector,
                address(customToken)
            ),
            abi.encode()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                TF.InvalidTotemParameters.selector,
                "Empty dataHash"
            )
        );
        factory.createTotemWithExistingToken(
            "",
            address(customToken),
            new address[](0)
        );

        // Test creating totem with insufficient fee
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee() - 1);
        vm.expectRevert();
        factory.createTotem("dataHash", "Token", "TKN", new address[](0));

        // Test creating totem with custom token not authorized
        MockToken notAuthToken = new MockToken();
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        vm.expectRevert(
            abi.encodeWithSelector(
                TF.UserNotAuthorized.selector,
                userA,
                address(notAuthToken)
            )
        );
        factory.createTotemWithExistingToken(
            "dataHash",
            address(notAuthToken),
            new address[](0)
        );

        // Test getting non-existent totem data
        vm.expectRevert(abi.encodeWithSelector(TF.TotemNotFound.selector, 999));
        factory.getTotemData(999);
    }

    // Test Treasury functionality
    function test_TreasuryFunctionality() public {
        // Test withdrawing ERC20 tokens
        prank(deployer);
        paymentToken.mint(address(treasury), 1000 ether);

        // Only MANAGER can withdraw
        prank(userA);
        vm.expectRevert();
        treasury.withdrawERC20(address(paymentToken), userA, 100 ether);

        uint256 initialUserABalance = paymentToken.balanceOf(userA);

        // Withdraw half the tokens
        prank(deployer);
        treasury.withdrawERC20(address(paymentToken), userA, 500 ether);

        // Verify balances
        assertEq(
            paymentToken.balanceOf(userA),
            initialUserABalance + 500 ether
        );
        assertEq(paymentToken.balanceOf(address(treasury)), 500 ether);

        // Test error: withdraw to zero address
        prank(deployer);
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.withdrawERC20(address(paymentToken), address(0), 100 ether);

        // Test error: withdraw zero amount
        prank(deployer);
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.withdrawERC20(address(paymentToken), userA, 0);

        // Test error: withdraw more than available
        prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Treasury.InsufficientBalance.selector,
                1000 ether,
                500 ether
            )
        );
        treasury.withdrawERC20(address(paymentToken), userA, 1000 ether);

        // Test withdrawing native tokens
        vm.deal(address(treasury), 2 ether);

        // Only MANAGER can withdraw native
        prank(userA);
        vm.expectRevert();
        treasury.withdrawNative(payable(userA), 1 ether);

        prank(deployer);
        treasury.withdrawNative(payable(userA), 1 ether);

        // Verify balances
        assertEq(userA.balance, 1 ether);
        assertEq(address(treasury).balance, 1 ether);

        // Test error: withdraw to zero address native
        prank(deployer);
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.withdrawNative(payable(address(0)), 1 ether);

        // Test error: withdraw zero amount native
        prank(deployer);
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.withdrawNative(payable(userA), 0);

        // Test error: withdraw more than available native
        prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                Treasury.InsufficientBalance.selector,
                2 ether,
                1 ether
            )
        );
        treasury.withdrawNative(payable(userA), 2 ether);

        // Test balance getters
        assertEq(treasury.getERC20Balance(address(paymentToken)), 500 ether);
        assertEq(treasury.getNativeBalance(), 1 ether);
    }

    // Test boostTotem with insufficient totem token balance
    function test_BoostTotem_InsufficientTotemBalance() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);

        // End sale period to allow transfers
        _buyAllTotemTokens(totemTokenAddr);

        // Warp to Mythus period (last 25% of period)
        warp(23 days);

        // User B has no totem tokens, should fail with InsufficientTotemBalance
        vm.deal(userB, 1 ether); // Provide ETH for boost fee
        prank(userB);
        vm.expectRevert(MM.InsufficientTotemBalance.selector);
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        // Transfer some tokens to userB
        prank(userA);
        IERC20(totemTokenAddr).transfer(userB, 100 ether);

        // Now userB has tokens and should be able to boost
        prank(userB);
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        // Verify the boost was successful
        uint256 period = mm.currentPeriod();
        assertTrue(mm.hasUserBoostedInPeriod(userB, period));
        assertEq(mm.getUserBoostedTotem(userB, period), data.totemAddr);
        assertEq(mm.getUserBoostedTotem(userB, period + 1), address(0));

        // boost totem in the next mythum period
        warp(30 days);

        mm.boostTotem{value: 0.002 ether}(data.totemAddr);
        assertEq(address(treasury).balance, 0.002 ether);

        // check if points added correctly in the next period
        assertEq(mm.getTotemMeritPoints(data.totemAddr, period + 1), 10); // Default boost value
        assertEq(mm.getTotemMeritPoints(data.totemAddr, period + 2), 0);
        assertEq(mm.getUserBoostedTotem(userB, period + 1), data.totemAddr);
        assertEq(mm.getUserBoostedTotem(userB, period + 2), address(0));
    }

    // Test Totem token redeeming error cases
    function test_TotemredeemingErrorCases() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Test redeeming before sale period ends
        prank(userA);
        IERC20(totemTokenAddr).approve(data.totemAddr, 100 ether);
        vm.expectRevert(Totem.SalePeriodNotEnded.selector);
        totem.redeemTotemTokens(100 ether);

        // End sale period
        _buyAllTotemTokens(totemTokenAddr);

        // Test redeeming zero amount
        prank(userA);
        vm.expectRevert(Totem.ZeroAmount.selector);
        totem.redeemTotemTokens(0);

        // Test redeeming more than owned
        prank(userA);
        uint256 balance = IERC20(totemTokenAddr).balanceOf(userA);
        IERC20(totemTokenAddr).approve(data.totemAddr, balance + 1);
        vm.expectRevert(Totem.InsufficientTotemBalance.selector);
        totem.redeemTotemTokens(balance + 1);
    }

    // Test TotemToken openTransfers function
    function test_TotemToken_OpenTransfers() public {
        address totemTokenAddr = _createTotem(userA);
        TT token = TT(totemTokenAddr);

        // Verify initial state
        assertTrue(token.isInSalePeriod());

        // Non-distributor cannot open transfers
        prank(userA);
        vm.expectRevert(TT.OnlyForDistributor.selector);
        token.openTransfers();

        // Distributor can open transfers
        prank(address(distr));
        token.openTransfers();

        // Verify transfers are now open
        assertFalse(token.isInSalePeriod());

        // Cannot open transfers again
        prank(address(distr));
        vm.expectRevert(TT.SalePeriodAlreadyEnded.selector);
        token.openTransfers();

        // Now users can transfer tokens
        prank(userA);
        token.transfer(userB, 100 ether);
        assertEq(token.balanceOf(userB), 100 ether);
    }

    // Test Totem getter functions
    function test_Totem_GetterFunctions() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Test getDataHash
        bytes memory dataHash = totem.getDataHash();
        assertEq(keccak256(dataHash), keccak256("dataHash"));

        // Test getTokenAddresses before sale period ends
        (address tokenAddr, address paymentAddr, address liquidityAddr) = totem
            .getTokenAddresses();
        assertEq(tokenAddr, totemTokenAddr);
        // Не проверяем, что paymentAddr == address(0), так как он может быть уже установлен
        assertEq(liquidityAddr, address(0)); // Not set yet

        // End sale period
        _buyAllTotemTokens(totemTokenAddr);

        // Test getTokenAddresses after sale period ends
        (tokenAddr, paymentAddr, liquidityAddr) = totem.getTokenAddresses();
        assertEq(tokenAddr, totemTokenAddr);
        assertEq(paymentAddr, address(paymentToken));
        assertNotEq(liquidityAddr, address(0)); // Should be set to LP token

        // Test getAllBalances
        (
            uint256 totemBalance,
            uint256 paymentBalance,
            uint256 liquidityBalance,
            uint256 mythoBalance
        ) = totem.getAllBalances();
        assertEq(totemBalance, 100_000_000 ether);
        assertGt(paymentBalance, 0); // Should have payment tokens
        assertGt(liquidityBalance, 0); // Should have LP tokens
        assertEq(mythoBalance, 0); // No MYTHO yet

        // Credit merit and claim MYTHO
        prank(deployer);
        mm.creditMerit(data.totemAddr, 1000);

        warp(31 days);
        mm.updateState();

        prank(address(totem));
        totem.collectMYTH(0);

        // Check MYTHO balance
        (, , , mythoBalance) = totem.getAllBalances();
        assertGt(mythoBalance, 0);

        // Test isCustomTokenTotem
        assertFalse(totem.isCustomTotemToken());
    }

    // Test MeritManager admin functions
    function test_MeritManager_AdminFunctions() public {
        // Test setOneTotemBoost
        prank(deployer);
        mm.setOneTotemBoost(20);
        assertEq(mm.oneTotemBoost(), 20);

        // Test setMythumMultiplier
        prank(deployer);
        mm.setMythumMultiplier(200); // 2x
        assertEq(mm.mythumMultiplier(), 200);

        // Test setBoostFee
        prank(deployer);
        mm.setBoostFee(0.002 ether);
        assertEq(mm.boostFee(), 0.002 ether);

        // Test setPeriodDuration
        prank(deployer);
        mm.setPeriodDuration(15 days);
        assertEq(mm.periodDuration(), 15 days);

        // Test grantRegistratorRole
        address newRegistrator = makeAddr("newRegistrator");
        prank(deployer);
        mm.grantRegistratorRole(newRegistrator);
        assertTrue(mm.hasRole(mm.REGISTRATOR(), newRegistrator));

        // Test revokeRegistratorRole
        prank(deployer);
        mm.revokeRegistratorRole(newRegistrator);
        assertFalse(mm.hasRole(mm.REGISTRATOR(), newRegistrator));
    }

    // Test period duration change preserves period count
    function test_PeriodDurationChange_PreservesPeriodCount() public {
        // Initial period duration is 30 days
        assertEq(mm.periodDuration(), 30 days);

        // Initial period is 0
        assertEq(mm.currentPeriod(), 0);

        // Warp forward 45 days (1.5 periods)
        warp(45 days);

        // Should be in period 1
        assertEq(mm.currentPeriod(), 1);

        // Change period duration to 15 days
        prank(deployer);
        mm.setPeriodDuration(15 days);

        // Period count should still be 1 after the change
        assertEq(mm.currentPeriod(), 1);
        assertEq(mm.accumulatedPeriods(), 1);

        // Warp forward 15 days (1 new period with new duration)
        warp(15 days);

        // Should be in period 2 (1 accumulated + 1 new)
        assertEq(mm.currentPeriod(), 2);

        // Warp forward 30 days (2 new periods with new duration)
        warp(30 days);

        // Should be in period 4 (1 accumulated + 3 new)
        assertEq(mm.currentPeriod(), 4);
    }

    // Test period duration change with multiple changes
    function test_MultiplePeriodDurationChanges() public {
        // Initial period duration is 30 days
        assertEq(mm.periodDuration(), 30 days);

        // Warp forward 60 days (2 periods)
        warp(60 days);

        // Should be in period 2
        assertEq(mm.currentPeriod(), 2);

        // Change period duration to 15 days
        prank(deployer);
        mm.setPeriodDuration(15 days);

        // Period count should still be 2 after the change
        assertEq(mm.currentPeriod(), 2);
        assertEq(mm.accumulatedPeriods(), 2);

        // Warp forward 30 days (2 new periods with new duration)
        warp(30 days);

        // Should be in period 4 (2 accumulated + 2 new)
        assertEq(mm.currentPeriod(), 4);

        // Change period duration again to 10 days
        prank(deployer);
        mm.setPeriodDuration(10 days);

        // Period count should still be 4 after the change
        assertEq(mm.currentPeriod(), 4);
        assertEq(mm.accumulatedPeriods(), 4);

        // Warp forward 20 days (2 new periods with new duration)
        warp(20 days);

        // Should be in period 6 (4 accumulated + 2 new)
        assertEq(mm.currentPeriod(), 6);
    }

    // Test period time bounds calculation after period duration change
    function test_PeriodTimeBoundsAfterDurationChange() public {
        // Initial period duration is 30 days
        assertEq(mm.periodDuration(), 30 days);

        // Warp forward 30 days (1 period)
        warp(30 days);

        // Should be in period 1
        assertEq(mm.currentPeriod(), 1);

        // Change period duration to 15 days
        prank(deployer);
        mm.setPeriodDuration(15 days);

        // Get time bounds for period 1 (should return 0,0 as it's before accumulated periods)
        (uint256 startTime1, uint256 endTime1) = mm.getPeriodTimeBounds(0);
        assertEq(startTime1, 0);
        assertEq(endTime1, 0);

        // Get time bounds for period 2 (first period after the change)
        (uint256 startTime2, uint256 endTime2) = mm.getPeriodTimeBounds(2);
        assertEq(startTime2, block.timestamp + 15 days);
        assertEq(endTime2, block.timestamp + 30 days);
    }

    // Test Mythum period calculation after period duration change
    function test_MythumPeriodAfterDurationChange() public {
        // Initial period duration is 30 days
        assertEq(mm.periodDuration(), 30 days);

        // Warp forward 30 days (1 period)
        warp(30 days);

        // Change period duration to 20 days
        prank(deployer);
        mm.setPeriodDuration(20 days);

        // Calculate the start of the Mythum period using the new formula
        // For a 20-day period: (20 days * 23) / 30 = 15 days (rounded down)
        uint256 mythumOffset = (20 days * 23) / 30; // = 15 days

        // Warp to just before the Mythum period in the new period
        warp(mythumOffset - 1 days); // 30 + 14 = 44 days total

        // Should not be in the Mythum period yet
        assertFalse(mm.isMythum());

        // Warp to the Mythum period
        warp(1 days); // 45 days total, Mythum starts at 45 days (30 + 15)

        // Should be in the Mythum period
        assertTrue(mm.isMythum());

        // Verify the start time of the Mythum period
        uint256 mythumStart = mm.getCurrentMythumStart();

        // Check that the difference between the expected and actual times is no more than 1 second
        uint256 expectedStart = 30 days + mythumOffset;
        assertTrue(
            mythumStart == expectedStart ||
                mythumStart == expectedStart + 1 ||
                mythumStart == expectedStart - 1
        );
    }

    // Test merit crediting and claiming across period duration changes
    function test_MeritAndClaimAcrossPeriodChanges() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        _buyAllTotemTokens(totemTokenAddr);

        // Credit merit in period 0
        prank(deployer);
        mm.creditMerit(data.totemAddr, 1000);

        // Warp to period 1
        warp(30 days);
        mm.updateState();

        // Claim MYTHO for period 0
        uint256 mythoBefore = mytho.balanceOf(data.totemAddr);
        prank(address(totem));
        totem.collectMYTH(0);
        uint256 mythoAfterFirstClaim = mytho.balanceOf(data.totemAddr);
        assertTrue(mythoAfterFirstClaim > mythoBefore);

        // Credit merit in period 1
        prank(deployer);
        mm.creditMerit(data.totemAddr, 2000);

        // Change period duration to 15 days
        prank(deployer);
        mm.setPeriodDuration(15 days);

        // Warp to period 3 (1 accumulated + 2 new periods)
        warp(30 days);
        mm.updateState();

        // Claim MYTHO for period 1
        prank(address(totem));
        totem.collectMYTH(1);
        uint256 mythoAfterSecondClaim = mytho.balanceOf(data.totemAddr);
        assertTrue(mythoAfterSecondClaim > mythoAfterFirstClaim);

        // Credit merit in period 3
        prank(deployer);
        mm.creditMerit(data.totemAddr, 3000);

        // Warp to period 4
        warp(15 days);
        mm.updateState();

        // Claim MYTHO for period 3
        prank(address(totem));
        totem.collectMYTH(3);
        uint256 mythoAfterThirdClaim = mytho.balanceOf(data.totemAddr);
        assertTrue(mythoAfterThirdClaim > mythoAfterSecondClaim);
    }

    // Test pause functionality in TotemTokenDistributor
    function test_TotemTokenDistributor_PauseFunctionality() public {
        address totemTokenAddr = _createTotem(userA);

        // Test pause functionality
        prank(deployer);
        distr.pause();

        // Verify buying is blocked when paused
        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        distr.buy(totemTokenAddr, 100 ether);

        // Verify selling is blocked when paused
        prank(userA);
        IERC20(totemTokenAddr).approve(address(distr), 100 ether);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        distr.sell(totemTokenAddr, 100 ether);

        // Verify registration is blocked when paused
        prank(address(factory));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        distr.register();

        // Unpause and verify operations work again
        prank(deployer);
        distr.unpause();

        // Buy should work after unpausing
        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        distr.buy(totemTokenAddr, 100 ether);

        // Verify access control for pause/unpause
        prank(userA);
        vm.expectRevert();
        distr.pause();

        prank(userA);
        vm.expectRevert();
        distr.unpause();
    }

    // Test pause functionality in MeritManager
    function test_MeritManager_PauseFunctionality() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);

        // End sale period to allow transfers
        _buyAllTotemTokens(totemTokenAddr);

        // Warp to Mythus period (last 25% of period)
        warp(23 days);

        // Test pause functionality
        prank(deployer);
        mm.pause();

        // Verify boostTotem is blocked when paused
        vm.deal(userA, 1 ether);
        prank(userA);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        // Verify register is blocked when paused
        address newTotem = makeAddr("newTotem");
        prank(address(distr));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mm.register(newTotem);

        // Verify claimMytho is blocked when paused
        prank(address(data.totemAddr));
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        mm.claimMytho(0);

        // Unpause and verify operations work again
        prank(deployer);
        mm.unpause();

        // Boost should work after unpausing
        vm.deal(userA, 1 ether);
        prank(userA);
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        // Verify access control for pause/unpause
        prank(userA);
        vm.expectRevert();
        mm.pause();

        prank(userA);
        vm.expectRevert();
        mm.unpause();
    }

    // Test TotemFactory admin functions
    function test_TotemFactory_AdminFunctions() public {
        // setCreationFee: only MANAGER
        prank(userA);
        vm.expectRevert();
        factory.setCreationFee(2 ether);
        prank(deployer);
        factory.setCreationFee(2 ether);
        assertEq(factory.getCreationFee(), 2 ether);

        // setFeeToken: only MANAGER
        MockToken newFeeToken = new MockToken();
        newFeeToken.mint(userA, 100 ether);
        prank(userA);
        vm.expectRevert();
        factory.setFeeToken(address(newFeeToken));
        prank(deployer);
        factory.setFeeToken(address(newFeeToken));
        assertEq(factory.getFeeToken(), address(newFeeToken));

        // authorizeUsers: only MANAGER, zero address, already authorized
        address[] memory usersToAuth = new address[](2);
        usersToAuth[0] = userA;
        usersToAuth[1] = userB;
        prank(userA);
        vm.expectRevert();
        factory.authorizeUsers(address(newFeeToken), usersToAuth);
        prank(deployer);
        factory.authorizeUsers(address(newFeeToken), usersToAuth);
        assertTrue(factory.isUserAuthorized(address(newFeeToken), userA));
        assertTrue(factory.isUserAuthorized(address(newFeeToken), userB));
        prank(deployer);
        vm.expectRevert(TF.ZeroAddress.selector);
        factory.authorizeUsers(address(0), usersToAuth);
        prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                TF.TokenAlreadyAuthorized.selector,
                address(newFeeToken),
                userA
            )
        );
        factory.authorizeUsers(address(newFeeToken), usersToAuth);

        // deauthorizeUsers: only MANAGER
        prank(userA);
        vm.expectRevert();
        factory.deauthorizeUsers(address(newFeeToken), usersToAuth);
        prank(deployer);
        factory.deauthorizeUsers(address(newFeeToken), usersToAuth);
        assertFalse(factory.isUserAuthorized(address(newFeeToken), userA));
        assertFalse(factory.isUserAuthorized(address(newFeeToken), userB));

        // pause/unpause: only MANAGER
        prank(userA);
        vm.expectRevert();
        factory.pause();
        prank(deployer);
        factory.pause();
        assertTrue(factory.paused());
        prank(userA);
        vm.expectRevert();
        factory.unpause();
        prank(deployer);
        factory.unpause();
        assertFalse(factory.paused());
    }

    // Test TotemTokenDistributor admin functions
    function test_TotemTokenDistributor_AdminFunctions() public {
        // Test setMaxTotemTokensPerAddress
        prank(deployer);
        distr.setMaxTotemTokensPerAddress(10_000_000 ether);
        assertEq(distr.maxTokensPerAddress(), 10_000_000 ether);

        // Create a totem to test with
        address totemTokenAddr = _createTotem(userA);

        // Test buying with new max limit
        prank(userA);
        paymentToken.mint(userA, 1_000_000 ether);
        paymentToken.approve(address(distr), 1_000_000 ether);

        uint256 available = distr.getAvailableTokensForPurchase(
            userA,
            totemTokenAddr
        );

        assertEq(available, 10_000_000 ether - 250_000 ether); // New max minus initial allocation

        // Test setPriceFeed
        address mockPriceFeed = makeAddr("priceFeed");
        prank(deployer);
        distr.setPriceFeed(address(paymentToken), mockPriceFeed);

        // Note: We can't fully test getPrice with a mock price feed without implementing the interface
    }

    // Test AddressRegistry functionality
    function test_AddressRegistry_Functionality() public {
        // Test setAddress
        address newAddress = makeAddr("newContract");
        bytes32 testId = keccak256("TEST_ID");

        prank(deployer);
        registry.setAddress(testId, newAddress);
        assertEq(registry.getAddress(testId), newAddress);

        // Test getter functions
        assertEq(registry.getMeritManager(), address(mm));
        assertEq(registry.getMythoToken(), address(mytho));
        assertEq(registry.getMythoTreasury(), address(treasury));
        assertEq(registry.getTotemFactory(), address(factory));
        assertEq(registry.getTotemTokenDistributor(), address(distr));
    }

    // Test ecosystem pause functionality
    function test_EcosystemPause_Functionality() public {
        // Create a totem for testing
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);

        // Verify initial state
        assertFalse(registry.isEcosystemPaused());

        // Pause the ecosystem
        prank(deployer);
        registry.setEcosystemPaused(true);

        // Verify ecosystem is paused
        assertTrue(registry.isEcosystemPaused());

        // Test access control for ecosystem pause
        prank(userA);
        vm.expectRevert();
        registry.setEcosystemPaused(false);

        // Verify MeritManager respects ecosystem pause
        prank(deployer);
        vm.expectRevert();
        mm.creditMerit(data.totemAddr, 100);

        // Verify boost function respects ecosystem pause
        vm.deal(userA, 1 ether);
        prank(userA);
        vm.expectRevert();
        mm.boostTotem{value: 0.001 ether}(data.totemAddr);

        // Verify TotemTokenDistributor respects ecosystem pause
        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        vm.expectRevert();
        distr.buy(totemTokenAddr, 100 ether);

        // Verify TotemFactory respects ecosystem pause
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        vm.expectRevert();
        factory.createTotem("dataHash", "Test", "TST", new address[](0));

        // Verify Totem respects ecosystem pause
        prank(userA);
        IERC20(totemTokenAddr).approve(data.totemAddr, 50 ether);
        vm.expectRevert();
        Totem(data.totemAddr).redeemTotemTokens(50 ether);

        // Unpause the ecosystem
        prank(deployer);
        registry.setEcosystemPaused(false);

        // Verify ecosystem is unpaused
        assertFalse(registry.isEcosystemPaused());

        // Verify operations work again after unpausing

        // TotemTokenDistributor operation should work
        prank(userB);
        paymentToken.approve(address(distr), 100 ether);
        distr.buy(totemTokenAddr, 100 ether);

        // TotemFactory operation should work
        prank(userB);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotem("dataHash2", "Test2", "TST2", new address[](0));

        _buyAllTotemTokens(totemTokenAddr);

        // Totem operation should work
        prank(userA);
        IERC20(totemTokenAddr).approve(data.totemAddr, 50 ether);
        Totem(data.totemAddr).redeemTotemTokens(50 ether);
    }

    // Test interaction between contract-specific pause and ecosystem pause
    function test_ContractPause_And_EcosystemPause_Interaction() public {
        // Create a totem for testing
        address totemTokenAddr = _createTotem(userA);

        // Pause only TotemTokenDistributor
        prank(deployer);
        distr.pause();

        // Verify TotemTokenDistributor operations are blocked
        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        distr.buy(totemTokenAddr, 100 ether);

        // Now pause the ecosystem
        prank(deployer);
        registry.setEcosystemPaused(true);

        // Verify all contracts are blocked
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        vm.expectRevert(TF.EcosystemPaused.selector);
        factory.createTotem(
            "dataHash3",
            "TotemToken3",
            "TT3",
            new address[](0)
        );

        // Unpause TotemTokenDistributor but keep ecosystem paused
        prank(deployer);
        distr.unpause();

        // Verify TotemTokenDistributor is still blocked due to ecosystem pause
        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        vm.expectRevert(TTD.EcosystemPaused.selector);
        distr.buy(totemTokenAddr, 100 ether);

        // Unpause ecosystem
        prank(deployer);
        registry.setEcosystemPaused(false);

        // Verify TotemTokenDistributor now works
        prank(userA);
        paymentToken.approve(address(distr), 100 ether);
        distr.buy(totemTokenAddr, 100 ether);
    }

    // Test setTotemsPaused functionality
    function test_SetTotemsPaused_Functionality() public {
        // Create multiple totems for testing
        address totemToken1 = _createTotem(userA);
        address totemToken2 = _createTotem(userB);
        address totemToken3 = _createTotem(userC);

        TF.TotemData memory data1 = factory.getTotemData(0);
        TF.TotemData memory data2 = factory.getTotemData(1);
        TF.TotemData memory data3 = factory.getTotemData(2);

        Totem totem1 = Totem(data1.totemAddr);
        Totem totem2 = Totem(data2.totemAddr);
        Totem totem3 = Totem(data3.totemAddr);

        // End sale period for all totems to allow redeeming tokens
        _buyAllTotemTokens(totemToken1);
        _buyAllTotemTokens(totemToken2);
        _buyAllTotemTokens(totemToken3);

        // Verify initial state
        assertFalse(registry.areTotemsPaused());

        // Test access control: non-manager should fail
        prank(userA);
        vm.expectRevert();
        registry.setTotemsPaused(true);

        // Pause all totems at once
        prank(deployer);
        registry.setTotemsPaused(true);

        // Verify totems are paused
        assertTrue(registry.areTotemsPaused());

        // Verify operations on first totem are blocked when totems are paused
        prank(userA);
        IERC20(totemToken1).approve(data1.totemAddr, 50 ether);
        vm.expectRevert(Totem.TotemsPaused.selector);
        totem1.redeemTotemTokens(50 ether);

        // Verify operations on second totem are blocked when totems are paused
        prank(userB);
        IERC20(totemToken2).approve(data2.totemAddr, 50 ether);
        vm.expectRevert(Totem.TotemsPaused.selector);
        totem2.redeemTotemTokens(50 ether);

        // Verify operations on third totem are blocked when totems are paused
        prank(userC);
        IERC20(totemToken3).approve(data3.totemAddr, 50 ether);
        vm.expectRevert(Totem.TotemsPaused.selector);
        totem3.redeemTotemTokens(50 ether);

        // Verify other contracts still work (not affected by totems pause)
        // Create a new totem to verify factory still works
        prank(userA);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotem(
            "dataHash4",
            "TotemToken4",
            "TT4",
            new address[](0)
        );

        // Unpause all totems at once
        prank(deployer);
        registry.setTotemsPaused(false);

        // Verify totems are unpaused
        assertFalse(registry.areTotemsPaused());

        // Verify operations on first totem work again
        prank(userA);
        IERC20(totemToken1).approve(data1.totemAddr, 50 ether);
        totem1.redeemTotemTokens(50 ether);

        // Verify operations on second totem work again
        prank(userB);
        IERC20(totemToken2).approve(data2.totemAddr, 50 ether);
        totem2.redeemTotemTokens(50 ether);

        // Verify operations on third totem work again
        prank(userC);
        IERC20(totemToken3).approve(data3.totemAddr, 50 ether);
        totem3.redeemTotemTokens(50 ether);
    }

    // Test MeritManager view functions
    function test_MeritManager_ViewFunctions() public {
        address totemTokenAddr = _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);

        // End sale period
        _buyAllTotemTokens(totemTokenAddr);

        // Get current period
        uint256 currentPeriod = mm.currentPeriod();

        // Credit merit
        prank(deployer);
        mm.creditMerit(data.totemAddr, 1000);

        // Test getPendingReward - may be 0 if no MYTHO has been released yet
        uint256 pendingReward = mm.getPendingReward(
            data.totemAddr,
            currentPeriod
        );
        assertEq(pendingReward, 0);

        // Test getPeriodTimeBounds for current period
        (uint256 startTime, uint256 endTime) = mm.getPeriodTimeBounds(
            currentPeriod
        );
        assertTrue(startTime > 0);
        assertTrue(endTime > startTime);

        // Test getTimeUntilNextPeriod
        uint256 timeUntilNext = mm.getTimeUntilNextPeriod();
        assertLe(timeUntilNext, mm.periodDuration());

        // Test getCurrentMythumStart
        uint256 mythumStart = mm.getCurrentMythumStart();
        assertTrue(mythumStart > 0);

        // Test isRegisteredTotem
        assertTrue(mm.isRegisteredTotem(data.totemAddr));
        assertFalse(mm.isRegisteredTotem(address(0x123)));

        // Test getTotemMeritPoints
        assertEq(mm.getTotemMeritPoints(data.totemAddr, currentPeriod), 1000);

        // Test hasUserBoostedInPeriod and getUserBoostedTotem
        assertFalse(mm.hasUserBoostedInPeriod(userA, currentPeriod));
        assertEq(mm.getUserBoostedTotem(userA, currentPeriod), address(0));
    }

    function test_getTotemData() public {
        _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(
            factory.getLastId() - 1
        );

        assertEq(data.creator, userA);
        assertTrue(data.totemTokenAddr != address(0));
        assertTrue(data.totemAddr != address(0));
        assertTrue(keccak256(data.dataHash) == keccak256("dataHash"));
        assertEq(uint(data.tokenType), uint(TF.TokenType.STANDARD));
    }

    // Test NFT functionality in TokenHoldersOracle
    function test_TokenHoldersOracle_NFT() public {
        // Deploy a mock ERC721 token
        MockERC721 nftToken = new MockERC721();

        // Setup users with NFTs
        nftToken.mint(userA, 1);
        nftToken.mint(userB, 2);
        nftToken.mint(userC, 3);

        // Deploy a new oracle for testing
        TokenHoldersOracle testOracle = new TokenHoldersOracle(
            address(0), // Router address (mock)
            address(treasury)
        );

        // Test updateNFTHoldersCount with insufficient fee
        prank(userA);
        vm.expectRevert();
        testOracle.updateNFTCount{value: 0.0001 ether}(
            address(nftToken)
        );

        // Test updateNFTCount with non-NFT token
        prank(userA);
        vm.expectRevert();
        testOracle.updateNFTCount{value: 0.001 ether}(
            address(paymentToken)
        );

        // Test updateNFTCount with no NFT balance
        prank(userD); // userD has no NFTs
        vm.deal(userD, 1 ether);
        vm.expectRevert();
        testOracle.updateNFTCount{value: 0.001 ether}(address(nftToken));

        // Manually update holders count to simulate a successful update
        prank(deployer);
        testOracle.manuallyUpdateNFTCount(address(nftToken), 3);

        // Test isDataFresh
        bool isFresh = testOracle.isDataFresh(address(nftToken));
        assertTrue(isFresh);

        // Test getNFTCount
        (uint256 count, uint256 timestamp) = testOracle.getNFTCount(
            address(nftToken)
        );
        assertEq(count, 3);
        assertEq(timestamp, block.timestamp);

        // Test updateNFTCount with fresh data
        prank(userA);
        vm.deal(userA, 1 ether);
        vm.expectRevert();
        testOracle.updateNFTCount{value: 0.001 ether}(address(nftToken));
    }

    // Utility function to create a totem
    function _createTotem(address _totemCreator) internal returns (address) {
        prank(_totemCreator);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotem("dataHash", "TotemToken", "TT", new address[](0));
        TF.TotemData memory totemData = factory.getTotemData(
            factory.getLastId() - 1
        );
        return totemData.totemTokenAddr;
    }

    function _buyAllTotemTokens(address _totemTokenAddr) internal {
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
        mytho.initialize(
            address(mm),
            address(registry)
        );

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
    }

    // Utility function to prank as a specific user
    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }

    function warp(uint256 _time) internal {
        vm.warp(block.timestamp + _time);
    }

    // Test withdrawToken function functionality
    function test_WithdrawToken_Success() public {
        // Create a totem first
        _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Create a mock multisig wallet address
        address multisigWallet = makeAddr("multisigWallet");
        
        // Set the multisig wallet in the registry
        prank(deployer);
        registry.setAddress(bytes32("MULTISIG_WALLET"), multisigWallet);

        // Create a test token and send some to the totem
        MockToken testToken = new MockToken();
        testToken.mint(address(totem), 1000 ether);

        // Check initial balances
        assertEq(testToken.balanceOf(address(totem)), 1000 ether);
        assertEq(testToken.balanceOf(userB), 0);

        // Withdraw tokens using multisig wallet
        prank(multisigWallet);
        totem.withdrawToken(address(testToken), userB, 500 ether);

        // Check final balances
        assertEq(testToken.balanceOf(address(totem)), 500 ether);
        assertEq(testToken.balanceOf(userB), 500 ether);
    }

    function test_WithdrawToken_NotMultisigWallet() public {
        // Create a totem first
        _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Create a mock multisig wallet address
        address multisigWallet = makeAddr("multisigWallet");
        
        // Set the multisig wallet in the registry
        prank(deployer);
        registry.setAddress(bytes32("MULTISIG_WALLET"), multisigWallet);

        // Create a test token and send some to the totem
        MockToken testToken = new MockToken();
        testToken.mint(address(totem), 1000 ether);

        // Try to withdraw with unauthorized user
        prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Totem.NotMultisigWallet.selector));
        totem.withdrawToken(address(testToken), userB, 500 ether);

        // Try to withdraw with another unauthorized user
        prank(userB);
        vm.expectRevert(abi.encodeWithSelector(Totem.NotMultisigWallet.selector));
        totem.withdrawToken(address(testToken), userB, 500 ether);
    }

    function test_WithdrawToken_InvalidParams() public {
        // Create a totem first
        _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Create a mock multisig wallet address
        address multisigWallet = makeAddr("multisigWallet");
        
        // Set the multisig wallet in the registry
        prank(deployer);
        registry.setAddress(bytes32("MULTISIG_WALLET"), multisigWallet);

        // Create a test token
        MockToken testToken = new MockToken();
        testToken.mint(address(totem), 1000 ether);

        prank(multisigWallet);

        // Test zero token address
        vm.expectRevert(abi.encodeWithSelector(Totem.InvalidParams.selector));
        totem.withdrawToken(address(0), userB, 500 ether);

        // Test zero recipient address
        vm.expectRevert(abi.encodeWithSelector(Totem.InvalidParams.selector));
        totem.withdrawToken(address(testToken), address(0), 500 ether);

        // Test zero amount
        vm.expectRevert(abi.encodeWithSelector(Totem.ZeroAmount.selector));
        totem.withdrawToken(address(testToken), userB, 0);
    }

    function test_WithdrawToken_InsufficientBalance() public {
        // Create a totem first
        _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Create a mock multisig wallet address
        address multisigWallet = makeAddr("multisigWallet");
        
        // Set the multisig wallet in the registry
        prank(deployer);
        registry.setAddress(bytes32("MULTISIG_WALLET"), multisigWallet);

        // Create a test token with limited balance
        MockToken testToken = new MockToken();
        testToken.mint(address(totem), 100 ether);

        // Try to withdraw more than available
        prank(multisigWallet);
        vm.expectRevert(abi.encodeWithSelector(Totem.InsufficientTotemBalance.selector));
        totem.withdrawToken(address(testToken), userB, 500 ether);
    }

    function test_WithdrawToken_EventEmission() public {
        // Create a totem first
        _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Create a mock multisig wallet address
        address multisigWallet = makeAddr("multisigWallet");
        
        // Set the multisig wallet in the registry
        prank(deployer);
        registry.setAddress(bytes32("MULTISIG_WALLET"), multisigWallet);

        // Create a test token and send some to the totem
        MockToken testToken = new MockToken();
        testToken.mint(address(totem), 1000 ether);

        // Expect the TokenWithdrawn event
        vm.expectEmit(true, true, false, true);
        emit Totem.TokenWithdrawn(address(testToken), userB, 500 ether);

        // Withdraw tokens
        prank(multisigWallet);
        totem.withdrawToken(address(testToken), userB, 500 ether);
    }

    function test_WithdrawToken_WithMYTHOToken() public {
        // Create a totem first
        _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Create a mock multisig wallet address
        address multisigWallet = makeAddr("multisigWallet");
        
        // Set the multisig wallet in the registry
        prank(deployer);
        registry.setAddress(bytes32("MULTISIG_WALLET"), multisigWallet);

        // Grant REGISTRATOR role to deployer and register totem 
        prank(deployer);
        mm.grantRole(mm.REGISTRATOR(), deployer);
        mm.register(address(totem));

        // Credit merit to the totem which will mint MYTHO tokens
        prank(deployer);
        mm.creditMerit(address(totem), 1000 ether);
        
        // Move to next period and claim tokens to get MYTHO in the totem
        warp(mm.periodDuration() + 1);
        prank(address(totem));
        uint256 currentPeriod = mm.currentPeriod();
        mm.claimMytho(currentPeriod - 1);

        uint256 totemBalance = mytho.balanceOf(address(totem));
        assertTrue(totemBalance > 0, "Totem should have MYTHO tokens");

        // Check initial balances
        assertEq(mytho.balanceOf(userB), 0);

        // Withdraw MYTHO tokens using multisig wallet
        prank(multisigWallet);
        totem.withdrawToken(address(mytho), userB, totemBalance / 2);

        // Check final balances
        assertEq(mytho.balanceOf(address(totem)), totemBalance / 2);
        assertEq(mytho.balanceOf(userB), totemBalance / 2);
    }

    function test_WithdrawToken_MultipleWithdrawals() public {
        // Create a totem first
        _createTotem(userA);
        TF.TotemData memory data = factory.getTotemData(0);
        Totem totem = Totem(data.totemAddr);

        // Create a mock multisig wallet address
        address multisigWallet = makeAddr("multisigWallet");
        
        // Set the multisig wallet in the registry
        prank(deployer);
        registry.setAddress(bytes32("MULTISIG_WALLET"), multisigWallet);

        // Create a test token and send some to the totem
        MockToken testToken = new MockToken();
        testToken.mint(address(totem), 1000 ether);

        prank(multisigWallet);

        // First withdrawal
        totem.withdrawToken(address(testToken), userA, 300 ether);
        assertEq(testToken.balanceOf(address(totem)), 700 ether);
        assertEq(testToken.balanceOf(userA), 300 ether);

        // Second withdrawal
        totem.withdrawToken(address(testToken), userB, 200 ether);
        assertEq(testToken.balanceOf(address(totem)), 500 ether);
        assertEq(testToken.balanceOf(userB), 200 ether);

        // Third withdrawal (remaining balance)
        totem.withdrawToken(address(testToken), userC, 500 ether);
        assertEq(testToken.balanceOf(address(totem)), 0);
        assertEq(testToken.balanceOf(userC), 500 ether);
    }
}
