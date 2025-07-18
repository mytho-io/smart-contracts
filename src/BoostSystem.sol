// SPDX-License-Identifier: BUSL-1.1
// Copyright © 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IVRFCoordinatorV2Plus} from "@ccip/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

import {VRFV2PlusClient} from "@ccip/vrf/dev/libraries/VRFV2PlusClient.sol";

import {AddressRegistry} from "./AddressRegistry.sol";
import {TotemFactory} from "./TotemFactory.sol";
import {MeritManager} from "./MeritManager.sol";
import {BadgeNFT} from "./BadgeNFT.sol";

/**
 * @title BoostSystem
 * @notice Core boost functionality with streak system, grace days, NFT badges, and ChainLink VRF integration
 * @dev Implements daily free boosts and premium boosts with signature verification and milestone achievements
 */

contract BoostSystem is AccessControlUpgradeable, PausableUpgradeable {
    MeritManager private meritManager;
    TotemFactory private factory;

    // VRF Configuration
    IVRFCoordinatorV2Plus private vrfCoordinator;
    uint256 private vrfSubscriptionId;
    bytes32 private vrfKeyHash;
    uint32 private vrfCallbackGasLimit;
    uint16 private vrfRequestConfirmations;
    uint32 private vrfNumWords;

    // State variables
    address private registryAddr;
    uint256 private minTotemTokensAmountForBoost;
    uint256 private freeBoostCooldown; // Time between free boosts
    uint256 private premiumBoostGracePeriod; // Time between premium boosts to earn grace days

    // Premium boost configuration
    uint256 private premiumBoostPrice;
    address private treasury;

    // Base merit points
    uint256 private boostRewardPoints; // Merit points awarded for boosting a totem

    // Frontend signature verification
    address private frontendSigner; // Address that signs frontend requests
    uint256 private signatureValidityWindow; // Time window for signature validity (default: 5 minutes)

    // NFT Badge system
    BadgeNFT private badgeNFT; // Badge NFT contract
    uint256[] private milestones; // Available milestones: [7, 14, 30, 100, 200]

    // Mappings
    mapping(address user => mapping(address totemAddr => BoostData)) private boosts; // prettier-ignore
    mapping(uint256 requestId => PendingBoost) private pendingBoosts;
    mapping(bytes32 signatureHash => bool used) private usedSignatures; // Prevent signature replay
    mapping(address user => mapping(uint256 milestone => uint256 availableBadges))
        private availableBadges; // Available badges for minting per user per milestone
    mapping(address user => mapping(address totemAddr => mapping(uint256 periodNum => uint256 meritAmount))) 
        public userTotemPeriodMerit; // Individual user merit contribution per totem per period
    mapping(address user => mapping(uint256 periodNum => uint256 totalMerit)) 
        public userTotalPeriodMerit; // Total user merit contribution per period across all totems

    // Structs
    struct BoostData {
        uint256 lastBoostTimestamp;
        uint256 lastPremiumBoostTimestamp;
        uint256 streakStartPoint;
        uint256 graceDaysWasted;
        uint256 graceDaysEarned;
        uint256 graceDaysFromStreak; // Track grace days earned from streak separately
        uint256 releasedBadges; // Number of badge releases (milestone achievements)
    }

    struct PendingBoost {
        address user;
        address totemAddr;
        uint256 baseReward;
    }

    // Constants - Roles
    bytes32 public constant MANAGER = keccak256("MANAGER");

    // Errors
    error TotemNotFound();
    error NotEnoughTokens();
    error NotEnoughTimePassedForFreeBoost();
    error InsufficientPayment();
    error TreasuryNotSet();
    error VRFNotConfigured();
    error OnlyCoordinatorCanFulfill(address have, address want);
    error InvalidSignature();
    error SignatureExpired();
    error SignatureAlreadyUsed();
    error FrontendSignerNotSet();
    error BadgeNFTNotSet();
    error MilestoneNotAchieved();

    // Events
    event ParameterUpdated(string indexed parameter, uint256 value);
    event TotemBoosted(address indexed user, address indexed totemAddr);
    event PremiumBoostPurchased(address indexed user, address indexed totemAddr, uint256 requestId, uint256 price); // prettier-ignore
    event PremiumBoostCompleted(address indexed user, address indexed totemAddr, uint256 baseReward, uint256 bonusReward, uint256 totalReward); // prettier-ignore
    event GraceDayEarned(address indexed user, address indexed totemAddr, uint256 graceDaysEarned); // prettier-ignore
    event MilestoneAchieved(address indexed user, address indexed totemAddr, uint256 milestone, uint256 streakDays); // prettier-ignore
    event BadgeMinted(address indexed user, address indexed totemAddr, uint256 milestone, uint256 tokenId); // prettier-ignore
    event UserMeritCredited(address indexed user, address indexed totemAddr, uint256 amount, uint256 period); // prettier-ignore

    /**
     * @notice Initialize the BoostSystem contract
     * @param _registryAddr Address of the AddressRegistry contract
     * @param _vrfCoordinator Address of the VRF Coordinator contract
     * @param _vrfSubscriptionId VRF subscription ID
     * @param _vrfKeyHash VRF key hash for randomness requests
     * @dev This function replaces the constructor for upgradeable contracts
     */
    function initialize(
        address _registryAddr,
        address _vrfCoordinator,
        uint256 _vrfSubscriptionId,
        bytes32 _vrfKeyHash
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        // Set up contract instances
        registryAddr = _registryAddr;
        meritManager = MeritManager(
            AddressRegistry(registryAddr).getMeritManager()
        );
        factory = TotemFactory(AddressRegistry(registryAddr).getTotemFactory());
        treasury = AddressRegistry(registryAddr).getMythoTreasury();
        badgeNFT = BadgeNFT(AddressRegistry(registryAddr).getBadgeNFT());

        // VRF Configuration - Initialize manually since we can't use constructor in upgradeable contract
        if (_vrfCoordinator == address(0)) revert VRFNotConfigured();
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        vrfSubscriptionId = _vrfSubscriptionId;
        vrfKeyHash = _vrfKeyHash;
        vrfCallbackGasLimit = 100000;
        vrfRequestConfirmations = 3;
        vrfNumWords = 1;

        // default values
        minTotemTokensAmountForBoost = 1e18;
        freeBoostCooldown = 1 days;
        boostRewardPoints = 100; // 100 merit points for boost
        premiumBoostPrice = 5e16; // Base price of premium boost
        premiumBoostGracePeriod = 24 hours; // Default period for premium boost grace days
        signatureValidityWindow = 5 minutes; // Default signature validity window

        // Initialize milestones for NFT badges
        milestones.push(7);
        milestones.push(14);
        milestones.push(30);
        milestones.push(100);
        milestones.push(200);

        // deployment todo
        // Treasury address is initialized from AddressRegistry.getMythoTreasury()
        // frontendSigner needs to be set by admin after deployment
        // badgeNFT needs to be set by admin after deployment
    }

    // MODIFIERS

    /**
     * @notice Modifier to check if totem is valid and user has enough tokens
     * @param _totemAddr Address of the totem to validate
     * @dev Reverts if totem doesn't exist or user doesn't have required tokens
     */
    modifier checkValidity(address _totemAddr) {
        _checkValidity(_totemAddr);
        _;
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Perform a free daily boost on a totem
     * @param _totemAddr Address of the totem to boost
     * @param _timestamp Timestamp used for signature verification
     * @param _signature Frontend signature for verification
     * @dev Requires valid signature from frontend signer and respects boost interval
     */
    function boost(
        address _totemAddr,
        uint256 _timestamp,
        bytes calldata _signature
    ) external checkValidity(_totemAddr) whenNotPaused {
        // Verify signature for boost function
        _verifySignature(_totemAddr, _timestamp, _signature);

        BoostData storage boostData = boosts[msg.sender][_totemAddr];
        if (boostData.lastBoostTimestamp + freeBoostCooldown > block.timestamp)
            revert NotEnoughTimePassedForFreeBoost();

        _updateStreakStartPoint(_totemAddr);
        boostData.lastBoostTimestamp = block.timestamp;

        // Check for badge achievements after updating streak
        _checkBadgesAfterBoost(_totemAddr);

        uint256 streakPoints = _getStreakPoints(_totemAddr, boostRewardPoints);

        // Record user merit contribution
        uint256 currentPeriod = meritManager.currentPeriod();
        userTotemPeriodMerit[msg.sender][_totemAddr][currentPeriod] += streakPoints;
        userTotalPeriodMerit[msg.sender][currentPeriod] += streakPoints;

        // credit merit points
        meritManager.boostReward(_totemAddr, streakPoints);

        emit TotemBoosted(msg.sender, _totemAddr);
        emit UserMeritCredited(msg.sender, _totemAddr, streakPoints, currentPeriod);
    }

    /**
     * @notice Perform a premium boost on a totem with ETH payment
     * @param _totemAddr Address of the totem to boost
     * @dev Uses ChainLink VRF for random reward calculation, grants grace days, and applies streak multiplier
     */
    function premiumBoost(
        address _totemAddr
    ) external payable checkValidity(_totemAddr) whenNotPaused {
        if (treasury == address(0)) revert TreasuryNotSet();
        if (address(vrfCoordinator) == address(0)) revert VRFNotConfigured();
        if (msg.value < premiumBoostPrice) revert InsufficientPayment();

        BoostData storage boostData = boosts[msg.sender][_totemAddr];

        // Return change to user if they sent more than required
        uint256 change = msg.value - premiumBoostPrice;
        if (change > 0) {
            Address.sendValue(payable(msg.sender), change);
        }

        // Process payment in native tokens (ETH) using Address library
        Address.sendValue(payable(treasury), premiumBoostPrice);

        // Update streak system
        _updateStreakStartPoint(_totemAddr);

        // Check for badge achievements after updating streak
        _checkBadgesAfterBoost(_totemAddr);

        // Grant grace day if premiumBoostGracePeriod time passed since last premium boost
        if (
            block.timestamp - boostData.lastPremiumBoostTimestamp >= premiumBoostGracePeriod
        ) {
            boostData.graceDaysEarned++;
            emit GraceDayEarned(msg.sender, _totemAddr, boostData.graceDaysEarned);
        } // prettier-ignore

        boostData.lastPremiumBoostTimestamp = block.timestamp;

        // Request VRF for base reward amount using V2Plus format
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: vrfNumWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = vrfCoordinator.requestRandomWords(req);

        // Store pending boost info (streak will be applied after VRF determines base reward)
        pendingBoosts[requestId] = PendingBoost({
            user: msg.sender,
            totemAddr: _totemAddr,
            baseReward: 0 // Will be determined by VRF
        });

        emit PremiumBoostPurchased(
            msg.sender,
            _totemAddr,
            requestId,
            premiumBoostPrice
        );
    }

    /**
     * @notice Mint badge for achieved milestone
     * @param _milestone Milestone to mint badge for (7, 14, 30, 100, 200)
     */
    function mintBadge(uint256 _milestone) external whenNotPaused {
        if (address(badgeNFT) == address(0)) revert BadgeNFTNotSet();

        // Check if milestone is valid
        bool validMilestone = false;
        for (uint256 i = 0; i < milestones.length; i++) {
            if (milestones[i] == _milestone) {
                validMilestone = true;
                break;
            }
        }
        if (!validMilestone) revert MilestoneNotAchieved();

        // Check if user has available badges for this milestone
        if (availableBadges[msg.sender][_milestone] == 0) {
            revert MilestoneNotAchieved();
        }

        // Decrease available badge count
        availableBadges[msg.sender][_milestone]--;

        // Mint badge
        uint256 tokenId = badgeNFT.mintBadge(msg.sender, _milestone);

        emit BadgeMinted(msg.sender, address(0), _milestone, tokenId);
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Sets the minimum totem tokens amount required for boost
     * @param _minTotemTokensAmountForBoost New minimum token amount
     * @dev Only applies to ERC20 tokens, ERC721 tokens require balance > 0
     */
    function setMinTotemTokensAmountForBoost(
        uint256 _minTotemTokensAmountForBoost
    ) external onlyRole(MANAGER) {
        minTotemTokensAmountForBoost = _minTotemTokensAmountForBoost;
        emit ParameterUpdated(
            "minTotemTokensAmountForBoost",
            _minTotemTokensAmountForBoost
        );
    }

    /**
     * @notice Sets the free boost cooldown (time between free boosts)
     * @param _freeBoostCooldown New free boost cooldown in seconds (default: 1 day)
     * @dev This affects how often users can perform free boosts
     */
    function setFreeBoostCooldown(
        uint256 _freeBoostCooldown
    ) external onlyRole(MANAGER) {
        freeBoostCooldown = _freeBoostCooldown;
        emit ParameterUpdated("freeBoostCooldown", _freeBoostCooldown);
    }

    /**
     * @notice Sets the premium boost grace period (time between premium boosts to earn grace days)
     * @param _premiumBoostGracePeriod New premium boost grace period in seconds (default: 24 hours)
     * @dev Grace days from premium boost are earned if premiumBoostGracePeriod time passed since last premium boost
     */
    function setPremiumBoostGracePeriod(
        uint256 _premiumBoostGracePeriod
    ) external onlyRole(MANAGER) {
        premiumBoostGracePeriod = _premiumBoostGracePeriod;
        emit ParameterUpdated(
            "premiumBoostGracePeriod",
            _premiumBoostGracePeriod
        );
    }

    /**
     * @notice Sets the boost reward points
     * @param _boostRewardPoints New boost reward points
     */
    function setBoostRewardPoints(
        uint256 _boostRewardPoints
    ) external onlyRole(MANAGER) {
        boostRewardPoints = _boostRewardPoints;
        emit ParameterUpdated("boostRewardPoints", _boostRewardPoints);
    }

    /**
     * @notice Sets the premium boost price
     * @param _premiumBoostPrice New premium boost price in payment token
     */
    function setPremiumBoostPrice(
        uint256 _premiumBoostPrice
    ) external onlyRole(MANAGER) {
        premiumBoostPrice = _premiumBoostPrice;
        emit ParameterUpdated("premiumBoostPrice", _premiumBoostPrice);
    }

    /**
     * @notice Sets the treasury address for premium boost payments
     * @param _treasury Address of the treasury
     * @dev This overrides the treasury address initialized from AddressRegistry
     */
    function setTreasury(address _treasury) external onlyRole(MANAGER) {
        treasury = _treasury;
        emit ParameterUpdated("treasury", uint256(uint160(_treasury)));
    }

    /**
     * @notice Updates VRF configuration
     * @param _vrfCoordinator VRF Coordinator address
     * @param _vrfSubscriptionId VRF subscription ID
     * @param _vrfKeyHash VRF key hash
     * @param _vrfCallbackGasLimit Gas limit for VRF callback
     */
    function updateVRFConfig(
        address _vrfCoordinator,
        uint256 _vrfSubscriptionId,
        bytes32 _vrfKeyHash,
        uint32 _vrfCallbackGasLimit
    ) external onlyRole(MANAGER) {
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        vrfSubscriptionId = _vrfSubscriptionId;
        vrfKeyHash = _vrfKeyHash;
        vrfCallbackGasLimit = _vrfCallbackGasLimit;
        emit ParameterUpdated("vrfCallbackGasLimit", _vrfCallbackGasLimit);
    }

    /**
     * @notice Sets the frontend signer address
     * @param _frontendSigner Address that signs frontend requests
     */
    function setFrontendSigner(
        address _frontendSigner
    ) external onlyRole(MANAGER) {
        frontendSigner = _frontendSigner;
        emit ParameterUpdated("frontendSigner", uint256(uint160(_frontendSigner))); // prettier-ignore
    }

    /**
     * @notice Sets the signature validity window
     * @param _signatureValidityWindow Time window for signature validity in seconds
     */
    function setSignatureValidityWindow(
        uint256 _signatureValidityWindow
    ) external onlyRole(MANAGER) {
        signatureValidityWindow = _signatureValidityWindow;
        emit ParameterUpdated("signatureValidityWindow", _signatureValidityWindow); // prettier-ignore
    }

    /**
     * @notice Sets the badge NFT contract address
     * @param _badgeNFT Address of the badge NFT contract
     */
    function setBadgeNFT(address _badgeNFT) external onlyRole(MANAGER) {
        badgeNFT = BadgeNFT(_badgeNFT);
        emit ParameterUpdated("badgeNFT", uint256(uint160(_badgeNFT)));
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Updates streak start point and handles grace day logic
     * @param _totemAddr Address of the totem
     * @dev Manages streak continuation, grace day consumption, and streak reset logic
     */
    function _updateStreakStartPoint(address _totemAddr) internal {
        BoostData storage boostData = boosts[msg.sender][_totemAddr];

        // For existing streaks, check if the last boost was less than 2 boost intervals ago
        if (
            boostData.streakStartPoint != 0 && (
                block.timestamp - boostData.lastBoostTimestamp < freeBoostCooldown * 2 ||
                block.timestamp - boostData.lastPremiumBoostTimestamp < freeBoostCooldown * 2
            )
        ) return;

        // Calculate how many grace days should be earned from 30-day streaks
        if (boostData.streakStartPoint != 0) {
            uint256 streakDays = (block.timestamp - boostData.streakStartPoint) / freeBoostCooldown + 1;
            uint256 expectedGraceDaysFromStreak = streakDays / 30;

            // Add new grace days from streak (only add the difference)
            if (expectedGraceDaysFromStreak > boostData.graceDaysFromStreak) {
                uint256 newGraceDaysFromStreak = expectedGraceDaysFromStreak - boostData.graceDaysFromStreak;
                boostData.graceDaysFromStreak = expectedGraceDaysFromStreak;
                boostData.graceDaysEarned += newGraceDaysFromStreak;
                emit GraceDayEarned(msg.sender, _totemAddr, boostData.graceDaysEarned);
            }
        }

        // if user has available grace days, consume one instead of resetting streak
        if (boostData.graceDaysEarned > boostData.graceDaysWasted) {
            boostData.graceDaysWasted++;
            return;
        }

        // reset streak
        boostData.graceDaysWasted = 0;
        boostData.graceDaysEarned = 0;
        boostData.graceDaysFromStreak = 0;
        boostData.releasedBadges = 0; // Reset badge counter for new streak
        boostData.streakStartPoint = block.timestamp;
    } // prettier-ignore

    /**
     * @notice Calculate streak points for current user
     * @param _totemAddr Address of the totem
     * @param _basePoints Base points before streak multiplier
     * @return Calculated points with streak multiplier applied
     */
    function _getStreakPoints(
        address _totemAddr,
        uint256 _basePoints
    ) internal view returns (uint256) {
        return _getStreakPointsForUser(msg.sender, _totemAddr, _basePoints);
    }

    /**
     * @notice Calculate streak points for specific user
     * @param _user User address
     * @param _totemAddr Address of the totem
     * @param _basePoints Base points before streak multiplier
     * @return Calculated points with streak multiplier applied (max 30 days streak)
     */
    function _getStreakPointsForUser(
        address _user,
        address _totemAddr,
        uint256 _basePoints
    ) internal view returns (uint256) {
        BoostData storage boostData = boosts[_user][_totemAddr];
        if (boostData.streakStartPoint == 0) return _basePoints;
        uint256 streak = (block.timestamp - boostData.streakStartPoint) / freeBoostCooldown + 1; // prettier-ignore
        if (streak > 30) streak = 30;
        return (_basePoints * (100 + (streak - 1) * 5)) / 100;
    }

    /**
     * @notice Validates totem existence and user token balance
     * @param _totemAddr Address of the totem to validate
     * @dev Checks if totem exists and user has sufficient tokens (ERC20/ERC721)
     */
    function _checkValidity(address _totemAddr) internal view {
        TotemFactory.TotemData memory data = factory.getTotemDataByAddress(
            _totemAddr
        );

        // check if totem exists
        if (data.totemAddr == address(0)) revert TotemNotFound();

        TotemFactory.TokenType tokenType = data.tokenType;

        // check if user has enough tokens for boost
        if (tokenType == TotemFactory.TokenType.ERC721) {
            if (IERC721(data.totemTokenAddr).balanceOf(msg.sender) == 0)
                revert NotEnoughTokens();
        } else {
            if (
                IERC20(data.totemTokenAddr).balanceOf(msg.sender) <
                minTotemTokensAmountForBoost
            ) revert NotEnoughTokens();
        }
    }

    /**
     * @notice Verifies frontend signature for boost function
     * @param _totemAddr Address of the totem
     * @param _timestamp Timestamp used in signature
     * @param _signature Signature to verify
     * @dev Prevents replay attacks and validates signature from frontend signer
     */
    function _verifySignature(
        address _totemAddr,
        uint256 _timestamp,
        bytes calldata _signature
    ) internal {
        if (frontendSigner == address(0)) revert FrontendSignerNotSet();

        // Check timestamp validity (within signatureValidityWindow)
        if (block.timestamp > _timestamp + signatureValidityWindow)
            revert SignatureExpired();
        if (_timestamp > block.timestamp + signatureValidityWindow)
            revert SignatureExpired(); // Future timestamp protection

        // Create message hash
        bytes32 messageHash = keccak256(
            abi.encodePacked(msg.sender, _totemAddr, _timestamp)
        );

        // Check if signature was already used
        if (usedSignatures[messageHash]) revert SignatureAlreadyUsed();

        // Verify signature
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            messageHash
        );
        address recoveredSigner = ECDSA.recover(
            ethSignedMessageHash,
            _signature
        );

        if (recoveredSigner != frontendSigner) revert InvalidSignature();

        // Mark signature as used
        usedSignatures[messageHash] = true;
    }

    /**
     * @notice Check badges after boost (calculates current streak)
     * @param _totemAddr Totem address
     */
    function _checkBadgesAfterBoost(address _totemAddr) internal {
        BoostData storage boostData = boosts[msg.sender][_totemAddr];

        // Calculate current streak
        uint256 currentStreak = 0;
        if (boostData.streakStartPoint != 0) {
            currentStreak =
                (block.timestamp - boostData.streakStartPoint) /
                freeBoostCooldown +
                1;
        }

        _checkAndReleaseBadges(msg.sender, _totemAddr, currentStreak);
    }

    /**
     * @notice Check and release badges for milestone achievements
     * @param _user User address
     * @param _totemAddr Totem address
     * @param _currentStreak Current streak length
     */
    function _checkAndReleaseBadges(
        address _user,
        address _totemAddr,
        uint256 _currentStreak
    ) internal {
        BoostData storage boostData = boosts[_user][_totemAddr];

        // Count how many milestones should be achieved based on current streak
        uint256 expectedBadges = 0;
        for (uint256 i = 0; i < milestones.length; i++) {
            if (_currentStreak >= milestones[i]) {
                expectedBadges++;
            }
        }

        // If we have more achievements than released badges, release new ones
        if (expectedBadges > boostData.releasedBadges) {
            // Add badges for each milestone from releasedBadges to expectedBadges
            for (
                uint256 i = boostData.releasedBadges;
                i < expectedBadges;
                i++
            ) {
                uint256 milestone = milestones[i];
                availableBadges[_user][milestone]++;

                emit MilestoneAchieved(_user, _totemAddr, milestone, _currentStreak); // prettier-ignore
            }

            // Update released badges counter
            boostData.releasedBadges = expectedBadges;
        }
    }

    // VRF CALLBACK FUNCTION

    /**
     * @notice Callback function used by VRF Coordinator to fulfill random words request
     * @param _requestId The ID of the VRF request
     * @param _randomWords Array of random words returned by VRF
     * @dev Calculates base reward, applies streak multiplier, and credits merit points
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal {
        PendingBoost memory pendingBoost = pendingBoosts[_requestId];
        require(pendingBoost.user != address(0), "Request not found");

        // Get base reward from VRF probabilities
        uint256 baseReward = _calculateBaseReward(_randomWords[0]);

        // Apply streak points calculation consistently with free boost
        // We need to temporarily set msg.sender context for _getStreakPoints
        address originalUser = pendingBoost.user;
        uint256 finalReward = _getStreakPointsForUser(
            originalUser,
            pendingBoost.totemAddr,
            baseReward
        );

        // Record user merit contribution
        uint256 currentPeriod = meritManager.currentPeriod();
        userTotemPeriodMerit[originalUser][pendingBoost.totemAddr][currentPeriod] += finalReward;
        userTotalPeriodMerit[originalUser][currentPeriod] += finalReward;

        // Credit merit points
        meritManager.boostReward(pendingBoost.totemAddr, finalReward);

        // Clean up
        delete pendingBoosts[_requestId];

        emit PremiumBoostCompleted(
            originalUser,
            pendingBoost.totemAddr,
            baseReward,
            finalReward - baseReward, // Streak bonus
            finalReward
        );
        emit UserMeritCredited(originalUser, pendingBoost.totemAddr, finalReward, currentPeriod);
    }

    /**
     * @notice Raw fulfillment function called by VRF Coordinator
     * @param _requestId The ID of the VRF request
     * @param _randomWords Array of random words returned by VRF
     * @dev Only callable by VRF Coordinator, delegates to internal fulfillRandomWords
     */
    function rawFulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) external {
        if (msg.sender != address(vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(
                msg.sender,
                address(vrfCoordinator)
            );
        }
        fulfillRandomWords(_requestId, _randomWords);
    }

    // VIEW FUNCTIONS

    /**
     * @notice Gets the last boost timestamp for a user and totem
     * @param _user User address
     * @param _totemAddr Totem address
     * @return Last boost timestamp
     */
    function getLastBoostTimestamp(
        address _user,
        address _totemAddr
    ) external view returns (uint256) {
        return boosts[_user][_totemAddr].lastBoostTimestamp;
    }

    /**
     * @notice Gets the free boost cooldown (time between free boosts)
     * @return Free boost cooldown in seconds
     */
    function getFreeBoostCooldown() external view returns (uint256) {
        return freeBoostCooldown;
    }

    /**
     * @notice Gets the premium boost grace period (time between premium boosts to earn grace days)
     * @return Premium boost grace period in seconds
     */
    function getPremiumBoostGracePeriod() external view returns (uint256) {
        return premiumBoostGracePeriod;
    }

    /**
     * @notice Gets time remaining before next free boost is available
     * @param _user User address
     * @param _totemAddr Totem address
     * @return Time in seconds before next free boost (0 if available now)
     */
    function getTimeBeforeNextFreeBoost(
        address _user,
        address _totemAddr
    ) external view returns (uint256) {
        return
            boosts[_user][_totemAddr].lastBoostTimestamp +
            freeBoostCooldown -
            block.timestamp;
    }

    /**
     * @notice Gets comprehensive boost data for a user and totem
     * @param _user User address
     * @param _totemAddr Totem address
     * @return lastBoostTimestamp Last free boost timestamp
     * @return lastPremiumBoostTimestamp Last premium boost timestamp
     * @return streakStartPoint Streak start point
     * @return graceDaysEarned Total grace days earned
     * @return graceDaysWasted Grace days used
     * @return graceDaysFromStreak Grace days earned from streak
     */
    function getBoostData(
        address _user,
        address _totemAddr
    )
        external
        view
        returns (
            uint256 lastBoostTimestamp,
            uint256 lastPremiumBoostTimestamp,
            uint256 streakStartPoint,
            uint256 graceDaysEarned,
            uint256 graceDaysWasted,
            uint256 graceDaysFromStreak
        )
    {
        BoostData storage data = boosts[_user][_totemAddr];
        return (
            data.lastBoostTimestamp,
            data.lastPremiumBoostTimestamp,
            data.streakStartPoint,
            data.graceDaysEarned,
            data.graceDaysWasted,
            data.graceDaysFromStreak
        );
    }

    /**
     * @notice Gets current streak information for a user and totem
     * @param _user User address
     * @param _totemAddr Totem address
     * @return streakDays Current streak in days
     * @return streakMultiplier Current streak multiplier (100 = 1.00x, 245 = 2.45x)
     * @return availableGraceDays Available grace days (earned - wasted)
     */
    function getStreakInfo(
        address _user,
        address _totemAddr
    )
        external
        view
        returns (
            uint256 streakDays,
            uint256 streakMultiplier,
            uint256 availableGraceDays
        )
    {
        BoostData storage data = boosts[_user][_totemAddr];

        if (data.streakStartPoint == 0) {
            return (0, 100, 0);
        }

        streakDays =
            (block.timestamp - data.streakStartPoint) /
            freeBoostCooldown +
            1;
        if (streakDays > 30) streakDays = 30;

        streakMultiplier = 100 + (streakDays - 1) * 5;
        availableGraceDays = data.graceDaysEarned - data.graceDaysWasted;
    }

    /**
     * @notice Gets detailed grace days information
     * @param _user User address
     * @param _totemAddr Totem address
     * @return totalGraceDays Total grace days earned
     * @return graceDaysFromStreak Grace days earned from streak
     * @return graceDaysFromPremium Grace days earned from premium boost
     * @return graceDaysWasted Grace days used
     * @return availableGraceDays Available grace days (earned - wasted)
     */
    function getGraceDaysInfo(
        address _user,
        address _totemAddr
    )
        external
        view
        returns (
            uint256 totalGraceDays,
            uint256 graceDaysFromStreak,
            uint256 graceDaysFromPremium,
            uint256 graceDaysWasted,
            uint256 availableGraceDays
        )
    {
        BoostData storage data = boosts[_user][_totemAddr];

        totalGraceDays = data.graceDaysEarned;
        graceDaysFromStreak = data.graceDaysFromStreak;
        graceDaysFromPremium = data.graceDaysEarned - data.graceDaysFromStreak;
        graceDaysWasted = data.graceDaysWasted;
        availableGraceDays = data.graceDaysEarned - data.graceDaysWasted;
    }

    /**
     * @notice Gets premium boost configuration
     * @return price Premium boost price in ETH
     * @return treasuryAddr Treasury address
     */
    function getPremiumBoostConfig()
        external
        view
        returns (uint256 price, address treasuryAddr)
    {
        return (premiumBoostPrice, treasury);
    }

    /**
     * @notice Calculates expected rewards for both boost types
     * @param _user User address
     * @param _totemAddr Totem address
     * @return freeBoostReward Expected free boost reward
     * @return premiumBoostMinReward Minimum premium boost reward (500 points * multiplier)
     * @return premiumBoostMaxReward Maximum premium boost reward (3000 points * multiplier)
     * @return premiumBoostExpectedReward Expected premium boost reward (weighted average * multiplier)
     */
    function getExpectedRewards(
        address _user,
        address _totemAddr
    )
        external
        view
        returns (
            uint256 freeBoostReward,
            uint256 premiumBoostMinReward,
            uint256 premiumBoostMaxReward,
            uint256 premiumBoostExpectedReward
        )
    {
        BoostData storage data = boosts[_user][_totemAddr];
        uint256 streak = 0;

        if (data.streakStartPoint != 0) {
            streak =
                (block.timestamp - data.streakStartPoint) /
                freeBoostCooldown +
                1;
            if (streak > 30) streak = 30;
        }

        uint256 multiplier = 100 + (streak - 1) * 5;

        freeBoostReward = (boostRewardPoints * multiplier) / 100;

        // Premium boost calculations
        premiumBoostMinReward = (500 * multiplier) / 100; // Min: 500 points
        premiumBoostMaxReward = (3000 * multiplier) / 100; // Max: 3000 points

        // Expected value: 500*0.5 + 700*0.25 + 1000*0.15 + 2000*0.07 + 3000*0.03 = 805 points
        uint256 expectedBase = 8050; // 805 * 10 for precision
        premiumBoostExpectedReward = (expectedBase * multiplier) / 1000; // Divide by 1000 (100 for multiplier, 10 for precision)
    }

    /**
     * @notice Gets signature configuration
     * @return frontendSignerAddr Frontend signer address
     * @return validityWindow Signature validity window in seconds
     */
    function getSignatureConfig()
        external
        view
        returns (address frontendSignerAddr, uint256 validityWindow)
    {
        return (frontendSigner, signatureValidityWindow);
    }

    /**
     * @notice Checks if a signature has been used (for boost function only)
     * @param _user User address
     * @param _totemAddr Totem address
     * @param _timestamp Timestamp used as salt
     * @return used Whether the signature has been used
     */
    function isSignatureUsed(
        address _user,
        address _totemAddr,
        uint256 _timestamp
    ) external view returns (bool used) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(_user, _totemAddr, _timestamp)
        );
        return usedSignatures[messageHash];
    }

    /**
     * @notice Creates message hash for signature verification (for frontend use)
     * @param _user User address
     * @param _totemAddr Totem address
     * @param _timestamp Timestamp used as salt
     * @return messageHash Hash that should be signed
     */
    function createMessageHash(
        address _user,
        address _totemAddr,
        uint256 _timestamp
    ) external pure returns (bytes32 messageHash) {
        return keccak256(abi.encodePacked(_user, _totemAddr, _timestamp));
    }

    // NFT BADGE VIEW FUNCTIONS

    /**
     * @notice Gets available milestones
     * @return milestoneArray Array of milestone values [7, 14, 30, 100, 200]
     */
    function getMilestones()
        external
        view
        returns (uint256[] memory milestoneArray)
    {
        return milestones;
    }

    /**
     * @notice Gets badge NFT contract configuration
     * @return badgeNFTAddr Address of badge NFT contract
     * @return isConfigured Whether badge NFT is configured
     */
    function getBadgeNFTConfig()
        external
        view
        returns (address badgeNFTAddr, bool isConfigured)
    {
        badgeNFTAddr = address(badgeNFT);
        isConfigured = badgeNFTAddr != address(0);
    }

    /**
     * @notice Checks if user can mint specific milestone badge
     * @param _user User address
     * @param _milestone Milestone to check
     * @return canMint Whether user can mint this milestone badge
     * @return reason Reason if cannot mint (0=can mint, 1=no available badges, 2=badge NFT not set)
     */
    function canMintBadge(
        address _user,
        uint256 _milestone
    ) external view returns (bool canMint, uint256 reason) {
        // Check if badge NFT is set
        if (address(badgeNFT) == address(0)) {
            return (false, 2);
        }

        // Check if milestone is valid
        bool validMilestone = false;
        for (uint256 i = 0; i < milestones.length; i++) {
            if (milestones[i] == _milestone) {
                validMilestone = true;
                break;
            }
        }
        if (!validMilestone) {
            return (false, 1);
        }

        // Check if user has available badges for this milestone
        if (availableBadges[_user][_milestone] == 0) {
            return (false, 1);
        }

        return (true, 0);
    }

    /**
     * @notice Get number of available badges for user and milestone
     * @param _user User address
     * @param _milestone Milestone to check (7, 14, 30, 100, 200)
     * @return Number of available badges
     */
    function getAvailableBadges(
        address _user,
        uint256 _milestone
    ) external view returns (uint256) {
        return availableBadges[_user][_milestone];
    }

    /**
     * @notice Get user's merit contribution to a specific totem in a specific period
     * @param _user User address
     * @param _totemAddr Totem address
     * @param _periodNum Period number
     * @return Merit points contributed by user to totem in period
     */
    function getUserTotemMerit(
        address _user,
        address _totemAddr,
        uint256 _periodNum
    ) external view returns (uint256) {
        return userTotemPeriodMerit[_user][_totemAddr][_periodNum];
    }

    /**
     * @notice Get user's total merit contribution in a specific period across all totems
     * @param _user User address
     * @param _periodNum Period number
     * @return Total merit points contributed by user in period
     */
    function getUserTotalMerit(
        address _user,
        uint256 _periodNum
    ) external view returns (uint256) {
        return userTotalPeriodMerit[_user][_periodNum];
    }

    /**
     * @notice Calculate user's share of MYTHO rewards for a specific totem in a period
     * @param _user User address
     * @param _totemAddr Totem address
     * @param _periodNum Period number
     * @return Estimated MYTHO tokens user would receive based on their merit contribution
     */
    function getUserTotemMythoShare(
        address _user,
        address _totemAddr,
        uint256 _periodNum
    ) external view returns (uint256) {
        uint256 userMerit = userTotemPeriodMerit[_user][_totemAddr][_periodNum];
        if (userMerit == 0) return 0;

        uint256 totalTotemMerit = meritManager.getTotemMeritPoints(_totemAddr, _periodNum);
        if (totalTotemMerit == 0) return 0;

        uint256 totemPendingReward = meritManager.getPendingReward(_totemAddr, _periodNum);
        return (totemPendingReward * userMerit) / totalTotemMerit;
    }

    /**
     * @notice Get user's merit contribution to current period for a specific totem
     * @param _user User address
     * @param _totemAddr Totem address
     * @return Merit points contributed by user to totem in current period
     */
    function getUserCurrentPeriodMerit(
        address _user,
        address _totemAddr
    ) external view returns (uint256) {
        uint256 currentPeriod = meritManager.currentPeriod();
        return userTotemPeriodMerit[_user][_totemAddr][currentPeriod];
    }

    /**
     * @notice Calculates base reward from VRF random number
     * @param _randomWord Random word from VRF
     * @return Base reward points based on probability distribution
     * @dev 50%=500pts, 25%=700pts, 15%=1000pts, 7%=2000pts, 3%=3000pts
     */
    function _calculateBaseReward(
        uint256 _randomWord
    ) private pure returns (uint256) {
        uint256 roll = _randomWord % 100; // 0-99

        // Premium boost probabilities:
        // 50% chance: 500 points
        // 25% chance: 700 points
        // 15% chance: 1000 points
        // 7% chance: 2000 points
        // 3% chance: 3000 points

        if (roll < 50) return 500; // 0-49: 50% chance
        if (roll < 75) return 700; // 50-74: 25% chance
        if (roll < 90) return 1000; // 75-89: 15% chance
        if (roll < 97) return 2000; // 90-96: 7% chance
        return 3000; // 97-99: 3% chance
    }
}
