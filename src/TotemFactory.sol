// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {Totem} from "./Totem.sol";
import {TotemToken} from "./TotemToken.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";

contract TotemFactory is PausableUpgradeable, AccessControlUpgradeable {
    // Totem token distributor instance
    TotemTokenDistributor private totemDistributor;

    // Core contract addresses
    address private beaconAddr;
    address private treasuryAddr;
    address private meritManagerAddr;
    address private registryAddr;

    // ASTR token address
    address private feeTokenAddr;

    // Fee settings
    uint256 private creationFee;

    uint256 private lastId;

    mapping(uint256 totemId => TotemData data) private totemData;

    struct TotemData {
        address creator;
        address totemTokenAddr;
        address totemAddr;
        bytes dataHash;
        bool isCustomToken;
    }

    bytes32 private constant MANAGER = keccak256("MANAGER");
    bytes32 private constant WHITELISTED = keccak256("WHITELISTED");

    event TotemCreated(
        address totemAddr,
        address totemTokenAddr,
        uint256 totemId
    );
    event TotemWithExistingTokenCreated(
        address totemAddr,
        address totemTokenAddr,
        uint256 totemId
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeTokenUpdated(address oldToken, address newToken);
    event BatchWhitelistUpdated(address[] tokens, bool isAdded);

    error AlreadyWhitelisted(address totemTokenAddr);
    error NotWhitelisted(address totemTokenAddr);
    error InsufficientFee(uint256 provided, uint256 required);
    error FeeTransferFailed();
    error ZeroAddress();
    error InvalidTotemParameters(string reason);
    error TotemNotFound(uint256 totemId);

    function initialize(
        address _registryAddr,
        address _beaconAddr,
        address _feeTokenAddr
    ) public initializer {
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        // Initialize fee settings
        if (_feeTokenAddr == address(0)) revert ZeroAddress();
        if (_registryAddr == address(0)) revert ZeroAddress();

        totemDistributor = TotemTokenDistributor(
            AddressRegistry(_registryAddr).getTotemTokenDistributor()
        );
        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();
        meritManagerAddr = AddressRegistry(_registryAddr).getMeritManager();
        beaconAddr = _beaconAddr;
        registryAddr = _registryAddr;

        feeTokenAddr = _feeTokenAddr;
        creationFee = 1 ether;
    }

    /**
     * @dev Collects creation fee from the sender
     * @param _sender The address paying the fee
     */
    function _collectFee(address _sender) internal {
        // Skip fee collection if fee is set to zero
        if (creationFee == 0) return;

        // Transfer tokens from sender to fee collector
        bool success = IERC20(feeTokenAddr).transferFrom(
            _sender,
            treasuryAddr,
            creationFee
        );
        if (!success) revert FeeTransferFailed();
    }

    /**
     * @dev Creates a new totem with a new token
     * @param _dataHash The hash of the totem data
     * @param _tokenName The name of the token
     * @param _tokenSymbol The symbol of the token
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

        totemData[lastId++] = TotemData({
            creator: msg.sender,
            totemTokenAddr: address(totemToken),
            totemAddr: address(proxy),
            dataHash: _dataHash,
            isCustomToken: false
        });

        // register the totem and make initial tokens distribution
        totemDistributor.register();

        emit TotemCreated(address(proxy), address(totemToken), lastId - 1);
    }

    /**
     * @dev Creates a new totem with an existing whitelisted token
     * @param _dataHash The hash of the totem data
     * @param _tokenAddr The address of the existing token
     */
    function createTotemWithExistingToken(
        bytes memory _dataHash,
        address _tokenAddr,
        address[] memory _collaborators
    ) public whenNotPaused {
        if (_dataHash.length == 0) {
            revert InvalidTotemParameters("Empty dataHash");
        }

        // Collect fee in ASTR tokens
        _collectFee(msg.sender);

        if (!hasRole(WHITELISTED, _tokenAddr))
            revert NotWhitelisted(_tokenAddr);

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

        totemData[lastId++] = TotemData({
            creator: msg.sender,
            totemTokenAddr: _tokenAddr,
            totemAddr: address(proxy),
            dataHash: _dataHash,
            isCustomToken: true
        });

        MeritManager(meritManagerAddr).register(address(proxy));

        emit TotemWithExistingTokenCreated(
            address(proxy),
            _tokenAddr,
            lastId - 1
        );
    }

    /// ADMIN LOGIC

    /**
     * @dev Updates the creation fee
     * @param _newFee The new fee amount
     */
    function setCreationFee(uint256 _newFee) public onlyRole(MANAGER) {
        uint256 oldFee = creationFee;
        creationFee = _newFee;
        emit CreationFeeUpdated(oldFee, _newFee);
    }

    /**
     * @dev Updates the fee token address
     * @param _newFeeToken The address of the new fee token
     */
    function setFeeToken(address _newFeeToken) public onlyRole(MANAGER) {
        if (_newFeeToken == address(0)) revert ZeroAddress();

        address oldToken = feeTokenAddr;
        feeTokenAddr = _newFeeToken;
        emit FeeTokenUpdated(oldToken, _newFeeToken);
    }

    /**
     * @dev Adds multiple tokens to the whitelist
     * @param _tokens Array of token addresses to whitelist
     */
    function batchAddToWhitelist(address[] calldata _tokens) external onlyRole(MANAGER) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!hasRole(WHITELISTED, _tokens[i])) {
                grantRole(WHITELISTED, _tokens[i]);
            }
        }
        
        emit BatchWhitelistUpdated(_tokens, true);
    }

    /**
     * @dev Removes multiple tokens from the whitelist
     * @param _tokens Array of token addresses to remove from whitelist
     */
    function batchRemoveFromWhitelist(address[] calldata _tokens) external onlyRole(MANAGER) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (hasRole(WHITELISTED, _tokens[i])) {
                revokeRole(WHITELISTED, _tokens[i]);
            }
        }
        
        emit BatchWhitelistUpdated(_tokens, false);
    }

    /**
     * @dev Adds a single token to the whitelist
     * @param _token The token address to whitelist
     */
    function addTokenToWhitelist(address _token) public onlyRole(MANAGER) {
        if (hasRole(WHITELISTED, _token)) revert AlreadyWhitelisted(_token);
        grantRole(WHITELISTED, _token);
        
        address[] memory tokens = new address[](1);
        tokens[0] = _token;
        emit BatchWhitelistUpdated(tokens, true);
    }

    /**
     * @dev Removes a single token from the whitelist
     * @param _token The token address to remove from whitelist
     */
    function removeTokenFromWhitelist(address _token) public onlyRole(MANAGER) {
        if (!hasRole(WHITELISTED, _token)) revert NotWhitelisted(_token);
        revokeRole(WHITELISTED, _token);
        
        address[] memory tokens = new address[](1);
        tokens[0] = _token;
        emit BatchWhitelistUpdated(tokens, false);
    }

    function pause() public onlyRole(MANAGER) {
        _pause();
    }

    function unpause() public onlyRole(MANAGER) {
        _unpause();
    }

    /// READERS

    /**
     * @dev Gets the current creation fee
     * @return The current fee amount in fee tokens
     */
    function getCreationFee() external view returns (uint256) {
        return creationFee;
    }

    /**
     * @dev Gets the current fee token address
     * @return The address of the current fee token
     */
    function getFeeToken() external view returns (address) {
        return feeTokenAddr;
    }

    /**
     * @dev Gets the last assigned totem ID
     * @return The last totem ID
     */
    function getLastId() external view returns (uint256) {
        return lastId;
    }

    /**
     * @dev Gets data for a specific totem
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
}
