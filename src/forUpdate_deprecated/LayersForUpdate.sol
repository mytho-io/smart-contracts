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

import {MeritManager} from "./MeritManagerForUpdate.sol";
import {Totem} from "./TotemForUpdate.sol";
import {Shards} from "./ShardsForUpdate.sol";
import {AddressRegistry} from "./AddressRegistryForUpdate.sol";
import {TotemTokenDistributor} from "./TotemTokenDistributorForUpdate.sol";
import {TotemFactory} from "./TotemFactoryForUpdate.sol";

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
    uint256 public layerCounter;
    uint256 public pendingLayerCounter;
    uint256 public baseShardReward; // Base Shards for formula (S)
    uint256 public minAuthorShardReward; // Minimum Shards for authors
    uint256 public authorShardPercentage; // Percentage of booster Shards for authors
    uint256 public royaltyPercentage; // Royalty percentage (e.g., 1000 = 10%)
    uint256 public boostWindow; // Boost window duration (24 hours)
    uint256 public minTotemTokenBalance; // Minimum totem token balance required to create a layer
    uint256 public donationFeePercentage; // Percentage of donation taken as fee (1000 = 10%)
    uint256 public minDonationFee; // Minimum fee amount in wei for donations
    uint256 public maxBoostAmount; // Maximum amount of tokens that can be boosted per user per layer

    // State variables - Addresses
    address private registryAddr;

    // State variables - Mappings
    mapping(uint256 => Layer) private layers; // Layer data by token ID
    mapping(uint256 => Layer) private pendingLayers; // Pending layer data by ID
    mapping(address => uint256) public userPendingLayer; // Maps user address to their pending layer ID (0 if none) - DEPRECATED but kept for storage compatibility
    mapping(uint256 => uint256) public totalShardRewards; // Total Shards distributed per layer
    mapping(uint256 => uint256) public totalDonations; // Total donations received per layer in wei
    mapping(uint256 => mapping(address => uint256)) public boosts; // Mapping layerId => user => boost amount
    mapping(uint256 => mapping(address => uint256[])) public nftBoosts; // Mapping layerId => user => array of NFT token IDs
    mapping(uint256 => bool) private creatorRewardClaimed; // Track if creator reward was claimed for layer

    // New storage variables added for upgrade - must be at the end
    mapping(address => mapping(address => uint256)) public userPendingLayerByTotem; // Maps user address => totem address => pending layer ID (0 if none)

    // Structs
    struct Layer {
        address totemAddr; // Associated Totem
        address creator; // Layer creator
        bytes metadataHash; // Hash of metadata (keccak256)
        uint32 createdAt; // Creation timestamp
        uint224 totalBoostedTokens; // Total tokens boosted (L)
    }

    // Constants - Roles
    bytes32 public constant MANAGER = keccak256("MANAGER");

    // Events
    event LayerCreated(uint256 indexed layerId, address indexed creator, address indexed totemAddr, bytes metadataHash, bool isPending); // prettier-ignore
    event LayerApproved(uint256 indexed pendingId, uint256 indexed newLayerId); // prettier-ignore
    event LayerRejected(uint256 indexed pendingId); // prettier-ignore
    event LayerBoostedERC20(uint256 indexed layerId, address indexed booster, uint256 tokenAmount); // prettier-ignore
    event LayerBoostedNFT(uint256 indexed layerId, address indexed booster, uint256 tokenId); // prettier-ignore
    event LayerUnboosted(uint256 indexed layerId, address indexed booster, uint256 shardReward); // prettier-ignore
    event DonationReceived(uint256 indexed layerId, address indexed donor, uint256 amount, uint256 fee); // prettier-ignore
    event ShardsDistributed(uint256 indexed layerId, address indexed recipient, uint256 amount); // prettier-ignore
    event ShardTokenSet(address indexed shards); // prettier-ignore

    event DonationFeeUpdated(uint256 oldFee, uint256 newFee); // prettier-ignore

    event BoostWindowUpdated(uint256 oldWindow, uint256 newWindow); // prettier-ignore

    // Custom errors
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
    error InvalidFeePercentage();
    error DonationFailed();
    error FeeTooLow();
    error InvalidDuration();
    error MaxBoostExceeded();
    error LayerAlreadyVerified();

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

        baseShardReward = 1 ether; // S in formula
        minAuthorShardReward = 50;
        authorShardPercentage = 1000; // 10%
        royaltyPercentage = 1000; // 10% (1000 basis points = 10%)
        boostWindow = 24 hours; // boost window duration (24 hours)
        minTotemTokenBalance = 1 ether; // min totem token balance required to create a layer
        donationFeePercentage = 100; // 1% donation fee by default

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
        bytes memory _dataHash
    ) external whenNotPaused nonReentrant returns (uint256) {
        TotemFactory.TotemData memory totemData = factory.getTotemDataByAddress(
            _totemAddr
        );

        // Check if Totem exists
        if (_dataHash.length == 0) revert InvalidMetadataHash();

        // Check token balance requirements based on token type
        if (totemData.tokenType == TotemFactory.TokenType.ERC721) {
            // For ERC721 tokens, require at least 1 NFT
            if (IERC20(totemData.totemTokenAddr).balanceOf(msg.sender) < 1)
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
        Layer storage layer;

        if (isAutoApproved) {
            id = layerCounter++;
            layer = layers[id];
        } else {
            // Check if user already has a pending layer id and create one if not
            if (userPendingLayerByTotem[msg.sender][_totemAddr] != 0) revert HasPendingLayer();

            id = pendingLayerCounter++;
            layer = pendingLayers[id];
            userPendingLayerByTotem[msg.sender][_totemAddr] = id;
        }

        // Fill the layer or pending layer data
        layer.totemAddr = _totemAddr;
        layer.creator = msg.sender;
        layer.metadataHash = _dataHash;
        layer.createdAt = uint32(block.timestamp);

        // Only mint Layer NFT if auto-approved
        if (isAutoApproved) {
            _safeMint(msg.sender, id);
            _setTokenRoyalty(id, msg.sender, uint96(royaltyPercentage)); // Set royalty (1000 = 10%)

            // Award Merit point for created layer only if totem is registered in Merit Manager
            if (meritManager.isRegisteredTotem(_totemAddr)) {
                meritManager.layerReward(_totemAddr);
            }
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
    ) external whenNotPaused nonReentrant returns (uint256) {
        Layer storage pendingLayer = pendingLayers[_pendingId];
        if (pendingLayer.creator == address(0)) revert LayerNotFound();

        // Check if layer was already verified by checking userPendingLayerByTotem mapping
        if (userPendingLayerByTotem[pendingLayer.creator][pendingLayer.totemAddr] != _pendingId) revert LayerAlreadyVerified();
        Totem totem = Totem(pendingLayer.totemAddr);

        // Check if caller is authorized
        if (
            msg.sender != totem.getOwner() &&
            !_isCollaborator(totem, msg.sender)
        ) revert NotAuthorized();

        address creator = pendingLayer.creator;

        uint256 newLayerId;

        // If approved, move from pending to active layers and mint NFT
        if (_approve) {
            newLayerId = layerCounter++;
            Layer storage layer = layers[newLayerId];
            layer.totemAddr = pendingLayer.totemAddr;
            layer.creator = creator;
            layer.metadataHash = pendingLayer.metadataHash;
            layer.createdAt = uint32(block.timestamp); // important to use current timestamp for correct boost window calculation

            _safeMint(creator, newLayerId);
            _setTokenRoyalty(newLayerId, creator, uint96(royaltyPercentage));

            // Award Merit point for approved layer only if totem is registered in Merit Manager
            if (meritManager.isRegisteredTotem(pendingLayer.totemAddr)) {
                meritManager.layerReward(pendingLayer.totemAddr);
            }

            emit LayerApproved(_pendingId, newLayerId);
        } else {
            emit LayerRejected(_pendingId);
        }

        // Clean up pending layer
        delete userPendingLayerByTotem[creator][pendingLayer.totemAddr];

        return newLayerId;
    }

    /**
     * @notice Allows users to boost a layer by staking totem tokens
     *      Boosts can only be made during the boost window and for approved layers
     *      For ERC20: _tokenAmountOrId is the amount of tokens to stake
     *      For ERC721: _tokenAmountOrId is the tokenId of the NFT to stake
     * @param _layerId ID of the layer to boost
     * @param _tokenAmountOrId Amount of tokens (ERC20) or tokenId (ERC721) to stake
     */
    function boostLayer(
        uint256 _layerId,
        uint224 _tokenAmountOrId
    ) external whenNotPaused nonReentrant {
        Layer storage layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();
        if (block.timestamp > layer.createdAt + boostWindow)
            revert BoostWindowClosed();

        // Get totem and token information
        Totem totem = Totem(layer.totemAddr);
        (address totemTokenAddr, , ) = totem.getTokenAddresses();

        // Get token type from factory
        TotemFactory.TotemData memory totemData = factory.getTotemDataByAddress(
            layer.totemAddr
        );

        if (totemData.tokenType == TotemFactory.TokenType.ERC721) {
            // For ERC721 tokens, _tokenAmountOrId is treated as tokenId
            uint256 tokenId = _tokenAmountOrId;
            IERC721 nftToken = IERC721(totemTokenAddr);

            // Check if user owns the NFT
            if (nftToken.ownerOf(tokenId) != msg.sender)
                revert InsufficientBalance();

            // Transfer NFT to this contract
            nftToken.safeTransferFrom(msg.sender, address(this), tokenId);

            // Update boost data
            boosts[_layerId][msg.sender] += 1; // Each NFT counts as 1 boost
            nftBoosts[_layerId][msg.sender].push(tokenId);
            layer.totalBoostedTokens += 1;

            emit LayerBoostedNFT(_layerId, msg.sender, tokenId);
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
            boosts[_layerId][msg.sender] += _tokenAmountOrId;
            layer.totalBoostedTokens += _tokenAmountOrId;

            emit LayerBoostedERC20(_layerId, msg.sender, _tokenAmountOrId);
        }
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

        uint256 circulatingSupply = totem.getCirculatingSupply();

        // Calculate user's shard reward
        uint256 shardReward = _calculateShardReward(
            boostAmount,
            layer.totalBoostedTokens,
            circulatingSupply
        );

        // Return tokens to user
        // Get token type from factory
        TotemFactory.TotemData memory totemData = factory.getTotemDataByAddress(
            layer.totemAddr
        );

        if (totemData.tokenType == TotemFactory.TokenType.ERC721) {
            // Return all NFTs that user boosted
            uint256[] storage userNFTs = nftBoosts[_layerId][msg.sender];
            IERC721 nftToken = IERC721(totemTokenAddr);

            for (uint256 i = 0; i < userNFTs.length; i++) {
                nftToken.safeTransferFrom(
                    address(this),
                    msg.sender,
                    userNFTs[i]
                );
            }

            // Clear the NFT array
            delete nftBoosts[_layerId][msg.sender];
        } else {
            // Transfer back ERC20 tokens
            IERC20(totemTokenAddr).safeTransfer(msg.sender, boostAmount);
        }

        // Mint shards for user
        if (shardReward > 0) {
            shards.mint(msg.sender, shardReward);
            totalShardRewards[_layerId] += shardReward;
            emit ShardsDistributed(_layerId, msg.sender, shardReward);

            // If this is the first unboost, calculate and distribute creator reward
            if (!creatorRewardClaimed[_layerId]) {
                uint256 totalLayerRewards = _calculateShardReward(
                    layer.totalBoostedTokens,
                    layer.totalBoostedTokens,
                    circulatingSupply
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
    function donateToLayer(uint256 _layerId) external payable whenNotPaused {
        Layer memory layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();

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
        payable(layer.creator).sendValue(creatorAmount);

        // Update total donations
        totalDonations[_layerId] += creatorAmount;

        // Award Merit points for donation only if totem is registered in Merit Manager
        if (meritManager.isRegisteredTotem(layer.totemAddr)) {
            meritManager.donationReward(layer.totemAddr, creatorAmount);
        }

        emit DonationReceived(_layerId, msg.sender, creatorAmount, fee);
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
     * @notice Get NFT token IDs boosted by a user for a specific layer
     * @param _layerId The layer ID
     * @param _user The user address
     * @return tokenIds Array of NFT token IDs
     */
    function getNFTBoosts(
        uint256 _layerId,
        address _user
    ) external view returns (uint256[] memory) {
        return nftBoosts[_layerId][_user];
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
     * @notice Get layer information without total boosted tokens
     * @param _layerId The layer ID
     * @return layer Layer information
     */
    function getLayer(uint256 _layerId) external view returns (Layer memory) {
        Layer memory layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();
        // If boost window is not closed, return 0
        // if (block.timestamp <= layer.createdAt + boostWindow)
        //     layer.totalBoostedTokens = 0;
        return layer;
    }

    /**
     * @notice Get pending layer information
     * @param _layerId The layer ID
     * @return layer Layer information
     */
    function getPendingLayer(
        uint256 _layerId
    ) external view returns (Layer memory) {
        return pendingLayers[_layerId];
    }

    /**
     * @notice Get the metadata hash for a layer
     * @param _layerId The layer ID
     * @return The metadata hash
     */
    function getMetadataHash(
        uint256 _layerId
    ) external view returns (bytes memory) {
        Layer storage layer = layers[_layerId];
        if (layer.creator == address(0)) revert LayerNotFound();
        return layer.metadataHash;
    }

    /**
     * @notice Get the pending layer ID for a specific user and totem
     * @param _user The user address
     * @param _totemAddr The totem address
     * @return The pending layer ID (0 if none)
     */
    function getUserPendingLayer(
        address _user,
        address _totemAddr
    ) external view returns (uint256) {
        return userPendingLayerByTotem[_user][_totemAddr];
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
