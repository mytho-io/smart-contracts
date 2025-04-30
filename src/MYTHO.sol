// SPDX-License-Identifier: BUSL-1.1
// Copyright © 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
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
}
