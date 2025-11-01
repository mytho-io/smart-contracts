// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Base.t.sol";

contract NativePaymentTokenTest is Base {
    function testProcess() public {
        prank(deployer);
        // Fill WETH balance
        vm.deal(deployer, 1_000_000_000 ether);
        weth.deposit{value: 1_000_000_000 ether}();

        // Set native wrapped token as a payment token
        distr.setPaymentToken(address(weth));

        // Set price feed for weth
        distr.setPriceFeed(address(weth), address(mockV3Aggregator));

        // Totem creation
        prank(userA);
        vm.deal(userA, 100 ether);
        astrToken.approve(address(factory), factory.getCreationFee());
        factory.createTotem(
            abi.encodePacked(keccak256("metaData")),
            "Yield&Brew",
            "Y&B",
            new address[](0)
        );
        TF.TotemData memory totemData = factory.getTotemData(
            factory.getLastId() - 1
        );
        TT totemToken = TT(totemData.totemTokenAddr);
        
        // How much for 1000 totem tokens?
        // --> 0.01 ETH
        
        // 250_000 totem tokens is initial balance of UserA
        assertTrue(totemToken.balanceOf(userA) == 250_000 ether);

        // Check initial balances
        assertTrue(weth.balanceOf(userA) == 0, "Zero balance at WETH tokens");
        assertTrue(userA.balance == 100 ether, "100 native tokens initially");

        // bnb amount for 1000 totem tokens
        uint256 value = distr.totemsToPaymentToken(address(weth), 1000 ether);

        distr.buy{value: value}(address(totemToken), 1000 ether);
        assertTrue(totemToken.balanceOf(userA) == 251_000 ether);

        // approve all for distributor
        totemToken.approve(address(distr), type(uint256).max);

        assertTrue(userA.balance == 99.9 ether);
        distr.sell(address(totemToken), 500 ether);
        assertTrue(totemToken.balanceOf(userA) == 250_500 ether);
        assertTrue(userA.balance == 99.95 ether);

        // buy rest totem tokens
        prank(deployer);
        // turn off limits
        distr.setMaxTotemTokensPerAddress(1_000_000_000 ether);

        prank(userA);
        uint256 restAmount = distr.getAvailableTokensForPurchase(userA, address(totemToken));
        uint256 valueForPurchase = distr.totemsToPaymentToken(address(weth), restAmount);
        vm.deal(userA, valueForPurchase);
        distr.buy{value: valueForPurchase}(address(totemToken), restAmount);

        TTD.TotemData memory distrTotemData = distr.getTotemData(address(totemToken));
        assertFalse(distrTotemData.isSalePeriod, "Sale period should be finished");
        assertGt(weth.balanceOf(totemData.totemAddr), 0);

        // multisig should be able to withdraw wbnb from totem
        prank(deployer);
        registry.setAddress(bytes32("MULTISIG_WALLET"), makeAddr("MULTISIG_WALLET"));

        prank(registry.getMultisigWallet());
        assertTrue(deployer.balance == 0, "Deployers balance in BNB eq to zero");
        Totem(payable(totemData.totemAddr)).withdrawToken(
            address(weth),
            deployer,
            10 ether
        );
        assertTrue(deployer.balance == 10 ether, "Deployers balance should incr on 10 BNB");

        // test redeem
        prank(userA);
        totemToken.transfer(userB, 100 ether);
        assertTrue(totemToken.balanceOf(userB) == 100 ether);
        assertTrue(userB.balance == 0);

        prank(userB);
        totemToken.approve(totemData.totemAddr, 100 ether);
        Totem(payable(totemData.totemAddr)).redeemTotemTokens(100 ether);
        assertGt(userB.balance, 0);
    }
}
