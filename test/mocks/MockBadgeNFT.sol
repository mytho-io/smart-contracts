// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BadgeNFT} from "../../src/BadgeNFT.sol";

// Mock BadgeNFT that doesn't check for OnlyBoostSystem
contract MockBadgeNFT is BadgeNFT {
    function mintBadgeForTest(address _to, uint256 _badgeType) external {
        // Skip the OnlyBoostSystem check
        _mint(_to, _badgeType);
    }
}