// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";

import {AddressRegistry} from "./AddressRegistry.sol";

/**
 * @title MeritManager
 * @dev Manages merit points for registered totems and distributes MYTHO tokens based on merit.
 * Includes features like totem registration, merit crediting, boosting, and claiming rewards.
 */
contract MeritManager is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;    

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
    mapping(uint256 period => bool isClaimed) public isClaimed; // Whether rewards have been claimed for a period
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
            payable(msg.sender).transfer(msg.value - boostFee);
        } else {
            // Transfer boost fee to revenue pool
            payable(treasuryAddr).transfer(boostFee);
        }

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
        if (isClaimed[_periodNum]) revert AlreadyClaimed(_periodNum);
        if (_periodNum > currentPeriod()) revert InvalidPeriod();

        _updateState();

        if (
            totemMerit[_periodNum][totemAddr] == 0 ||
            totalMeritPoints[_periodNum] == 0 ||
            releasedMytho[_periodNum] == 0
        ) revert NoMythoToClaim();

        uint256 totalPoints = totalMeritPoints[_periodNum];
        uint256 totemPoints = totemMerit[_periodNum][totemAddr];

        isClaimed[_periodNum] = true;

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
        if (_currentPeriod > lastProcessedPeriod + 1) {
            // Process all completed periods up to but not including the current period
            for (
                uint256 period = lastProcessedPeriod + 1;
                period < _currentPeriod;
                period++
            ) {
                releasedMytho[period] = vestingWalletsAllocation[yearIdx] / 12;
                emit MythoReleased(releasedMytho[period], period);
            }

            wallet.release(address(mythoToken));
            lastProcessedPeriod = _currentPeriod - 1; // Set the last processed period to the previous period
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
            isClaimed[_periodNum] ||
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
        _updateState();
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
        _updateState();
        mythumMultiplier = _mythumMultiplier;
        emit ParameterUpdated("mythumMultiplier", _mythumMultiplier);
    }

    /**
     * @dev Sets the boost fee in native tokens
     * @param _boostFee New boost fee
     */
    function setBoostFee(uint256 _boostFee) external onlyRole(MANAGER) {
        _updateState();
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
        _updateState();
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
