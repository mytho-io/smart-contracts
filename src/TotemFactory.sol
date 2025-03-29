// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {Totem} from "./Totem.sol";
import {TotemToken} from "./TotemToken.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";

contract TotemFactory is AccessControlUpgradeable {
    // Totem token distributor instance
    TotemTokenDistributor private totemDistributor;

    // Core contract addresses
    address private beaconAddr;
    address private treasuryAddr;
    address private meritManagerAddr;
    address private registryAddr;
    
    // ASTR token address
    address private astrTokenAddr;
    
    // Fee settings
    uint256 private creationFee;

    uint256 private lastId;

    mapping(uint256 totemId => TotemData data) private totemData;

    struct TotemData {
        address creator;
        address tokenAddr;
        address totemAddr;
        bytes dataHash;
        bool isCustomToken;
    }

    bytes32 private constant MANAGER = keccak256("MANAGER");
    bytes32 private constant WHITELISTED = keccak256("WHITELISTED");

    event TotemCreated(address totemAddr, address totemTokenAddr, uint256 totemId);
    event TotemWithExistingTokenCreated(
        address totemAddr,
        address totemTokenAddr,
        uint256 totemId
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    error AlreadyWhitelisted(address tokenAddr);
    error NotWhitelisted(address tokenAddr);
    error InsufficientFee(uint256 provided, uint256 required);
    error FeeTransferFailed();
    error ZeroAddress();

    function initialize(
        address _registryAddr,
        address _beaconAddr,
        address _astrTokenAddr
    ) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        // Initialize fee settings
        if (_astrTokenAddr == address(0)) revert ZeroAddress();
        if (_registryAddr == address(0)) revert ZeroAddress();

        totemDistributor = TotemTokenDistributor(AddressRegistry(_registryAddr).getTotemTokenDistributor());
        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();
        meritManagerAddr = AddressRegistry(_registryAddr).getMeritManager();
        beaconAddr = _beaconAddr;
        registryAddr = _registryAddr;
        
        astrTokenAddr = _astrTokenAddr;
        creationFee = 1 ether;
    }

    /**
     * @dev Collects creation fee from the sender
     * @param _sender The address paying the fee
     */
    function _collectFee(address _sender) private {
        // Skip fee collection if fee is set to zero
        if (creationFee == 0) return;
        
        // Transfer tokens from sender to fee collector
        bool success = IERC20(astrTokenAddr).transferFrom(_sender, treasuryAddr, creationFee);
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
        string memory _tokenSymbol
    ) public {
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
                "initialize(address,bytes,address,bool)",
                address(totemToken),
                _dataHash,
                registryAddr,
                false
            )
        );

        totemData[lastId++] = TotemData({
            creator: msg.sender,
            tokenAddr: address(totemToken),
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
        address _tokenAddr
    ) public {
        // Collect fee in ASTR tokens
        _collectFee(msg.sender);

        if (!hasRole(WHITELISTED, _tokenAddr))
            revert NotWhitelisted(_tokenAddr);

        BeaconProxy proxy = new BeaconProxy(
            beaconAddr,
            abi.encodeWithSignature(
                "initialize(address,bytes,address,bool)",
                _tokenAddr,
                _dataHash,
                registryAddr,
                true
            )
        );

        totemData[lastId++] = TotemData({
            creator: msg.sender,
            tokenAddr: _tokenAddr,
            totemAddr: address(proxy),
            dataHash: _dataHash,
            isCustomToken: true
        });

        MeritManager(meritManagerAddr).register(address(proxy)); 

        emit TotemWithExistingTokenCreated(address(proxy), _tokenAddr, lastId - 1);
    }

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
     * @dev Adds a token to the whitelist
     * @param _token The token address to whitelist
     */
    function addTokenToWhitelist(address _token) public onlyRole(MANAGER) {
        if (hasRole(WHITELISTED, _token)) revert AlreadyWhitelisted(_token);
        grantRole(WHITELISTED, _token);
    }

    /**
     * @dev Removes a token from the whitelist
     * @param _token The token address to remove from whitelist
     */
    function removeTokenFromWhitelist(address _token) public onlyRole(MANAGER) {
        if (!hasRole(WHITELISTED, _token)) revert NotWhitelisted(_token);
        revokeRole(WHITELISTED, _token);
    }

    /// READERS

    /**
     * @dev Gets the current creation fee
     * @return The current fee amount in ASTR tokens
     */
    function getCreationFee() external view returns (uint256) {
        return creationFee;
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
        return totemData[_totemId];
    }
}