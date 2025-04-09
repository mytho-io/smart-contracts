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
