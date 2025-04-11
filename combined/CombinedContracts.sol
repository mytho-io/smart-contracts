
// --- src/MeritManager.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {AddressRegistry} from "./AddressRegistry.sol";
import {Totem} from "./Totem.sol";

/**
 * @title MeritManager
 * @notice Manages merit points for registered totems and distributes MYTHO tokens based on merit.
 * Includes features like totem registration, merit crediting, boosting, and claiming rewards.
 * Contract can be paused in emergency situations.
 */
contract MeritManager is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address payable;

    // State variables
    address private mythoToken;
    address private treasuryAddr;
    address private registryAddr;
    address[4] private vestingWallets;
    uint256[4] private vestingWalletsAllocation;
    uint256 public boostFee; // Fee in native tokens for boosting
    uint256 public periodDuration;
    uint256 public startTime; // Initially set to deployment timestamp, updated when period duration changes
    uint256 public oneTotemBoost; // Amount of merit points awarded for a boost
    uint256 public mythumMultiplier; // Multiplier for merit during Mythum period (default: 150 = 1.5x)
    uint256 public lastProcessedPeriod; // Last period that was fully processed
    uint256 public accumulatedPeriods; // Number of periods accumulated before period duration changes
    address[] public registeredTotemsList; // Array to track all registered totems

    // Mappings
    mapping(uint256 period => uint256 totalPoints) public totalMeritPoints; // Total merit points across all totems per period
    mapping(uint256 period => mapping(address totemAddress => uint256 points))
        public totemMerit; // Merit points for each totem per period
    mapping(uint256 period => mapping(address totemAddr => bool claimed))
        public isClaimed; // Whether rewards have been claimed for a period by a specific totem
    mapping(uint256 period => uint256 releasedMytho) public releasedMytho; // Total MYTHO released per period
    mapping(uint256 => mapping(address => bool)) public userBoostedInPeriod; // Whether a user has boosted in a period
    mapping(uint256 => mapping(address => address)) public userBoostedTotem; // Which Totem a user boosted in a period
    mapping(address => bool) public registeredTotems; // Totem state tracking

    // Constants - Roles
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
    error InsufficientTotemBalance();
    error InvalidPeriodDuration();
    error ZeroAmount();
    error EcosystemPaused();

    /**
     * @notice Initializes the contract with required parameters
     * @param _registryAddr Address of the AddressRegistry contract
     * @param _vestingWallets Array of vesting wallet addresses
     */
    function initialize(
        address _registryAddr,
        address[4] memory _vestingWallets
    ) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        registryAddr = _registryAddr;
        mythoToken = AddressRegistry(_registryAddr).getMythoToken();
        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();

        vestingWallets = _vestingWallets;
        periodDuration = 30 days;
        startTime = block.timestamp; // Initially set to deployment timestamp
        accumulatedPeriods = 0;
        vestingWalletsAllocation = [
            175_000_000 ether,
            125_000_000 ether,
            100_000_000 ether,
            50_000_000 ether
        ];

        oneTotemBoost = 10; // 10 merit points per boost initially
        mythumMultiplier = 150; // 1.5x multiplier (150/100)
        boostFee = 0.001 ether; // 0.001 native tokens for boost fee
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Registers a new totem
     * @param _totemAddr Address of the totem to register
     */
    function register(address _totemAddr) external whenNotPaused {
        if (!hasRole(REGISTRATOR, msg.sender)) revert AccessControl();
        if (registeredTotems[_totemAddr]) revert TotemAlreadyRegistered();
        if (_totemAddr == address(0)) revert InvalidAddress();

        registeredTotems[_totemAddr] = true;
        registeredTotemsList.push(_totemAddr);

        emit TotemRegistered(_totemAddr);
    }

    /**
     * @notice Allows a user to boost a totem by paying a fee
     * @param _totemAddr Address of the totem to boost
     */
    function boostTotem(
        address _totemAddr
    ) external payable nonReentrant whenNotPaused {
        if (!registeredTotems[_totemAddr]) revert TotemNotRegistered();
        if (hasRole(BLACKLISTED, _totemAddr)) revert TotemInBlocklist();
        if (msg.value < boostFee) revert InsufficientBoostFee();
        if (!isMythum()) revert NotInMythumPeriod();

        // Get the totem token address and check if the user has it
        (address totemTokenAddr, , ) = Totem(_totemAddr).getTokenAddresses();
        if (IERC20(totemTokenAddr).balanceOf(msg.sender) == 0)
            revert InsufficientTotemBalance();

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
     * @notice Allows a totem to claim MYTHO tokens for a specific period
     * @param _periodNum Period number to claim for
     */
    function claimMytho(
        uint256 _periodNum
    ) external nonReentrant whenNotPaused {
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

    // ADMIN FUNCTIONS

    /**
     * @notice Manually triggers state update
     */
    function updateState() external onlyRole(MANAGER) {
        _updateState();
    }

    /**
     * @notice Credits merit points to a registered totem
     * @param _totemAddr Address of the totem to credit
     * @param _amount Amount of merit points to credit
     */
    function creditMerit(
        address _totemAddr,
        uint256 _amount
    ) external onlyRole(MANAGER) {
        if (_amount == 0) revert ZeroAmount();
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
     * @notice Sets the blacklist status for a totem
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
     * @notice Sets the one Totem boost amount
     * @param _oneTotemBoost New boost amount
     */
    function setOneTotemBoost(
        uint256 _oneTotemBoost
    ) external onlyRole(MANAGER) {
        if (_oneTotemBoost == 0) revert ZeroAmount();
        oneTotemBoost = _oneTotemBoost;
        emit ParameterUpdated("oneTotemBoost", _oneTotemBoost);
    }

    /**
     * @notice Sets the Mythum multiplier (in percentage, e.g., 150 = 1.5x)
     * @param _mythumMultiplier New multiplier value
     */
    function setMythumMultiplier(
        uint256 _mythumMultiplier
    ) external onlyRole(MANAGER) {
        if (_mythumMultiplier == 0) revert ZeroAmount();
        mythumMultiplier = _mythumMultiplier;
        emit ParameterUpdated("mythumMultiplier", _mythumMultiplier);
    }

    /**
     * @notice Sets the boost fee in native tokens
     * @param _boostFee New boost fee
     */
    function setBoostFee(uint256 _boostFee) external onlyRole(MANAGER) {
        boostFee = _boostFee;
        emit ParameterUpdated("boostFee", _boostFee);
    }

    /**
     * @notice Sets the period duration
     * @param _newPeriodDuration New period duration in seconds
     */
    function setPeriodDuration(
        uint256 _newPeriodDuration
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newPeriodDuration == 0) revert InvalidPeriodDuration();
        _updateState();

        // Store the current period count before changing the duration
        accumulatedPeriods = currentPeriod();
        startTime = block.timestamp; // Reset the start time to now

        periodDuration = _newPeriodDuration;
        lastProcessedPeriod = currentPeriod();
        emit ParameterUpdated("periodDuration", _newPeriodDuration);
    }

    /**
     * @notice Grants the registrator role to an address
     * @param _registrator Address to grant the role to
     * @notice This role is given to TotemFactory and TotemTokenDistributor contracts
     */
    function grantRegistratorRole(
        address _registrator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_registrator == address(0)) revert InvalidAddress();
        grantRole(REGISTRATOR, _registrator);
    }

    /**
     * @notice Revokes the registrator role from an address
     * @param _registrator Address to revoke the role from
     */
    function revokeRegistratorRole(
        address _registrator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_registrator == address(0)) revert InvalidAddress();
        revokeRole(REGISTRATOR, _registrator);
    }

    /**
     * @notice Pauses the contract
     * @dev Only callable by MANAGER role
     */
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by MANAGER role
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
     * @notice Updates the state of the contract by processing pending periods
     */
    function _updateState() private {
        uint256 yearIdx = getYearIndex();

        // Check if we're still within the valid year range
        if (yearIdx >= 4) {
            return;
        }

        VestingWallet wallet = VestingWallet(payable(vestingWallets[yearIdx]));

        uint256 _currentPeriod = currentPeriod();

        // Only process completed periods, not the current period
        if (_currentPeriod > lastProcessedPeriod) {
            uint256 slices = (30 days * 12) / periodDuration;
            // Process all completed periods up to but not including the current period
            for (
                uint256 period = lastProcessedPeriod;
                period < _currentPeriod;
                period++
            ) {
                releasedMytho[period] =
                    vestingWalletsAllocation[yearIdx] /
                    slices;
                emit MythoReleased(releasedMytho[period], period);
            }

            wallet.release(address(mythoToken));
            lastProcessedPeriod = _currentPeriod;
        }
    }

    // VIEW FUNCTIONS

    /**
     * @notice Returns the current period number
     * @return Current period number
     */
    function currentPeriod() public view returns (uint256) {
        if (block.timestamp < startTime) return accumulatedPeriods;
        return
            accumulatedPeriods + (block.timestamp - startTime) / periodDuration;
    }

    /**
     * @notice Checks if the current time is within the Mythum period
     * @return Whether current time is in Mythum period
     */
    function isMythum() public view returns (bool) {
        uint256 currentPeriodNumber = currentPeriod();
        uint256 periodsAfterAccumulation = currentPeriodNumber -
            accumulatedPeriods;
        uint256 currentPeriodStart = startTime +
            (periodsAfterAccumulation * periodDuration);
        uint256 mythumStart = currentPeriodStart + ((periodDuration * 3) / 4);
        return block.timestamp >= mythumStart;
    }

    /**
     * @notice Returns the year index based on the current period
     * @return Year index (0-3)
     */
    function getYearIndex() public view returns (uint256) {
        uint256 slices = (30 days * 12) / periodDuration;
        return (currentPeriod() / slices) > 3 ? 3 : (currentPeriod() / slices);
    }

    /**
     * @notice Gets the total number of registered totems
     * @return Total number of registered totems
     */
    function getRegisteredTotemsCount() external view returns (uint256) {
        return registeredTotemsList.length;
    }

    /**
     * @notice Gets all registered totems
     * @return Array of registered totem addresses
     */
    function getAllRegisteredTotems() external view returns (address[] memory) {
        return registeredTotemsList;
    }

    /**
     * @notice Gets the pending MYTHO reward for a totem in a specific period
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
     * @notice Gets the period time bounds
     * @param _periodNum Period number to check
     * @return periodStartTime Period start timestamp
     * @return endTime Period end timestamp
     */
    function getPeriodTimeBounds(
        uint256 _periodNum
    ) external view returns (uint256 periodStartTime, uint256 endTime) {
        // For periods before the accumulated periods, we can't accurately determine bounds
        // since the period duration might have changed
        if (_periodNum < accumulatedPeriods) {
            return (0, 0); // Indicate that we can't determine bounds for historical periods
        }

        uint256 periodsAfterAccumulation = _periodNum - accumulatedPeriods;
        periodStartTime =
            startTime +
            (periodsAfterAccumulation * periodDuration);
        endTime = periodStartTime + periodDuration;
        return (periodStartTime, endTime);
    }

    /**
     * @notice Gets the time remaining until the next period
     * @return Time in seconds until the next period
     */
    function getTimeUntilNextPeriod() external view returns (uint256) {
        uint256 currentPeriodNumber = currentPeriod();
        uint256 periodsAfterAccumulation = currentPeriodNumber -
            accumulatedPeriods;
        uint256 nextPeriodStart = startTime +
            ((periodsAfterAccumulation + 1) * periodDuration);

        if (block.timestamp >= nextPeriodStart) {
            return 0;
        }
        return nextPeriodStart - block.timestamp;
    }

    /**
     * @notice Gets the timestamp when the current Mythum period starts
     * @return Timestamp of the current Mythum period start
     */
    function getCurrentMythumStart() external view returns (uint256) {
        uint256 currentPeriodNumber = currentPeriod();
        uint256 periodsAfterAccumulation = currentPeriodNumber -
            accumulatedPeriods;
        uint256 currentPeriodStart = startTime +
            (periodsAfterAccumulation * periodDuration);
        return currentPeriodStart + ((periodDuration * 3) / 4);
    }

    /**
     * @notice Checks if a totem has been registered
     * @param _totemAddr Address to check
     * @return Whether the address is a registered totem
     */
    function isRegisteredTotem(
        address _totemAddr
    ) external view returns (bool) {
        return registeredTotems[_totemAddr];
    }

    /**
     * @notice Checks if a totem is blacklisted
     * @param _totemAddr Address to check
     * @return Whether the totem is blacklisted
     */
    function isBlacklisted(address _totemAddr) external view returns (bool) {
        return hasRole(BLACKLISTED, _totemAddr);
    }

    /**
     * @notice Gets the total merit points for a totem in a specific period
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
     * @notice Gets whether a user has boosted in a specific period
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
     * @notice Gets which totem a user boosted in a specific period
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

/**
 * @title TotemFactory
 * @notice Factory contract for creating new Totems in the MYTHO ecosystem
 *      Handles creation of new Totems with either new or existing tokens
 */
contract TotemFactory is PausableUpgradeable, AccessControlUpgradeable {
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
    bytes32 private constant WHITELISTED = keccak256("WHITELISTED");

    // Events
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

    // Custom errors
    error AlreadyWhitelisted(address totemTokenAddr);
    error NotWhitelisted(address totemTokenAddr);
    error InsufficientFee(uint256 provided, uint256 required);
    error FeeTransferFailed();
    error ZeroAddress();
    error InvalidTotemParameters(string reason);
    error TotemNotFound(uint256 totemId);
    error ZeroAmount();
    error EcosystemPaused();

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
     * @notice Adds multiple tokens to the whitelist
     * @param _tokens Array of token addresses to whitelist
     */
    function batchAddToWhitelist(
        address[] calldata _tokens
    ) external onlyRole(MANAGER) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (!hasRole(WHITELISTED, _tokens[i])) {
                grantRole(WHITELISTED, _tokens[i]);
            }
        }

        emit BatchWhitelistUpdated(_tokens, true);
    }

    /**
     * @notice Removes multiple tokens from the whitelist
     * @param _tokens Array of token addresses to remove from whitelist
     */
    function batchRemoveFromWhitelist(
        address[] calldata _tokens
    ) external onlyRole(MANAGER) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            if (hasRole(WHITELISTED, _tokens[i])) {
                revokeRole(WHITELISTED, _tokens[i]);
            }
        }

        emit BatchWhitelistUpdated(_tokens, false);
    }

    /**
     * @notice Adds a single token to the whitelist
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
     * @notice Removes a single token from the whitelist
     * @param _token The token address to remove from whitelist
     */
    function removeTokenFromWhitelist(address _token) public onlyRole(MANAGER) {
        if (!hasRole(WHITELISTED, _token)) revert NotWhitelisted(_token);
        revokeRole(WHITELISTED, _token);

        address[] memory tokens = new address[](1);
        tokens[0] = _token;
        emit BatchWhitelistUpdated(tokens, false);
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

        // Transfer tokens from sender to fee collector
        bool success = IERC20(feeTokenAddr).transferFrom(
            _sender,
            treasuryAddr,
            creationFee
        );
        if (!success) revert FeeTransferFailed();
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
}

// --- src/TotemTokenDistributor.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
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
 * @notice This contract manages the distribution of Totem tokens during and after sales periods
 *      Handles registration of new totems, token sales, distribution of collected payment tokens,
 *      adding liquidity to AMM pools, and burning totem tokens
 */

contract TotemTokenDistributor is
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // State variables - Contracts
    TotemFactory private factory;
    MeritManager private meritManager;
    IERC20 private mytho;

    // State variables - Configuration
    uint256 private oneTotemPriceInUsd;
    uint256 public maxTokensPerAddress;

    // State variables - Distribution shares
    uint256 public revenuePaymentTokenShare;
    uint256 public totemCreatorPaymentTokenShare;
    uint256 public poolPaymentTokenShare;
    uint256 public vaultPaymentTokenShare;

    // State variables - Addresses
    address private treasuryAddr; // contract address for revenue in payment tokens
    address private paymentTokenAddr; // address of payment token
    address private uniswapV2RouterAddr; // Uniswap V2 router address
    address private registryAddr; // address of the AddressRegistry contract

    // State variables - Mappings
    mapping(address => address) private priceFeedAddresses; // Mapping from token address to Chainlink price feed address
    mapping(address totemTokenAddr => TotemData TotemData) private totems; // General info about totems
    mapping(address userAddress => mapping(address totemTokenAddr => SalePosInToken))
        private salePositions;

    // Constants
    uint256 private constant PRECISION = 10000;
    uint256 private constant POOL_INITIAL_SUPPLY = 200_000_000 ether;
    uint256 public constant PRICE_FEED_STALE_THRESHOLD = 1 hours; // Maximum age of price feed data before it's considered stale (1 hour)

    bytes32 private constant MANAGER = keccak256("MANAGER");

    // Structs
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
    error EcosystemPaused();

    /**
     * @notice Initializes the TotemTokenDistributor contract
     *      Sets up initial roles and configuration
     * @param _registryAddr Address of the AddressRegistry contract
     */
    function initialize(address _registryAddr) public initializer {
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        if (_registryAddr == address(0)) revert ZeroAddress();

        registryAddr = _registryAddr;
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

    // EXTERNAL FUNCTIONS

    /**
     * @notice Being called by TotemFactory during totem creation
     *      Registers a new totem and distributes initial tokens
     */
    function register() external whenNotPaused {
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

    /**
     * @notice Buy totems for allowed payment tokens
     * @param _totemTokenAddr Address of the totem token to buy
     * @param _totemTokenAmount Amount of totem tokens to buy
     */
    function buy(
        address _totemTokenAddr,
        uint256 _totemTokenAmount
    ) external whenNotPaused {
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

    /**
     * @notice Sell totems for used payment token in sale period
     * @param _totemTokenAddr Address of the totem token to sell
     * @param _totemTokenAmount Amount of totem tokens to sell
     */
    function sell(
        address _totemTokenAddr,
        uint256 _totemTokenAmount
    ) external whenNotPaused {
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

    // ADMIN FUNCTIONS

    /**
     * @notice Pauses the contract
     * @dev Only callable by accounts with the MANAGER role
     */
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by accounts with the MANAGER role
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

    /**
     * @notice Sets the payment token address
     * @param _paymentTokenAddr Address of the payment token
     */
    function setPaymentToken(
        address _paymentTokenAddr
    ) external onlyRole(MANAGER) {
        if (_paymentTokenAddr == address(0)) revert ZeroAddress();
        paymentTokenAddr = _paymentTokenAddr;
    }

    /**
     * @notice Sets the TotemFactory address from registry
     * @param _registryAddr Address of the AddressRegistry contract
     */
    function setTotemFactory(address _registryAddr) external onlyRole(MANAGER) {
        if (address(factory) != address(0)) revert AlreadySet();
        if (_registryAddr == address(0)) revert ZeroAddress();
        factory = TotemFactory(
            AddressRegistry(_registryAddr).getTotemFactory()
        );
    }

    /**
     * @notice Sets the maximum number of totem tokens per address
     * @param _amount Maximum amount of tokens
     */
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

    /// INTERNAL FUNCTIONS

    /**
     * @notice Closes the sale period for a totem token
     *      Distributes collected payment tokens and adds liquidity to AMM
     * @param _totemTokenAddr Address of the totem token
     */
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
     *      Approves tokens for the router and adds liquidity to the pool
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
            (_totemTokenAmount * 950) / 1000, // 5% slippage
            (_paymentTokenAmount * 950) / 1000, // 5% slippage
            address(this),
            block.timestamp + 600 // Deadline: 10 minutes from now
        );

        liquidityToken = factory_.getPair(_totemTokenAddr, _paymentTokenAddr);

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

    // VIEW FUNCTIONS

    /**
     * @notice Returns the token price in USD
     * @return The current token price in USD (18 decimals)
     */
    function getTotemPriceInUsd() external view returns (uint256) {
        return oneTotemPriceInUsd;
    }

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
        uint256 amount = (_totemsAmount * oneTotemPriceInUsd) /
            getPrice(_tokenAddr);
        return amount == 0 ? 1 : amount;
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
        uint256 amount = (_paymentTokenAmount * getPrice(_tokenAddr)) /
            oneTotemPriceInUsd;
        return amount == 0 ? 1 : amount;
    }

    /**
     * @notice Returns the price of a given token in USD
     *      Uses Chainlink price feeds to get the token price in USD
     * @param _tokenAddr Address of the token to get the price for
     * @return Amount of tokens equivalent to 1 USD
     */
    function getPrice(address _tokenAddr) public view returns (uint256) {
        address priceFeedAddr = priceFeedAddresses[_tokenAddr];

        if (priceFeedAddr == address(0)) {
            // If no price feed is set for this token, return a default value. For test purposes
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
     *      Takes into account the user's current balance and the maximum allowed tokens per address
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
 *      Extends ERC20 to manage token distribution and control transfers
 */
contract TotemToken is ERC20, ERC20Burnable, ERC20Permit {
    // State variables
    bool private salePeriod; // Indicates if the token is in the sale period (transfers restricted)

    // Immutable variables
    address public immutable totemDistributor; // Address of the distributor, the only one who can transfer tokens during sale period

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
     * @param _totemDistributor The address of the token distributor
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _totemDistributor
    ) ERC20(_name, _symbol) ERC20Permit(_name) {
        if (_totemDistributor == address(0)) revert InvalidAddress();

        totemDistributor = _totemDistributor;

        // Mint all tokens at once and assign them to the distributor
        _mint(_totemDistributor, 1_000_000_000 ether);

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
        // During sale period, only the distributor can transfer tokens
        // Burning (transfer to address(0)) is also restricted during sale period
        if (salePeriod && msg.sender != totemDistributor) {
            revert NotAllowedInSalePeriod();
        }

        super._update(_from, _to, _value);
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
 *      Handles the lifecycle of a Totem, including token burning after sale period and merit distribution
 */
contract Totem is AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for TotemToken;

    // State variables - Tokens
    TotemToken private totemToken;
    IERC20 private paymentToken;
    IERC20 private liquidityToken;
    IERC20 private mythoToken;

    // State variables - Data
    bytes private dataHash;

    // State variables - Addresses
    address private treasuryAddr;
    address private totemDistributorAddr;
    address private meritManagerAddr;
    address private owner;
    address[] private collaborators;
    address private registryAddr;

    // State variables - Flags
    bool private isCustomToken;
    bool private salePeriodEnded;

    // Constants
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
    error NothingToDistribute();
    error ZeroAmount();
    error ZeroCirculatingSupply();
    error InvalidParams();
    error TotemsPaused();
    error EcosystemPaused();

    /**
     * @notice Modifier to check if Totems are paused or if the ecosystem is paused in the AddressRegistry
     */
    modifier whenNotPaused() {
        if (AddressRegistry(registryAddr).areTotemsPaused())
            revert TotemsPaused();
        if (AddressRegistry(registryAddr).isEcosystemPaused())
            revert EcosystemPaused();
        _;
    }

    /**
     * @notice Initializes the Totem contract with token addresses, data hash, and revenue pool
     *      Sets up the initial state and grants roles
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
        if (
            address(_totemToken) == address(0) ||
            _registryAddr == address(0) ||
            _owner == address(0) ||
            _dataHash.length == 0
        ) revert InvalidParams();

        __AccessControl_init();

        totemToken = _totemToken;
        dataHash = _dataHash;

        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();
        totemDistributorAddr = AddressRegistry(_registryAddr)
            .getTotemTokenDistributor();
        meritManagerAddr = AddressRegistry(_registryAddr).getMeritManager();
        mythoToken = IERC20(AddressRegistry(_registryAddr).getMythoToken());

        isCustomToken = _isCustomToken;
        salePeriodEnded = false; // Initially, sale period is active
        registryAddr = _registryAddr;

        // Set owner and collaborators
        owner = _owner;
        collaborators = _collaborators;

        if (_isCustomToken) {
            paymentToken = IERC20(
                TotemTokenDistributor(totemDistributorAddr).getPaymentToken()
            );
        }

        _grantRole(TOTEM_DISTRIBUTOR, totemDistributorAddr);
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Allows TotemToken holders to burn or transfer their tokens and receive proportional shares of assets
     *      After the sale period ends, burns TotemTokens for standard tokens or transfers custom tokens to treasuryAddr.
     *      User receives proportional shares of payment tokens, MYTHO tokens, and LP tokens based on circulating supply.
     * @param _totemTokenAmount The amount of TotemToken to burn or transfer
     */
    function burnTotemTokens(uint256 _totemTokenAmount) external whenNotPaused {
        if (!isCustomToken && !salePeriodEnded) revert SalePeriodNotEnded();
        if (totemToken.balanceOf(msg.sender) < _totemTokenAmount)
            revert InsufficientTotemBalance();
        if (_totemTokenAmount == 0) revert ZeroAmount();

        // Get the circulating supply using the dedicated function
        uint256 circulatingSupply = getCirculatingSupply();
        if (circulatingSupply == 0) revert ZeroCirculatingSupply();

        // Check balances of all token types
        uint256 paymentTokenBalance = address(paymentToken) != address(0)
            ? paymentToken.balanceOf(address(this))
            : 0;
        uint256 mythoBalance = mythoToken.balanceOf(address(this));
        uint256 lpBalance = address(liquidityToken) != address(0)
            ? liquidityToken.balanceOf(address(this))
            : 0;

        // Check if all balances are zero
        if (paymentTokenBalance == 0 && mythoBalance == 0 && lpBalance == 0) {
            revert NothingToDistribute();
        }

        // Calculate user share for each token type based on circulating supply
        uint256 paymentAmount = (paymentTokenBalance * _totemTokenAmount) /
            circulatingSupply;
        uint256 mythoAmount = (mythoBalance * _totemTokenAmount) /
            circulatingSupply;
        uint256 lpAmount = (lpBalance * _totemTokenAmount) / circulatingSupply;

        // Take TotemTokens from the caller
        totemToken.safeTransferFrom(
            msg.sender,
            address(this),
            _totemTokenAmount
        );

        // Handle token disposal based on whether it's a custom token
        if (isCustomToken) {
            // For custom tokens, transfer to treasuryAddr instead of burning
            totemToken.safeTransfer(treasuryAddr, _totemTokenAmount);
        } else {
            // For standard TotemTokens, burn them
            totemToken.burn(_totemTokenAmount);
        }

        // Transfer the proportional payment tokens to the caller if there are any
        if (paymentAmount > 0) {
            paymentToken.safeTransfer(msg.sender, paymentAmount);
        }

        // Transfer MYTHO tokens if there are any
        if (mythoAmount > 0) {
            mythoToken.safeTransfer(msg.sender, mythoAmount);
        }

        // Transfer LP tokens if there are any
        if (lpAmount > 0 && address(liquidityToken) != address(0)) {
            liquidityToken.safeTransfer(msg.sender, lpAmount);
        }

        emit TotemTokenBurned(
            msg.sender,
            _totemTokenAmount,
            paymentAmount,
            mythoAmount,
            lpAmount
        );
    }

    /**
     * @notice Collects accumulated MYTHO from MeritManager for a specific period
     * @param _periodNum The period number to collect rewards for
     */
    function collectMYTH(uint256 _periodNum) public whenNotPaused {
        MeritManager(meritManagerAddr).claimMytho(_periodNum);
        emit MythoCollected(msg.sender, _periodNum);
    }

    /**
     * @notice Sets the payment token and liquidity token addresses and ends the sale period
     *      Should be called by TotemTokenDistributor after sale period ends
     * @param _paymentToken The address of the payment token contract
     * @param _liquidityToken The address of the liquidity token (LP token)
     */
    function closeSalePeriod(
        IERC20 _paymentToken,
        IERC20 _liquidityToken
    ) external onlyRole(TOTEM_DISTRIBUTOR) whenNotPaused {
        paymentToken = _paymentToken;
        liquidityToken = _liquidityToken;
        salePeriodEnded = true;

        emit SalePeriodEnded();
    }

    // VIEW FUNCTIONS

    /**
     * @notice Get the data hash associated with this Totem
     *      Returns the data hash that was set during initialization
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
    function getTokenAddresses()
        external
        view
        returns (
            address totemTokenAddr,
            address paymentTokenAddr,
            address liquidityTokenAddr
        )
    {
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
    function getAllBalances()
        external
        view
        returns (
            uint256 totemBalance,
            uint256 paymentBalance,
            uint256 liquidityBalance,
            uint256 mythoBalance
        )
    {
        totemBalance = totemToken.balanceOf(address(this));
        paymentBalance = address(paymentToken) != address(0)
            ? paymentToken.balanceOf(address(this))
            : 0;
        liquidityBalance = address(liquidityToken) != address(0)
            ? liquidityToken.balanceOf(address(this))
            : 0;

        address mythoAddr = AddressRegistry(registryAddr).getMythoToken();
        mythoBalance = mythoAddr != address(0)
            ? IERC20(mythoAddr).balanceOf(address(this))
            : 0;

        return (totemBalance, paymentBalance, liquidityBalance, mythoBalance);
    }

    /**
     * @notice Check if this is a custom token Totem
     * @return True if this is a custom token Totem, false otherwise
     */
    function isCustomTotemToken() external view returns (bool) {
        return isCustomToken;
    }

    /**
     * @notice Get the owner of this Totem
     * @return The address of the Totem owner
     */
    function getOwner() external view returns (address) {
        return owner;
    }

    /**
     * @notice Get the collaborator at the specified index
     * @param _index Index in the collaborators array
     * @return The address of the collaborator
     */
    function getCollaborator(uint256 _index) external view returns (address) {
        require(_index < collaborators.length, "Index out of bounds");
        return collaborators[_index];
    }

    /**
     * @notice Get all collaborators of this Totem
     * @return Array of collaborator addresses
     */
    function getAllCollaborators() external view returns (address[] memory) {
        return collaborators;
    }

    /**
     * @notice Check if the sale period has ended
     * @return True if the sale period has ended, false otherwise
     */
    function isSalePeriodEnded() external view returns (bool) {
        return salePeriodEnded;
    }

    /**
     * @notice Get the circulating supply of the TotemToken
     * @return The circulating supply (total supply minus tokens held by Totem and Treasury for custom tokens)
     */
    function getCirculatingSupply() public view returns (uint256) {
        uint256 totalSupply = totemToken.totalSupply();
        uint256 totemBalance = totemToken.balanceOf(address(this));
        uint256 treasuryBalance = isCustomToken
            ? totemToken.balanceOf(treasuryAddr)
            : 0;
        return totalSupply - totemBalance - treasuryBalance;
    }
}

// --- src/MYTHO.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AddressRegistry} from "./AddressRegistry.sol";

/**
 * @title MYTHO Government Token (Upgradeable)
 */
contract MYTHO is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    OwnableUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // Token distribution
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens with 18 decimals

    // Totem incentives distribution (50% of total supply)
    uint256 public constant MERIT_YEAR_1 = 200_000_000 * 10 ** 18; // 40% of incentives
    uint256 public constant MERIT_YEAR_2 = 150_000_000 * 10 ** 18; // 30% of incentives
    uint256 public constant MERIT_YEAR_3 = 100_000_000 * 10 ** 18; // 20% of incentives
    uint256 public constant MERIT_YEAR_4 = 50_000_000 * 10 ** 18; // 10% of incentives

    // Team allocation (20% of total supply)
    uint256 public constant TEAM_ALLOCATION = 200_000_000 * 10 ** 18;

    // Treasury allocation (23% of total supply - includes previous airdrop allocation)
    uint256 public constant TREASURY_ALLOCATION = 230_000_000 * 10 ** 18;

    // Mytho AMM incentives (7% of total supply)
    uint256 public constant AMM_INCENTIVES = 70_000_000 * 10 ** 18;

    // Vesting duration
    uint64 public constant ONE_YEAR = 12 * 30 days;
    uint64 public constant TWO_YEARS = 2 * ONE_YEAR;
    uint64 public constant FOUR_YEARS = 4 * ONE_YEAR;

    // Vesting wallet and recipient addresses
    address public meritVestingYear1;
    address public meritVestingYear2;
    address public meritVestingYear3;
    address public meritVestingYear4;
    address public teamVesting;
    address public ammVesting;
    address public treasury;

    // Registry address
    address public registryAddr;

    // Custom errors
    error ZeroAddressNotAllowed(string receiverType);
    error InvalidAmount(uint256 amount);
    error EcosystemPaused();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

/**
 * @notice Initializes the MYTHO token contract
 * @param _meritManager Address to receive totem incentives
 * @param _teamReceiver Address to receive team allocation
 * @param _treasuryReceiver Address to receive treasury allocation
 * @param _ammReceiver Address to receive AMM incentives
 * @param _registryAddr Address of the registry contract
 */
function initialize(
    address _meritManager,
    address _teamReceiver,
    address _treasuryReceiver,
    address _ammReceiver,
    address _registryAddr
) public initializer {
        __ERC20_init("MYTHO Government Token", "MYTHO");
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);

        if (_meritManager == address(0))
            revert ZeroAddressNotAllowed("totem receiver");
        if (_teamReceiver == address(0))
            revert ZeroAddressNotAllowed("team receiver");
        if (_treasuryReceiver == address(0))
            revert ZeroAddressNotAllowed("treasury receiver");
        if (_ammReceiver == address(0))
            revert ZeroAddressNotAllowed("AMM receiver");
        if (_registryAddr == address(0))
            revert ZeroAddressNotAllowed("registry");

        // Set the start timestamp for vesting
        uint64 startTimestamp = uint64(block.timestamp);

        // Create vesting wallets for totem incentives (4 years)
        meritVestingYear1 = address(
            new VestingWallet(_meritManager, startTimestamp, ONE_YEAR)
        );
        meritVestingYear2 = address(
            new VestingWallet(
                _meritManager,
                startTimestamp + ONE_YEAR,
                ONE_YEAR
            )
        );
        meritVestingYear3 = address(
            new VestingWallet(
                _meritManager,
                startTimestamp + 2 * ONE_YEAR,
                ONE_YEAR
            )
        );
        meritVestingYear4 = address(
            new VestingWallet(
                _meritManager,
                startTimestamp + 3 * ONE_YEAR,
                ONE_YEAR
            )
        );

        // Create vesting wallet for team (2 years)
        teamVesting = address(
            new VestingWallet(_teamReceiver, startTimestamp, TWO_YEARS)
        );

        // Create vesting wallet for AMM incentives (2 years)
        ammVesting = address(
            new VestingWallet(_ammReceiver, startTimestamp, TWO_YEARS)
        );

        // Treasury (no vesting, immediate access)
        treasury = _treasuryReceiver;
        
        // Set registry address
        registryAddr = _registryAddr;

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

    // ADMIN FUNCTIONS
    
    /**
     * @notice Pauses all token transfers
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Throws if the contract is paused or if the ecosystem is paused.
     */
    function _requireNotPaused() internal view virtual override {
        super._requireNotPaused();
        if (registryAddr != address(0) && AddressRegistry(registryAddr).isEcosystemPaused()) {
            revert EcosystemPaused();
        }
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Internal function to update token balances
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

// --- src/Treasury.sol ---
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Treasury
 * @notice This contract manages and withdraws ERC20 and native tokens.
 * It provides functionality to:
 * - Withdraw ERC20 tokens to specified addresses
 * - Withdraw native tokens to specified addresses
 * - Check balances of ERC20 and native tokens
 */
contract Treasury is AccessControlUpgradeable {
    // Constants
    bytes32 private constant MANAGER = keccak256("MANAGER");

    // Events
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event NativeWithdrawn(address indexed to, uint256 amount);

    // Custom errors
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);
    error NativeTransferFailed();

    function initialize() public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Withdraws ERC20 tokens, restricted to MANAGER
     * @param _token Address of the ERC20 token to withdraw
     * @param _to Recipient address
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawERC20(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyRole(MANAGER) {
        if (_token == address(0) || _to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance < _amount) revert InsufficientBalance(_amount, balance);
        IERC20(_token).transfer(_to, _amount);
        emit ERC20Withdrawn(_token, _to, _amount);
    }

    /**
     * @notice Withdraws native tokens, restricted to MANAGER
     * @param _to Recipient address (payable)
     * @param _amount Amount of native tokens to withdraw (in wei)
     */
    function withdrawNative(
        address payable _to,
        uint256 _amount
    ) external onlyRole(MANAGER) {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        if (address(this).balance < _amount) revert InsufficientBalance(_amount, address(this).balance);
        
        (bool success, ) = _to.call{value: _amount}("");
        if (!success) revert NativeTransferFailed();
        
        emit NativeWithdrawn(_to, _amount);
    }

    /**
     * @notice Allows contract to receive native tokens
     */
    receive() external payable {}

    // VIEW FUNCTIONS

    /**
     * @notice Returns balance of a specific ERC20 token
     * @param _token Address of the ERC20 token
     * @return Token balance of the contract
     */
    function getERC20Balance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /**
     * @notice Returns native token balance
     * @return Native token balance of the contract (in wei)
     */
    function getNativeBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
