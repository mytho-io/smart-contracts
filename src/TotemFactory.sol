// SPDX-License-Identifier: BUSL-1.1
// Copyright © 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {TotemToken} from "./TotemToken.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";

/**
 * @title TotemFactory
 * @notice Factory contract for creating new Totems in the MYTHO ecosystem
 *      Handles creation of new Totems with either new or existing tokens
 */
contract TotemFactory is PausableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    // State variables - Contracts
    TotemTokenDistributor private totemDistributor;

    // State variables - Addresses
    address private beaconAddr;
    address private treasuryAddr;
    address private meritManagerAddr;
    address private registryAddr;
    address private feeTokenAddr;

    // State variables - Fee settings
    uint256 private creationFee;
    uint256 private lastId;

    // Mappings
    mapping(uint256 totemId => TotemData data) private totemData;
    mapping(address totemAddr => TotemData data) private totemDataByAddress;
    mapping(address token => mapping(address user => bool)) private authorized;

    // Structs
    struct TotemData {
        address creator;
        address totemTokenAddr;
        address totemAddr;
        bytes dataHash;
        bool isCustomToken;
    }

    // Constants - Roles
    bytes32 private constant MANAGER = keccak256("MANAGER");

    // Events
    event TotemCreated(address totemAddr, address totemTokenAddr, uint256 totemId); // prettier-ignore
    event TotemWithExistingTokenCreated(address totemAddr, address totemTokenAddr, uint256 totemId); // prettier-ignore
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeTokenUpdated(address oldToken, address newToken);
    event BatchWhitelistUpdated(address[] tokens, bool isAdded);
    event TokenAuthorizationUpdated(address indexed token, address indexed user, bool isAuthorized); // prettier-ignore

    // Custom errors
    error TokenAlreadyAuthorized(address token, address user);
    error AlreadyWhitelisted(address totemTokenAddr);
    error NotWhitelisted(address totemTokenAddr);
    error ZeroAddress();
    error InvalidTotemParameters(string reason);
    error TotemNotFound(uint256 totemId);
    error EcosystemPaused();
    error UserNotAuthorized(address user, address token);

    /**
     * @notice Initializes the TotemFactory contract
     *      Sets up initial roles and configuration
     * @param _registryAddr Address of the AddressRegistry contract
     * @param _beaconAddr Address of the beacon for Totem proxies
     * @param _feeTokenAddr Address of the token used for creation fees
     */
    function initialize(
        address _registryAddr,
        address _beaconAddr,
        address _feeTokenAddr
    ) public initializer {
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        // Initialize fee settings
        if (_registryAddr == address(0)) revert ZeroAddress();
        if (_beaconAddr == address(0)) revert ZeroAddress();
        if (_feeTokenAddr == address(0)) revert ZeroAddress();

        totemDistributor = TotemTokenDistributor(
            AddressRegistry(_registryAddr).getTotemTokenDistributor()
        );
        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();
        meritManagerAddr = AddressRegistry(_registryAddr).getMeritManager();
        beaconAddr = _beaconAddr;
        registryAddr = _registryAddr;

        feeTokenAddr = _feeTokenAddr;
        creationFee = 1 ether; // Initial fee
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Creates a new totem with a new token
     *      Deploys a new TotemToken and Totem proxy
     * @param _dataHash The hash of the totem data
     * @param _tokenName The name of the token
     * @param _tokenSymbol The symbol of the token
     * @param _collaborators Array of collaborator addresses
     */
    function createTotem(
        bytes memory _dataHash,
        string memory _tokenName,
        string memory _tokenSymbol,
        address[] memory _collaborators
    ) public whenNotPaused {
        if (
            bytes(_tokenName).length == 0 ||
            bytes(_tokenSymbol).length == 0 ||
            _dataHash.length == 0
        ) {
            revert InvalidTotemParameters("Empty token name or symbol");
        }

        // Collect fee in ASTR tokens
        _collectFee(msg.sender);

        TotemToken totemToken = new TotemToken(
            _tokenName,
            _tokenSymbol,
            address(totemDistributor)
        );

        BeaconProxy proxy = new BeaconProxy(
            beaconAddr,
            abi.encodeWithSignature(
                "initialize(address,bytes,address,bool,address,address[])",
                address(totemToken),
                _dataHash,
                registryAddr,
                false,
                msg.sender,
                _collaborators
            )
        );

        TotemData memory data = TotemData({
            creator: msg.sender,
            totemTokenAddr: address(totemToken),
            totemAddr: address(proxy),
            dataHash: _dataHash,
            isCustomToken: false
        });
        
        totemData[lastId++] = data;
        totemDataByAddress[address(proxy)] = data;

        // register the totem and make initial tokens distribution
        totemDistributor.register();

        emit TotemCreated(address(proxy), address(totemToken), lastId - 1);
    }

    /**
     * @notice Creates a new totem with an existing whitelisted token
     *      Uses an existing token instead of deploying a new one
     * @param _dataHash The hash of the totem data
     * @param _tokenAddr The address of the existing token
     * @param _collaborators Array of collaborator addresses
     */
    function createTotemWithExistingToken(
        bytes memory _dataHash,
        address _tokenAddr,
        address[] memory _collaborators
    ) public whenNotPaused {
        if (_dataHash.length == 0) {
            revert InvalidTotemParameters("Empty dataHash");
        }
        if (_tokenAddr == address(0)) revert ZeroAddress();

        // Collect fee in ASTR tokens
        _collectFee(msg.sender);

        // Check if user is authorized to create totem with this token
        if (!authorized[_tokenAddr][msg.sender])
            revert UserNotAuthorized(msg.sender, _tokenAddr);

        BeaconProxy proxy = new BeaconProxy(
            beaconAddr,
            abi.encodeWithSignature(
                "initialize(address,bytes,address,bool,address,address[])",
                _tokenAddr,
                _dataHash,
                registryAddr,
                true,
                msg.sender,
                _collaborators
            )
        );

        TotemData memory data = TotemData({
            creator: msg.sender,
            totemTokenAddr: _tokenAddr,
            totemAddr: address(proxy),
            dataHash: _dataHash,
            isCustomToken: true
        });
        
        totemData[lastId++] = data;
        totemDataByAddress[address(proxy)] = data;

        MeritManager(meritManagerAddr).register(address(proxy));

        emit TotemWithExistingTokenCreated(
            address(proxy),
            _tokenAddr,
            lastId - 1
        );
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Updates the creation fee
     * @param _newFee The new fee amount
     */
    function setCreationFee(uint256 _newFee) public onlyRole(MANAGER) {
        uint256 oldFee = creationFee;
        creationFee = _newFee;
        emit CreationFeeUpdated(oldFee, _newFee);
    }

    /**
     * @notice Updates the fee token address
     * @param _newFeeToken The address of the new fee token
     */
    function setFeeToken(address _newFeeToken) public onlyRole(MANAGER) {
        if (_newFeeToken == address(0)) revert ZeroAddress();

        address oldToken = feeTokenAddr;
        feeTokenAddr = _newFeeToken;
        emit FeeTokenUpdated(oldToken, _newFeeToken);
    }

    /**
     * @notice Authorizes users for a token
     * @param _token The token address
     * @param _users Array of user addresses to authorize
     */
    function authorizeUsers(
        address _token,
        address[] calldata _users
    ) public onlyRole(MANAGER) {
        if (_token == address(0)) revert ZeroAddress();

        for (uint256 i = 0; i < _users.length; i++) {
            if (_users[i] != address(0)) {
                if (authorized[_token][_users[i]]) 
                    revert TokenAlreadyAuthorized(_token, _users[i]);
                
                authorized[_token][_users[i]] = true;
                emit TokenAuthorizationUpdated(_token, _users[i], true);
            }
        }
    }

    /**
     * @notice Removes authorization from users for a token
     * @param _token The token address
     * @param _users Array of user addresses to deauthorize
     */
    function deauthorizeUsers(
        address _token,
        address[] calldata _users
    ) public onlyRole(MANAGER) {
        for (uint256 i = 0; i < _users.length; i++) {
            if (_users[i] != address(0)) {
                authorized[_token][_users[i]] = false;
                emit TokenAuthorizationUpdated(_token, _users[i], false);
            }
        }
    }

    /**
     * @notice Checks if a user is authorized for a token
     * @param _token The token address
     * @param _user The user address
     * @return Whether the user is authorized
     */
    function isUserAuthorized(
        address _token,
        address _user
    ) external view returns (bool) {
        return authorized[_token][_user];
    }

    /**
     * @notice Pauses the contract
     */
    function pause() public onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() public onlyRole(MANAGER) {
        _unpause();
    }

    /**
     * @dev Throws if the contract is paused or if the ecosystem is paused.
     */
    function _requireNotPaused() internal view virtual override {
        super._requireNotPaused();
        if (AddressRegistry(registryAddr).isEcosystemPaused()) {
            revert EcosystemPaused();
        }
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Collects creation fee from the sender
     * @param _sender The address paying the fee
     */
    function _collectFee(address _sender) internal {
        // Skip fee collection if fee is set to zero
        if (creationFee == 0) return;

        IERC20(feeTokenAddr).safeTransferFrom(
            _sender,
            treasuryAddr,
            creationFee
        );
    }

    // VIEW FUNCTIONS

    /**
     * @notice Gets the current creation fee
     * @return The current fee amount in fee tokens
     */
    function getCreationFee() external view returns (uint256) {
        return creationFee;
    }

    /**
     * @notice Gets the current fee token address
     * @return The address of the current fee token
     */
    function getFeeToken() external view returns (address) {
        return feeTokenAddr;
    }

    /**
     * @notice Gets the last assigned totem ID
     * @return The last totem ID
     */
    function getLastId() external view returns (uint256) {
        return lastId;
    }

    /**
     * @notice Gets data for a specific totem
     * @param _totemId The ID of the totem
     * @return The totem data structure
     */
    function getTotemData(
        uint256 _totemId
    ) external view returns (TotemData memory) {
        TotemData memory data = totemData[_totemId];
        if (data.totemAddr == address(0)) revert TotemNotFound(_totemId);
        return data;
    }

    /**
     * @notice Gets data for a specific totem by address
     * @param _totemAddr The address of the totem
     * @return The totem data structure
     */
    function getTotemDataByAddress(
        address _totemAddr
    ) external view returns (TotemData memory) {
        TotemData memory data = totemDataByAddress[_totemAddr];
        if (data.totemAddr == address(0)) revert TotemNotFound(0);
        return data;
    }
}
