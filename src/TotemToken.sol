// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title TotemToken
 * @notice ERC20 token with sale period restrictions and autonomous management
 * @dev Extends ERC20 to manage token distribution and control transfers
 */
contract TotemToken is ERC20, ERC20Burnable, ERC20Permit {
    // Indicates if the token is in the sale period (transfers restricted)
    bool public salePeriod;

    // Address of the distributor, the only one who can transfer tokens during sale period
    address public immutable totemDistributor;

    // Events
    event SalePeriodEnded();

    // Custom errors
    error InvalidAddress(); 
    error NotAllowedInSalePeriod();    
    error OnlyForDistributor();
    error SalePeriodAlreadyEnded();

    /**
     * @dev Mints 1_000_000_000 tokens and assigns them to the distributor
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param _totemDistributor The address of the token distributor
     */
    constructor(
        string memory name, 
        string memory symbol,
        address _totemDistributor
    ) ERC20(name, symbol) ERC20Permit(name) {
        if (_totemDistributor == address(0)) revert InvalidAddress();

        totemDistributor = _totemDistributor;

        // Mint all tokens at once and assign them to the distributor
        _mint(_totemDistributor, 1_000_000_000 ether);
        
        // Enable sale period
        salePeriod = true;
    }

    /**
     * @notice Opens token transfers, ending the sale period
     * @dev Can only be called by the distributor and only once
     */
    function openTransfers() external {
        if (msg.sender != totemDistributor) revert OnlyForDistributor();
        if (!salePeriod) revert SalePeriodAlreadyEnded();

        salePeriod = false;
        emit SalePeriodEnded();
    }

    /**
     * @notice Updates token balances with transfer restrictions during sale period
     * @dev Overrides _update from ERC20 to enforce sale period rules
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param value The amount of tokens being transferred
     */
    function _update(address from, address to, uint256 value) internal override {
        // During sale period, only the distributor can transfer tokens
        // Burning (transfer to address(0)) is also restricted during sale period
        if (salePeriod && msg.sender != totemDistributor) {
            revert NotAllowedInSalePeriod();
        }
        
        super._update(from, to, value);
    }
}
