// SPDX-License-Identifier: BUSL-1.1
// Copyright © 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {ERC721Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";

/**
 * @title BadgeNFT
 * @notice NFT contract for milestone achievement badges in the Boost System
 * @dev Implements ERC721 with milestone-based badge minting functionality
 */
contract BadgeNFT is
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    // State variables
    uint256 private _tokenIdCounter;
    address private boostSystem;

    // Milestone configuration
    mapping(uint256 milestone => string uri) private milestoneURIs;
    mapping(uint256 tokenId => uint256 milestone) private tokenMilestones;
    mapping(address user => mapping(uint256 milestone => uint256 count))
        private userBadgeCounts;

    // Constants - Roles
    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant MINTER = keccak256("MINTER");

    // Events
    event BadgeMinted(
        address indexed to,
        uint256 indexed tokenId,
        uint256 indexed milestone
    );
    event MilestoneURIUpdated(uint256 indexed milestone, string uri);
    event BoostSystemUpdated(
        address indexed oldBoostSystem,
        address indexed newBoostSystem
    );

    // Errors
    error OnlyBoostSystem();
    error InvalidMilestone();
    error MilestoneURINotSet();

    function initialize(
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __ERC721URIStorage_init();
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        _tokenIdCounter = 1; // Start token IDs from 1

        // 7, 14, 30, 100, 200 days
        milestoneURIs[7] = "7 days";
        milestoneURIs[14] = "14 days";
        milestoneURIs[30] = "30 days";
        milestoneURIs[100] = "100 days";
        milestoneURIs[200] = "200 days";
    }

    // MODIFIERS

    modifier onlyBoostSystem() {
        if (msg.sender != boostSystem) revert OnlyBoostSystem();
        _;
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Mint badge for achieved milestone (called by BoostSystem)
     * @param to Address to mint badge to
     * @param milestone Milestone achieved (7, 14, 30, 100, 200)
     * @return tokenId Minted token ID
     */
    function mintBadge(
        address to,
        uint256 milestone
    ) external onlyBoostSystem whenNotPaused returns (uint256 tokenId) {
        if (bytes(milestoneURIs[milestone]).length == 0)
            revert MilestoneURINotSet();

        tokenId = _tokenIdCounter++;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, milestoneURIs[milestone]);

        tokenMilestones[tokenId] = milestone;
        userBadgeCounts[to][milestone]++;

        emit BadgeMinted(to, tokenId, milestone);
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Set the BoostSystem contract address
     * @param _boostSystem Address of the BoostSystem contract
     */
    function setBoostSystem(address _boostSystem) external onlyRole(MANAGER) {
        address oldBoostSystem = boostSystem;
        boostSystem = _boostSystem;
        _grantRole(MINTER, _boostSystem);

        if (oldBoostSystem != address(0)) {
            _revokeRole(MINTER, oldBoostSystem);
        }

        emit BoostSystemUpdated(oldBoostSystem, _boostSystem);
    }

    /**
     * @notice Set URI for a specific milestone
     * @param milestone Milestone value (7, 14, 30, 100, 200)
     * @param uri Metadata URI for the milestone badge
     */
    function setMilestoneURI(
        uint256 milestone,
        string calldata uri
    ) external onlyRole(MANAGER) {
        milestoneURIs[milestone] = uri;
        emit MilestoneURIUpdated(milestone, uri);
    }

    /**
     * @notice Set URIs for multiple milestones at once
     * @param milestones Array of milestone values
     * @param uris Array of corresponding URIs
     */
    function setMilestoneURIs(
        uint256[] calldata milestones,
        string[] calldata uris
    ) external onlyRole(MANAGER) {
        require(milestones.length == uris.length, "Arrays length mismatch");

        for (uint256 i = 0; i < milestones.length; i++) {
            milestoneURIs[milestones[i]] = uris[i];
            emit MilestoneURIUpdated(milestones[i], uris[i]);
        }
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyRole(MANAGER) {
        _unpause();
    }

    // VIEW FUNCTIONS

    /**
     * @notice Get milestone for a specific token
     * @param tokenId Token ID
     * @return milestone Milestone value
     */
    function getTokenMilestone(
        uint256 tokenId
    ) external view returns (uint256 milestone) {
        _requireOwned(tokenId);
        return tokenMilestones[tokenId];
    }

    /**
     * @notice Get URI for a specific milestone
     * @param milestone Milestone value
     * @return uri Metadata URI
     */
    function getMilestoneURI(
        uint256 milestone
    ) external view returns (string memory uri) {
        return milestoneURIs[milestone];
    }

    /**
     * @notice Get badge count for user by milestone
     * @param user User address
     * @param milestone Milestone value
     * @return count Number of badges for this milestone
     */
    function getUserBadgeCount(
        address user,
        uint256 milestone
    ) external view returns (uint256 count) {
        return userBadgeCounts[user][milestone];
    }

    /**
     * @notice Get total badge count for user across all milestones
     * @param user User address
     * @return totalCount Total number of badges
     */
    function getUserTotalBadgeCount(
        address user
    ) external view returns (uint256 totalCount) {
        return balanceOf(user);
    }

    /**
     * @notice Get current token ID counter
     * @return counter Current token ID counter
     */
    function getCurrentTokenId() external view returns (uint256 counter) {
        return _tokenIdCounter;
    }

    /**
     * @notice Get BoostSystem contract address
     * @return boostSystemAddr Address of the BoostSystem contract
     */
    function getBoostSystem() external view returns (address boostSystemAddr) {
        return boostSystem;
    }

    /**
     * @notice Check if milestone URI is set
     * @param milestone Milestone value
     * @return isSet Whether URI is set for this milestone
     */
    function isMilestoneURISet(
        uint256 milestone
    ) external view returns (bool isSet) {
        return bytes(milestoneURIs[milestone]).length > 0;
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Override required by Solidity for multiple inheritance
     */
    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    /**
     * @notice Override required by Solidity for multiple inheritance
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            ERC721Upgradeable,
            ERC721URIStorageUpgradeable,
            AccessControlUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Hook called before token transfer
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }
}
