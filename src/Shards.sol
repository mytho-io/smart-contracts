// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol";

import {AddressRegistry} from "./AddressRegistry.sol";

/**
 * @title Shards
 * @notice MYTHO Shard Token - ERC20 token used for post rewards in the MYTHO ecosystem
 * @dev Upgradeable contract with minting, burning, and pause functionality
 */
contract Shards is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable
{
    // State variables - Addresses
    address private registryAddr;

    // Constants - Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant MANAGER = keccak256("MANAGER");

    // Custom errors
    error ZeroAddress();
    error EcosystemPaused();

    /**
     * @notice Initializes the Shards contract
     * @dev Sets up initial roles and connects to the ecosystem registry
     * @param _registryAddr Address of the AddressRegistry contract
     */
    function initialize(address _registryAddr) public initializer {
        __ERC20_init("Mytho Shard Token", "SHARD");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();

        if (_registryAddr == address(0)) revert ZeroAddress();

        registryAddr = _registryAddr;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
        _grantRole(MINTER_ROLE, AddressRegistry(registryAddr).getPosts());
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Mints new SHARD tokens
     * @dev Only callable by the Posts contract (MINTER_ROLE)
     * @param _to Address to receive the minted tokens
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _mint(_to, _amount);
    }

    /**
     * @notice Pauses all token transfers and minting
     * @dev Only callable by MANAGER role
     */
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpauses token transfers and minting
     * @dev Only callable by MANAGER role
     */
    function unpause() external onlyRole(MANAGER) {
        _unpause();
    }

    // INTERNAL FUNCTIONS

    /**
     * @dev Throws if the contract is paused or if the ecosystem is paused
     * @dev Overrides OpenZeppelin's PausableUpgradeable _requireNotPaused
     */
    function _requireNotPaused() internal view virtual override {
        super._requireNotPaused();
        if (AddressRegistry(registryAddr).isEcosystemPaused()) {
            revert EcosystemPaused();
        }
    }

    /**
     * @dev Updates token balances, handling both ERC20 and ERC20Pausable logic
     * @param from The address to transfer from
     * @param to The address to transfer to
     * @param value The amount to transfer
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20PausableUpgradeable, ERC20Upgradeable) {
        super._update(from, to, value);
    }
}