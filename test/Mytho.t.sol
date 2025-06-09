// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";

import {MYTHO} from "../src/MYTHO.sol";
import {BurnMintMYTHO} from "../src/BurnMintMYTHO.sol";
import {AddressRegistry} from "../src/AddressRegistry.sol";

contract MythoTest is Test {
    MYTHO mytho;
    MYTHO mythoImpl;
    TransparentUpgradeableProxy proxy;
    ProxyAdmin proxyAdmin;
    
    // BurnMintMYTHO for non-native chain testing
    BurnMintMYTHO burnMintMytho;
    BurnMintMYTHO burnMintMythoImpl;
    TransparentUpgradeableProxy burnMintProxy;
    
    // Address registry
    AddressRegistry registry;
    AddressRegistry registryImpl;
    TransparentUpgradeableProxy registryProxy;

    address deployer;
    address meritManager;
    address teamReceiver;
    address treasuryReceiver;
    address ammReceiver;
    address minter;
    address burner;
    address user;
    address manager;

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens with 18 decimals
    uint256 public constant MERIT_YEAR_1 = 200_000_000 * 10 ** 18;
    uint256 public constant MERIT_YEAR_2 = 150_000_000 * 10 ** 18;
    uint256 public constant MERIT_YEAR_3 = 100_000_000 * 10 ** 18;
    uint256 public constant MERIT_YEAR_4 = 50_000_000 * 10 ** 18;
    uint256 public constant TEAM_ALLOCATION = 200_000_000 * 10 ** 18;
    uint256 public constant TREASURY_ALLOCATION = 230_000_000 * 10 ** 18;
    uint256 public constant AMM_INCENTIVES = 70_000_000 * 10 ** 18;

    function setUp() public {
        deployer = makeAddr("deployer");
        meritManager = makeAddr("meritManager");
        teamReceiver = makeAddr("teamReceiver");
        treasuryReceiver = makeAddr("treasuryReceiver");
        ammReceiver = makeAddr("ammReceiver");
        minter = makeAddr("minter");
        burner = makeAddr("burner");
        user = makeAddr("user");
        manager = makeAddr("manager");

        vm.startPrank(deployer);
        
        // Deploy proxy admin
        proxyAdmin = new ProxyAdmin(deployer);
        
        // Deploy and initialize AddressRegistry
        registryImpl = new AddressRegistry();
        bytes memory registryInitData = abi.encodeWithSelector(
            AddressRegistry.initialize.selector
        );
        
        registryProxy = new TransparentUpgradeableProxy(
            address(registryImpl),
            address(proxyAdmin),
            registryInitData
        );
        
        registry = AddressRegistry(address(registryProxy));
        
        // Deploy MYTHO implementation (native chain token)
        mythoImpl = new MYTHO();
        
        // Prepare initialization data for MYTHO
        bytes memory initData = abi.encodeWithSelector(
            MYTHO.initialize.selector,
            meritManager,
            teamReceiver,
            treasuryReceiver,
            ammReceiver,
            address(registry)
        );
        
        // Deploy MYTHO proxy
        proxy = new TransparentUpgradeableProxy(
            address(mythoImpl),
            address(proxyAdmin),
            initData
        );
        
        // Get the proxied MYTHO instance
        mytho = MYTHO(address(proxy));
        
        // Deploy BurnMintMYTHO implementation (non-native chain token)
        burnMintMythoImpl = new BurnMintMYTHO();
        
        // Prepare initialization data for BurnMintMYTHO
        bytes memory burnMintInitData = abi.encodeWithSelector(
            BurnMintMYTHO.initialize.selector
        );
        
        // Deploy BurnMintMYTHO proxy
        burnMintProxy = new TransparentUpgradeableProxy(
            address(burnMintMythoImpl),
            address(proxyAdmin),
            burnMintInitData
        );
        
        // Get the proxied BurnMintMYTHO instance
        burnMintMytho = BurnMintMYTHO(address(burnMintProxy));
        
        vm.stopPrank();
    }

    function test_Initialization() public {
        // Check token name and symbol
        assertEq(mytho.name(), "MYTHO Government Token");
        assertEq(mytho.symbol(), "MYTHO");
        
        // Check total supply
        assertEq(mytho.totalSupply(), TOTAL_SUPPLY);
        
        // Check owner
        assertEq(mytho.owner(), deployer);
        
        // Check vesting wallets have correct balances
        assertEq(mytho.balanceOf(mytho.meritVestingYear1()), MERIT_YEAR_1);
        assertEq(mytho.balanceOf(mytho.meritVestingYear2()), MERIT_YEAR_2);
        assertEq(mytho.balanceOf(mytho.meritVestingYear3()), MERIT_YEAR_3);
        assertEq(mytho.balanceOf(mytho.meritVestingYear4()), MERIT_YEAR_4);
        assertEq(mytho.balanceOf(mytho.teamVesting()), TEAM_ALLOCATION);
        assertEq(mytho.balanceOf(mytho.ammVesting()), AMM_INCENTIVES);
        assertEq(mytho.balanceOf(mytho.treasury()), TREASURY_ALLOCATION);
        
        // Verify vesting wallet beneficiaries (owner is the beneficiary in VestingWallet)
        assertEq(VestingWallet(payable(mytho.meritVestingYear1())).owner(), meritManager);
        assertEq(VestingWallet(payable(mytho.teamVesting())).owner(), teamReceiver);
        assertEq(VestingWallet(payable(mytho.ammVesting())).owner(), ammReceiver);
    }

    function test_InitializeWithZeroAddress() public {
        vm.startPrank(deployer);
        
        MYTHO newImpl = new MYTHO();
        TransparentUpgradeableProxy newProxy;
        
        // Test with zero address for meritManager
        bytes memory initData = abi.encodeWithSelector(
            MYTHO.initialize.selector,
            address(0),
            teamReceiver,
            treasuryReceiver,
            ammReceiver,
            address(registry)
        );
        
        vm.expectRevert(abi.encodeWithSelector(MYTHO.ZeroAddressNotAllowed.selector, "totem receiver"));
        newProxy = new TransparentUpgradeableProxy(
            address(newImpl),
            address(proxyAdmin),
            initData
        );
        
        // Test with zero address for teamReceiver
        initData = abi.encodeWithSelector(
            MYTHO.initialize.selector,
            meritManager,
            address(0),
            treasuryReceiver,
            ammReceiver,
            address(registry)
        );
        
        vm.expectRevert(abi.encodeWithSelector(MYTHO.ZeroAddressNotAllowed.selector, "team receiver"));
        newProxy = new TransparentUpgradeableProxy(
            address(newImpl),
            address(proxyAdmin),
            initData
        );
        
        vm.stopPrank();
    }

    // Test BurnMintMYTHO minting permissions (for non-native chains)
    function test_BurnMintMYTHO_MintingPermissions() public {
        // Initially no one should have minting permissions
        assertEq(burnMintMytho.getMinters().length, 0);
        
        // Grant minting permission
        vm.prank(deployer);
        burnMintMytho.grantMintAccess(minter);
        
        // Check minter was added
        assertEq(burnMintMytho.getMinters().length, 1);
        assertEq(burnMintMytho.getMinters()[0], minter);
        assertTrue(burnMintMytho.isMinter(minter));
        
        // Non-minter should not be able to mint
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(BurnMintMYTHO.SenderNotMinter.selector, user));
        burnMintMytho.mint(user, 1000 * 10**18);
        
        // Minter should be able to mint
        vm.prank(minter);
        burnMintMytho.mint(user, 1000 * 10**18);
        assertEq(burnMintMytho.balanceOf(user), 1000 * 10**18);
        
        // Revoke minting permission
        vm.prank(deployer);
        burnMintMytho.revokeMintAccess(minter);
        
        // Check minter was removed
        assertEq(burnMintMytho.getMinters().length, 0);
        assertFalse(burnMintMytho.isMinter(minter));
        
        // Former minter should not be able to mint anymore
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(BurnMintMYTHO.SenderNotMinter.selector, minter));
        burnMintMytho.mint(user, 1000 * 10**18);
    }

    // Test BurnMintMYTHO burning permissions (for non-native chains)
    function test_BurnMintMYTHO_BurningPermissions() public {
        // Initially no one should have burning permissions
        assertEq(burnMintMytho.getBurners().length, 0);
        
        // Grant burning permission
        vm.prank(deployer);
        burnMintMytho.grantBurnAccess(burner);
        
        // Check burner was added
        assertEq(burnMintMytho.getBurners().length, 1);
        assertEq(burnMintMytho.getBurners()[0], burner);
        assertTrue(burnMintMytho.isBurner(burner));
        
        // Mint some tokens to user for burning tests
        vm.prank(deployer);
        burnMintMytho.grantMintAccess(minter);
        vm.prank(minter);
        burnMintMytho.mint(user, 2000 * 10**18);
        
        // Non-burner should not be able to burn
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(BurnMintMYTHO.SenderNotBurner.selector, user));
        burnMintMytho.burn(1000 * 10**18);
        
        // Approve burner to burn user's tokens
        vm.prank(user);
        burnMintMytho.approve(burner, 1000 * 10**18);
        
        // Burner should be able to burn from user
        vm.prank(burner);
        burnMintMytho.burnFrom(user, 1000 * 10**18);
        assertEq(burnMintMytho.balanceOf(user), 1000 * 10**18);
        
        // Burner should be able to burn their own tokens
        vm.prank(minter);
        burnMintMytho.mint(burner, 1000 * 10**18);
        
        vm.prank(burner);
        burnMintMytho.burn(500 * 10**18);
        assertEq(burnMintMytho.balanceOf(burner), 500 * 10**18);
        
        // Revoke burning permission
        vm.prank(deployer);
        burnMintMytho.revokeBurnAccess(burner);
        
        // Check burner was removed
        assertEq(burnMintMytho.getBurners().length, 0);
        assertFalse(burnMintMytho.isBurner(burner));
        
        // Former burner should not be able to burn anymore
        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(BurnMintMYTHO.SenderNotBurner.selector, burner));
        burnMintMytho.burn(500 * 10**18);
    }

    // Test MYTHO pause/unpause functionality
    function test_PauseUnpause() public {
        // Initially token should not be paused
        assertFalse(mytho.paused());
        
        // Only owner can pause
        vm.prank(user);
        vm.expectRevert();  // Just expect any revert for non-owner
        mytho.pause();
        
        // Owner pauses the token
        vm.prank(deployer);
        mytho.pause();
        assertTrue(mytho.paused());
        
        // Transfers should be blocked when paused
        vm.prank(treasuryReceiver);
        vm.expectRevert(); // Just expect any revert when paused
        mytho.transfer(address(1), 100 * 10**18);
        
        // Only owner can unpause
        vm.prank(user);
        vm.expectRevert();  // Just expect any revert for non-owner
        mytho.unpause();
        
        // Owner unpauses the token
        vm.prank(deployer);
        mytho.unpause();
        assertFalse(mytho.paused());
        
        // After unpausing, transfers should work again
        uint256 treasuryBalance = mytho.balanceOf(treasuryReceiver);
        vm.prank(treasuryReceiver);
        mytho.transfer(address(1), 100 * 10**18);
        assertEq(mytho.balanceOf(address(1)), 100 * 10**18);
        assertEq(mytho.balanceOf(treasuryReceiver), treasuryBalance - 100 * 10**18);
    }
    
    // Test BurnMintMYTHO pause/unpause functionality
    function test_BurnMintMYTHO_PauseUnpause() public {
        // Initially token should not be paused
        assertFalse(burnMintMytho.paused());
        
        // Setup for testing various functions with pause
        // Grant minting and burning permissions
        vm.startPrank(deployer);
        burnMintMytho.grantMintAccess(minter);
        burnMintMytho.grantBurnAccess(burner);
        vm.stopPrank();
        
        // Mint some tokens to user before pausing
        vm.prank(minter);
        burnMintMytho.mint(user, 1000 * 10**18);
        
        // Mint some tokens to burner for self-burn test
        vm.prank(minter);
        burnMintMytho.mint(burner, 500 * 10**18);
        
        // User approves burner to burn their tokens
        vm.prank(user);
        burnMintMytho.approve(burner, 500 * 10**18);
        
        // Owner pauses the token
        vm.prank(deployer);
        burnMintMytho.pause();
        assertTrue(burnMintMytho.paused());
        
        // 1. Transfers should be blocked when paused
        vm.prank(user);
        vm.expectRevert(); // Just expect any revert when paused
        burnMintMytho.transfer(address(1), 100 * 10**18);
        
        // 2. Minting should be blocked when paused
        vm.prank(minter);
        vm.expectRevert(); // Just expect any revert when paused
        burnMintMytho.mint(user, 100 * 10**18);
        
        // 3. Burning should be blocked when paused
        vm.prank(burner);
        vm.expectRevert(); // Just expect any revert when paused
        burnMintMytho.burn(100 * 10**18);
        
        // 4. BurnFrom should be blocked when paused
        vm.prank(burner);
        vm.expectRevert(); // Just expect any revert when paused
        burnMintMytho.burnFrom(user, 100 * 10**18);
        
        // Owner unpauses the token
        vm.prank(deployer);
        burnMintMytho.unpause();
        assertFalse(burnMintMytho.paused());
        
        // After unpausing, all operations should work again
        
        // 1. Transfers should work after unpausing
        vm.prank(user);
        burnMintMytho.transfer(address(1), 100 * 10**18);
        assertEq(burnMintMytho.balanceOf(address(1)), 100 * 10**18);
        
        // 2. Minting should work after unpausing
        vm.prank(minter);
        burnMintMytho.mint(user, 100 * 10**18);
        assertEq(burnMintMytho.balanceOf(user), 1000 * 10**18); // 1000 - 100 (transferred) + 100 (minted) = 1000
        
        // 3. Burning should work after unpausing
        vm.prank(burner);
        burnMintMytho.burn(100 * 10**18);
        assertEq(burnMintMytho.balanceOf(burner), 400 * 10**18); // 500 - 100 = 400
        
        // 4. BurnFrom should work after unpausing
        vm.prank(burner);
        burnMintMytho.burnFrom(user, 100 * 10**18);
        assertEq(burnMintMytho.balanceOf(user), 900 * 10**18); // 1000 - 100 = 900
    }

    // Test BurnMintMYTHO zero address checks
    function test_BurnMintMYTHO_ZeroAddressChecks() public {
        // Cannot grant mint access to zero address
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(BurnMintMYTHO.ZeroAddressNotAllowed.selector, "minter"));
        burnMintMytho.grantMintAccess(address(0));
        
        // Cannot grant burn access to zero address
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(BurnMintMYTHO.ZeroAddressNotAllowed.selector, "burner"));
        burnMintMytho.grantBurnAccess(address(0));
    }

    // Test ecosystem pause functionality
    function test_EcosystemPause() public {
        // Grant manager role to the manager address
        vm.prank(deployer);
        registry.grantRole(keccak256("MANAGER"), manager);
        
        // Verify registry address is set in MYTHO
        assertEq(mytho.registryAddr(), address(registry));
        
        // Initially ecosystem should not be paused
        assertFalse(registry.isEcosystemPaused());
        
        // Transfer should work when ecosystem is not paused
        uint256 treasuryBalance = mytho.balanceOf(treasuryReceiver);
        vm.prank(treasuryReceiver);
        mytho.transfer(user, 1000 * 10**18);
        assertEq(mytho.balanceOf(user), 1000 * 10**18);
        assertEq(mytho.balanceOf(treasuryReceiver), treasuryBalance - 1000 * 10**18);
        
        // Pause the ecosystem
        vm.prank(manager);
        registry.setEcosystemPaused(true);
        assertTrue(registry.isEcosystemPaused());
        
        // Transfer should be blocked when ecosystem is paused
        vm.prank(treasuryReceiver);
        vm.expectRevert(abi.encodeWithSelector(MYTHO.EcosystemPaused.selector));
        mytho.transfer(user, 1000 * 10**18);
        
        // Unpause the ecosystem
        vm.prank(manager);
        registry.setEcosystemPaused(false);
        assertFalse(registry.isEcosystemPaused());
        
        // Transfer should work again after ecosystem is unpaused
        treasuryBalance = mytho.balanceOf(treasuryReceiver);
        vm.prank(treasuryReceiver);
        mytho.transfer(user, 1000 * 10**18);
        assertEq(mytho.balanceOf(user), 2000 * 10**18);
        assertEq(mytho.balanceOf(treasuryReceiver), treasuryBalance - 1000 * 10**18);
    }
    
    function test_VestingSchedule() public {
        // Get vesting wallet addresses
        address meritVestingYear1 = mytho.meritVestingYear1();
        address meritVestingYear2 = mytho.meritVestingYear2();
        address meritVestingYear3 = mytho.meritVestingYear3();
        address meritVestingYear4 = mytho.meritVestingYear4();
        address teamVesting = mytho.teamVesting();
        address ammVesting = mytho.ammVesting();
        
        // Check initial balances
        assertEq(mytho.balanceOf(meritVestingYear1), MERIT_YEAR_1);
        assertEq(mytho.balanceOf(meritVestingYear2), MERIT_YEAR_2);
        assertEq(mytho.balanceOf(meritVestingYear3), MERIT_YEAR_3);
        assertEq(mytho.balanceOf(meritVestingYear4), MERIT_YEAR_4);
        assertEq(mytho.balanceOf(teamVesting), TEAM_ALLOCATION);
        assertEq(mytho.balanceOf(ammVesting), AMM_INCENTIVES);
        
        // Check vesting duration and start time
        VestingWallet meritVesting1 = VestingWallet(payable(meritVestingYear1));
        VestingWallet meritVesting2 = VestingWallet(payable(meritVestingYear2));
        VestingWallet meritVesting3 = VestingWallet(payable(meritVestingYear3));
        VestingWallet meritVesting4 = VestingWallet(payable(meritVestingYear4));
        VestingWallet teamVestingWallet = VestingWallet(payable(teamVesting));
        VestingWallet ammVestingWallet = VestingWallet(payable(ammVesting));
        
        // Check beneficiaries (owner is the beneficiary in VestingWallet)
        assertEq(meritVesting1.owner(), meritManager);
        assertEq(meritVesting2.owner(), meritManager);
        assertEq(meritVesting3.owner(), meritManager);
        assertEq(meritVesting4.owner(), meritManager);
        assertEq(teamVestingWallet.owner(), teamReceiver);
        assertEq(ammVestingWallet.owner(), ammReceiver);
        
        // Check vesting duration
        uint64 ONE_YEAR = 12 * 30 days;
        uint64 TWO_YEARS = 2 * ONE_YEAR;
        
        assertEq(meritVesting1.duration(), ONE_YEAR);
        assertEq(meritVesting2.duration(), ONE_YEAR);
        assertEq(meritVesting3.duration(), ONE_YEAR);
        assertEq(meritVesting4.duration(), ONE_YEAR);
        assertEq(teamVestingWallet.duration(), TWO_YEARS);
        assertEq(ammVestingWallet.duration(), TWO_YEARS);
        
        // Check start times for sequential vesting
        uint64 startTime = uint64(meritVesting1.start());
        assertEq(uint64(meritVesting2.start()), startTime + ONE_YEAR);
        assertEq(uint64(meritVesting3.start()), startTime + 2 * ONE_YEAR);
        assertEq(uint64(meritVesting4.start()), startTime + 3 * ONE_YEAR);
        
        // Test vesting release at different times
        // Fast forward to 50% of vesting period for merit year 1
        vm.warp(startTime + ONE_YEAR / 2);
        
        // Check vested amount (should be ~50%)
        uint256 vestedAmount = meritVesting1.vestedAmount(address(mytho), uint64(block.timestamp));
        assertApproxEqRel(vestedAmount, MERIT_YEAR_1 / 2, 0.01e18); // Allow 1% deviation
        
        // Fast forward to end of vesting period for year 1
        vm.warp(startTime + ONE_YEAR);
        
        // Check vested amount (should be 100% for year 1, 0% for year 2)
        vestedAmount = meritVesting1.vestedAmount(address(mytho), uint64(block.timestamp));
        assertEq(vestedAmount, MERIT_YEAR_1);
        
        vestedAmount = meritVesting2.vestedAmount(address(mytho), uint64(block.timestamp));
        assertEq(vestedAmount, 0);
    }
}
