// SPDX-License-Identifier: BUSL-1.1
// Copyright © 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {AddressRegistry} from "./AddressRegistry.sol";

/**
 * @title MYTHO Government Token
 */
contract MYTHOBNB is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable
{
    // Token distribution
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens with 18 decimals

    // Vesting duration
    uint64 public constant ONE_YEAR = 12 * 30 days;
    uint64 public constant TWO_YEARS = 2 * ONE_YEAR;
    uint64 public constant FOUR_YEARS = 4 * ONE_YEAR;

    // Roles
    bytes32 public constant MANAGER = keccak256("MANAGER");
    bytes32 public constant MULTISIG = keccak256("MULTISIG");

    // Vesting wallet addresses for merit distribution
    address public meritVestingYear1;
    address public meritVestingYear2;
    address public meritVestingYear3;
    address public meritVestingYear4;

    // Registry address
    address public registryAddr;

    // Track total minted amount (never decreases, even with burns)
    uint256 public totalMinted;

    // Merit distribution state
    bool public meritDistributionInitialized;

    // Custom errors
    error ZeroAddressNotAllowed(string receiverType);
    error EcosystemPaused();
    error InvalidAmount();
    error ExceedsMaxSupply();
    error MeritDistributionAlreadyInitialized();
    error InvalidStartTime();

    // Events
    event VestingCreated(
        address indexed beneficiary,
        address vestingWallet,
        uint256 amount,
        uint64 duration
    );
    event MeritDistributionInitialized(
        address indexed meritManager,
        uint64 startTimestamp,
        uint256[4] amounts,
        address year1,
        address year2,
        address year3,
        address year4
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the MYTHO token contract
     * @param _registryAddr Address of the registry contract
     */
    function initialize(address _registryAddr) public initializer {
        __ERC20_init("MYTHO Governance Token", "MYTHO");
        __ERC20Pausable_init();
        __AccessControl_init();

        if (_registryAddr == address(0))
            revert ZeroAddressNotAllowed("registry");

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
        _grantRole(MULTISIG, msg.sender);

        // Set registry address
        registryAddr = _registryAddr;

        // Merit distribution will be initialized separately via initializeMeritDistribution
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Pauses all token transfers
     */
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers
     */
    function unpause() external onlyRole(MANAGER) {
        _unpause();
    }

    /**
     * @notice Initializes merit distribution by creating vesting wallets
     * @param _amounts Array of token amounts for each year [year1, year2, year3, year4]
     * @param _startTimestamp When vesting should start
     * @dev Can only be called once. Gets MeritManager address from registry.
     */
    function initializeMeritDistribution(
        uint256[4] calldata _amounts,
        uint64 _startTimestamp
    ) external onlyRole(MULTISIG) {
        if (meritDistributionInitialized) revert MeritDistributionAlreadyInitialized();
        if (_startTimestamp <= block.timestamp) revert InvalidStartTime();

        // Get MeritManager address from registry
        address meritManager = AddressRegistry(registryAddr).getMeritManager();
        if (meritManager == address(0)) revert ZeroAddressNotAllowed("merit manager");

        // Calculate total amount needed
        uint256 totalMeritAmount = _amounts[0] + _amounts[1] + _amounts[2] + _amounts[3];
        if (totalMeritAmount == 0) revert InvalidAmount();
        if (totalMinted + totalMeritAmount > TOTAL_SUPPLY) revert ExceedsMaxSupply();

        // Create vesting wallets for merit distribution (4 years)
        meritVestingYear1 = address(
            new VestingWallet(meritManager, _startTimestamp, ONE_YEAR)
        );
        meritVestingYear2 = address(
            new VestingWallet(meritManager, _startTimestamp + ONE_YEAR, ONE_YEAR)
        );
        meritVestingYear3 = address(
            new VestingWallet(meritManager, _startTimestamp + 2 * ONE_YEAR, ONE_YEAR)
        );
        meritVestingYear4 = address(
            new VestingWallet(meritManager, _startTimestamp + 3 * ONE_YEAR, ONE_YEAR)
        );

        // Update total minted tracking
        totalMinted += totalMeritAmount;

        // Mint tokens to vesting wallets
        if (_amounts[0] > 0) _mint(meritVestingYear1, _amounts[0]);
        if (_amounts[1] > 0) _mint(meritVestingYear2, _amounts[1]);
        if (_amounts[2] > 0) _mint(meritVestingYear3, _amounts[2]);
        if (_amounts[3] > 0) _mint(meritVestingYear4, _amounts[3]);

        meritDistributionInitialized = true;

        emit MeritDistributionInitialized(
            meritManager,
            _startTimestamp,
            _amounts,
            meritVestingYear1,
            meritVestingYear2,
            meritVestingYear3,
            meritVestingYear4
        );
    }

    /**
     * @notice Creates a new vesting wallet and mints tokens to it
     * @param beneficiary Address that will receive the vested tokens
     * @param amount Amount of tokens to vest
     * @param startTimestamp When vesting starts
     * @param durationSeconds Duration of vesting in seconds
     * @return vestingWallet Address of the created vesting wallet
     */
    function createVesting(
        address beneficiary,
        uint256 amount,
        uint64 startTimestamp,
        uint64 durationSeconds
    ) external onlyRole(MULTISIG) returns (address vestingWallet) {
        if (beneficiary == address(0))
            revert ZeroAddressNotAllowed("beneficiary");
        if (amount == 0) revert InvalidAmount();
        if (totalMinted + amount > TOTAL_SUPPLY) revert ExceedsMaxSupply();

        // Create new vesting wallet
        vestingWallet = address(
            new VestingWallet(beneficiary, startTimestamp, durationSeconds)
        );

        // Update total minted tracking
        totalMinted += amount;

        // Mint tokens directly to vesting wallet
        _mint(vestingWallet, amount);

        emit VestingCreated(
            beneficiary,
            vestingWallet,
            amount,
            durationSeconds
        );
    }

    /**
     * @dev Throws if the contract is paused or if the ecosystem is paused.
     */
    function _requireNotPaused() internal view virtual override {
        super._requireNotPaused();
        if (
            registryAddr != address(0) &&
            AddressRegistry(registryAddr).isEcosystemPaused()
        ) {
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

    /**
     * @notice Checks if merit distribution has been initialized
     * @return Whether merit distribution vesting wallets have been created
     */
    function isMeritDistributionInitialized() external view returns (bool) {
        return meritDistributionInitialized;
    }

    /**
     * @notice Gets all merit vesting wallet addresses
     * @return Array of merit vesting wallet addresses [year1, year2, year3, year4]
     */
    function getMeritVestingWallets() external view returns (address[4] memory) {
        return [meritVestingYear1, meritVestingYear2, meritVestingYear3, meritVestingYear4];
    }

    /**
     * @notice Gets the address registry
     * @return Address of the AddressRegistry contract
     */
    function getRegistry() external view returns (address) {
        return registryAddr;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
