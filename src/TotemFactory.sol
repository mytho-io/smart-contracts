// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {TotemToken} from "./TotemToken.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";
import {TokenHoldersOracle} from "./utils/TokenHoldersOracle.sol";

/**
 * @title TotemFactory
 * @notice Factory contract for creating new Totems in the MYTHO ecosystem
 *      Handles creation of new Totems with either new or existing tokens
 */
contract TotemFactory is PausableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    // Enum for token types
    enum TokenType {
        STANDARD,  // 0: Standard (non-custom) token
        ERC20,     // 1: Custom ERC20 token
        ERC721     // 2: Custom ERC721 token
    }

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
        TokenType tokenType;
    }

    // Constants - Roles
    bytes32 private constant MANAGER = keccak256("MANAGER");

    // Constants - ERC165 Interface IDs
    bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;

    // Events
    event TotemCreated(address totemAddr, address totemTokenAddr, uint256 totemId); // prettier-ignore
    event TotemWithExistingTokenCreated(address totemAddr, address totemTokenAddr, uint256 totemId, TokenType tokenType); // prettier-ignore
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeTokenUpdated(address oldToken, address newToken);
    event BatchWhitelistUpdated(address[] tokens, bool isAdded);
    event TokenAuthorizationUpdated(address indexed token, address indexed user, bool isAuthorized); // prettier-ignore
    event TokenHoldersOracleUpdated(address oldOracle, address newOracle);

    // Custom errors
    error TokenAlreadyAuthorized(address token, address user);
    error AlreadyWhitelisted(address totemTokenAddr);
    error NotWhitelisted(address totemTokenAddr);
    error ZeroAddress();
    error InvalidTotemParameters(string reason);
    error TotemNotFound(uint256 totemId);
    error EcosystemPaused();
    error UserNotAuthorized(address user, address token);
    error UnsupportedTokenType();

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
     *      Deploys a new TotemToken and Totem contract
     * @param _dataHash The hash of the totem data
     * @param _tokenName The name of the new token
     * @param _tokenSymbol The symbol of the new token
     * @param _collaborators Array of collaborator addresses
     */
    function createTotem(
        bytes memory _dataHash,
        string memory _tokenName,
        string memory _tokenSymbol,
        address[] memory _collaborators
    ) external whenNotPaused {
        if (
            bytes(_tokenName).length == 0 ||
            bytes(_tokenSymbol).length == 0 ||
            _dataHash.length == 0
        ) {
            revert InvalidTotemParameters("Empty token name or symbol");
        }

        // Collect fee in ASTR tokens
        _collectFee(msg.sender);

        // Deploy a new TotemToken
        TotemToken totemToken = new TotemToken(
            _tokenName,
            _tokenSymbol,
            registryAddr
        );

        // Deploy a new Totem proxy
        BeaconProxy proxy = new BeaconProxy(
            beaconAddr,
            abi.encodeWithSignature(
                "initialize(address,bytes,address,address,address[],uint8)",
                totemToken,
                _dataHash,
                registryAddr,
                msg.sender,
                _collaborators,
                uint8(TokenType.STANDARD)
            )
        );

        TotemData memory data = TotemData({
            creator: msg.sender,
            totemTokenAddr: address(totemToken),
            totemAddr: address(proxy),
            dataHash: _dataHash,
            tokenType: TokenType.STANDARD
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
    ) external whenNotPaused {
        if (_dataHash.length == 0) {
            revert InvalidTotemParameters("Empty dataHash");
        }
        if (_tokenAddr == address(0)) revert ZeroAddress();

        // Collect fee in ASTR tokens
        _collectFee(msg.sender);

        // Check if user is authorized to create totem with this token
        if (!authorized[_tokenAddr][msg.sender])
            revert UserNotAuthorized(msg.sender, _tokenAddr);

        // Determine token type (ERC20 or ERC721)
        TokenType tokenType = TokenType.ERC20; // Default to ERC20
        
        // Check if token is ERC721
        if (_isERC721(_tokenAddr)) {
            tokenType = TokenType.ERC721;

            // Set token holders oracle
            TokenHoldersOracle oracle = TokenHoldersOracle(AddressRegistry(registryAddr).getTokenHoldersOracle());
            
            // Request initial holders count from oracle
            oracle.requestHoldersCount(_tokenAddr);
        }

        BeaconProxy proxy = new BeaconProxy(
            beaconAddr,
            abi.encodeWithSignature(
                "initialize(address,bytes,address,address,address[],uint8)",
                _tokenAddr,
                _dataHash,
                registryAddr,
                msg.sender,
                _collaborators,
                uint8(tokenType)
            )
        );

        TotemData memory data = TotemData({
            creator: msg.sender,
            totemTokenAddr: _tokenAddr,
            totemAddr: address(proxy),
            dataHash: _dataHash,
            tokenType: tokenType
        });
        
        totemData[lastId++] = data;
        totemDataByAddress[address(proxy)] = data;

        MeritManager(meritManagerAddr).register(address(proxy));

        emit TotemWithExistingTokenCreated(
            address(proxy),
            _tokenAddr,
            lastId - 1,
            tokenType
        );
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Updates the creation fee
     * @param _newFee The new fee amount
     */
    function setCreationFee(uint256 _newFee) external onlyRole(MANAGER) {
        uint256 oldFee = creationFee;
        creationFee = _newFee;
        emit CreationFeeUpdated(oldFee, _newFee);
    }

    /**
     * @notice Updates the fee token
     * @param _newToken The new fee token address
     */
    function setFeeToken(address _newToken) external onlyRole(MANAGER) {
        if (_newToken == address(0)) revert ZeroAddress();
        address oldToken = feeTokenAddr;
        feeTokenAddr = _newToken;
        emit FeeTokenUpdated(oldToken, _newToken);
    }

    /**
     * @notice Authorizes users to create totems with specific tokens
     * @param _token The token address
     * @param _users Array of user addresses to authorize
     */
    function authorizeUsers(
        address _token,
        address[] calldata _users
    ) external onlyRole(MANAGER) {
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
    ) external onlyRole(MANAGER) {
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
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     */
    function unpause() external onlyRole(MANAGER) {
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

    /**
     * @notice Checks if a token is an ERC721 token
     * @param _token The token address to check
     * @return True if the token is an ERC721, false otherwise
     */
    function _isERC721(address _token) internal view returns (bool) {
        try IERC165(_token).supportsInterface(ERC721_INTERFACE_ID) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
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

    /**
     * @notice Checks if a token is a custom token
     * @param _tokenType The token type to check
     * @return True if the token is custom (ERC20 or ERC721), false otherwise
     */
    function isCustomToken(TokenType _tokenType) external pure returns (bool) {
        return _tokenType != TokenType.STANDARD;
    }
}
