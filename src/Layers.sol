// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {ERC721RoyaltyUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MeritManager} from "./MeritManager.sol";
import {Totem} from "./Totem.sol";
import {Shards} from "./Shards.sol";
import {AddressRegistry} from "./AddressRegistry.sol";
import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {TotemFactory} from "./TotemFactory.sol";

/**
 * @title Layers
 * @notice This contract represents a collection of layers in the MYTHO ecosystem, managing layer creation, boosting, and rewards.
 *      Includes features like layer registration, boosting, and reward distribution.
 *      Rewards are distributed in the form of SHARD tokens, which are minted and transferred to the user.
 *      Contract can be paused in emergency situations.
 */
contract Layers is
    ERC721Upgradeable,
    ERC721RoyaltyUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address payable;

    // State variables - Contracts
    MeritManager private meritManager;
    Shards private shards;
    IERC20 private mythoToken;
    TotemFactory private factory;

    // State variables - Configuration
    uint256 private layerCounter;
    uint256 private pendingLayerCounter;
    uint256 public baseShardReward; // Base Shards for formula (S)
    uint256 public minAuthorShardReward; // Minimum Shards for authors
    uint256 public authorShardPercentage; // Percentage of booster Shards for authors
    uint256 public royaltyPercentage; // Royalty percentage (e.g., 1000 = 10%)
    uint256 public boostWindow; // Boost window duration (24 hours)
    uint256 public minTotemTokenBalance; // Minimum totem token balance required to create a layer
    uint256 public donationFeePercentage; // Percentage of donation taken as fee (1000 = 10%)
    uint256 public minDonationFee; // Minimum fee amount in wei for donations

    // State variables - Addresses
    address private registryAddr;

    // State variables - Mappings
    mapping(uint256 => Layer) private layers; // Layer data by token ID
    mapping(uint256 => Layer) private pendingLayers; // Pending layer data by ID
    mapping(address => uint256) public userPendingLayer; // Maps user address to their pending layer ID (0 if none)
    mapping(uint256 => uint256) public totalShardRewards; // Total Shards distributed per layer
    mapping(uint256 => uint256) public totalDonations; // Total donations received per layer in wei
    mapping(uint256 => mapping(address => uint256)) public boosts; // Mapping layerId => user => boost amount
    mapping(uint256 => bool) private creatorRewardClaimed; // Track if creator reward was claimed for layer

    // Structs
    struct Layer {
        address totemAddr; // Associated Totem
        address creator; // Layer creator
        bytes32 metadataHash; // Hash of metadata (keccak256)
        uint32 createdAt; // Creation timestamp
        uint224 totalBoostedTokens; // Total tokens boosted (L)
    }

    // Constants - Roles
    bytes32 public constant MANAGER = keccak256("MANAGER");

    // Events
    event LayerCreated(uint256 indexed layerId, address indexed creator, address indexed totemAddr, bytes32 metadataHash, bool isPending); // prettier-ignore
    event LayerApproved(uint256 indexed pendingId, uint256 indexed newLayerId); // prettier-ignore
    event LayerRejected(uint256 indexed pendingId); // prettier-ignore
    event LayerBoosted(uint256 indexed layerId, address indexed booster, uint256 tokenAmount); // prettier-ignore
    event LayerUnboosted(uint256 indexed layerId, address indexed booster, uint256 shardReward); // prettier-ignore
    event DonationReceived(uint256 indexed layerId, address indexed donor, uint256 amount, uint256 fee); // prettier-ignore
    event ShardsDistributed(uint256 indexed layerId, address indexed recipient, uint256 amount); // prettier-ignore
    event ShardTokenSet(address indexed shards); // prettier-ignore
    event PendingLayerAdded(uint256 indexed pendingId,address indexed creator,address indexed totemAddr,bytes32 metadataHash); // prettier-ignore
    event DonationFeeUpdated(uint256 oldFee, uint256 newFee); // prettier-ignore
    event MinDonationFeeUpdated(uint256 newFee); // prettier-ignore

    // Custom errors
    error InvalidTotem();
    error InvalidMetadataHash();
    error LayerNotFound();
    error NotLayerOwner();
    error NotAuthorized();
    error InvalidAmount();
    error NotEnoughTotemTokens();
    error EcosystemPaused();
    error ZeroAddressNotAllowed(string receiverType);
    error InsufficientBalance();
    error HasPendingLayer();
    error BoostWindowClosed();
    error AlreadyBoosted();
    error BoostNotFound();
    error BoostLocked();
    error BoostWindowNotClosed();
    error InvalidFeePercentage();
    error DonationFailed();
    error FeeTooLow();

    /**
     * @notice Initializes the contract with the registry address
     * @param _registryAddr Address of the AddressRegistry contract
     */
    function initialize(address _registryAddr) public initializer {
        __ERC721_init("MYTHO Totem Layer", "LAYER");
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

        baseShardReward = 100; // S in formula
        minAuthorShardReward = 50;
        authorShardPercentage = 1000; // 10%
        royaltyPercentage = 1000; // 10% (1000 basis points = 10%)
        boostWindow = 24 hours; // boost window duration (24 hours)
        minTotemTokenBalance = 250_000 ether; // min totem token balance required to create a layer
        donationFeePercentage = 0; // 0% donation fee by default
        minDonationFee = 0; // 0 minimum donation fee by default

        // Start counters from 1 so 0 can be used as "no pending layer" indicator
        layerCounter = 1;
        pendingLayerCounter = 1;
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Creates a new or pending layer
     * @param _totemAddr Address of the Totem
     * @param _dataHash Hash of the layer data
     * @return layerId ID of the created layer
     */
    function createLayer(
        address _totemAddr,
        bytes32 _dataHash
    ) external whenNotPaused nonReentrant returns (uint256) {
        TotemFactory.TotemData memory totemData = factory.getTotemDataByAddress(
            _totemAddr
        );

        // Check if Totem exists
        if (totemData.creator == address(0)) revert InvalidTotem();
        if (_dataHash == bytes32(0)) revert InvalidMetadataHash();

        // Check if caller has enough totem tokens
        if (
            IERC20(totemData.totemTokenAddr).balanceOf(msg.sender) <
            minTotemTokenBalance // 250_000 min balance by default
        ) revert NotEnoughTotemTokens();

        // Check if caller is authorized
        bool isAutoApproved = msg.sender == totemData.creator ||
            _isCollaborator(Totem(totemData.totemAddr), msg.sender);

        uint256 id;
        Layer storage layer;

        if (isAutoApproved) {
            id = layerCounter++;
            layer = layers[id];
        } else {
            // Check if user already has a pending layer id and create one if not
            if (userPendingLayer[msg.sender] != 0) revert HasPendingLayer();

            id = pendingLayerCounter++;
            layer = pendingLayers[id];
            userPendingLayer[msg.sender] = id;

            emit PendingLayerAdded(id, msg.sender, _totemAddr, _dataHash);
        }

        // Fill the layer or pending layer data
        layer.totemAddr = _totemAddr;
        layer.creator = msg.sender;
        layer.metadataHash = _dataHash;
        layer.createdAt = uint32(block.timestamp);

        // Only mint Layer NFT if auto-approved
        if (isAutoApproved) {
            _safeMint(msg.sender, id);
            _setTokenRoyalty(id, msg.sender, uint96(royaltyPercentage * 100)); // Set royalty (1000 = 10%)

            // Award Merit point for created layer
            meritManager.layerReward(_totemAddr);
        }

        emit LayerCreated(
            id,
            msg.sender,
            _totemAddr,
            _dataHash,
            !isAutoApproved
        );

        return id;
    }

    /**
     * @notice Verifies a pending layer
     * @param _pendingId ID of the pending layer to verify
     * @param _approve Whether to approve or reject the pending layer true/false
     */
    function verifyLayer(
        uint256 _pendingId,
        bool _approve
    ) external whenNotPaused {
        Layer storage pendingLayer = pendingLayers[_pendingId];

        if (pendingLayer.creator == address(0)) revert LayerNotFound();
        Totem totem = Totem(pendingLayer.totemAddr);

        // Check if caller is authorized
        if (
            msg.sender != totem.getOwner() &&
            !_isCollaborator(totem, msg.sender)
        ) revert NotAuthorized();

        address creator = pendingLayer.creator;

        // If approved, move from pending to active layers and mint NFT
        if (_approve) {
            uint256 newLayerId = layerCounter++;
            Layer storage layer = layers[newLayerId];
            layer.totemAddr = pendingLayer.totemAddr;
            layer.creator = creator;
            layer.metadataHash = pendingLayer.metadataHash;
            layer.createdAt = uint32(block.timestamp); // important to use current timestamp for correct boost window calculation

            _safeMint(creator, newLayerId);
            _setTokenRoyalty(
                newLayerId,
                creator,
                uint96(royaltyPercentage * 100)
            );

            // Award Merit point for approved layer
            meritManager.layerReward(pendingLayer.totemAddr);

            emit LayerApproved(_pendingId, newLayerId);
        } else {
            emit LayerRejected(_pendingId);
        }

        // Clean up pending layer
        delete userPendingLayer[creator];
    }

    /**
     * @notice Allows users to boost a layer by staking totem tokens
     *      Boosts can only be made during the boost window and for approved layers
     * @param _layerId ID of the layer to boost
     * @param _tokenAmount Amount of totem tokens to stake for the boost
     */
    function boostLayer(
        uint256 _layerId,
        uint224 _tokenAmount
    ) external whenNotPaused nonReentrant {
        Layer storage layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();
        if (block.timestamp > layer.createdAt + boostWindow)
            revert BoostWindowClosed();
        if (_tokenAmount == 0) revert InvalidAmount();

        // Check if caller has enough totem tokens
        Totem totem = Totem(layer.totemAddr);
        (address totemTokenAddr, , ) = totem.getTokenAddresses();
        if (IERC20(totemTokenAddr).balanceOf(msg.sender) < _tokenAmount)
            revert InsufficientBalance();

        IERC20(totemTokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );

        // Update boost data
        boosts[_layerId][msg.sender] += _tokenAmount;
        layer.totalBoostedTokens += _tokenAmount;

        emit LayerBoosted(_layerId, msg.sender, _tokenAmount);
    }

    /**
     * @notice Unboosts a layer by removing staked totem tokens and receive shards
     * @param _layerId ID of the layer to unboost
     */
    function unboostLayer(
        uint256 _layerId
    ) external whenNotPaused nonReentrant {
        Layer memory layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();
        if (block.timestamp < layer.createdAt + boostWindow)
            revert BoostLocked();
        uint256 boostAmount = boosts[_layerId][msg.sender];
        if (boostAmount == 0) revert BoostNotFound();

        Totem totem = Totem(layer.totemAddr);
        (address totemTokenAddr, , ) = totem.getTokenAddresses();

        uint256 totalSupply = IERC20(totemTokenAddr).totalSupply();

        // Calculate user's shard reward
        uint256 shardReward = calculateShardReward(
            boostAmount,
            layer.totalBoostedTokens,
            totalSupply
        );

        // Return tokens to user
        IERC20(totemTokenAddr).safeTransfer(msg.sender, boostAmount);

        // Mint shards for user
        if (shardReward > 0) {
            shards.mint(msg.sender, shardReward);
            totalShardRewards[_layerId] += shardReward;
            emit ShardsDistributed(_layerId, msg.sender, shardReward);

            // If this is the first unboost, calculate and distribute creator reward
            if (!creatorRewardClaimed[_layerId]) {
                uint256 totalLayerRewards = calculateShardReward(
                    layer.totalBoostedTokens,
                    layer.totalBoostedTokens,
                    totalSupply
                );
                uint256 creatorReward = Math.max(
                    minAuthorShardReward,
                    (totalLayerRewards * authorShardPercentage) / 10000
                );
                shards.mint(layer.creator, creatorReward);
                totalShardRewards[_layerId] += creatorReward;
                emit ShardsDistributed(_layerId, layer.creator, creatorReward);
                creatorRewardClaimed[_layerId] = true;
            }
        }

        // Clear user's boost amount to mark it as unboosted
        delete boosts[_layerId][msg.sender];
        emit LayerUnboosted(_layerId, msg.sender, shardReward);
    }

    /**
     * @notice Donate native tokens to a layer
     * @param _layerId ID of the layer to donate to
     */
    function donateToLayer(
        uint256 _layerId
    ) external payable whenNotPaused {
        Layer memory layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();

        // Calculate fee
        uint256 fee = (msg.value * donationFeePercentage) / 10000;
        if (fee < minDonationFee) revert FeeTooLow();

        uint256 creatorAmount = msg.value - fee;

        // Send fee to Treasury
        if (fee > 0) {
            payable(AddressRegistry(registryAddr).getMythoTreasury()).sendValue(fee);
        }

        // Send donation to creator
        payable(layer.creator).sendValue(creatorAmount);

        // Update total donations
        totalDonations[_layerId] += msg.value;

        // Award merit points to the totem based on donation amount
        meritManager.donationReward(layer.totemAddr, msg.value);

        emit DonationReceived(_layerId, msg.sender, msg.value, fee);
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
     * @notice Sets the royalty percentage for layer NFTs
     * @param _percentage The new royalty percentage (1000 = 10%)
     */
    function setRoyaltyPercentage(
        uint256 _percentage
    ) external onlyRole(MANAGER) {
        royaltyPercentage = _percentage;
    }

    /**
     * @notice Sets the minimum totem token balance required to create a layer
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
     * @notice Sets the minimum fee amount for donations
     * @param _minFee The new minimum fee amount in wei
     */
    function setMinDonationFee(uint256 _minFee) external onlyRole(MANAGER) {
        minDonationFee = _minFee;
        emit MinDonationFeeUpdated(_minFee);
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
     * @param _totalLockedTokens Total amount of tokens locked for the layer
     * @param _tokenTotalSupply Total supply of the totem token
     * @return shardReward Amount of shards to be rewarded
     */
    function calculateShardReward(
        uint256 _userLockedTokens,
        uint256 _totalLockedTokens,
        uint256 _tokenTotalSupply
    ) internal view returns (uint256) {
        if (_totalLockedTokens == 0 || _tokenTotalSupply == 0) return 0;

        // Calculate square root of (L/T)
        uint256 sqrtRatio = Math.sqrt(
            (_totalLockedTokens * 1e18) / _tokenTotalSupply
        );

        // Calculate (l/T)
        uint256 userRatio = (_userLockedTokens * 1e18) / _tokenTotalSupply;

        // Final formula: S * (l/T) * sqrt(L/T)
        return (baseShardReward * userRatio * sqrtRatio) / 1e36;
    }

    /**
     * @notice Get boost amount for a specific layer and user
     * @param _layerId The layer ID
     * @param _user The user address
     * @return amount Amount of tokens boosted
     */
    function getBoostAmount(
        uint256 _layerId,
        address _user
    ) external view returns (uint256 amount) {
        return boosts[_layerId][_user];
    }

    /**
     * @notice Get layer information without total boosted tokens
     * @param _layerId The layer ID
     * @return totemAddr Address of the associated Totem
     * @return creator Address of the layer creator
     * @return metadataHash Hash of the layer metadata
     * @return createdAt Timestamp when the layer was created
     */
    function getLayerInfo(
        uint256 _layerId
    )
        external
        view
        returns (
            address totemAddr,
            address creator,
            bytes32 metadataHash,
            uint32 createdAt
        )
    {
        Layer memory layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();
        return (
            layer.totemAddr,
            layer.creator,
            layer.metadataHash,
            layer.createdAt
        );
    }

    /**
     * @notice Get total boosted tokens for a layer
     * @param _layerId The layer ID
     * @return totalBoosted Total amount of boosted tokens
     */
    function getLayerTotalBoosted(
        uint256 _layerId
    ) external view returns (uint224 totalBoosted) {
        Layer memory layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();
        if (block.timestamp <= layer.createdAt + boostWindow)
            revert BoostWindowNotClosed();
        return layer.totalBoostedTokens;
    }

    /**
     * @notice Get the metadata hash for a layer
     * @param _layerId The layer ID
     * @return The metadata hash
     */
    function getMetadataHash(uint256 _layerId) external view returns (bytes32) {
        Layer storage layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();
        return layer.metadataHash;
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
        return super.supportsInterface(interfaceId);
    }
}
