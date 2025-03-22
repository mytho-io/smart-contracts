// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin-upgradeable/contracts/access/manager/AccessManagedUpgradeable.sol";
import "@openzeppelin-upgradeable/contracts/access/manager/AccessManagerUpgradeable.sol";
import "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 * @title TestContract1
 * @dev First test contract with restricted and unrestricted functions
 */
contract TestContract1 is AccessManagedUpgradeable {
    uint256 public value;

    function __TestContract1_init(address initialAuthority) public initializer {
        __AccessManaged_init(initialAuthority);
    }

    function restrictedFunction1() external restricted returns (uint256) {
        return 1;
    }

    function restrictedFunction2() external restricted returns (uint256) {
        return 2;
    }

    function unrestrictedFunction() external returns (uint256) {
        return 3;
    }

    function setValue(uint256 _value) external restricted {
        value = _value;
    }
}

/**
 * @title TestContract2
 * @dev Second test contract with restricted functions
 */
contract TestContract2 is AccessManagedUpgradeable {
    bool public flag;

    function __TestContract2_init(address initialAuthority) public initializer {
        __AccessManaged_init(initialAuthority);
    }

    function restrictedFunction3() external restricted returns (uint256) {
        return 3;
    }

    function setFlag(bool _flag) external restricted {
        flag = _flag;
    }
}

/**
 * @title AccessManagedTest
 * @dev Comprehensive test suite for AccessManaged pattern implementation
 */
contract AccessManagedTest is Test {
    AccessManagerUpgradeable public manager;
    TestContract1 public contract1;
    TestContract2 public contract2;

    address public deployer;
    address public admin;
    address public role1User;
    address public role2User;
    address public unauthorizedUser;
    address public temporaryUser;

    uint64 public constant ROLE_1 = 1;
    uint64 public constant ROLE_2 = 2;
    uint64 public constant ROLE_3 = 3;

    uint32 public constant EXECUTION_DELAY = 2 days;

    event AuthorityUpdated(address indexed authority);

    /**
     * @dev Setup function executed before each test
     */
    function setUp() public {
        deployer = makeAddr("deployer");
        admin = makeAddr("admin");
        role1User = makeAddr("role1User");
        role2User = makeAddr("role2User");
        unauthorizedUser = makeAddr("unauthorizedUser");
        temporaryUser = makeAddr("temporaryUser");

        vm.startPrank(deployer);

        // Deploy AccessManager
        manager = new AccessManagerUpgradeable();
        manager.initialize(admin);

        // Deploy test contracts
        contract1 = new TestContract1();
        contract2 = new TestContract2();

        contract1.__TestContract1_init(address(manager));
        contract2.__TestContract2_init(address(manager));

        vm.stopPrank();

        // Configure roles through admin
        vm.startPrank(admin);
        manager.grantRole(ROLE_1, role1User, 0); // No delay
        manager.grantRole(ROLE_2, role2User, 0);

        // Link roles to functions using bytes4 arrays
        bytes4[] memory selectors1 = new bytes4[](1);
        bytes4[] memory selectors2 = new bytes4[](1);
        bytes4[] memory selectors3 = new bytes4[](1);
        bytes4[] memory selectors4 = new bytes4[](1);
        bytes4[] memory selectors5 = new bytes4[](1);

        selectors1[0] = TestContract1.restrictedFunction1.selector;
        selectors2[0] = TestContract1.restrictedFunction2.selector;
        selectors3[0] = TestContract2.restrictedFunction3.selector;
        selectors4[0] = TestContract1.setValue.selector;
        selectors5[0] = TestContract2.setFlag.selector;

        manager.setTargetFunctionRole(address(contract1), selectors1, ROLE_1);
        manager.setTargetFunctionRole(address(contract1), selectors2, ROLE_2);
        manager.setTargetFunctionRole(address(contract2), selectors3, ROLE_1);
        manager.setTargetFunctionRole(address(contract1), selectors4, ROLE_1);
        manager.setTargetFunctionRole(address(contract2), selectors5, ROLE_2);

        vm.stopPrank();
    }

    /**
     * @dev Test access for users with Role 1
     */
    function testRole1Access() public {
        vm.prank(role1User);
        assertEq(contract1.restrictedFunction1(), 1);

        vm.prank(role1User);
        assertEq(contract2.restrictedFunction3(), 3);
    }

    /**
     * @dev Test access for users with Role 2
     */
    function testRole2Access() public {
        vm.prank(role2User);
        assertEq(contract1.restrictedFunction2(), 2);
    }

    /**
     * @dev Test denied access for unauthorized users
     */
    function testUnauthorizedAccess() public {
        bytes4 unauthorizedSelector = IAccessManaged
            .AccessManagedUnauthorized
            .selector;

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(unauthorizedSelector, unauthorizedUser)
        );
        contract1.restrictedFunction1();

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(unauthorizedSelector, unauthorizedUser)
        );
        contract1.restrictedFunction2();

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(unauthorizedSelector, unauthorizedUser)
        );
        contract2.restrictedFunction3();
    }

    /**
     * @dev Test that roles cannot access functions restricted to other roles
     */
    function testCrossRoleAccess() public {
        bytes4 unauthorizedSelector = IAccessManaged
            .AccessManagedUnauthorized
            .selector;

        vm.prank(role1User);
        vm.expectRevert(
            abi.encodeWithSelector(unauthorizedSelector, role1User)
        );
        contract1.restrictedFunction2();

        vm.prank(role2User);
        vm.expectRevert(
            abi.encodeWithSelector(unauthorizedSelector, role2User)
        );
        contract1.restrictedFunction1();
    }

    /**
     * @dev Test authority management operations
     */
    function testAuthorityManagement() public {
        bytes4 unauthorizedSelector = IAccessManaged
            .AccessManagedUnauthorized
            .selector;
        bytes4 invalidAuthoritySelector = IAccessManaged
            .AccessManagedInvalidAuthority
            .selector;

        // Check current authority
        assertEq(contract1.authority(), address(manager));

        // Only current authority can change authority
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(unauthorizedSelector, unauthorizedUser)
        );
        contract1.setAuthority(unauthorizedUser);

        // Cannot set an authority without code
        vm.prank(address(manager));
        vm.expectRevert(
            abi.encodeWithSelector(invalidAuthoritySelector, unauthorizedUser)
        );
        contract1.setAuthority(unauthorizedUser);

        // Successful authority change
        AccessManagerUpgradeable newManager = new AccessManagerUpgradeable();
        newManager.initialize(admin);

        vm.prank(address(manager));
        contract1.setAuthority(address(newManager));

        assertEq(contract1.authority(), address(newManager));
    }

    /**
     * @dev Test unrestricted function access
     */
    function testUnrestrictedFunction() public {
        vm.prank(unauthorizedUser);
        assertEq(contract1.unrestrictedFunction(), 3);
    }

    /**
     * @dev Test isConsumingScheduledOp default behavior
     */
    function testIsConsumingScheduledOp() public {
        // Should return 0 by default
        assertEq(contract1.isConsumingScheduledOp(), bytes4(0));
    }

    /**
     * @dev Test role granting with execution delay
     */
    function testRoleGrantingWithDelay() public {
        bytes4 unauthorizedSelector = IAccessManaged
            .AccessManagedUnauthorized
            .selector;
        bytes4 notReadySelector = bytes4(keccak256("AccessManagerNotReady(bytes32)"));

        // Link ROLE_3 to setValue function
        vm.prank(admin);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = TestContract1.setValue.selector;
        manager.setTargetFunctionRole(address(contract1), selectors, ROLE_3);

        // Grant ROLE_3 to temporaryUser with execution delay
        vm.prank(admin);
        manager.grantRole(ROLE_3, temporaryUser, EXECUTION_DELAY);

        // Schedule the operation
        bytes memory callData = abi.encodeWithSelector(
            TestContract1.setValue.selector,
            100
        );
        vm.prank(temporaryUser);
        (bytes32 operationId, ) = manager.schedule(
            address(contract1),
            callData,
            uint48(block.timestamp + EXECUTION_DELAY)
        );

        // Attempt to execute before delay expires - should fail
        vm.prank(temporaryUser);
        vm.expectRevert(abi.encodeWithSelector(notReadySelector, operationId));
        contract1.setValue(100);

        // Wait for the delay to expire
        vm.warp(block.timestamp + EXECUTION_DELAY + 1);

        // Now the operation should be executable
        vm.prank(temporaryUser);
        contract1.setValue(100);

        // Verify the state change occurred
        assertEq(contract1.value(), 100);
    }

    /**
     * @dev Test role revocation
     */
    function testRoleRevocation() public {
        bytes4 unauthorizedSelector = IAccessManaged
            .AccessManagedUnauthorized
            .selector;

        // Verify access before revocation
        vm.prank(role1User);
        assertEq(contract1.restrictedFunction1(), 1);

        // Revoke role
        vm.prank(admin);
        manager.revokeRole(ROLE_1, role1User);

        // Verify access is denied after revocation
        vm.prank(role1User);
        vm.expectRevert(
            abi.encodeWithSelector(unauthorizedSelector, role1User)
        );
        contract1.restrictedFunction1();
    }

    /**
     * @dev Test role transfer functionality
     */
    function testRoleTransfer() public {
        // Grant ROLE_1 to temporaryUser
        vm.prank(admin);
        manager.grantRole(ROLE_1, temporaryUser, 0);

        // Check both users have access
        vm.prank(role1User);
        assertEq(contract1.restrictedFunction1(), 1);

        vm.prank(temporaryUser);
        assertEq(contract1.restrictedFunction1(), 1);

        // State modification via restricted function
        vm.prank(role1User);
        contract1.setValue(42);
        assertEq(contract1.value(), 42);

        vm.prank(temporaryUser);
        contract1.setValue(84);
        assertEq(contract1.value(), 84);
    }

    /**
     * @dev Test multiple function permissions
     */
    function testMultipleFunctionPermissions() public {
        // Grant multiple roles to a single user
        vm.prank(admin);
        manager.grantRole(ROLE_1, temporaryUser, 0);

        vm.prank(admin);
        manager.grantRole(ROLE_2, temporaryUser, 0);

        // The user should have access to functions from both roles
        vm.prank(temporaryUser);
        assertEq(contract1.restrictedFunction1(), 1);

        vm.prank(temporaryUser);
        assertEq(contract1.restrictedFunction2(), 2);

        vm.prank(temporaryUser);
        assertEq(contract2.restrictedFunction3(), 3);
    }

    /**
     * @dev Test access manager admin functions
     */
    function testAccessManagerAdmin() public {
        // Only admin can grant roles
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        manager.grantRole(ROLE_1, temporaryUser, 0);

        // Admin can grant roles
        vm.prank(admin);
        manager.grantRole(ROLE_1, temporaryUser, 0);

        // Admin can transfer admin role
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        manager.grantRole(0, newAdmin, 0);

        // New admin can grant roles
        vm.prank(newAdmin);
        manager.grantRole(ROLE_2, temporaryUser, 0);

        // Verify temporary user has both roles now
        vm.prank(temporaryUser);
        assertEq(contract1.restrictedFunction1(), 1);

        vm.prank(temporaryUser);
        assertEq(contract1.restrictedFunction2(), 2);
    }

    /**
     * @dev Test state modification through restricted functions
     */
    function testStateModification() public {
        // ROLE_1 user can modify state through setValue
        vm.prank(role1User);
        contract1.setValue(123);
        assertEq(contract1.value(), 123);

        // ROLE_2 user can modify flag in contract2
        vm.prank(role2User);
        contract2.setFlag(true);
        assertTrue(contract2.flag());

        // Unauthorized user cannot modify state
        vm.prank(unauthorizedUser);
        vm.expectRevert();
        contract1.setValue(456);

        // Value should remain unchanged
        assertEq(contract1.value(), 123);
    }

    /**
     * @dev Helper function to switch the pranked account
     * @param _user Address to impersonate
     */
    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }
}
