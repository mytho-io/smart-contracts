// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RevenuePool
 * @dev This contract manages and withdraws ERC20 and native tokens.
 * It provides functionality to:
 * - Withdraw ERC20 tokens to specified addresses
 * - Withdraw native tokens to specified addresses
 * - Check balances of ERC20 and native tokens
 */
contract Treasury is AccessControlUpgradeable {
    bytes32 private constant MANAGER = keccak256("MANAGER");

    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event NativeWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);

    function initialize() public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
    }

    /**
     * @dev Withdraws ERC20 tokens, restricted to MANAGER
     * @param _token Address of the ERC20 token to withdraw
     * @param _to Recipient address
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawERC20(address _token, address _to, uint256 _amount) external onlyRole(MANAGER) {
        if (_token == address(0) || _to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if (balance < _amount) revert InsufficientBalance(_amount, balance);
        IERC20(_token).transfer(_to, _amount);
        emit ERC20Withdrawn(_token, _to, _amount);
    }

    /**
     * @dev Withdraws native tokens, restricted to MANAGER
     * @param _to Recipient address (payable)
     * @param _amount Amount of native tokens to withdraw (in wei)
     */
    function withdrawNative(address payable _to, uint256 _amount) external onlyRole(MANAGER) {
        if (_to == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        if (address(this).balance < _amount) revert InsufficientBalance(_amount, address(this).balance);
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Native transfer failed");
        emit NativeWithdrawn(_to, _amount);
    }

    /**
     * @dev Allows contract to receive native tokens
     */
    receive() external payable {}

    /// READERS

    /**
     * @dev Returns balance of a specific ERC20 token
     * @param _token Address of the ERC20 token
     * @return Token balance of the contract
     */
    function getERC20Balance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    /**
     * @dev Returns native token balance
     * @return Native token balance of the contract (in wei)
     */
    function getNativeBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
