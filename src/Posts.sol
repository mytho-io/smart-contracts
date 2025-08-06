// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721RoyaltyUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MeritManager} from "./MeritManager.sol";
import {Totem} from "./Totem.sol";
import {Shards} from "./Shards.sol";
import {AddressRegistry} from "./AddressRegistry.sol";
import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {TotemFactory} from "./TotemFactory.sol";
import {TokenHoldersOracle} from "./utils/TokenHoldersOracle.sol";

/**
 * @title Posts
 * @notice This contract represents a collection of posts in the MYTHO ecosystem, managing post creation, boosting, and rewards.
 *      Each post is represented as an ERC721 NFT token, allowing for ownership, transfer, and royalty functionality.
 *      Includes features like post registration, boosting, and reward distribution.
 *      Rewards are distributed in the form of SHARD tokens, which are minted and transferred to the user.
 *      Contract can be paused in emergency situations.
 */
contract Posts is
    ERC721Upgradeable,
    ERC721RoyaltyUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IERC721Receiver
{
    using SafeERC20 for IERC20;
    using Address for address payable;

    // State variables - Contracts
    MeritManager private meritManager;
    Shards private shards;
    IERC20 private mythoToken;
    TotemFactory private factory;

    // State variables - Configuration
    uint256 public postCounter;
    uint256 public pendingPostCounter;
    uint256 public baseShardReward; // Base Shards for formula (S)
    uint256 public minAuthorShardReward; // Minimum Shards for authors
    uint256 public authorShardPercentage; // Percentage of booster Shards for authors
    uint256 public royaltyPercentage; // Royalty percentage (e.g., 1000 = 10%)
    uint256 public boostWindow; // Boost window duration (24 hours)
    uint256 public minTotemTokenBalance; // Minimum totem token balance required to create a post
    uint256 public donationFeePercentage; // Percentage of donation taken as fee (1000 = 10%)
    uint256 public maxNFTBoostsPerUser; // Maximum NFT boosts per user per post

    // State variables - Addresses
    address private registryAddr;

    // State variables - Mappings
    mapping(uint256 => Post) private posts; // Post data by token ID
    mapping(uint256 => Post) private pendingPosts; // Pending post data by ID
    mapping(address => uint256) public userPendingPost; // Maps user address to their pending post ID (0 if none) - DEPRECATED but kept for storage compatibility
    mapping(uint256 => uint256) public totalShardRewards; // Total Shards distributed per post
    mapping(uint256 => uint256) public totalDonations; // Total donations received per post in wei
    mapping(uint256 => mapping(address => uint256)) public boosts; // Mapping postId => user => boost amount
    mapping(uint256 => mapping(address => uint256[])) public nftBoosts; // Mapping postId => user => array of NFT token IDs
    mapping(uint256 => bool) private creatorRewardClaimed; // Track if creator reward was claimed for post

    // New storage variables added for upgrade - must be at the end
    mapping(address => mapping(address => uint256))
        public userPendingPostByTotem; // Maps user address => totem address => pending post ID (0 if none)

    // Structs
    struct Post {
        address totemAddr; // Associated Totem
        address creator; // Post creator
        bytes metadataHash; // Hash of metadata (keccak256)
        uint32 createdAt; // Creation timestamp
        uint256 totalBoostedTokens; // Total tokens boosted
    }

    // Constants - Roles
    bytes32 public constant MANAGER = keccak256("MANAGER");

    // Constants - Limits
    uint256 public constant MAX_NFT_BOOSTS_PER_USER = 50; // Maximum NFT boosts per user per post

    // Events
    event PostCreated(uint256 indexed postId, address indexed creator, address indexed totemAddr, bytes metadataHash, bool isPending); // prettier-ignore
    event PostApproved(uint256 indexed pendingId, uint256 indexed newPostId); // prettier-ignore
    event PostRejected(uint256 indexed pendingId); // prettier-ignore
    event PostBoostedERC20(uint256 indexed postId, address indexed booster, uint256 tokenAmount); // prettier-ignore
    event PostBoostedNFT(uint256 indexed postId, address indexed booster, uint256 tokenId); // prettier-ignore
    event PostUnboosted(uint256 indexed postId, address indexed booster, uint256 shardReward); // prettier-ignore
    event DonationReceived(uint256 indexed postId, address indexed donor, uint256 amount, uint256 fee); // prettier-ignore
    event ShardsDistributed(uint256 indexed postId, address indexed recipient, uint256 amount); // prettier-ignore
    event ShardTokenSet(address indexed shards); // prettier-ignore
    event DonationFeeUpdated(uint256 oldFee, uint256 newFee); // prettier-ignore
    event BoostWindowUpdated(uint256 oldWindow, uint256 newWindow); // prettier-ignore

    // Custom errors
    error InvalidMetadataHash();
    error PostNotFound();
    error NotPostOwner();
    error NotAuthorized();
    error InvalidAmount();
    error NotEnoughTotemTokens();
    error EcosystemPaused();
    error ZeroAddressNotAllowed(string receiverType);
    error InsufficientBalance();
    error HasPendingPost();
    error BoostWindowClosed();
    error AlreadyBoosted();
    error BoostNotFound();
    error BoostLocked();
    error InvalidFeePercentage();
    error DonationFailed();
    error FeeTooLow();
    error InvalidDuration();
    error PostAlreadyVerified();
    error StaleOracleData();
    error MaxNFTBoostsExceeded();
    error TotemNotFound();

    /**
     * @notice Initializes the contract with the registry address
     * @param _registryAddr Address of the AddressRegistry contract
     */
    function initialize(address _registryAddr) public initializer {
        __ERC721_init("MYTHO Community Post", "POST");
        __ERC721Royalty_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        registryAddr = _registryAddr;
        meritManager = MeritManager(
            AddressRegistry(_registryAddr).getMeritManager()
        );
        mythoToken = IERC20(AddressRegistry(_registryAddr).getMythoToken());
        factory = TotemFactory(
            AddressRegistry(_registryAddr).getTotemFactory()
        );

        baseShardReward = 1 ether; // S in formula
        minAuthorShardReward = 50;
        authorShardPercentage = 1000; // 10%
        royaltyPercentage = 1000; // 10% (1000 basis points = 10%)
        boostWindow = 24 hours; // boost window duration (24 hours)
        minTotemTokenBalance = 1 ether; // min totem token balance required to create a post
        donationFeePercentage = 100; // 1% donation fee by default
        maxNFTBoostsPerUser = MAX_NFT_BOOSTS_PER_USER; // Default NFT boost limit

        // Start counters from 1 so 0 can be used as "no pending post" indicator
        postCounter = 1;
        pendingPostCounter = 1;
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Creates a new or pending post
     * @param _totemAddr Address of the Totem
     * @param _dataHash Hash of the post data
     * @return postId ID of the created post
     */
    function createPost(
        address _totemAddr,
        bytes memory _dataHash
    ) external whenNotPaused nonReentrant returns (uint256) {
        TotemFactory.TotemData memory totemData = factory.getTotemDataByAddress(
            _totemAddr
        );

        if (_dataHash.length == 0) revert InvalidMetadataHash();

        // Check if Totem exists
        if (totemData.totemAddr == address(0)) revert TotemNotFound();

        // Check token balance requirements based on token type
        if (totemData.tokenType == TotemFactory.TokenType.ERC721) {
            // For ERC721 tokens, require at least 1 NFT
            if (IERC721(totemData.totemTokenAddr).balanceOf(msg.sender) < 1)
                revert NotEnoughTotemTokens();
        } else {
            // For ERC20 tokens (standard or custom), require minimum token balance
            if (
                IERC20(totemData.totemTokenAddr).balanceOf(msg.sender) <
                minTotemTokenBalance
            ) revert NotEnoughTotemTokens();
        }

        // Check if caller is authorized
        bool isAutoApproved = msg.sender == totemData.creator ||
            _isCollaborator(Totem(totemData.totemAddr), msg.sender);

        uint256 id;
        Post storage post;

        if (isAutoApproved) {
            id = postCounter++;
            post = posts[id];
        } else {
            // Check if user already has a pending post id and create one if not
            if (userPendingPostByTotem[msg.sender][_totemAddr] != 0)
                revert HasPendingPost();

            id = pendingPostCounter++;
            post = pendingPosts[id];
            userPendingPostByTotem[msg.sender][_totemAddr] = id;
        }

        // Fill the post or pending post data
        post.totemAddr = _totemAddr;
        post.creator = msg.sender;
        post.metadataHash = _dataHash;
        post.createdAt = uint32(block.timestamp);

        // Only mint Post NFT if auto-approved
        if (isAutoApproved) {
            _safeMint(msg.sender, id);
            _setTokenRoyalty(id, msg.sender, uint96(royaltyPercentage)); // Set royalty (1000 = 10%)

            // Award Merit point for created post only if totem is registered in Merit Manager
            if (meritManager.isRegisteredTotem(_totemAddr)) {
                meritManager.postReward(_totemAddr, msg.sender);
            }
        }

        emit PostCreated(
            id,
            msg.sender,
            _totemAddr,
            _dataHash,
            !isAutoApproved
        );

        return id;
    }

    /**
     * @notice Verifies a pending post
     * @param _pendingId ID of the pending post to verify
     * @param _approve Whether to approve or reject the pending post true/false
     */
    function verifyPost(
        uint256 _pendingId,
        bool _approve
    ) external whenNotPaused nonReentrant returns (uint256) {
        Post storage pendingPost = pendingPosts[_pendingId];
        if (pendingPost.creator == address(0)) revert PostNotFound();

        // Check if post was already verified by checking both new and old mapping for backward compatibility
        bool isValidNewMapping = userPendingPostByTotem[pendingPost.creator][
            pendingPost.totemAddr
        ] == _pendingId;
        bool isValidOldMapping = userPendingPost[pendingPost.creator] ==
            _pendingId;

        if (!isValidNewMapping && !isValidOldMapping)
            revert PostAlreadyVerified();

        Totem totem = Totem(pendingPost.totemAddr);

        // Check if caller is authorized
        if (
            msg.sender != totem.getOwner() &&
            !_isCollaborator(totem, msg.sender)
        ) revert NotAuthorized();

        address creator = pendingPost.creator;

        uint256 newPostId;

        // If approved, move from pending to active posts and mint NFT
        if (_approve) {
            newPostId = postCounter++;
            Post storage post = posts[newPostId];
            post.totemAddr = pendingPost.totemAddr;
            post.creator = creator;
            post.metadataHash = pendingPost.metadataHash;
            post.createdAt = uint32(block.timestamp); // important to use current timestamp for correct boost window calculation

            _safeMint(creator, newPostId);
            _setTokenRoyalty(newPostId, creator, uint96(royaltyPercentage));

            // Award Merit point for approved post only if totem is registered in Merit Manager
            if (meritManager.isRegisteredTotem(pendingPost.totemAddr)) {
                meritManager.postReward(pendingPost.totemAddr, post.creator);
            }

            emit PostApproved(_pendingId, newPostId);
        } else {
            emit PostRejected(_pendingId);
        }

        // Clean up pending post (both old and new mappings for backward compatibility)
        delete userPendingPostByTotem[creator][pendingPost.totemAddr];
        if (userPendingPost[creator] == _pendingId) {
            delete userPendingPost[creator];
        }

        return newPostId;
    }

    /**
     * @notice Allows users to boost a post by staking totem tokens
     *      Boosts can only be made during the boost window and for approved posts
     *      For ERC20: _tokenAmountOrId is the amount of tokens to stake
     *      For ERC721: _tokenAmountOrId is the tokenId of the NFT to stake
     * @param _postId ID of the post to boost
     * @param _tokenAmountOrId Amount of tokens (ERC20) or tokenId (ERC721) to stake
     */
    function boostPost(
        uint256 _postId,
        uint256 _tokenAmountOrId
    ) external whenNotPaused nonReentrant {
        Post storage post = posts[_postId];
        if (post.creator == address(0)) revert PostNotFound();
        if (block.timestamp > post.createdAt + boostWindow)
            revert BoostWindowClosed();

        // Get totem and token information
        Totem totem = Totem(post.totemAddr);
        (address totemTokenAddr, , ) = totem.getTokenAddresses();

        // Get token type from factory
        TotemFactory.TotemData memory totemData = factory.getTotemDataByAddress(
            post.totemAddr
        );

        if (totemData.tokenType == TotemFactory.TokenType.ERC721) {
            // For ERC721 tokens, _tokenAmountOrId is treated as tokenId
            uint256 tokenId = _tokenAmountOrId;
            IERC721 nftToken = IERC721(totemTokenAddr);

            // Check if user owns the NFT
            if (nftToken.ownerOf(tokenId) != msg.sender)
                revert InsufficientBalance();

            // Check NFT boost limit per user
            if (nftBoosts[_postId][msg.sender].length >= maxNFTBoostsPerUser)
                revert MaxNFTBoostsExceeded();

            // Transfer NFT to this contract
            nftToken.safeTransferFrom(msg.sender, address(this), tokenId);
            
            // Update boost data
            boosts[_postId][msg.sender] += 1; // Each NFT counts as 1 boost
            nftBoosts[_postId][msg.sender].push(tokenId);
            post.totalBoostedTokens += 1;

            emit PostBoostedNFT(_postId, msg.sender, tokenId);
        } else {
            // For ERC20 tokens
            if (_tokenAmountOrId == 0) revert InvalidAmount();

            // Check balance and transfer
            if (IERC20(totemTokenAddr).balanceOf(msg.sender) < _tokenAmountOrId)
                revert InsufficientBalance();

            IERC20(totemTokenAddr).safeTransferFrom(
                msg.sender,
                address(this),
                _tokenAmountOrId
            );

            // Update boost data
            boosts[_postId][msg.sender] += _tokenAmountOrId;
            post.totalBoostedTokens += _tokenAmountOrId;

            emit PostBoostedERC20(_postId, msg.sender, _tokenAmountOrId);
        }
    }

    /**
     * @notice Unboosts a post by removing staked totem tokens and receive shards
     * @param _postId ID of the post to unboost
     */
    function unboostPost(uint256 _postId) external whenNotPaused nonReentrant {
        _unboost(_postId, msg.sender, true);
    }

    /**
     * @notice Donate native tokens to a post
     * @param _postId ID of the post to donate to
     */
    function donateToPost(
        uint256 _postId
    ) external payable whenNotPaused nonReentrant {
        Post memory post = posts[_postId];
        if (post.creator == address(0)) revert PostNotFound();

        // Calculate fee
        uint256 fee = (msg.value * donationFeePercentage) / 10000;

        uint256 creatorAmount = msg.value - fee;

        // Send fee to Treasury
        if (fee > 0) {
            payable(AddressRegistry(registryAddr).getMythoTreasury()).sendValue(
                    fee
                );
        }

        // Send donation to creator
        payable(post.creator).sendValue(creatorAmount);

        // Update total donations
        totalDonations[_postId] += creatorAmount;

        // Award Merit points for donation only if totem is registered in Merit Manager
        if (meritManager.isRegisteredTotem(post.totemAddr)) {
            meritManager.donationReward(post.totemAddr, creatorAmount);
        }

        emit DonationReceived(_postId, msg.sender, creatorAmount, fee);
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Sets the shard token contract address
     */
    function setShardToken() external onlyRole(MANAGER) {
        address _shardToken = AddressRegistry(registryAddr).getShardToken();
        if (_shardToken == address(0)) revert ZeroAddressNotAllowed("Shards");

        shards = Shards(_shardToken);

        emit ShardTokenSet(_shardToken);
    }

    /**
     * @notice Sets the base shard reward for the formula
     * @param _reward The new base shard reward
     */
    function setBaseShardReward(uint256 _reward) external onlyRole(MANAGER) {
        if (_reward == 0) revert InvalidAmount();
        baseShardReward = _reward;
    }

    /**
     * @notice Sets the minimum shard reward for authors
     * @param _reward The new minimum author shard reward
     */
    function setMinAuthorShardReward(
        uint256 _reward
    ) external onlyRole(MANAGER) {
        minAuthorShardReward = _reward;
    }

    /**
     * @notice Sets the percentage of booster shards for authors
     * @param _percentage The new author shard percentage (10000 = 100%)
     */
    function setAuthorShardPercentage(
        uint256 _percentage
    ) external onlyRole(MANAGER) {
        authorShardPercentage = _percentage;
    }

    /**
     * @notice Sets the royalty percentage for post NFTs
     * @param _percentage The new royalty percentage (1000 = 10%)
     */
    function setRoyaltyPercentage(
        uint256 _percentage
    ) external onlyRole(MANAGER) {
        royaltyPercentage = _percentage;
    }

    /**
     * @notice Sets the minimum totem token balance required to create a post
     * @param _balance The new minimum balance in wei (18 decimals)
     */
    function setMinTotemTokenBalance(
        uint256 _balance
    ) external onlyRole(MANAGER) {
        minTotemTokenBalance = _balance;
    }

    /**
     * @notice Sets the donation fee percentage
     * @param _percentage The new fee percentage (1000 = 10%)
     */
    function setDonationFee(uint256 _percentage) external onlyRole(MANAGER) {
        if (_percentage > 5000) revert InvalidFeePercentage(); // Max 50%
        uint256 oldFee = donationFeePercentage;
        donationFeePercentage = _percentage;
        emit DonationFeeUpdated(oldFee, _percentage);
    }

    /**
     * @notice Sets the boost window duration
     * @param _window The new boost window duration in seconds
     */
    function setBoostWindow(uint256 _window) external onlyRole(MANAGER) {
        if (_window == 0) revert InvalidDuration();
        uint256 oldWindow = boostWindow;
        boostWindow = _window;
        emit BoostWindowUpdated(oldWindow, _window);
    }

    /**
     * @notice Sets the maximum NFT boosts per user per post
     * @param _maxNFTBoosts The new maximum NFT boosts per user
     */
    function setMaxNFTBoostsPerUser(
        uint256 _maxNFTBoosts
    ) external onlyRole(MANAGER) {
        if (_maxNFTBoosts == 0) revert InvalidAmount();
        maxNFTBoostsPerUser = _maxNFTBoosts;
    }

    /**
     * @notice Force unboost a user's tokens from a post (admin function)
     * @param _postId ID of the post to unboost from
     * @param _user Address of the user to unboost for
     * @dev Only callable by MANAGER role. Useful for emergency situations or when users cannot unboost themselves
     */
    function forceUnboost(
        uint256 _postId,
        address _user
    ) external onlyRole(MANAGER) nonReentrant {
        _unboost(_postId, _user, false);
    }

    /**
     * @notice Pauses all contract operations
     */
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpauses all contract operations
     */
    function unpause() external onlyRole(MANAGER) {
        _unpause();
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Internal function to handle unboost logic for both user and admin unboost
     * @param _postId ID of the post to unboost from
     * @param _user Address of the user to unboost for
     * @param _checkBoostWindow Whether to check if boost window is closed (true for user unboost, false for admin force unboost)
     */
    function _unboost(
        uint256 _postId,
        address _user,
        bool _checkBoostWindow
    ) internal {
        Post memory post = posts[_postId];
        if (post.creator == address(0)) revert PostNotFound();

        if (_checkBoostWindow && block.timestamp < post.createdAt + boostWindow)
            revert BoostLocked();

        uint256 boostAmount = boosts[_postId][_user];
        if (boostAmount == 0) revert BoostNotFound();

        Totem totem = Totem(post.totemAddr);
        (address totemTokenAddr, , ) = totem.getTokenAddresses();

        // Get token type from factory
        TotemFactory.TotemData memory totemData = factory.getTotemDataByAddress(
            post.totemAddr
        );

        // For NFT totems, verify oracle data is fresh before calculating rewards
        if (totemData.tokenType == TotemFactory.TokenType.ERC721) {
            TokenHoldersOracle oracle = TokenHoldersOracle(
                AddressRegistry(registryAddr).getTokenHoldersOracle()
            );
            if (
                address(oracle) != address(0) &&
                !oracle.isDataFresh(totemTokenAddr)
            ) {
                revert StaleOracleData();
            }
        }

        uint256 circulatingSupply = totem.getCirculatingSupply();

        // Calculate user's shard reward
        uint256 shardReward = _calculateShardReward(
            boostAmount,
            post.totalBoostedTokens,
            circulatingSupply
        );

        // Return tokens to user
        if (totemData.tokenType == TotemFactory.TokenType.ERC721) {
            // Return all NFTs that user boosted
            uint256[] storage userNFTs = nftBoosts[_postId][_user];
            IERC721 nftToken = IERC721(totemTokenAddr);

            for (uint256 i = 0; i < userNFTs.length; i++) {
                nftToken.safeTransferFrom(address(this), _user, userNFTs[i]);
            }

            // Clear the NFT array
            delete nftBoosts[_postId][_user];
        } else {
            // Transfer back ERC20 tokens
            IERC20(totemTokenAddr).safeTransfer(_user, boostAmount);
        }

        // Mint shards for user
        if (shardReward > 0) {
            shards.mint(_user, shardReward);
            totalShardRewards[_postId] += shardReward;
            emit ShardsDistributed(_postId, _user, shardReward);

            // If this is the first unboost, calculate and distribute creator reward
            if (!creatorRewardClaimed[_postId]) {
                uint256 totalPostRewards = _calculateShardReward(
                    post.totalBoostedTokens,
                    post.totalBoostedTokens,
                    circulatingSupply
                );
                uint256 creatorReward = Math.max(
                    minAuthorShardReward,
                    (totalPostRewards * authorShardPercentage) / 10000
                );
                shards.mint(post.creator, creatorReward);
                totalShardRewards[_postId] += creatorReward;
                emit ShardsDistributed(_postId, post.creator, creatorReward);
                creatorRewardClaimed[_postId] = true;
            }
        }

        // Clear user's boost amount to mark it as unboosted
        delete boosts[_postId][_user];
        emit PostUnboosted(_postId, _user, shardReward);
    }

    /**
     * @notice Checks if ecosystem is paused before allowing operations
     */
    function _requireNotPaused() internal view virtual override {
        super._requireNotPaused();
        if (AddressRegistry(registryAddr).isEcosystemPaused()) {
            revert EcosystemPaused();
        }
    }

    /**
     * @notice Checks if a user is a collaborator of a Totem
     * @param _totem The Totem contract
     * @param _user The user address to check
     * @return True if the user is a collaborator, false otherwise
     */
    function _isCollaborator(
        Totem _totem,
        address _user
    ) internal view returns (bool) {
        address[] memory collaborators = _totem.getAllCollaborators();
        for (uint256 i = 0; i < collaborators.length; i++) {
            if (collaborators[i] == _user) return true;
        }
        return false;
    }

    // VIEW FUNCTIONS

    /**
     * @notice Calculate shard reward for a booster
     * @param _userLockedTokens Amount of tokens locked by the user
     * @param _totalLockedTokens Total amount of tokens locked for the post
     * @param _tokenCirculatingSupply Circulating supply of the totem token (excluding Totem and Treasury balances)
     * @return shardReward Amount of shards to be rewarded
     */
    function _calculateShardReward(
        uint256 _userLockedTokens,
        uint256 _totalLockedTokens,
        uint256 _tokenCirculatingSupply
    ) internal view returns (uint256) {
        if (_totalLockedTokens == 0 || _tokenCirculatingSupply == 0) return 0;

        // Calculate square root of (L/T), capped at 10%
        uint256 lockedRatio = Math.min(
            (_totalLockedTokens * 1e18) / _tokenCirculatingSupply,
            1e17
        );
        uint256 sqrtRatio = Math.sqrt(lockedRatio);

        // Calculate (l/T), capped at 5% (1/20)
        uint256 userRatio = Math.min(
            (_userLockedTokens * 1e18) / _tokenCirculatingSupply,
            5e16 // 5% = 0.05 = 5e16 in 1e18 precision
        );

        // Final formula: S * (l/T) * sqrt(L/T)
        return (baseShardReward * userRatio * sqrtRatio) / 1e36;
    }

    /**
     * @notice Get boost amount for a specific post and user
     * @param _postId The post ID
     * @param _user The user address
     * @return amount Amount of tokens boosted
     */
    function getBoostAmount(
        uint256 _postId,
        address _user
    ) external view returns (uint256 amount) {
        return boosts[_postId][_user];
    }

    /**
     * @notice Get NFT token IDs boosted by a user for a specific post
     * @param _postId The post ID
     * @param _user The user address
     * @return tokenIds Array of NFT token IDs
     */
    function getNFTBoosts(
        uint256 _postId,
        address _user
    ) external view returns (uint256[] memory) {
        return nftBoosts[_postId][_user];
    }

    /**
     * @notice Handle the receipt of an NFT
     * @dev Implements IERC721Receiver to allow this contract to receive NFTs
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Get post information without total boosted tokens
     * @param _postId The post ID
     * @return post Post information
     */
    function getPost(uint256 _postId) external view returns (Post memory) {
        Post memory post = posts[_postId];
        if (post.creator == address(0)) revert PostNotFound();
        return post;
    }

    /**
     * @notice Get pending post information
     * @param _postId The post ID
     * @return post Post information
     */
    function getPendingPost(
        uint256 _postId
    ) external view returns (Post memory) {
        return pendingPosts[_postId];
    }

    /**
     * @notice Get the metadata hash for a post
     * @param _postId The post ID
     * @return The metadata hash
     */
    function getMetadataHash(
        uint256 _postId
    ) external view returns (bytes memory) {
        Post storage post = posts[_postId];
        if (post.creator == address(0)) revert PostNotFound();
        return post.metadataHash;
    }

    /**
     * @notice Get the pending post ID for a specific user and totem
     * @param _user The user address
     * @param _totemAddr The totem address
     * @return The pending post ID (0 if none)
     */
    function getUserPendingPost(
        address _user,
        address _totemAddr
    ) external view returns (uint256) {
        return userPendingPostByTotem[_user][_totemAddr];
    }

    // OVERRIDES

    /**
     * @notice Checks if a given interface is supported by the contract
     *      Required by ERC165
     * @param interfaceId The interface identifier to check
     * @return bool True if the interface is supported, false otherwise
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            ERC721Upgradeable,
            ERC721RoyaltyUpgradeable,
            AccessControlUpgradeable
        )
        returns (bool)
    {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
