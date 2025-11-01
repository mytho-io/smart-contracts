// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";
import {SendParam} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract OFTTest is Test {
    Token public token;
    address deployer;
    address user1;
    address user2;
    address lzEndpoint;
    address delegate;
    uint32 dstEid = 2;
    address dstPeer;
    
    function setUp() public {
        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        lzEndpoint = makeAddr("lzEndpoint");
        delegate = deployer;
        dstPeer = makeAddr("dstPeer");

        // Corrected mock to match the exact quote function signature
        vm.mockCall(
            lzEndpoint,
            abi.encodeWithSelector(
                bytes4(keccak256("quote((uint32,bytes32,bytes,bytes,bool),address)"))
            ),
            abi.encode(MessagingFee(1 ether, 0))
        );

        prank(deployer);
        token = new Token("TestToken", "TTK", lzEndpoint, delegate);

        prank(deployer);
        token.setPeer(dstEid, bytes32(uint256(uint160(dstPeer))));
    }    

    function testTokenInitialization() public {
        assertEq(token.name(), "TestToken");
        assertEq(token.symbol(), "TTK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 100 ether);
        assertEq(token.balanceOf(deployer), 100 ether);
    }

    function testTransfer() public {
        prank(deployer);
        token.transfer(user1, 25 ether);
        
        assertEq(token.balanceOf(deployer), 75 ether);
        assertEq(token.balanceOf(user1), 25 ether);
    }

    function testApproveAndTransferFrom() public {
        prank(deployer);
        token.approve(user1, 30 ether);
        assertEq(token.allowance(deployer, user1), 30 ether);

        prank(user1);
        token.transferFrom(deployer, user2, 20 ether);

        assertEq(token.balanceOf(deployer), 80 ether);
        assertEq(token.balanceOf(user2), 20 ether);
        assertEq(token.allowance(deployer, user1), 10 ether);
    }

    function testInitialOwnership() public {
        assertEq(token.owner(), delegate);
    }

    function testTransferOwnership() public {
        prank(deployer);
        token.transferOwnership(user1);
        assertEq(token.owner(), user1);
    }

    function testNonOwnerCannotTransferOwnership() public {
        prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1));
        token.transferOwnership(user2);
    }

    function testQuoteSendFee() public {
        uint256 amount = 10 ether;
        bytes32 toAddress = bytes32(uint256(uint160(user2)));

        prank(deployer);
        MessagingFee memory fee = token.quoteSend(
            SendParam(
                dstEid,
                toAddress,
                amount,
                amount,
                bytes(""),
                bytes(""),
                bytes("")
            ),
            false
        );

        assertEq(fee.nativeFee, 1 ether, "Incorrect native fee");
        assertEq(fee.lzTokenFee, 0, "Incorrect lzToken fee");
    }

    function test_Revert_TransferInsufficientBalance() public {
        prank(user1);
        vm.expectRevert();
        token.transfer(user2, 1 ether);
    }

    function testF_Revert_TransferFromInsufficientAllowance() public {
        prank(deployer);
        token.approve(user1, 5 ether);

        prank(user1);
        vm.expectRevert();
        token.transferFrom(deployer, user2, 10 ether);
    }

    function testF_Revert_TransferToZeroAddress() public {
        prank(deployer);
        vm.expectRevert();
        token.transfer(address(0), 10 ether);
    }

    function prank(address _user) internal {
        vm.stopPrank();
        vm.startPrank(_user);
    }
}

contract Token is OFT {
    constructor(
        string memory _name,
        string memory _symbol,
        address _endpoint,
        address _delegate
    ) OFT(_name, _symbol, _endpoint, _delegate) Ownable(_delegate) {
        _mint(msg.sender, 100 ether);
    }
}