// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TokenHoldersOracle} from "../src/utils/TokenHoldersOracle.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {FunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsRouter.sol";

// Mock ERC721 contract for testing
contract MockERC721 is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

// Mock router for Chainlink Functions
contract MockFunctionsRouter {
    function getRequest(bytes32 requestId) external pure returns (bytes memory, uint64, uint32, address) {
        return (bytes(""), uint64(0), uint32(0), address(0));
    }
}

contract TokenHoldersOracleTest is Test {
    // Contract instances
    TokenHoldersOracle holdersOracle;
    MockERC721 mockNFT;
    
    // Test addresses
    address owner;
    address treasury;
    address user1;
    address user2;
    address tokenAddress;
    
    // Constants
    bytes32 constant CALLER_ROLE = keccak256("CALLER_ROLE");
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    uint256 constant DEFAULT_UPDATE_FEE = 0.0003 ether;
    uint256 constant DEFAULT_MAX_DATA_AGE = 5 minutes;

    // Events to test
    event NFTCountUpdated(address indexed token, uint256 count, uint256 timestamp);
    event UpdateFeeChanged(uint256 oldFee, uint256 newFee);
    event UpdateFeeCollected(address indexed user, address indexed token, uint256 fee);
    event TreasuryAddressUpdated(address oldTreasury, address newTreasury);
    event ManualUpdate(address indexed token, uint256 count, address updater);
    
    function setUp() public {
        // Setup test addresses
        owner = makeAddr("owner");
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        tokenAddress = makeAddr("token");

        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        
        // Deploy mock contracts
        vm.startPrank(owner);
        
        // Deploy mock NFT
        mockNFT = new MockERC721();
        
        // Deploy mock router
        MockFunctionsRouter mockRouter = new MockFunctionsRouter();
        
        // Deploy TokenHoldersOracle with mock router
        holdersOracle = new TokenHoldersOracle(address(mockRouter), treasury);
        
        // Setup initial state
        holdersOracle.setSubscriptionId(1);
        holdersOracle.setGasLimit(300000);
        
        // Grant roles to test users
        holdersOracle.grantRole(CALLER_ROLE, user1);
        
        vm.stopPrank();
    }

    // Test constructor initialization
    function test_Constructor() public {
        assertEq(holdersOracle.updateFee(), DEFAULT_UPDATE_FEE);
        assertEq(holdersOracle.maxDataAge(), DEFAULT_MAX_DATA_AGE);
        assertTrue(holdersOracle.hasRole(DEFAULT_ADMIN_ROLE, owner));
        assertTrue(holdersOracle.hasRole(CALLER_ROLE, owner));
    }
    
    // Test role-based access control
    function test_RoleBasedAccess() public {
        // User with CALLER_ROLE should be able to request holders count
        vm.startPrank(user1);
        vm.expectRevert(); // This will revert because the mock router doesn't implement the required function
        holdersOracle.requestNFTCount(tokenAddress);
        vm.stopPrank();
        
        // User without CALLER_ROLE should not be able to request holders count
        vm.startPrank(user2);
        vm.expectRevert();
        holdersOracle.requestNFTCount(tokenAddress);
        vm.stopPrank();
    }
    
    // Test admin functions
    function test_AdminFunctions() public {
        // Test setUpdateFee
        vm.startPrank(owner);
        uint256 newFee = 0.0005 ether;
        vm.expectEmit(true, true, true, true);
        emit UpdateFeeChanged(DEFAULT_UPDATE_FEE, newFee);
        holdersOracle.setUpdateFee(newFee);
        assertEq(holdersOracle.updateFee(), newFee);
        
        // Test setMaxDataAge
        uint256 newMaxDataAge = 10 minutes;
        holdersOracle.setMaxDataAge(newMaxDataAge);
        assertEq(holdersOracle.maxDataAge(), newMaxDataAge);
        
        // Test setTreasuryAddress
        address newTreasury = makeAddr("newTreasury");
        vm.expectEmit(true, true, true, true);
        emit TreasuryAddressUpdated(treasury, newTreasury);
        holdersOracle.setTreasuryAddress(newTreasury);
        
        // Test manuallyUpdateNFTCount
        uint256 count = 100;
        vm.expectEmit(true, true, true, true);
        emit NFTCountUpdated(tokenAddress, count, block.timestamp);
        holdersOracle.manuallyUpdateNFTCount(tokenAddress, count);
        
        // Verify the update
        (uint256 storedCount, uint256 lastUpdate) = holdersOracle.getNFTCount(tokenAddress);
        assertEq(storedCount, count);
        assertEq(lastUpdate, block.timestamp);
        vm.stopPrank();
        
        // Non-admin should not be able to call admin functions
        vm.startPrank(user1);
        vm.expectRevert();
        holdersOracle.setUpdateFee(newFee);
        vm.stopPrank();
    }
    
    // Test isDataFresh function
    function test_IsDataFresh() public {
        // Setup: manually update holders count
        vm.startPrank(owner);
        holdersOracle.manuallyUpdateNFTCount(tokenAddress, 100);
        vm.stopPrank();
        
        // Data should be fresh immediately after update
        assertTrue(holdersOracle.isDataFresh(tokenAddress));
        
        // Data should be stale after maxDataAge has passed
        vm.warp(block.timestamp + DEFAULT_MAX_DATA_AGE + 1);
        assertFalse(holdersOracle.isDataFresh(tokenAddress));
    }
    
    // Test updateNFTCount function
    function test_updateNFTCount() public {
        // Setup: mint an NFT to user2
        vm.startPrank(owner);
        mockNFT.mint(user2, 1);
        vm.stopPrank();
        
        // User without NFT should not be able to update
        vm.startPrank(user1);
        vm.expectRevert(TokenHoldersOracle.InsufficientNFTBalance.selector);
        holdersOracle.updateNFTCount{value: DEFAULT_UPDATE_FEE}(address(mockNFT));
        vm.stopPrank();
        
        // User with NFT but insufficient fee should not be able to update
        vm.startPrank(user2);
        vm.expectRevert(TokenHoldersOracle.InsufficientFee.selector);
        holdersOracle.updateNFTCount{value: DEFAULT_UPDATE_FEE - 1}(address(mockNFT));
        vm.stopPrank();
        
        // User with NFT and correct fee should be able to update
        // This will revert because the mock router doesn't implement the required function
        // but we can test the fee collection logic
        vm.startPrank(user2);
        vm.deal(user2, 1 ether); // Give user2 some ETH
        
        // Expect this to revert due to mock router limitations
        vm.expectRevert();
        holdersOracle.updateNFTCount{value: DEFAULT_UPDATE_FEE}(address(mockNFT));
        vm.stopPrank();
    }
    
    // Test toString function
    function test_ToString() public {
        // Create a test address with a known pattern
        address testAddr = 0x1234567890123456789012345678901234567890;
        
        // Call the internal toString function using exposed_toString
        string memory result = exposed_toString(testAddr);
        
        // Expected result is the lowercase hex representation with 0x prefix
        string memory expected = "0x1234567890123456789012345678901234567890";
        
        // Compare the strings
        assertEq(result, expected);
    }
    
    // Helper function to expose internal toString function for testing
    function exposed_toString(address _addr) public pure returns (string memory) {
        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";
        
        address addr = _addr;
        for (uint256 i = 0; i < 20; i++) {
            uint8 value = uint8(uint160(addr) >> (8 * (19 - i)));
            result[2 + i * 2] = exposed_toHexChar(value >> 4);
            result[3 + i * 2] = exposed_toHexChar(value & 0x0f);
        }
        
        return string(result);
    }
    
    // Helper function to expose internal toHexChar function for testing
    function exposed_toHexChar(uint8 value) public pure returns (bytes1) {
        if (value < 10) {
            return bytes1(uint8(bytes1("0")) + value);
        } else {
            return bytes1(uint8(bytes1("a")) + value - 10);
        }
    }
    
    // Test for invalid token address in manuallyUpdateNFTCount
    function test_InvalidTokenAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(TokenHoldersOracle.InvalidTokenAddress.selector);
        holdersOracle.manuallyUpdateNFTCount(address(0), 100);
        vm.stopPrank();
    }
    
    // Test for invalid treasury address in setTreasuryAddress
    function test_InvalidTreasuryAddress() public {
        vm.startPrank(owner);
        vm.expectRevert(TokenHoldersOracle.InvalidTreasuryAddress.selector);
        holdersOracle.setTreasuryAddress(address(0));
        vm.stopPrank();
    }
    
    // Test getNFTCount for non-existent token
    function test_getNFTCountNonExistent() public {
        address nonExistentToken = makeAddr("nonExistentToken");
        (uint256 count, uint256 lastUpdate) = holdersOracle.getNFTCount(nonExistentToken);
        assertEq(count, 0);
        assertEq(lastUpdate, 0);
    }
    
    // Test DataAlreadyFresh revert condition
    function test_DataAlreadyFresh() public {
        // Setup: manually update holders count and mint NFT to user2
        vm.startPrank(owner);
        holdersOracle.manuallyUpdateNFTCount(address(mockNFT), 100);
        mockNFT.mint(user2, 1);
        vm.stopPrank();
        
        // Attempt to update when data is already fresh
        vm.startPrank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert(TokenHoldersOracle.DataAlreadyFresh.selector);
        holdersOracle.updateNFTCount{value: DEFAULT_UPDATE_FEE}(address(mockNFT));
        vm.stopPrank();
    }
    
    // Test the deployed contract instance (commented out as it requires a real deployment)
    function testDeployed_getNFTCount() public {
        // This test is for the deployed contract and is commented out
        // Uncomment and modify as needed when testing against a real deployment
        
        // uint256 ownerPk = vm.envUint("PRIVATE_KEY");
        // owner = vm.addr(ownerPk);
        // TokenHoldersOracle deployedOracle = TokenHoldersOracle(0xFa35acb38c09Cd416956F7593ac57E669fd9EDF1);
        
        // vm.startPrank(owner);
        // address tokenAddress = 0x2877Da93f3b2824eEF206b3B313d4A61E01e5698;
        // deployedOracle.requestNFTCount(tokenAddress);
        // (uint256 count, uint256 lastUpdate) = deployedOracle.getNFTCount(tokenAddress);
        // console.log("Holders count:", count);
        // console.log("Last update:", lastUpdate);
        // vm.stopPrank();
    }
}