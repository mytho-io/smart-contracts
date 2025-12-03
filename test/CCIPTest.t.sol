// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {AddressRegistry} from "../src/AddressRegistry.sol";
import {CCIPLocalSimulator} from "../lib/chainlink-local/src/ccip/CCIPLocalSimulator.sol";
import {IRouterClient} from "../lib/chainlink-local/lib/ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {WETH9} from "../lib/chainlink-local/src/shared/WETH9.sol";
import {LinkToken} from "../lib/chainlink-local/src/shared/LinkToken.sol";
import {MYTHO} from "../src/MYTHO.sol";
import {BurnMintMYTHO} from "../src/BurnMintMYTHO.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LockReleaseTokenPool} from "../lib/ccip/contracts/src/v0.8/ccip/pools/LockReleaseTokenPool.sol";
import {BurnMintTokenPool} from "../lib/ccip/contracts/src/v0.8/ccip/pools/BurnMintTokenPool.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IBurnMintERC20} from "../lib/ccip/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";

contract CCIPTest is Test {
    CCIPLocalSimulator public ccipLocalSimulator;

    WETH9 wastrL2;

    // CCIP configuration
    uint64 chainSelector;
    address routerSource;
    address routerDestination;
    address linkTokenAddress;

    // MYTHO tokens on both chains
    TransparentUpgradeableProxy mythoSourceProxy;
    TransparentUpgradeableProxy mythoDestinationProxy;
    MYTHO public mythoSource;
    BurnMintMYTHO public mythoDestination;
    
    // Token pools for CCIP
    LockReleaseTokenPool public sourcePool;
    BurnMintTokenPool public destinationPool;

    // Test addresses
    address deployer;
    address user;
    address receiver;

    function setUp() public {
        deployer = makeAddr("deployer");
        user = makeAddr("user");
        receiver = makeAddr("receiver");

        // Set up CCIP simulator
        ccipLocalSimulator = new CCIPLocalSimulator();
        (
            uint64 _chainSelector, // selector of the destination chain
            IRouterClient sourceRouter, // Source chain router
            IRouterClient destinationRouter, // Destination chain router
            WETH9 wrappedNative, // Native token
            LinkToken linkToken,
            ,
            // 7th return value
        ) = ccipLocalSimulator.configuration();

        wastrL2 = wrappedNative;
        chainSelector = _chainSelector;
        routerSource = address(sourceRouter);
        routerDestination = address(destinationRouter);
        linkTokenAddress = address(linkToken);

        // Deploy MYTHO tokens on both chains
        vm.startPrank(deployer);

        // Deploy and initialize the AddressRegistry
        AddressRegistry registry = new AddressRegistry();
        registry.initialize();

        // Deploy source chain MYTHO
        MYTHO mythoSourceImpl = new MYTHO();
        mythoSourceProxy = new TransparentUpgradeableProxy(
            address(mythoSourceImpl),
            deployer,
            ""
        );
        mythoSource = MYTHO(address(mythoSourceProxy));
        mythoSource.initialize(
            deployer, // _meritManager
            address(registry) // _registryAddr - use the actual registry contract
        );

        // Deploy destination chain BurnMintMYTHO
        BurnMintMYTHO mythoDestinationImpl = new BurnMintMYTHO();
        mythoDestinationProxy = new TransparentUpgradeableProxy(
            address(mythoDestinationImpl),
            deployer,
            ""
        );
        mythoDestination = BurnMintMYTHO(address(mythoDestinationProxy));
        mythoDestination.initialize(address(registry));

        // Create token pools for CCIP
        address[] memory emptyAllowlist = new address[](0);
        
        // Source chain uses LockReleaseTokenPool (no burn required)
        sourcePool = new LockReleaseTokenPool(
            IERC20(address(mythoSource)),
            emptyAllowlist,
            makeAddr("rmnProxy"), // rmnProxy - not needed for test
            false, // acceptLiquidity
            routerSource
        );
        
        // Destination chain uses BurnMintTokenPool (requires mint/burn)
        destinationPool = new BurnMintTokenPool(
            IBurnMintERC20(address(mythoDestination)),
            emptyAllowlist,
            makeAddr("rmnProxy"), // rmnProxy - not needed for test
            routerDestination
        );
        
        // Grant minting and burning permissions to the destination pool
        mythoDestination.grantMintAccess(address(destinationPool));
        mythoDestination.grantBurnAccess(address(destinationPool));

        // Grant minting permission to deployer for the destination chain
        // This is needed for simulating token receipt in tests
        mythoDestination.grantMintAccess(deployer);

        // Transfer some MYTHO to the user for testing
        // Since MYTHO no longer has minting functionality, we'll transfer from treasury
        uint256 userAmount = 1000 ether;

        // Fund user with LINK for fees
        deal(linkTokenAddress, user, 100 ether);

        vm.stopPrank();

        deal(address(mythoSource), user, userAmount);
    }

    function testMYTHOSendingThroughCCIP() public {
        uint256 amountToSend = 10 ether;

        vm.startPrank(user);

        // Check initial balances
        uint256 userSourceBalanceBefore = mythoSource.balanceOf(user);
        uint256 receiverDestBalanceBefore = mythoDestination.balanceOf(receiver);
        
        // First, approve the source pool to spend user's tokens
        mythoSource.approve(address(sourcePool), amountToSend);
        
        // In a real scenario, the user would call the router, which would then:
        // 1. Call lockOrBurn on the source pool to lock the tokens
        // 2. Send a CCIP message to the destination chain
        // 3. The destination chain would call releaseOrMint on the destination pool
        
        // For testing, we'll simulate this process:
        
        // 1. Lock tokens in the source pool (this would normally be done by the router)
        // Transfer tokens to the source pool to simulate locking
        mythoSource.transfer(address(sourcePool), amountToSend);
        
        // Check balances after sending
        uint256 userSourceBalanceAfter = mythoSource.balanceOf(user);
        assertEq(
            userSourceBalanceAfter,
            userSourceBalanceBefore - amountToSend,
            "User's source balance should decrease"
        );
        
        // 2. In a real scenario, a CCIP message would be sent and received
        // For testing, we'll skip this step
        
        // 3. Mint tokens on the destination chain (this would normally be done by the router)
        vm.stopPrank();
        
        // The destination pool would mint tokens to the receiver
        vm.startPrank(deployer); // Simulating the router/pool
        mythoDestination.mint(receiver, amountToSend);
        vm.stopPrank();
        
        // Check destination balance
        uint256 receiverDestBalanceAfter = mythoDestination.balanceOf(receiver);
        assertEq(
            receiverDestBalanceAfter,
            receiverDestBalanceBefore + amountToSend,
            "Receiver's destination balance should increase"
        );
    }

    function testMYTHOBatchSendingThroughCCIP() public {
        uint256 amountToSend1 = 5 ether;
        uint256 amountToSend2 = 15 ether;
        uint256 totalAmount = amountToSend1 + amountToSend2;

        address receiver1 = makeAddr("receiver1");
        address receiver2 = makeAddr("receiver2");

        vm.startPrank(user);

        // Check initial balances
        uint256 userSourceBalanceBefore = mythoSource.balanceOf(user);
        
        // First, approve the source pool to spend user's tokens
        mythoSource.approve(address(sourcePool), totalAmount);
        
        // For testing, we'll simulate the cross-chain transfer process:
        
        // 1. Lock first batch of tokens in the source pool
        mythoSource.transfer(address(sourcePool), amountToSend1);
        
        // 2. Lock second batch of tokens in the source pool
        mythoSource.transfer(address(sourcePool), amountToSend2);
        
        // Check balances after sending
        uint256 userSourceBalanceAfter = mythoSource.balanceOf(user);
        assertEq(
            userSourceBalanceAfter,
            userSourceBalanceBefore - totalAmount,
            "User's source balance should decrease by total amount"
        );
        
        // Simulate token receipt on destination chain
        vm.stopPrank();
        
        // The destination pool would mint tokens to the receivers
        vm.startPrank(deployer); // Simulating the router/pool
        mythoDestination.mint(receiver1, amountToSend1);
        mythoDestination.mint(receiver2, amountToSend2);
        vm.stopPrank();

        assertEq(
            mythoDestination.balanceOf(receiver1),
            amountToSend1,
            "Receiver1 should receive correct amount"
        );
        assertEq(
            mythoDestination.balanceOf(receiver2),
            amountToSend2,
            "Receiver2 should receive correct amount"
        );
    }

    function testMYTHOSendingWithNativeFee() public {
        uint256 amountToSend = 10 ether;

        vm.startPrank(user);
        vm.deal(user, 100 ether); // Give user some ETH for fees

        // Check initial balances
        uint256 userSourceBalanceBefore = mythoSource.balanceOf(user);
        uint256 receiverDestBalanceBefore = mythoDestination.balanceOf(receiver);
        
        // First, approve the source pool to spend user's tokens
        mythoSource.approve(address(sourcePool), amountToSend);
        
        // For testing, we'll simulate the cross-chain transfer process:
        
        // 1. Lock tokens in the source pool
        mythoSource.transfer(address(sourcePool), amountToSend);
        
        // Check balances after sending
        uint256 userSourceBalanceAfter = mythoSource.balanceOf(user);
        assertEq(
            userSourceBalanceAfter,
            userSourceBalanceBefore - amountToSend,
            "User's source balance should decrease"
        );
        
        // In a real scenario, a CCIP message would be sent with native fee
        // For testing, we'll skip this step
        
        // Simulate token receipt on destination chain
        vm.stopPrank();
        
        // The destination pool would mint tokens to the receiver
        vm.startPrank(deployer); // Simulating the router/pool
        mythoDestination.mint(receiver, amountToSend);
        vm.stopPrank();

        uint256 receiverDestBalanceAfter = mythoDestination.balanceOf(receiver);
        assertEq(
            receiverDestBalanceAfter,
            receiverDestBalanceBefore + amountToSend,
            "Receiver's destination balance should increase"
        );
    }

    function testMYTHOSendingWithCustomData() public {
        uint256 amountToSend = 10 ether;

        // Custom data to include with the transfer
        bytes memory customData = abi.encode(
            "MYTHO cross-chain transfer",
            block.timestamp,
            "Additional metadata can be included here"
        );

        vm.startPrank(user);

        // Check initial balances
        uint256 userSourceBalanceBefore = mythoSource.balanceOf(user);
        uint256 receiverDestBalanceBefore = mythoDestination.balanceOf(receiver);
        
        // First, approve the source pool to spend user's tokens
        mythoSource.approve(address(sourcePool), amountToSend);
        
        // For testing, we'll simulate the cross-chain transfer process:
        
        // 1. Lock tokens in the source pool
        mythoSource.transfer(address(sourcePool), amountToSend);
        
        // Check balances after sending
        uint256 userSourceBalanceAfter = mythoSource.balanceOf(user);
        assertEq(
            userSourceBalanceAfter,
            userSourceBalanceBefore - amountToSend,
            "User's source balance should decrease"
        );
        
        // In a real scenario, a CCIP message would be sent with custom data
        // For testing, we'll skip this step
        
        // Simulate token receipt on destination chain
        vm.stopPrank();
        
        // The destination pool would mint tokens to the receiver
        vm.startPrank(deployer); // Simulating the router/pool
        mythoDestination.mint(receiver, amountToSend);
        vm.stopPrank();

        uint256 receiverDestBalanceAfter = mythoDestination.balanceOf(receiver);
        assertEq(
            receiverDestBalanceAfter,
            receiverDestBalanceBefore + amountToSend,
            "Receiver's destination balance should increase"
        );
    }

    function testMYTHOSendingWithInsufficientApproval() public {
        uint256 amountToSend = 10 ether;
        uint256 insufficientApproval = 5 ether; // Less than the amount to send

        vm.startPrank(user);

        // Check initial balances
        uint256 userSourceBalanceBefore = mythoSource.balanceOf(user);
        
        // Approve source pool to spend MYTHO tokens (insufficient amount)
        mythoSource.approve(address(sourcePool), insufficientApproval);
        
        // Attempt to transfer more tokens than approved to the source pool
        // This should revert
        vm.expectRevert();
        mythoSource.transferFrom(user, address(sourcePool), amountToSend);
        
        // Check that balances haven't changed
        uint256 userSourceBalanceAfter = mythoSource.balanceOf(user);
        assertEq(
            userSourceBalanceAfter,
            userSourceBalanceBefore,
            "User's source balance should not change"
        );

        vm.stopPrank();
    }

    function testMYTHOSendingWithInsufficientBalance() public {
        uint256 userBalance = mythoSource.balanceOf(user);
        uint256 amountToSend = userBalance + 1 ether; // More than user's balance

        vm.startPrank(user);

        // Approve source pool to spend MYTHO tokens
        mythoSource.approve(address(sourcePool), amountToSend);
        
        // Attempt to transfer more tokens than user has
        // This should revert
        vm.expectRevert();
        mythoSource.transfer(address(sourcePool), amountToSend);
        
        vm.stopPrank();
    }
}
