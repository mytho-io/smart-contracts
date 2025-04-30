// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MYTHO Government Token for non-native chains (Upgradeable)
 * @dev This token is used on non-native chains and implements the IBurnMintERC20 interface
 * for cross-chain transfers via CCIP's BurnMintTokenPool
 */
contract BurnMintMYTHO is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    OwnableUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for ERC20Upgradeable;

    // Allowed minter addresses
    EnumerableSet.AddressSet internal s_minters;
    // Allowed burner addresses
    EnumerableSet.AddressSet internal s_burners;

    // Events
    event MintAccessGranted(address indexed minter);
    event BurnAccessGranted(address indexed burner);
    event MintAccessRevoked(address indexed minter);
    event BurnAccessRevoked(address indexed burner);

    // Custom errors
    error ZeroAddressNotAllowed(string receiverType);
    error SenderNotMinter(address sender);
    error SenderNotBurner(address sender);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the BurnMintMYTHO token contract for non-native chains
     */
    function initialize() public initializer {
        __ERC20_init("MYTHO Government Token", "MYTHO");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(msg.sender);

        // No initial token minting or distribution
        // Tokens will be minted by the BurnMintTokenPool when transferred from the native chain
    }

    // MODIFIERS

    /// @notice Checks whether the msg.sender is a permissioned minter for this token
    /// @dev Reverts with a SenderNotMinter if the check fails
    modifier onlyMinter() {
        if (!isMinter(msg.sender)) revert SenderNotMinter(msg.sender);
        _;
    }

    /// @notice Checks whether the msg.sender is a permissioned burner for this token
    /// @dev Reverts with a SenderNotBurner if the check fails
    modifier onlyBurner() {
        if (!isBurner(msg.sender)) revert SenderNotBurner(msg.sender);
        _;
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Mints new tokens to the specified account
     * @param account The address to mint tokens to
     * @param amount The amount of tokens to mint
     * @dev Implements IBurnMintERC20.mint
     */
    function mint(address account, uint256 amount) external onlyMinter {
        _mint(account, amount);
    }

    /**
     * @notice Burns tokens from the caller's account
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) public override onlyBurner {
        super.burn(amount);
    }

    /**
     * @notice Burns tokens from a specified account
     * @param account The address to burn tokens from
     * @param amount The amount of tokens to burn
     * @dev Implements IBurnMintERC20.burn(address,uint256)
     */
    function burn(address account, uint256 amount) public virtual {
        burnFrom(account, amount);
    }

    /**
     * @notice Burns tokens from a specified account
     * @param account The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(
        address account,
        uint256 amount
    ) public override onlyBurner {
        _burn(account, amount);
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Pauses all token transfers
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Grants minting permission to an address
     * @param minter The address to grant minting permission to
     */
    function grantMintAccess(address minter) external onlyOwner {
        if (minter == address(0)) revert ZeroAddressNotAllowed("minter");
        if (s_minters.add(minter)) {
            emit MintAccessGranted(minter);
        }
    }

    /**
     * @notice Revokes minting permission from an address
     * @param minter The address to revoke minting permission from
     */
    function revokeMintAccess(address minter) external onlyOwner {
        if (s_minters.remove(minter)) {
            emit MintAccessRevoked(minter);
        }
    }

    /**
     * @notice Grants burning permission to an address
     * @param burner The address to grant burning permission to
     */
    function grantBurnAccess(address burner) external onlyOwner {
        if (burner == address(0)) revert ZeroAddressNotAllowed("burner");
        if (s_burners.add(burner)) {
            emit BurnAccessGranted(burner);
        }
    }

    /**
     * @notice Revokes burning permission from an address
     * @param burner The address to revoke burning permission from
     */
    function revokeBurnAccess(address burner) external onlyOwner {
        if (s_burners.remove(burner)) {
            emit BurnAccessRevoked(burner);
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

    // VIEW FUNCTIONS

    /**
     * @notice Returns all permissioned minters
     * @return Array of minter addresses
     */
    function getMinters() external view returns (address[] memory) {
        return s_minters.values();
    }

    /**
     * @notice Returns all permissioned burners
     * @return Array of burner addresses
     */
    function getBurners() external view returns (address[] memory) {
        return s_burners.values();
    }

    /**
     * @notice Checks whether a given address is a minter for this token
     * @param minter The address to check
     * @return true if the address is allowed to mint
     */
    function isMinter(address minter) public view returns (bool) {
        return s_minters.contains(minter);
    }

    /**
     * @notice Checks whether a given address is a burner for this token
     * @param burner The address to check
     * @return true if the address is allowed to burn
     */
    function isBurner(address burner) public view returns (bool) {
        return s_burners.contains(burner);
    }
}
