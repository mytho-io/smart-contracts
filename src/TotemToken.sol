// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TotemToken
 * @notice ERC20 token with sale period restrictions and role-based access control
 * @dev Extends ERC20 and AccessControl to manage token distribution and transfers
 */
contract TotemToken is ERC20, AccessControl {
    // Indicates if the token is in the sale period (transfers restricted)
    bool private salePeriod;

    // Mapping of addresses allowed to receive tokens during the sale period
    mapping(address => bool) private allowedRecipients;

    // Roles
    bytes32 private constant MANAGER = keccak256("MANAGER");
    bytes32 private constant TOTEM_DISTRIBUTOR = keccak256("TOTEM_DISTRIBUTOR");

    // Custom errors
    error NotAllowedInSalePeriod();    
    error OnlyForDistributor();

    /**
     * @dev Mints 1_000_000_000 tokens and assigns roles; 100% goes to the distributor initially
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param _totemDistributorAddr The address of the totem distributor
     */
    constructor(
        string memory name, 
        string memory symbol,
        address _totemDistributorAddr
    ) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
        _grantRole(TOTEM_DISTRIBUTOR, _totemDistributorAddr);

        _mint(_totemDistributorAddr, 1_000_000_000 ether);
        
        salePeriod = true;
    }

    /**
     * @notice Opens token transfers, ending the sale period
     * @dev Can only be called by the totem distributor
     */
    function openTransfers() external onlyRole(TOTEM_DISTRIBUTOR) {
        salePeriod = false;
    }

    function burn(address _who, uint256 _amount) external onlyRole(TOTEM_DISTRIBUTOR) {
        _burn(_who, _amount);
    }

    /**
     * @notice Adds an address to the list of allowed recipients during sale period
     * @dev Restricted to the MANAGER role
     * @param _recipient The address to be allowed as a recipient
     */
    function addAllowedRecipient(address _recipient) external onlyRole(MANAGER) {
        allowedRecipients[_recipient] = true;
    }

    /**
     * @notice Removes an address from the list of allowed recipients during sale period
     * @dev Restricted to the MANAGER role
     * @param _recipient The address to be removed from allowed recipients
     */
    function removeAllowedRecipient(address _recipient) external onlyRole(MANAGER) {
        allowedRecipients[_recipient] = false;
    }

    /**
     * @notice Checks if an address is an allowed recipient during the sale period
     * @param _addr The address to check
     * @return bool True if the address is an allowed recipient, false otherwise
     */
    function isAllowedRecipient(address _addr) public view returns (bool) {
        return allowedRecipients[_addr];
    }

    /// INTERNAL LOGIC

    /**
     * @notice Updates token balances with transfer restrictions during sale period
     * @dev Overrides ERC20 _update to enforce sale period rules
     * @param from The address sending the tokens
     * @param to The address receiving the tokens
     * @param value The amount of tokens being transferred
     */
    function _update(address from, address to, uint256 value) internal override {
        if (salePeriod && !hasRole(TOTEM_DISTRIBUTOR, msg.sender)) revert NotAllowedInSalePeriod();
        super._update(from, to, value);
    }
}