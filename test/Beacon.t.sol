// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MeritManager} from "../src/MeritManager.sol";

contract BeaconTest is Test {
    UpgradeableBeacon beacon;

    BeaconProxy proxyA;
    BeaconProxy proxyB;

    Implementation contractA;
    Implementation contractB;

    ImplementationUpdated contractAUpd;
    ImplementationUpdated contractBUpd;

    address deployer;

    function setUp() public {
        deployer = makeAddr("deployer");

        prank(deployer);

        Implementation impl = new Implementation();
        beacon = new UpgradeableBeacon(address(impl), deployer);

        proxyA = new BeaconProxy(address(beacon), abi.encodeWithSignature("initialize(uint256)", 42));
        proxyB = new BeaconProxy(address(beacon), abi.encodeWithSignature("initialize(uint256)", 61));

        contractA = Implementation(payable(address(proxyA)));
        contractB = Implementation(payable(address(proxyB)));
    }

    function test() public {
        assertEq(contractA.num(), 42);
        assertEq(contractB.num(), 61);

        ImplementationUpdated implUpd = new ImplementationUpdated();
        beacon.upgradeTo(address(implUpd));

        contractAUpd = ImplementationUpdated(payable(address(contractA)));
        contractBUpd = ImplementationUpdated(payable(address(contractB)));

        assertEq(contractAUpd.getPhrase(), unicode"Impl updated 👌");
        assertEq(contractBUpd.getPhrase(), unicode"Impl updated 👌");

        contractAUpd.setNum(100);
        assertEq(contractA.num(), 100);
        assertEq(contractB.num(), 61);
    }

    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }
}

contract Implementation {
    uint256 public num;

    function initialize(uint256 _num) public {
        num = _num;
    }

    function setNum(uint256 _num) public {
        num = _num;
    }
}

contract ImplementationUpdated {
    uint256 public num;

    function initialize(uint256 _num) public {
        num = _num;
    }

    function setNum(uint256 _num) public {
        num = _num;
    }

    function getPhrase() public pure returns (string memory) {
        return unicode"Impl updated 👌";
    }
}