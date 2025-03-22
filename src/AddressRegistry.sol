// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/**
 * @title AddressRegistry
 * @dev Central registry for storing and retrieving addresses of key contracts in the system.
 * Provides a single source of truth for contract addresses and manages access control.
 */
contract AddressRegistry is AccessControlUpgradeable {
    // Map of registered addresses (identifier => registeredAddress)
    mapping(bytes32 => address) private _addresses;

    // Roles
    bytes32 private constant MANAGER = keccak256("MANAGER");

    // Main identifiers
    bytes32 private constant MERIT_MANAGER = "MERIT_MANAGER";
    bytes32 private constant MYTHO_TOKEN = "MYTHO_TOKEN";
    bytes32 private constant MYTHO_TREASURY = "MYTHO_TREASURY";
    bytes32 private constant TOTEM_FACTORY = "TOTEM_FACTORY";
    bytes32 private constant TOTEM_TOKEN_DISTRIBUTOR = "TOTEM_TOKEN_DISTRIBUTOR";

    // Events
    event AddressSet(
        bytes32 indexed id,
        address oldAddress,
        address newAddress
    );

    /**
     * @dev Initializes the contract and sets up initial roles
     * Sets the deployer as both DEFAULT_ADMIN_ROLE and MANAGER
     */
    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
    }

    /**
     * @dev Sets or updates an address in the registry
     * @param _id Identifier for the address being set
     * @param _newAddress New address to associate with the identifier
     */
    function setAddress(
        bytes32 _id,
        address _newAddress
    ) external onlyRole(MANAGER) {
        address oldAddress = _addresses[_id];
        _addresses[_id] = _newAddress;

        emit AddressSet(_id, oldAddress, _newAddress);
    }

    /**
     * @dev Gets the address of the MeritManager contract
     * @return Address of the MeritManager contract
     */
    function getMeritManager() external view returns (address) {
        return getAddress(MERIT_MANAGER);
    }

    /**
     * @dev Gets the address of the MYTHO token contract
     * @return Address of the MYTHO token contract
     */
    function getMythoToken() external view returns (address) {
        return getAddress(MYTHO_TOKEN);
    }

    /**
     * @dev Gets the address of the MYTHO treasury
     * @return Address of the MYTHO treasury
     */
    function getMythoTreasury() external view returns (address) {
        return getAddress(MYTHO_TREASURY);
    }

    /**
     * @dev Gets the address of the TotemFactory contract
     * @return Address of the TotemFactory contract
     */
    function getTotemFactory() external view returns (address) {
        return getAddress(TOTEM_FACTORY);
    }

    /**
     * @dev Gets the address of the TotemTokenDistributor contract
     * @return Address of the TotemTokenDistributor contract
     */
    function getTotemTokenDistributor() external view returns (address) {
        return getAddress(TOTEM_TOKEN_DISTRIBUTOR);
    }    

    /**
     * @dev Gets an address from the registry by its identifier
     * @param id Identifier for the address to retrieve
     * @return Address associated with the given identifier
     */
    function getAddress(bytes32 id) public view returns (address) {
        return _addresses[id];
    }
}
