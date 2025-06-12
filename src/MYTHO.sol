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
contract MYTHO is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable
{
    // Token distribution
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens with 18 decimals

    // Totem incentives distribution (20M total)
    uint256 public constant MERIT_YEAR_1 = 8_000_000 * 10 ** 18; // 40% of 20M
    uint256 public constant MERIT_YEAR_2 = 6_000_000 * 10 ** 18; // 30% of 20M
    uint256 public constant MERIT_YEAR_3 = 4_000_000 * 10 ** 18; // 20% of 20M
    uint256 public constant MERIT_YEAR_4 = 2_000_000 * 10 ** 18; // 10% of 20M

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

    // Custom errors
    error ZeroAddressNotAllowed(string receiverType);
    error EcosystemPaused();
    error InvalidAmount();
    error ExceedsMaxSupply();

    // Events
    event VestingCreated(
        address indexed beneficiary,
        address vestingWallet,
        uint256 amount,
        uint64 duration
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the MYTHO token contract
     * @param _meritManager Address to receive totem incentives
     * @param _registryAddr Address of the registry contract
     */
    function initialize(
        address _meritManager,
        address _registryAddr
    ) public initializer {
        __ERC20_init("MYTHO Government Token", "MYTHO");
        __ERC20Pausable_init();
        __AccessControl_init();

        if (_meritManager == address(0))
            revert ZeroAddressNotAllowed("merit manager");
        if (_registryAddr == address(0))
            revert ZeroAddressNotAllowed("registry");

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
        _grantRole(MULTISIG, msg.sender);

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

        // Set registry address
        registryAddr = _registryAddr;

        // Mint and distribute only merit tokens to vesting wallets
        uint256 meritTotal = MERIT_YEAR_1 + MERIT_YEAR_2 + MERIT_YEAR_3 + MERIT_YEAR_4;
        totalMinted = meritTotal;

        _mint(meritVestingYear1, MERIT_YEAR_1);
        _mint(meritVestingYear2, MERIT_YEAR_2);
        _mint(meritVestingYear3, MERIT_YEAR_3);
        _mint(meritVestingYear4, MERIT_YEAR_4);
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
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
