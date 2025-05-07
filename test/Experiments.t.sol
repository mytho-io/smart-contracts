// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract Implementation {
    uint256 public constant x = 100;
}

contract NewImplementation {
    uint256 public constant x = 6700;
    uint256 public constant y = 200;
}

contract ExperimentsTest is Test {
    ProxyAdmin proxyAdmin;

    Implementation impl;
    TransparentUpgradeableProxy proxy;

    address deployer;

    function setUp() public {
        deployer = makeAddr("deployer");

        prank(deployer);
        Implementation newImpl = new Implementation();
        proxy = new TransparentUpgradeableProxy(address(newImpl), deployer, "");
        impl = Implementation(address(proxy));
    }

    function test_ConstantsInProxyImplementation() public {
        assertEq(impl.x(), 100);

        updateImpl();
        NewImplementation newImpl = NewImplementation(address(proxy));
        assertEq(newImpl.y(), 200);
        assertEq(newImpl.x(), 6700);
    }

    function updateImpl() internal {
        address adminProxyAddr = getProxyAdmin(address(proxy));
        ProxyAdmin admin = ProxyAdmin(adminProxyAddr);
        admin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(new NewImplementation()),
            ""
        );
    }

    function getProxyAdmin(address proxyAddress) public view returns (address) {
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        bytes32 value = vm.load(proxyAddress, adminSlot);
        return address(uint160(uint256(value)));
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
