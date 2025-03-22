// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MYTHO Government Token
 * @notice Non-upgradeable ERC20 token with fixed supply and vesting distribution
 */
contract MYTHO is ERC20 {
    using SafeERC20 for ERC20;    

    // Token distribution constants
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens with 18 decimals
    
    // Totem incentives distribution (50% of total supply)
    uint256 public constant MERIT_YEAR_1 = 175_000_000 * 10**18; // 35% of incentives
    uint256 public constant MERIT_YEAR_2 = 125_000_000 * 10**18; // 25% of incentives
    uint256 public constant MERIT_YEAR_3 = 100_000_000 * 10**18; // 20% of incentives
    uint256 public constant MERIT_YEAR_4 = 50_000_000 * 10**18;  // 10% of incentives
    
    // Team allocation (20% of total supply)
    uint256 public constant TEAM_ALLOCATION = 200_000_000 * 10**18;
    
    // Treasury allocation (18% of total supply)
    uint256 public constant TREASURY_ALLOCATION = 180_000_000 * 10**18;
    
    // Mytho AMM incentives (7% of total supply)
    uint256 public constant AMM_INCENTIVES = 70_000_000 * 10**18;
    
    // Airdrop allocation (5% of total supply)
    uint256 public constant AIRDROP_ALLOCATION = 50_000_000 * 10**18;

    // Vesting duration constants
    uint64 public constant ONE_YEAR = 12 * 30 days;
    uint64 public constant TWO_YEARS = 2 * ONE_YEAR;
    uint64 public constant FOUR_YEARS = 4 * ONE_YEAR;

    // Vesting wallet and recipient addresses (immutable)
    address public immutable meritVestingYear1;
    address public immutable meritVestingYear2;
    address public immutable meritVestingYear3;
    address public immutable meritVestingYear4;
    address public immutable teamVesting;
    address public immutable ammVesting;
    address public immutable treasury;
    address public immutable airdrop;

    // Custom errors
    error ZeroAddressNotAllowed(string receiverType);
    error OnlyOwnerCanBurn();

    /**
     * @notice Constructor to deploy the token and set up vesting schedules
     * @param _meritManager Address to receive totem incentives
     * @param _teamReceiver Address to receive team allocation
     * @param _treasuryReceiver Address to receive treasury allocation
     * @param _ammReceiver Address to receive AMM incentives
     * @param _airdropReceiver Address to receive airdrop allocation
     */
    constructor(
        address _meritManager,
        address _teamReceiver,
        address _treasuryReceiver,
        address _ammReceiver,
        address _airdropReceiver
    ) ERC20("MYTHO Government Token", "MYTHO") {
        if (_meritManager == address(0)) revert ZeroAddressNotAllowed("totem receiver");
        if (_teamReceiver == address(0)) revert ZeroAddressNotAllowed("team receiver");
        if (_treasuryReceiver == address(0)) revert ZeroAddressNotAllowed("treasury receiver");
        if (_ammReceiver == address(0)) revert ZeroAddressNotAllowed("AMM receiver");
        if (_airdropReceiver == address(0)) revert ZeroAddressNotAllowed("airdrop receiver");

        // Set the start timestamp for vesting
        uint64 startTimestamp = uint64(block.timestamp);
        
        // Create vesting wallets for totem incentives (4 years with annual releases)
        meritVestingYear1 = address(new VestingWallet(_meritManager, startTimestamp, ONE_YEAR));
        meritVestingYear2 = address(new VestingWallet(_meritManager, startTimestamp + ONE_YEAR, ONE_YEAR));
        meritVestingYear3 = address(new VestingWallet(_meritManager, startTimestamp + 2 * ONE_YEAR, ONE_YEAR));
        meritVestingYear4 = address(new VestingWallet(_meritManager, startTimestamp + 3 * ONE_YEAR, ONE_YEAR));
        
        // Create vesting wallet for team (2 years)
        teamVesting = address(new VestingWallet(_teamReceiver, startTimestamp, TWO_YEARS));
        
        // Create vesting wallet for AMM incentives (2 years)
        ammVesting = address(new VestingWallet(_ammReceiver, startTimestamp, TWO_YEARS));
        
        // Treasury (no vesting, immediate access)
        treasury = _treasuryReceiver;
        
        // Airdrop (no vesting, immediate access)
        airdrop = _airdropReceiver;

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
        _transfer(address(this), airdrop, AIRDROP_ALLOCATION);
    }

    /**
     * @notice Burns tokens from the caller's address
     * @dev Can only be called by the token owner
     * @param _account Address from which tokens are burned
     * @param _amount Amount of tokens to burn
     */
    function burn(address _account, uint256 _amount) external {
        if (msg.sender != _account) revert OnlyOwnerCanBurn();
        _burn(_account, _amount);
    }

    /// TEST LOGIC

    function mint(address _account, uint256 _amount) external {
        _mint(_account, _amount);
    }
}