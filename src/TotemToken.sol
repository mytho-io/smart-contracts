// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import {AddressRegistry} from "../src/AddressRegistry.sol";

/**
 * @title TotemToken
 * @notice ERC20 token with sale period restrictions and autonomous management
 *      Extends ERC20 to manage token distribution and control transfers
 */
contract TotemToken is ERC20, ERC20Burnable, ERC20Permit {
    // State variables
    bool private salePeriod; // Indicates if the token is in the sale period (transfers restricted)

    // Immutable variables
    address public immutable totemDistributor; // Address of the distributor, the only one who can transfer tokens during sale period
    address public immutable registryAddr;

    // Constants
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 ether;

    // Events
    event SalePeriodEnded();

    // Custom errors
    error InvalidAddress();
    error NotAllowedInSalePeriod();
    error OnlyForDistributor();
    error SalePeriodAlreadyEnded();

    /**
     * @notice Mints 1_000_000_000 tokens and assigns them to the distributor
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     * @param _registryAddr The address of the registry contract used to access system contracts
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _registryAddr
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        if (_registryAddr == address(0)) revert InvalidAddress();

        totemDistributor = AddressRegistry(_registryAddr)
            .getTotemTokenDistributor();

        registryAddr = _registryAddr;

        // Mint all tokens at once and assign them to the distributor
        _mint(totemDistributor, INITIAL_SUPPLY);

        // Enable sale period
        salePeriod = true;
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Opens token transfers, ending the sale period
     *      Can only be called by the distributor and only once
     */
    function openTransfers() external {
        if (msg.sender != totemDistributor) revert OnlyForDistributor();
        if (!salePeriod) revert SalePeriodAlreadyEnded();

        salePeriod = false;
        emit SalePeriodEnded();
    }

    // VIEW FUNCTIONS

    /**
     * @notice Checks if the token is in the sale period
     * @return True if the token is in the sale period, false otherwise
     */
    function isInSalePeriod() external view returns (bool) {
        return salePeriod;
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Updates token balances with transfer restrictions during sale period
     *      Overrides _update from ERC20 to enforce sale period rules
     * @param _from The address sending the tokens
     * @param _to The address receiving the tokens
     * @param _value The amount of tokens being transferred
     */
    function _update(
        address _from,
        address _to,
        uint256 _value
    ) internal override {
        // During sale period, only the distributor and Layers contract can transfer tokens
        // All other transfers (including burning) are restricted during sale period
        if (
            salePeriod &&
            msg.sender != totemDistributor &&
            msg.sender != AddressRegistry(registryAddr).getLayers()
        ) {
            revert NotAllowedInSalePeriod();
        }

        super._update(_from, _to, _value);
    }
}