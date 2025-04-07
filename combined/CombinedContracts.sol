
// --- src/MeritManager.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {AddressRegistry} from "./AddressRegistry.sol";

/**
 * @title MeritManager
 * @dev Manages merit points for registered totems and distributes MYTHO tokens based on merit.
 * Includes features like totem registration, merit crediting, boosting, and claiming rewards.
 */
contract MeritManager is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;    
    using Address for address payable;

    // State variables
    address public mythoToken;
    address public treasuryAddr;
    address[4] public vestingWallets;
    uint256[4] public vestingWalletsAllocation;
    uint256 public boostFee; // Fee in native tokens for boosting
    uint256 public periodDuration;
    uint256 public deploymentTimestamp;
    uint256 public oneTotemBoost; // Amount of merit points awarded for a boost
    uint256 public mythumMultiplier; // Multiplier for merit during Mythum period (default: 150 = 1.5x)

    mapping(uint256 period => uint256 totalPoints) public totalMeritPoints; // Total merit points across all totems per period
    mapping(uint256 period => mapping(address totemAddress => uint256 points))
        public totemMerit; // Total merit points across all totems per period
    mapping(uint256 period => mapping(address totemAddr => bool claimed)) public isClaimed; // Whether rewards have been claimed for a period by a specific totem
    mapping(uint256 period => uint256 releasedMytho) public releasedMytho; // Total MYTHO released per period

    // Period tracking
    uint256 public lastProcessedPeriod; // Last period that was fully processed

    // Array to track all registered totems
    address[] public registeredTotemsList;

    // Boost tracking
    mapping(uint256 => mapping(address => bool)) public userBoostedInPeriod; // Whether a user has boosted in a period
    mapping(uint256 => mapping(address => address)) public userBoostedTotem; // Which Totem a user boosted in a period

    // Totem state tracking
    mapping(address => bool) public registeredTotems;

    // Roles
    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant REGISTRATOR = keccak256("REGISTRATOR");
    bytes32 public constant BLACKLISTED = keccak256("BLACKLISTED");

    // Events
    event TotemRegistered(address indexed totem);
    event TotemBlacklisted(address indexed totem, bool blacklisted);
    event MeritCredited(address indexed totem, uint256 amount, uint256 period);
    event TotemBoosted(
        address indexed totem,
        address indexed booster,
        uint256 amount,
        uint256 period
    );
    event MythoClaimed(address indexed totem, uint256 amount, uint256 period);
    event MythoReleased(uint256 amount, uint256 period);
    event ParameterUpdated(string parameterName, uint256 newValue);

    // Custom errors
    error TotemNotRegistered();
    error TotemInBlocklist();
    error TotemAlreadyRegistered();
    error AlreadyBlacklisted(address totem);
    error AlreadyNotInBlacklist(address totem);
    error InsufficientBoostFee();
    error NotInMythumPeriod();
    error AlreadyBoostedInPeriod();
    error AccessControl();
    error NoMythoToClaim();
    error AlreadyClaimed(uint256 period);
    error InvalidPeriod();
    error TransferFailed();
    error InvalidAddress();

    /**
     * @dev Initializes the contract with required parameters
     * @param _registryAddr Address of the AddressRegistry contract
     * @param _vestingWallets Array of vesting wallet addresses
     */
    function initialize(
        address _registryAddr,
        address[4] memory _vestingWallets
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        mythoToken = AddressRegistry(_registryAddr).getMythoToken();
        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();

        vestingWallets = _vestingWallets;
        periodDuration = 30 days;
        deploymentTimestamp = block.timestamp;
        vestingWalletsAllocation = [
            175_000_000 ether,
            125_000_000 ether,
            100_000_000 ether,
            50_000_000 ether
        ];

        oneTotemBoost = 10; // 10 merit points per boost
        mythumMultiplier = 150; // 1.5x multiplier (150/100)
        boostFee = 0.001 ether; // 0.001 native tokens for boost fee
    }

    /**
     * @dev Registers a new totem
     * @param _totemAddr Address of the totem to register
     */
    function register(address _totemAddr) external {
        if (!hasRole(REGISTRATOR, msg.sender)) revert AccessControl();
        if (registeredTotems[_totemAddr]) revert TotemAlreadyRegistered();
        if (_totemAddr == address(0)) revert InvalidAddress();

        registeredTotems[_totemAddr] = true;
        registeredTotemsList.push(_totemAddr);

        emit TotemRegistered(_totemAddr);
    }

    /**
     * @dev Credits merit points to a registered totem
     * @param _totemAddr Address of the totem to credit
     * @param _amount Amount of merit points to credit
     */
    function creditMerit(
        address _totemAddr,
        uint256 _amount
    ) external onlyRole(MANAGER) {
        if (!registeredTotems[_totemAddr]) revert TotemNotRegistered();
        if (hasRole(BLACKLISTED, _totemAddr)) revert TotemInBlocklist();

        uint256 currentPeriod_ = currentPeriod();

        // Apply Mythum multiplier if in Mythum period
        if (isMythum()) {
            _amount = (_amount * mythumMultiplier) / 100;
        }

        // Add merit to the totem
        totemMerit[currentPeriod_][_totemAddr] += _amount;
        totalMeritPoints[currentPeriod_] += _amount;

        emit MeritCredited(_totemAddr, _amount, currentPeriod_);
    }

    /**
     * @dev Allows a user to boost a totem by paying a fee
     * @param _totemAddr Address of the totem to boost
     */
    function boostTotem(address _totemAddr) external payable nonReentrant {
        if (!registeredTotems[_totemAddr]) revert TotemNotRegistered();
        if (hasRole(BLACKLISTED, _totemAddr)) revert TotemInBlocklist();
        if (msg.value < boostFee) revert InsufficientBoostFee();
        if (!isMythum()) revert NotInMythumPeriod();

        uint256 currentPeriod_ = currentPeriod();

        if (userBoostedInPeriod[currentPeriod_][msg.sender])
            revert AlreadyBoostedInPeriod();

        if (msg.value > boostFee) {
            // Refund excess boost fee
            payable(msg.sender).sendValue(msg.value - boostFee);
        }

        // Transfer boost fee to revenue pool
        payable(treasuryAddr).sendValue(boostFee);

        // Mark user as having boosted in this period
        userBoostedInPeriod[currentPeriod_][msg.sender] = true;
        userBoostedTotem[currentPeriod_][msg.sender] = _totemAddr;

        // Add merit to the totem
        totemMerit[currentPeriod_][_totemAddr] += oneTotemBoost;
        totalMeritPoints[currentPeriod_] += oneTotemBoost;

        emit TotemBoosted(
            _totemAddr,
            msg.sender,
            oneTotemBoost,
            currentPeriod_
        );
    }

    /**
     * @dev Allows a totem to claim MYTHO tokens for a specific period
     * @param _periodNum Period number to claim for
     */
    function claimMytho(uint256 _periodNum) external nonReentrant {
        address totemAddr = msg.sender;
        if (!registeredTotems[totemAddr]) revert TotemNotRegistered();
        if (hasRole(BLACKLISTED, totemAddr)) revert TotemInBlocklist();
        if (isClaimed[_periodNum][totemAddr]) revert AlreadyClaimed(_periodNum);
        if (_periodNum > currentPeriod()) revert InvalidPeriod();

        _updateState();

        if (
            totemMerit[_periodNum][totemAddr] == 0 ||
            totalMeritPoints[_periodNum] == 0 ||
            releasedMytho[_periodNum] == 0
        ) revert NoMythoToClaim();

        uint256 totalPoints = totalMeritPoints[_periodNum];
        uint256 totemPoints = totemMerit[_periodNum][totemAddr];

        isClaimed[_periodNum][totemAddr] = true;

        uint256 totemShare = (releasedMytho[_periodNum] * totemPoints) /
            totalPoints;

        IERC20(mythoToken).safeTransfer(totemAddr, totemShare);

        emit MythoClaimed(totemAddr, totemShare, _periodNum);
    }

    /**
     * @dev Updates the state of the contract by processing pending periods
     */
    function _updateState() private {
        uint256 yearIdx = _yearIndex();

        // Check if we're still within the valid year range
        if (yearIdx >= 4) {
            return;
        }

        VestingWallet wallet = VestingWallet(payable(vestingWallets[yearIdx]));

        uint256 _currentPeriod = currentPeriod();

        // Only process completed periods, not the current period
        if (_currentPeriod > lastProcessedPeriod) {
            // Process all completed periods up to but not including the current period
            for (
                uint256 period = lastProcessedPeriod;
                period < _currentPeriod;
                period++
            ) {
                releasedMytho[period] = vestingWalletsAllocation[yearIdx] / 12;
                emit MythoReleased(releasedMytho[period], period);
            }

            wallet.release(address(mythoToken));
            lastProcessedPeriod = _currentPeriod; // Set the last processed period to the previous period
        }
    }

    /**
     * @dev Manually triggers state update
     */
    function updateState() external onlyRole(MANAGER) {
        _updateState();
    }

    // VIEW FUNCTIONS

    /**
     * @dev Returns the current period number
     * @return Current period number
     */
    function currentPeriod() public view returns (uint256) {
        if (block.timestamp < deploymentTimestamp) return 0;
        return (block.timestamp - deploymentTimestamp) / periodDuration;
    }

    /**
     * @dev Checks if the current time is within the Mythum period
     * @return Whether current time is in Mythum period
     */
    function isMythum() public view returns (bool) {
        uint256 currentPeriodStart = deploymentTimestamp +
            (currentPeriod() * periodDuration);
        uint256 mythumStart = currentPeriodStart + ((periodDuration * 3) / 4);
        return block.timestamp >= mythumStart;
    }

    /**
     * @dev Returns the year index based on the current period
     * @return Year index (0-3)
     */
    function _yearIndex() private view returns (uint256) {
        return (currentPeriod() / 12) > 3 ? 3 : (currentPeriod() / 12);
    }

    /**
     * @dev Gets the total number of registered totems
     * @return Total number of registered totems
     */
    function getRegisteredTotemsCount() external view returns (uint256) {
        return registeredTotemsList.length;
    }

    /**
     * @dev Gets all registered totems
     * @return Array of registered totem addresses
     */
    function getAllRegisteredTotems() external view returns (address[] memory) {
        return registeredTotemsList;
    }

    /**
     * @dev Gets the pending MYTHO reward for a totem in a specific period
     * @param _totemAddr Address of the totem
     * @param _periodNum Period number to check
     * @return Pending MYTHO reward amount
     */
    function getPendingReward(
        address _totemAddr,
        uint256 _periodNum
    ) external view returns (uint256) {
        if (
            !registeredTotems[_totemAddr] ||
            hasRole(BLACKLISTED, _totemAddr) ||
            isClaimed[_periodNum][_totemAddr] ||
            totemMerit[_periodNum][_totemAddr] == 0 ||
            totalMeritPoints[_periodNum] == 0 ||
            releasedMytho[_periodNum] == 0
        ) {
            return 0;
        }

        uint256 totemPoints = totemMerit[_periodNum][_totemAddr];
        uint256 totalPoints = totalMeritPoints[_periodNum];

        return (releasedMytho[_periodNum] * totemPoints) / totalPoints;
    }

    /**
     * @dev Gets the period time bounds
     * @param _periodNum Period number to check
     * @return startTime Period start timestamp
     * @return endTime Period end timestamp
     */
    function getPeriodTimeBounds(
        uint256 _periodNum
    ) external view returns (uint256 startTime, uint256 endTime) {
        startTime = deploymentTimestamp + (_periodNum * periodDuration);
        endTime = startTime + periodDuration;
        return (startTime, endTime);
    }

    /**
     * @dev Gets the time remaining until the next period
     * @return Time in seconds until the next period
     */
    function getTimeUntilNextPeriod() external view returns (uint256) {
        uint256 currentPeriodEnd = deploymentTimestamp +
            ((currentPeriod() + 1) * periodDuration);
        if (block.timestamp >= currentPeriodEnd) {
            return 0;
        }
        return currentPeriodEnd - block.timestamp;
    }

    /**
     * @dev Gets the timestamp when the current Mythum period starts
     * @return Timestamp of the current Mythum period start
     */
    function getCurrentMythumStart() external view returns (uint256) {
        uint256 currentPeriodStart = deploymentTimestamp +
            (currentPeriod() * periodDuration);
        return currentPeriodStart + ((periodDuration * 3) / 4);
    }

    /**
     * @dev Checks if a totem has been registered
     * @param _totemAddr Address to check
     * @return Whether the address is a registered totem
     */
    function isRegisteredTotem(
        address _totemAddr
    ) external view returns (bool) {
        return registeredTotems[_totemAddr];
    }

    /**
     * @dev Checks if a totem is blacklisted
     * @param _totemAddr Address to check
     * @return Whether the totem is blacklisted
     */
    function isBlacklisted(address _totemAddr) external view returns (bool) {
        return hasRole(BLACKLISTED, _totemAddr);
    }

    /**
     * @dev Gets the total merit points for a totem in a specific period
     * @param _totemAddr Address of the totem
     * @param _periodNum Period number to check
     * @return Merit points for the totem in the specified period
     */
    function getTotemMeritPoints(
        address _totemAddr,
        uint256 _periodNum
    ) external view returns (uint256) {
        return totemMerit[_periodNum][_totemAddr];
    }

    /**
     * @dev Gets whether a user has boosted in a specific period
     * @param _user User address to check
     * @param _periodNum Period number to check
     * @return Whether the user has boosted in the specified period
     */
    function hasUserBoostedInPeriod(
        address _user,
        uint256 _periodNum
    ) external view returns (bool) {
        return userBoostedInPeriod[_periodNum][_user];
    }

    /**
     * @dev Gets which totem a user boosted in a specific period
     * @param _user User address to check
     * @param _periodNum Period number to check
     * @return Address of the totem the user boosted
     */
    function getUserBoostedTotem(
        address _user,
        uint256 _periodNum
    ) external view returns (address) {
        return userBoostedTotem[_periodNum][_user];
    }

    // ADMIN FUNCTIONS

    /**
     * @dev Sets the one Totem boost amount
     * @param _oneTotemBoost New boost amount
     */
    function setOneTotemBoost(
        uint256 _oneTotemBoost
    ) external onlyRole(MANAGER) {
        oneTotemBoost = _oneTotemBoost;
        emit ParameterUpdated("oneTotemBoost", _oneTotemBoost);
    }

    /**
     * @dev Sets the Mythum multiplier (in percentage, e.g., 150 = 1.5x)
     * @param _mythumMultiplier New multiplier value
     */
    function setMythmsMultiplier(
        uint256 _mythumMultiplier
    ) external onlyRole(MANAGER) {
        mythumMultiplier = _mythumMultiplier;
        emit ParameterUpdated("mythumMultiplier", _mythumMultiplier);
    }

    /**
     * @dev Sets the boost fee in native tokens
     * @param _boostFee New boost fee
     */
    function setBoostFee(uint256 _boostFee) external onlyRole(MANAGER) {
        boostFee = _boostFee;
        emit ParameterUpdated("boostFee", _boostFee);
    }

    /**
     * @dev Sets the blacklist status for a totem
     * @param _totem Address of the totem
     * @param _blacklisted Whether to blacklist or unblacklist the totem
     */
    function setTotemBlacklisted(
        address _totem,
        bool _blacklisted
    ) external onlyRole(MANAGER) {
        if (!registeredTotems[_totem]) revert TotemNotRegistered();
        if (hasRole(BLACKLISTED, _totem) && _blacklisted)
            revert AlreadyBlacklisted(_totem);
        if (!hasRole(BLACKLISTED, _totem) && !_blacklisted)
            revert AlreadyNotInBlacklist(_totem);

        if (_blacklisted) {
            grantRole(BLACKLISTED, _totem);
        } else {
            revokeRole(BLACKLISTED, _totem);
        }

        emit TotemBlacklisted(_totem, _blacklisted);
    }

    /**
     * @dev Sets the period duration
     * @param _periodDuration New period duration in seconds
     */
    function setPeriodDuration(
        uint256 _periodDuration
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        periodDuration = _periodDuration;
        emit ParameterUpdated("periodDuration", _periodDuration);
    }

    /**
     * @dev Grants the registrator role to an address
     * @param _registrator Address to grant the role to
     */
    function grantRegistratorRole(
        address _registrator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(REGISTRATOR, _registrator);
    }

    /**
     * @dev Revokes the registrator role from an address
     * @param _registrator Address to revoke the role from
     */
    function revokeRegistratorRole(
        address _registrator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(REGISTRATOR, _registrator);
    }

    /**
     * @dev Updates a vesting wallet address
     * @param _index Index of the wallet to update (0-3)
     * @param _newWallet New wallet address
     */
    function setVestingWallet(
        uint256 _index,
        address _newWallet
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_index >= 4) revert InvalidPeriod();
        if (_newWallet == address(0)) revert InvalidAddress();

        vestingWallets[_index] = _newWallet;
    }

    /**
     * @dev Updates a vesting wallet allocation
     * @param _index Index of the allocation to update (0-3)
     * @param _newAllocation New allocation amount
     */
    function setVestingWalletAllocation(
        uint256 _index,
        uint256 _newAllocation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_index >= 4) revert InvalidPeriod();

        vestingWalletsAllocation[_index] = _newAllocation;
    }

    /**
     * @dev Force update of released MYTHO for a specific period
     * @param _periodNum Period number to update
     * @param _amount Amount of MYTHO released
     */
    function forceUpdateReleasedMytho(
        uint256 _periodNum,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        releasedMytho[_periodNum] = _amount;
        emit MythoReleased(_amount, _periodNum);
    }
}

// --- src/TotemFactory.sol ---
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
        string memory _tokenSymbol
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
                new address[](0)
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
        address _tokenAddr
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
                new address[](0)
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

// --- src/TotemTokenDistributor.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TotemFactory} from "./TotemFactory.sol";
import {TotemToken} from "./TotemToken.sol";
import {Totem} from "./Totem.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/**
 * @title TotemTokenDistributor
 * @dev This contract manages the distribution of Totem tokens during and after sales periods.
 * It handles:
 * - Registration of new totems from the TotemFactory
 * - Buying and selling totems during the sales period
 * - Distribution of collected payment tokens after the sales period ends
 * - Adding liquidity to AMM pools
 * - Burning totem tokens
 */

contract TotemTokenDistributor is AccessControlUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    TotemFactory private factory;
    MeritManager private meritManager;
    IERC20 private mytho;

    uint256 public maxTokensPerAddress;
    uint256 private oneTotemPriceInUsd;

    // Maximum age of price feed data before it's considered stale (1 hour)
    uint256 public constant PRICE_FEED_STALE_THRESHOLD = 1 hours;

    // contract address for revenue in payment tokens
    address private treasuryAddr;

    // address of payment token
    address private paymentTokenAddr;

    // Uniswap V2 router address
    address private uniswapV2RouterAddr;

    // Mapping from token address to Chainlink price feed address
    mapping(address => address) private priceFeedAddresses;

    /// @dev General info about totems
    mapping(address totemTokenAddr => TotemData TotemData) private totems;

    /// @dev Number of sale positions are eq to the used paymentTokens by address
    mapping(address userAddress => mapping(address totemTokenAddr => SalePosInToken))
        private salePositions;

    bytes32 private constant MANAGER = keccak256("MANAGER");

    // Default percentage shares for distribution - can be made configurable
    uint256 public revenuePaymentTokenShare;
    uint256 public totemCreatorPaymentTokenShare;
    uint256 public poolPaymentTokenShare;
    uint256 public vaultPaymentTokenShare;
    uint256 private constant PRECISION = 10000;
    uint256 private constant POOL_INITIAL_SUPPLY = 200_000_000 ether;

    struct TotemData {
        address totemAddr;
        address creator;
        address paymentToken;
        bool registered;
        bool isSalePeriod;
        uint256 collectedPaymentTokens;
    }

    struct SalePosInToken {
        // Payment tokens which spent on totems
        uint256 paymentTokenAmount;
        // Totem tokens which bought for payment tokens
        uint256 totemTokenAmount;
    }

    // Events
    event TotemTokensBought(
        address buyer,
        address paymentTokenAddr,
        address totemTokenAddr,
        uint256 totemTokenAmount,
        uint256 paymentTokenAmount
    );
    event TotemTokensSold(
        address buyer,
        address paymentTokenAddr,
        address totemTokenAddr,
        uint256 totemTokenAmount,
        uint256 paymentTokenAmount
    );
    event TotemRegistered(
        address totemAddr,
        address creator,
        address totemTokenAddr
    );
    event SalePeriodClosed(address totemTokenAddr, uint256 totalCollected);
    event LiquidityAdded(
        address totemTokenAddr,
        address paymentTokenAddr,
        uint256 totemAmount,
        uint256 paymentAmount,
        uint256 liquidity
    );
    event TokenDistributionSharesUpdated(
        uint256 revenueShare,
        uint256 creatorShare,
        uint256 poolShare,
        uint256 vaultShare
    );
    event PriceFeedSet(address tokenAddr, address priceFeedAddr);

    // Custom errors
    error AlreadyRegistered(address totemTokenAddr);
    error NotAllowedForCustomTokens();
    error UnknownTotemToken(address tokenAddr);
    error WrongAmount(uint256 tokenAmount);
    error NotPaymentToken(address tokenAddr);
    error OnlyInSalePeriod();
    error SalePeriodAlreadyEnded();
    error WrongPaymentTokenAmount(uint256 paymentTokenAmount);
    error OnlyForTotem();
    error AlreadySet();
    error OnlyFactory();
    error ZeroAddress();
    error InvalidShares();
    error NoPriceFeedSet(address tokenAddr);
    error InvalidPrice(address tokenAddr);
    error StalePrice(address tokenAddr);
    error LiquidityAdditionFailed();
    error UniswapRouterNotSet();

    function initialize(address _registryAddr) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        if (_registryAddr == address(0)) revert ZeroAddress();

        AddressRegistry registry = AddressRegistry(_registryAddr);
        mytho = IERC20(registry.getMythoToken());
        treasuryAddr = registry.getMythoTreasury();
        meritManager = MeritManager(registry.getMeritManager());

        maxTokensPerAddress = 5_000_000 ether;
        oneTotemPriceInUsd = 0.00004 ether;

        // Initialize distribution shares
        revenuePaymentTokenShare = 250; // 2.5%
        totemCreatorPaymentTokenShare = 50; // 0.5%
        poolPaymentTokenShare = 2857; // 28.57%
        vaultPaymentTokenShare = 6843; // 68.43%
    }

    /// @notice Being called by TotemFactory during totem creation
    function register() external {
        if (address(factory) == address(0)) revert AlreadySet();
        if (msg.sender != address(factory)) revert OnlyFactory();

        // get info about the totem being created
        TotemFactory.TotemData memory totemDataFromFactory = factory
            .getTotemData(factory.getLastId() - 1);

        if (totemDataFromFactory.isCustomToken)
            revert NotAllowedForCustomTokens();
        if (totems[totemDataFromFactory.totemTokenAddr].registered)
            revert AlreadyRegistered(totemDataFromFactory.totemTokenAddr);
        if (paymentTokenAddr == address(0)) revert ZeroAddress();

        totems[totemDataFromFactory.totemTokenAddr] = TotemData(
            totemDataFromFactory.totemAddr,
            totemDataFromFactory.creator,
            paymentTokenAddr,
            true,
            true,
            0
        );

        TotemToken token = TotemToken(totemDataFromFactory.totemTokenAddr);
        token.transfer(totemDataFromFactory.creator, 250_000 ether);
        token.transfer(totemDataFromFactory.totemAddr, 100_000_000 ether);

        emit TotemRegistered(
            totemDataFromFactory.totemAddr,
            totemDataFromFactory.creator,
            totemDataFromFactory.totemTokenAddr
        );
    }

    /// @notice Buy totems for allowed payment tokens
    function buy(address _totemTokenAddr, uint256 _totemTokenAmount) external {
        if (!totems[_totemTokenAddr].registered)
            revert UnknownTotemToken(_totemTokenAddr);
        if (!totems[_totemTokenAddr].isSalePeriod)
            revert SalePeriodAlreadyEnded();
        if (
            // check if contract has enough totem tokens + initial pool supply
            IERC20(_totemTokenAddr).balanceOf(address(this)) <
            _totemTokenAmount + POOL_INITIAL_SUPPLY ||
            // check if user has no more than maxTokensPerAddress
            IERC20(_totemTokenAddr).balanceOf(msg.sender) + _totemTokenAmount >
            maxTokensPerAddress ||
            _totemTokenAmount == 0
        ) revert WrongAmount(_totemTokenAmount);

        if (paymentTokenAddr == address(0)) revert ZeroAddress();

        uint256 paymentTokenAmount = totemsToPaymentToken(
            paymentTokenAddr,
            _totemTokenAmount
        );

        // check if user has enough payment tokens
        if (IERC20(paymentTokenAddr).balanceOf(msg.sender) < paymentTokenAmount)
            revert WrongPaymentTokenAmount(paymentTokenAmount);

        // update totems payment token amount
        totems[_totemTokenAddr].collectedPaymentTokens += paymentTokenAmount;

        // update user sale position
        SalePosInToken storage position = salePositions[msg.sender][
            _totemTokenAddr
        ];
        position.paymentTokenAmount += paymentTokenAmount;
        position.totemTokenAmount += _totemTokenAmount;

        // Transfer tokens using SafeERC20
        IERC20(paymentTokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            paymentTokenAmount
        );
        IERC20(_totemTokenAddr).safeTransfer(msg.sender, _totemTokenAmount);

        emit TotemTokensBought(
            msg.sender,
            paymentTokenAddr,
            _totemTokenAddr,
            _totemTokenAmount,
            paymentTokenAmount
        );

        // close sale period when the remaining tokens are exactly what's needed for the pool
        if (
            IERC20(_totemTokenAddr).balanceOf(address(this)) ==
            POOL_INITIAL_SUPPLY
        ) {
            _closeSalePeriod(_totemTokenAddr);
        }
    }

    /// @notice Sell totems for used payment token in sale period
    function sell(address _totemTokenAddr, uint256 _totemTokenAmount) external {
        if (!totems[_totemTokenAddr].registered)
            revert UnknownTotemToken(_totemTokenAddr);
        if (!totems[_totemTokenAddr].isSalePeriod)
            revert SalePeriodAlreadyEnded();

        SalePosInToken storage position = salePositions[msg.sender][
            _totemTokenAddr
        ];
        address _paymentTokenAddr = totems[_totemTokenAddr].paymentToken;

        // check if balances are correct
        if (
            _totemTokenAmount > position.totemTokenAmount ||
            _totemTokenAmount > IERC20(_totemTokenAddr).balanceOf(msg.sender) ||
            _totemTokenAmount == 0
        ) revert WrongAmount(_totemTokenAmount);

        // calculate the right number of payment tokens according to _totemTokenAmount share in sale position
        uint256 paymentTokensBack = (position.paymentTokenAmount *
            _totemTokenAmount) / position.totemTokenAmount;

        // update totems payment token amount
        totems[_totemTokenAddr].collectedPaymentTokens -= paymentTokensBack;

        // update user sale position
        position.totemTokenAmount -= _totemTokenAmount;
        position.paymentTokenAmount -= paymentTokensBack;

        // send payment tokens and take totem tokens using SafeERC20
        IERC20(_totemTokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            _totemTokenAmount
        );
        IERC20(_paymentTokenAddr).safeTransfer(msg.sender, paymentTokensBack);

        emit TotemTokensSold(
            msg.sender,
            _paymentTokenAddr,
            _totemTokenAddr,
            _totemTokenAmount,
            paymentTokensBack
        );
    }

    /// INTERNAL LOGIC

    function _closeSalePeriod(address _totemTokenAddr) internal {
        // close sale period and open burn functionality for totem token
        totems[_totemTokenAddr].isSalePeriod = false;

        // open transfers for totem token
        TotemToken(_totemTokenAddr).openTransfers();

        // register totem in MeritManager and activate merit distribution for it
        meritManager.register(totems[_totemTokenAddr].totemAddr);

        // distribute collected payment tokens
        uint256 paymentTokenAmount = totems[_totemTokenAddr]
            .collectedPaymentTokens;
        address _paymentTokenAddr = totems[_totemTokenAddr].paymentToken;

        // calculate revenue share
        uint256 revenueShare = (paymentTokenAmount * revenuePaymentTokenShare) /
            PRECISION;
        IERC20(_paymentTokenAddr).safeTransfer(treasuryAddr, revenueShare);

        // calculate totem creator share
        uint256 creatorShare = (paymentTokenAmount *
            totemCreatorPaymentTokenShare) / PRECISION;
        IERC20(_paymentTokenAddr).safeTransfer(
            totems[_totemTokenAddr].creator,
            creatorShare
        );

        // calculate totem vault share
        uint256 vaultShare = (paymentTokenAmount * vaultPaymentTokenShare) /
            PRECISION;
        IERC20(_paymentTokenAddr).safeTransfer(
            totems[_totemTokenAddr].totemAddr,
            vaultShare
        );

        // calculate totem pool share
        uint256 poolShare = (paymentTokenAmount * poolPaymentTokenShare) /
            PRECISION;

        // send liquidity to AMM and relay LP tokens to Totem
        (uint256 liquidity, address liquidityToken) = _addLiquidity(
            _totemTokenAddr,
            _paymentTokenAddr,
            POOL_INITIAL_SUPPLY,
            poolShare
        );

        // set payment token for Totem and close sale period
        Totem(totems[_totemTokenAddr].totemAddr).closeSalePeriod(
            IERC20(_paymentTokenAddr),
            IERC20(liquidityToken)
        );

        IERC20(liquidityToken).safeTransfer(
            totems[_totemTokenAddr].totemAddr,
            liquidity
        );

        emit SalePeriodClosed(_totemTokenAddr, paymentTokenAmount);
    }

    /**
     * @notice Adds liquidity to a Uniswap V2 pool
     * @dev Approves tokens for the router and adds liquidity to the pool
     * @param _totemTokenAddr Address of the totem token
     * @param _paymentTokenAddr Address of the payment token
     * @param _totemTokenAmount Amount of totem tokens to add to the pool
     * @param _paymentTokenAmount Amount of payment tokens to add to the pool
     * @return liquidity Amount of liquidity tokens received
     * @return liquidityToken Address of the liquidity token (pair)
     */
    function _addLiquidity(
        address _totemTokenAddr,
        address _paymentTokenAddr,
        uint256 _totemTokenAmount,
        uint256 _paymentTokenAmount
    ) internal returns (uint256 liquidity, address liquidityToken) {
        if (uniswapV2RouterAddr == address(0)) revert UniswapRouterNotSet();

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2RouterAddr);

        // Get the factory address
        address factoryAddr = router.factory();
        IUniswapV2Factory factory_ = IUniswapV2Factory(factoryAddr);

        // Get or create the pair
        liquidityToken = factory_.getPair(_totemTokenAddr, _paymentTokenAddr);
        if (liquidityToken == address(0)) {
            liquidityToken = factory_.createPair(
                _totemTokenAddr,
                _paymentTokenAddr
            );
        }

        // Approve tokens for the uni router
        IERC20(_totemTokenAddr).approve(uniswapV2RouterAddr, _totemTokenAmount);
        IERC20(_paymentTokenAddr).approve(
            uniswapV2RouterAddr,
            _paymentTokenAmount
        );

        // Add liquidity
        (, , liquidity) = router.addLiquidity(
            _totemTokenAddr,
            _paymentTokenAddr,
            _totemTokenAmount,
            _paymentTokenAmount,
            (_totemTokenAmount * 995) / 1000, // 0.5% slippage
            (_paymentTokenAmount * 995) / 1000, // 0.5% slippage
            address(this),
            block.timestamp + 600 // Deadline: 10 minutes from now
        );

        if (liquidity == 0) revert LiquidityAdditionFailed();

        emit LiquidityAdded(
            _totemTokenAddr,
            _paymentTokenAddr,
            _totemTokenAmount,
            _paymentTokenAmount,
            liquidity
        );

        return (liquidity, liquidityToken);
    }

    /// ADMIN LOGIC

    function setPaymentToken(
        address _paymentTokenAddr
    ) external onlyRole(MANAGER) {
        if (_paymentTokenAddr == address(0)) revert ZeroAddress();
        paymentTokenAddr = _paymentTokenAddr;
    }

    function setTotemFactory(address _registryAddr) external onlyRole(MANAGER) {
        if (address(factory) != address(0)) revert AlreadySet();
        if (_registryAddr == address(0)) revert ZeroAddress();
        factory = TotemFactory(
            AddressRegistry(_registryAddr).getTotemFactory()
        );
    }

    function setMaxTotemTokensPerAddress(
        uint256 _amount
    ) external onlyRole(MANAGER) {
        if (_amount == 0) revert WrongAmount(0);
        maxTokensPerAddress = _amount;
    }

    /**
     * @notice Sets the Uniswap V2 router address
     * @param _routerAddr Address of the Uniswap V2 router
     */
    function setUniswapV2Router(
        address _routerAddr
    ) external onlyRole(MANAGER) {
        if (_routerAddr == address(0)) revert ZeroAddress();
        uniswapV2RouterAddr = _routerAddr;
    }

    /**
     * @notice Sets the price feed address for a token
     * @param _tokenAddr Address of the token
     * @param _priceFeedAddr Address of the Chainlink price feed for the token/USD pair
     */
    function setPriceFeed(
        address _tokenAddr,
        address _priceFeedAddr
    ) external onlyRole(MANAGER) {
        if (_tokenAddr == address(0) || _priceFeedAddr == address(0))
            revert ZeroAddress();
        priceFeedAddresses[_tokenAddr] = _priceFeedAddr;
        emit PriceFeedSet(_tokenAddr, _priceFeedAddr);
    }

    /**
     * @notice Sets the distribution shares for payment tokens
     * @param _revenueShare Percentage going to treasury (multiplied by PRECISION)
     * @param _creatorShare Percentage going to totem creator (multiplied by PRECISION)
     * @param _poolShare Percentage going to liquidity pool (multiplied by PRECISION)
     * @param _vaultShare Percentage going to totem vault (multiplied by PRECISION)
     */
    function setDistributionShares(
        uint256 _revenueShare,
        uint256 _creatorShare,
        uint256 _poolShare,
        uint256 _vaultShare
    ) external onlyRole(MANAGER) {
        if (
            _revenueShare + _creatorShare + _poolShare + _vaultShare !=
            PRECISION
        ) revert InvalidShares();

        revenuePaymentTokenShare = _revenueShare;
        totemCreatorPaymentTokenShare = _creatorShare;
        poolPaymentTokenShare = _poolShare;
        vaultPaymentTokenShare = _vaultShare;

        emit TokenDistributionSharesUpdated(
            _revenueShare,
            _creatorShare,
            _poolShare,
            _vaultShare
        );
    }

    /**
     * @notice Sets the token price in USD
     * @param _priceInUsd New price in USD (18 decimals)
     */
    function setTotemPriceInUsd(
        uint256 _priceInUsd
    ) external onlyRole(MANAGER) {
        if (_priceInUsd == 0) revert WrongAmount(0);
        oneTotemPriceInUsd = _priceInUsd;
    }

    /// READERS

    /**
     * @notice Converts totem tokens to payment tokens based on price
     * @param _tokenAddr Address of the payment token
     * @param _totemsAmount Amount of totem tokens
     * @return Amount of payment tokens required
     */
    function totemsToPaymentToken(
        address _tokenAddr,
        uint256 _totemsAmount
    ) public view returns (uint256) {
        return (_totemsAmount * oneTotemPriceInUsd) / getPrice(_tokenAddr);
    }

    /**
     * @notice Converts payment tokens to totem tokens based on price
     * @param _tokenAddr Address of the payment token
     * @param _paymentTokenAmount Amount of payment tokens
     * @return Amount of totem tokens that can be purchased
     */
    function paymentTokenToTotems(
        address _tokenAddr,
        uint256 _paymentTokenAmount
    ) public view returns (uint256) {
        return
            (_paymentTokenAmount * getPrice(_tokenAddr)) / oneTotemPriceInUsd;
    }

    /**
     * @notice Returns the price of a given token in USD
     * @dev Uses Chainlink price feeds to get the token price in USD
     * @param _tokenAddr Address of the token to get the price for
     * @return Amount of tokens equivalent to 1 USD
     */
    function getPrice(address _tokenAddr) public view returns (uint256) {
        address priceFeedAddr = priceFeedAddresses[_tokenAddr];

        if (priceFeedAddr == address(0)) {
            // If no price feed is set for this token, return a default value
            return 0.05 * 1e18;
            // revert NoPriceFeedSet(_tokenAddr);
        }

        // Get the latest price from Chainlink
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddr);
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // Validate the price feed data
        if (price <= 0) revert InvalidPrice(_tokenAddr);
        if (answeredInRound < roundId) revert StalePrice(_tokenAddr);
        if (block.timestamp > updatedAt + PRICE_FEED_STALE_THRESHOLD)
            revert StalePrice(_tokenAddr);

        // Get the number of decimals in the price feed
        uint8 decimals = priceFeed.decimals();

        // Calculate how many tokens are equivalent to 1 USD
        // Price from Chainlink is in USD per token with 'decimals' decimal places
        // We want tokens per USD with 18 decimal places

        // First, normalize the price to 18 decimals
        uint256 normalizedPrice;
        if (decimals < 18) {
            normalizedPrice = uint256(price) * (10 ** (18 - decimals));
        } else {
            normalizedPrice = uint256(price) / (10 ** (decimals - 18));
        }

        // Then calculate tokens per USD: 1e36 / price
        // 1e36 = 1 USD (with 18 decimals) * 1e18 (for division precision)
        return (1e36) / normalizedPrice;
    }

    /**
     * @notice Returns the address of the current payment token
     * @return Address of the payment token
     */
    function getPaymentToken() external view returns (address) {
        return paymentTokenAddr;
    }

    /**
     * @notice Returns the sale position of a user for a specific totem token
     * @param _userAddr Address of the user
     * @param _totemTokenAddr Address of the totem token
     * @return Sale position details
     */
    function getPosition(
        address _userAddr,
        address _totemTokenAddr
    ) external view returns (SalePosInToken memory) {
        return salePositions[_userAddr][_totemTokenAddr];
    }

    /**
     * @notice Calculates the number of totem tokens available for purchase
     * @dev Takes into account the user's current balance and the maximum allowed tokens per address
     * @param _userAddr Address of the user
     * @param _totemTokenAddr Address of the totem token
     * @return The number of totem tokens available for purchase
     */
    function getAvailableTokensForPurchase(
        address _userAddr,
        address _totemTokenAddr
    ) external view returns (uint256) {
        if (
            !totems[_totemTokenAddr].registered ||
            !totems[_totemTokenAddr].isSalePeriod
        ) {
            return 0; // Tokens are only available for purchase during sale period
        }

        // Get user's current balance
        uint256 currentBalance = IERC20(_totemTokenAddr).balanceOf(_userAddr);

        // Calculate how many more tokens the user can buy based on the max limit
        if (currentBalance >= maxTokensPerAddress) {
            return 0; // User has reached the maximum allowed tokens
        }

        uint256 remainingAllowance = maxTokensPerAddress - currentBalance;

        // Check contract's available balance (excluding pool initial supply)
        uint256 contractBalance = IERC20(_totemTokenAddr).balanceOf(
            address(this)
        );
        uint256 availableForSale = contractBalance > POOL_INITIAL_SUPPLY
            ? contractBalance - POOL_INITIAL_SUPPLY
            : 0;

        // Return the minimum of remaining allowance and available tokens
        return
            remainingAllowance < availableForSale
                ? remainingAllowance
                : availableForSale;
    }

    /**
     * @notice Returns the TotemData for a specific totem token address
     * @param _totemTokenAddr Address of the totem token
     * @return TotemData struct containing information about the totem
     */
    function getTotemData(
        address _totemTokenAddr
    ) external view returns (TotemData memory) {
        return totems[_totemTokenAddr];
    }

    /**
     * @notice Returns the current distribution shares
     */
    function getDistributionShares()
        external
        view
        returns (uint256 revenue, uint256 creator, uint256 pool, uint256 vault)
    {
        return (
            revenuePaymentTokenShare,
            totemCreatorPaymentTokenShare,
            poolPaymentTokenShare,
            vaultPaymentTokenShare
        );
    }
}

// --- src/TotemToken.sol ---
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

// --- src/Totem.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";
import {TotemToken} from "./TotemToken.sol";

/**
 * @title Totem
 * @notice This contract represents a Totem in the MYTHO ecosystem, managing token burning and merit distribution
 * @dev Handles the lifecycle of a Totem, including token burning after sale period and merit distribution
 */
contract Totem is AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for TotemToken;

    TotemToken private totemToken;
    IERC20 private paymentToken;
    IERC20 private liquidityToken;
    IERC20 private mythoToken;

    bytes private dataHash;

    address private treasuryAddr;
    address private totemDistributorAddr;
    address private meritManagerAddr;
    
    address public owner;
    address[] public collaborators;

    bool private isCustomToken;
    bool public salePeriodEnded;

    bytes32 private constant MANAGER = keccak256("MANAGER");
    bytes32 private constant TOTEM_DISTRIBUTOR = keccak256("TOTEM_DISTRIBUTOR");

    // Events
    event TotemTokenBurned(
        address indexed user,
        uint256 totemTokenAmount,
        uint256 paymentAmount,
        uint256 mythoAmount,
        uint256 lpAmount
    );
    event SalePeriodEnded();
    event MythoCollected(address indexed user, uint256 periodNum);

    // Custom errors
    error SalePeriodNotEnded();
    error InsufficientTotemBalance();
    error InsufficientPaymentTokenBalance();
    error ZeroAmount();

    /**
     * @notice Initializes the Totem contract with token addresses, data hash, and revenue pool
     * @dev Sets up the initial state and grants roles
     * @param _totemToken The address of the TotemToken or custom token
     * @param _dataHash The data hash associated with this Totem
     * @param _registryAddr Address of the AddressRegistry contract
     * @param _isCustomToken Flag indicating if the token is custom (not burnable)
     * @param _owner The address of the Totem owner
     * @param _collaborators Array of collaborator addresses
     */
    function initialize(
        TotemToken _totemToken,
        bytes memory _dataHash,
        address _registryAddr,
        bool _isCustomToken,
        address _owner,
        address[] memory _collaborators
    ) public initializer {
        __AccessControl_init();

        totemToken = _totemToken;
        dataHash = _dataHash;

        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();
        totemDistributorAddr = AddressRegistry(_registryAddr).getTotemTokenDistributor();
        meritManagerAddr = AddressRegistry(_registryAddr).getMeritManager();
        mythoToken = IERC20(MeritManager(meritManagerAddr).mythoToken());
        
        isCustomToken = _isCustomToken;
        salePeriodEnded = false; // Initially, sale period is active

        // Set owner and collaborators
        owner = _owner;
        collaborators = _collaborators;

        _grantRole(TOTEM_DISTRIBUTOR, totemDistributorAddr);
    }

    /**
     * @notice Allows TotemToken holders to burn or transfer their tokens and receive proportional shares of assets
     * @dev After the sale period ends, burns TotemTokens for standard tokens or transfers custom tokens to treasuryAddr.
     *      User receives proportional shares of payment tokens, MYTHO tokens, and LP tokens.
     * @param _totemTokenAmount The amount of TotemToken to burn or transfer
     */
    function burnTotemTokens(uint256 _totemTokenAmount) external {
        if (!salePeriodEnded) revert SalePeriodNotEnded();
        if (totemToken.balanceOf(msg.sender) < _totemTokenAmount)
            revert InsufficientTotemBalance();
        if (_totemTokenAmount == 0) revert ZeroAmount();

        // Get the total supply of TotemToken
        uint256 totalSupply = totemToken.totalSupply();

        // Calculate the user's share of payment tokens based on their submitted amount
        uint256 paymentTokenBalance = paymentToken.balanceOf(address(this));
        uint256 paymentAmount = (paymentTokenBalance * _totemTokenAmount) /
            totalSupply;

        // Verify payment token balance if needed
        if (paymentAmount == 0) revert InsufficientPaymentTokenBalance();

        // Take TotemTokens from the caller
        totemToken.safeTransferFrom(msg.sender, address(this), _totemTokenAmount);

        // Handle token disposal based on whether it's a custom token
        if (isCustomToken) {
            // For custom tokens, transfer to treasuryAddr instead of burning
            totemToken.safeTransfer(treasuryAddr, _totemTokenAmount);
        } else {
            // For standard TotemTokens, burn them
            totemToken.burn(_totemTokenAmount);
        }

        // Transfer the proportional payment tokens to the caller if there are any
        paymentToken.safeTransfer(msg.sender, paymentAmount);
        
        // Calculate and distribute MYTHO tokens
        uint256 mythoBalance = mythoToken.balanceOf(address(this));
        uint256 mythoAmount;
        
        if (mythoBalance > 0) {
            mythoAmount = (mythoBalance * _totemTokenAmount) / totalSupply;
            if (mythoAmount > 0) {
                mythoToken.safeTransfer(msg.sender, mythoAmount);
            }
        }
        
        // Calculate and distribute LP tokens
        uint256 lpAmount;
        if (address(liquidityToken) != address(0)) {
            uint256 lpBalance = liquidityToken.balanceOf(address(this));
            if (lpBalance > 0) {
                lpAmount = (lpBalance * _totemTokenAmount) / totalSupply;
                if (lpAmount > 0) {
                    liquidityToken.safeTransfer(msg.sender, lpAmount);
                }
            }
        }

        emit TotemTokenBurned(msg.sender, _totemTokenAmount, paymentAmount, mythoAmount, lpAmount);
    }

    /**
     * @notice Collects accumulated MYTHO from MeritManager for a specific period
     * @param _periodNum The period number to collect rewards for
     */
    function collectMYTH(uint256 _periodNum) public {
        MeritManager(meritManagerAddr).claimMytho(_periodNum);
        emit MythoCollected(msg.sender, _periodNum);
    }

    /**
     * @notice Sets the payment token and liquidity token addresses and ends the sale period
     * @dev Should be called by TotemTokenDistributor after sale period ends
     * @param _paymentToken The address of the payment token contract
     * @param _liquidityToken The address of the liquidity token (LP token)
     */
    function closeSalePeriod(
        IERC20 _paymentToken,
        IERC20 _liquidityToken
    ) external onlyRole(TOTEM_DISTRIBUTOR) {
        paymentToken = _paymentToken;
        liquidityToken = _liquidityToken;
        salePeriodEnded = true;

        emit SalePeriodEnded();
    }

    /**
     * @notice Get the data hash associated with this Totem
     * @dev Returns the data hash that was set during initialization
     * @return The data hash stored in the contract
     */
    function getDataHash() external view returns (bytes memory) {
        return dataHash;
    }

    /**
     * @notice Get the addresses of tokens associated with this Totem
     * @return totemTokenAddr The address of the Totem token
     * @return paymentTokenAddr The address of the payment token
     * @return liquidityTokenAddr The address of the liquidity token
     */
    function getTokenAddresses() external view returns (
        address totemTokenAddr,
        address paymentTokenAddr,
        address liquidityTokenAddr
    ) {
        return (
            address(totemToken),
            address(paymentToken),
            address(liquidityToken)
        );
    }

    /**
     * @notice Get all token balances of this Totem
     * @return totemBalance The balance of Totem tokens
     * @return paymentBalance The balance of payment tokens
     * @return liquidityBalance The balance of liquidity tokens
     * @return mythoBalance The balance of MYTHO tokens
     */
    function getAllBalances() external view returns (
        uint256 totemBalance,
        uint256 paymentBalance,
        uint256 liquidityBalance,
        uint256 mythoBalance
    ) {
        totemBalance = totemToken.balanceOf(address(this));
        paymentBalance = address(paymentToken) != address(0) ? paymentToken.balanceOf(address(this)) : 0;
        liquidityBalance = address(liquidityToken) != address(0) ? liquidityToken.balanceOf(address(this)) : 0;
        
        address mythoAddr = MeritManager(meritManagerAddr).mythoToken();
        mythoBalance = mythoAddr != address(0) ? IERC20(mythoAddr).balanceOf(address(this)) : 0;
        
        return (totemBalance, paymentBalance, liquidityBalance, mythoBalance);
    }

    /**
     * @notice Check if this is a custom token Totem
     * @return True if this is a custom token Totem, false otherwise
     */
    function isCustomTokenTotem() external view returns (bool) {
        return isCustomToken;
    }
}

// --- src/MYTHO.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MYTHO Government Token
 * @notice Non-upgradeable ERC20 token with fixed supply and vesting distribution
 */
contract MYTHO is ERC20 {
    using SafeERC20 for ERC20;    

    // Token distribution constants
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens with 18 decimals
    
    // Totem incentives distribution (50% of total supply)
    uint256 public constant MERIT_YEAR_1 = 175_000_000 * 10**18; // 35% of incentives
    uint256 public constant MERIT_YEAR_2 = 125_000_000 * 10**18; // 25% of incentives
    uint256 public constant MERIT_YEAR_3 = 100_000_000 * 10**18; // 20% of incentives
    uint256 public constant MERIT_YEAR_4 = 50_000_000 * 10**18;  // 10% of incentives
    
    // Team allocation (20% of total supply)
    uint256 public constant TEAM_ALLOCATION = 200_000_000 * 10**18;
    
    // Treasury allocation (23% of total supply - includes previous airdrop allocation)
    uint256 public constant TREASURY_ALLOCATION = 230_000_000 * 10**18;
    
    // Mytho AMM incentives (7% of total supply)
    uint256 public constant AMM_INCENTIVES = 70_000_000 * 10**18;

    // Vesting duration constants
    uint64 public constant ONE_YEAR = 12 * 30 days;
    uint64 public constant TWO_YEARS = 2 * ONE_YEAR;
    uint64 public constant FOUR_YEARS = 4 * ONE_YEAR;

    // Vesting wallet and recipient addresses (immutable)
    address public immutable meritVestingYear1;
    address public immutable meritVestingYear2;
    address public immutable meritVestingYear3;
    address public immutable meritVestingYear4;
    address public immutable teamVesting;
    address public immutable ammVesting;
    address public immutable treasury;

    // Custom errors
    error ZeroAddressNotAllowed(string receiverType);
    error OnlyOwnerCanBurn();

    /**
     * @notice Constructor to deploy the token and set up vesting schedules
     * @param _meritManager Address to receive totem incentives
     * @param _teamReceiver Address to receive team allocation
     * @param _treasuryReceiver Address to receive treasury allocation
     * @param _ammReceiver Address to receive AMM incentives
     */
    constructor(
        address _meritManager,
        address _teamReceiver,
        address _treasuryReceiver,
        address _ammReceiver
    ) ERC20("MYTHO Government Token", "MYTHO") {
        if (_meritManager == address(0)) revert ZeroAddressNotAllowed("totem receiver");
        if (_teamReceiver == address(0)) revert ZeroAddressNotAllowed("team receiver");
        if (_treasuryReceiver == address(0)) revert ZeroAddressNotAllowed("treasury receiver");
        if (_ammReceiver == address(0)) revert ZeroAddressNotAllowed("AMM receiver");

        // Set the start timestamp for vesting
        uint64 startTimestamp = uint64(block.timestamp);
        
        // Create vesting wallets for totem incentives (4 years with annual releases)
        meritVestingYear1 = address(new VestingWallet(_meritManager, startTimestamp, ONE_YEAR));
        meritVestingYear2 = address(new VestingWallet(_meritManager, startTimestamp + ONE_YEAR, ONE_YEAR));
        meritVestingYear3 = address(new VestingWallet(_meritManager, startTimestamp + 2 * ONE_YEAR, ONE_YEAR));
        meritVestingYear4 = address(new VestingWallet(_meritManager, startTimestamp + 3 * ONE_YEAR, ONE_YEAR));
        
        // Create vesting wallet for team (2 years)
        teamVesting = address(new VestingWallet(_teamReceiver, startTimestamp, TWO_YEARS));
        
        // Create vesting wallet for AMM incentives (2 years)
        ammVesting = address(new VestingWallet(_ammReceiver, startTimestamp, TWO_YEARS));
        
        // Treasury (no vesting, immediate access)
        treasury = _treasuryReceiver;

        // Mint the total supply of tokens
        _mint(address(this), TOTAL_SUPPLY);
        
        // Distribute tokens to vesting wallets and addresses
        _transfer(address(this), meritVestingYear1, MERIT_YEAR_1);
        _transfer(address(this), meritVestingYear2, MERIT_YEAR_2);
        _transfer(address(this), meritVestingYear3, MERIT_YEAR_3);
        _transfer(address(this), meritVestingYear4, MERIT_YEAR_4);
        _transfer(address(this), teamVesting, TEAM_ALLOCATION);
        _transfer(address(this), ammVesting, AMM_INCENTIVES);
        _transfer(address(this), treasury, TREASURY_ALLOCATION);
    }

    /**
     * @notice Burns tokens from the caller's address
     * @dev Can only be called by the token owner
     * @param _account Address from which tokens are burned
     * @param _amount Amount of tokens to burn
     */
    function burn(address _account, uint256 _amount) external {
        if (msg.sender != _account) revert OnlyOwnerCanBurn();
        _burn(_account, _amount);
    }

    /// TEST LOGIC

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }
}

// --- src/Treasury.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RevenuePool
 * @dev This contract manages and withdraws ERC20 and native tokens.
 * It provides functionality to:
 * - Withdraw ERC20 tokens to specified addresses
 * - Withdraw native tokens to specified addresses
 * - Check balances of ERC20 and native tokens
 */
contract Treasury is AccessControlUpgradeable {
    bytes32 private constant MANAGER = keccak256("MANAGER");

    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event NativeWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);

    function initialize() public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
    }

    /**
     * @dev Withdraws ERC20 tokens, restricted to MANAGER
     * @param _token Address of the ERC20 token to withdraw
     * @param _to Recipient address
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawERC20(address _token, address _to, uint256 _amount) external onlyRole(MANAGER) {
        if (_token == address(0) || _to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance < _amount) revert InsufficientBalance(_amount, balance);
        IERC20(_token).transfer(_to, _amount);
        emit ERC20Withdrawn(_token, _to, _amount);
    }

    /**
     * @dev Withdraws native tokens, restricted to MANAGER
     * @param _to Recipient address (payable)
     * @param _amount Amount of native tokens to withdraw (in wei)
     */
    function withdrawNative(address payable _to, uint256 _amount) external onlyRole(MANAGER) {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        if (address(this).balance < _amount) revert InsufficientBalance(_amount, address(this).balance);
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Native transfer failed");
        emit NativeWithdrawn(_to, _amount);
    }

    /**
     * @dev Allows contract to receive native tokens
     */
    receive() external payable {}

    /// READERS

    /**
     * @dev Returns balance of a specific ERC20 token
     * @param _token Address of the ERC20 token
     * @return Token balance of the contract
     */
    function getERC20Balance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /**
     * @dev Returns native token balance
     * @return Native token balance of the contract (in wei)
     */
    function getNativeBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
