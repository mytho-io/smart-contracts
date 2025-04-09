// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/**
 * @title AddressRegistry
 * @notice Central registry for storing and retrieving addresses of key contracts in the system.
 * Provides a single source of truth for contract addresses and manages access control.
 */
contract AddressRegistry is AccessControlUpgradeable {
    // State variables
    mapping(bytes32 => address) private _addresses;
    bool private _totemsArePaused;
    bool private _ecosystemPaused;

    // Constants
    bytes32 private constant MANAGER = keccak256("MANAGER");
    bytes32 private constant MERIT_MANAGER = "MERIT_MANAGER";
    bytes32 private constant MYTHO_TOKEN = "MYTHO_TOKEN";
    bytes32 private constant MYTHO_TREASURY = "MYTHO_TREASURY";
    bytes32 private constant TOTEM_FACTORY = "TOTEM_FACTORY";
    bytes32 private constant TOTEM_TOKEN_DISTRIBUTOR =
        "TOTEM_TOKEN_DISTRIBUTOR";

    // Events
    event AddressSet(
        bytes32 indexed id,
        address oldAddress,
        address newAddress
    );
    event TotemsPaused(bool isPaused);
    event EcosystemPaused(bool isPaused);

    // Custom errors
    error InvalidIdentifier(bytes32 id);
    error ZeroAddress();

    /**
     * @notice Initializes the contract and sets up initial roles
     * Sets the deployer as both DEFAULT_ADMIN_ROLE and MANAGER
     */
    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Sets or updates an address in the registry
     * @param _id Identifier for the address being set
     * @param _newAddress New address to associate with the identifier
     */
    function setAddress(
        bytes32 _id,
        address _newAddress
    ) external onlyRole(MANAGER) {
        if (_newAddress == address(0)) revert ZeroAddress();

        address oldAddress = _addresses[_id];
        _addresses[_id] = _newAddress;

        emit AddressSet(_id, oldAddress, _newAddress);
    }

    /**
     * @notice Pauses or unpauses all Totem implementations
     * @param _isPaused True to pause, false to unpause
     */
    function setTotemsPaused(bool _isPaused) external onlyRole(MANAGER) {
        _totemsArePaused = _isPaused;
        emit TotemsPaused(_isPaused);
    }

    /**
     * @notice Pauses or unpauses the entire ecosystem
     * @param _isPaused True to pause, false to unpause
     */
    function setEcosystemPaused(bool _isPaused) external onlyRole(MANAGER) {
        _ecosystemPaused = _isPaused;
        emit EcosystemPaused(_isPaused);
    }

    // VIEW FUNCTIONS

    /**
     * @notice Gets the address of the MeritManager contract
     * @return Address of the MeritManager contract
     */
    function getMeritManager() external view returns (address) {
        return getAddress(MERIT_MANAGER);
    }

    /**
     * @notice Gets the address of the MYTHO token contract
     * @return Address of the MYTHO token contract
     */
    function getMythoToken() external view returns (address) {
        return getAddress(MYTHO_TOKEN);
    }

    /**
     * @notice Gets the address of the MYTHO treasury
     * @return Address of the MYTHO treasury
     */
    function getMythoTreasury() external view returns (address) {
        return getAddress(MYTHO_TREASURY);
    }

    /**
     * @notice Gets the address of the TotemFactory contract
     * @return Address of the TotemFactory contract
     */
    function getTotemFactory() external view returns (address) {
        return getAddress(TOTEM_FACTORY);
    }

    /**
     * @notice Gets the address of the TotemTokenDistributor contract
     * @return Address of the TotemTokenDistributor contract
     */
    function getTotemTokenDistributor() external view returns (address) {
        return getAddress(TOTEM_TOKEN_DISTRIBUTOR);
    }

    /**
     * @notice Gets an address from the registry by its identifier
     * @param _id Identifier for the address to retrieve
     * @return Address associated with the given identifier
     */
    function getAddress(bytes32 _id) public view returns (address) {
        return _addresses[_id];
    }

    /**
     * @notice Checks if all Totems are paused
     * @return True if Totems are paused, false otherwise
     */
    function areTotemsPaused() external view returns (bool) {
        return _totemsArePaused;
    }

    /**
     * @notice Checks if the entire ecosystem is paused
     * @return True if the ecosystem is paused, false otherwise
     */
    function isEcosystemPaused() external view returns (bool) {
        return _ecosystemPaused;
    }
}
