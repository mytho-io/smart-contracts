// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {MeritManager} from "./MeritManager.sol";

/**
 * @title Totem
 * @notice This contract represents a Totem in the MYTHO ecosystem, managing token burning and merit distribution
 * @dev Handles the lifecycle of a Totem, including token burning after sale period and merit distribution
 */
contract Totem is AccessControlUpgradeable {
    IERC20 private totemToken;
    IERC20 private paymentToken;

    bytes private dataHash;

    address private revenuePool;
    address private totemDistributorAddr;
    address private meritManagerAddr;

    bytes32 private constant MANAGER = keccak256("MANAGER");
    bytes32 private constant TOTEM_DISTRIBUTOR = keccak256("TOTEM_DISTRIBUTOR");

    bool private isCustomToken;
    bool public salePeriodEnded;

    // Events
    event TotemTokenBurned(
        address indexed user,
        uint256 totemTokenAmount,
        uint256 paymentAmount
    );
    event SalePeriodEnded();
    event MythoCollected(address indexed user, uint256 periodNum);

    // Custom errors
    error SalePeriodNotEnded();
    error InsufficientTotemBalance();
    error InsufficientPaymentTokenBalance();
    error ZeroAmount();

    /**
     * @notice Initializes the Totem contract with token addresses, data hash, and revenue pool
     * @dev Sets up the initial state and grants roles
     * @param _totemToken The address of the TotemToken or custom token
     * @param _dataHash The data hash associated with this Totem
     * @param _totemDistributorAddr The address of the TotemDistributor contract
     * @param _revenuePool The address of the revenue pool for custom token transfers
     * @param _isCustomToken Flag indicating if the token is custom (not burnable)
     */
    function initialize(
        IERC20 _totemToken,
        bytes memory _dataHash,
        address _totemDistributorAddr,
        address _revenuePool,
        bool _isCustomToken,
        address _meritManagerAddr
    ) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
        _grantRole(TOTEM_DISTRIBUTOR, _totemDistributorAddr);

        totemToken = _totemToken;
        dataHash = _dataHash;
        revenuePool = _revenuePool;
        isCustomToken = _isCustomToken;
        totemDistributorAddr = _totemDistributorAddr;
        meritManagerAddr = _meritManagerAddr;
        salePeriodEnded = false; // Initially, sale period is active
    }

    /**
     * @notice Allows TotemToken holders to burn or transfer their tokens and receive a proportional share of payment tokens
     * @dev After the sale period ends, burns TotemTokens for standard tokens or transfers custom tokens to revenuePool.
     *      User's share of payment tokens is proportional to their submitted tokens relative to the total supply.
     * @param _totemTokenAmount The amount of TotemToken to burn or transfer
     */
    function burnTotemTokens(uint256 _totemTokenAmount) external {
        if (!salePeriodEnded) revert SalePeriodNotEnded();
        if (totemToken.balanceOf(msg.sender) < _totemTokenAmount)
            revert InsufficientTotemBalance();
        if (_totemTokenAmount == 0) revert ZeroAmount();

        // Get the total supply of TotemToken
        uint256 totalSupply = totemToken.totalSupply();

        // Calculate the user's share of payment tokens based on their submitted amount
        uint256 paymentTokenBalance = paymentToken.balanceOf(address(this));
        uint256 paymentAmount = (paymentTokenBalance * _totemTokenAmount) /
            totalSupply;

        if (paymentAmount == 0 || paymentAmount > paymentTokenBalance)
            revert InsufficientPaymentTokenBalance();

        // Take TotemTokens from the caller
        totemToken.transferFrom(msg.sender, address(this), _totemTokenAmount);

        // Handle token disposal based on whether it's a custom token
        if (isCustomToken) {
            // For custom tokens, transfer to revenuePool instead of burning
            totemToken.transfer(revenuePool, _totemTokenAmount);
        } else {
            // For standard TotemTokens, burn them
            TotemTokenDistributor(totemDistributorAddr).burnTotemTokens(
                address(this),
                _totemTokenAmount
            );
        }

        // Transfer the proportional payment tokens to the caller
        paymentToken.transfer(msg.sender, paymentAmount);

        emit TotemTokenBurned(msg.sender, _totemTokenAmount, paymentAmount);
    }

    /**
     * @notice Collects accumulated MYTH from MeritManager
     * @dev Implementation pending
     */
    function collectMYTH(uint256 _periodNum) public {
        MeritManager(meritManagerAddr).claimMytho(_periodNum);
        emit MythoCollected(msg.sender, _periodNum);
    }

    /**
     * @notice Sets the payment token address and updates the sale period status
     * @dev Should be called by TotemTokenDistributor after sale period ends
     * @param _paymentToken The address of the payment token contract
     */
    function setPaymentTokenAndEndSale(
        IERC20 _paymentToken
    ) external onlyRole(TOTEM_DISTRIBUTOR) {
        paymentToken = _paymentToken;
        salePeriodEnded = true;

        emit SalePeriodEnded();
    }

    /**
     * @notice Get reserves of Totem in TotemTokens and Payment Tokens
     * @dev Returns the current balances of tokens held by this contract
     * @return totemReserve The balance of TotemToken in the contract
     * @return paymentReserve The balance of Payment Token in the contract
     */
    function getReserves()
        external
        view
        returns (uint256 totemReserve, uint256 paymentReserve)
    {
        return (
            totemToken.balanceOf(address(this)),
            paymentToken != IERC20(address(0))
                ? paymentToken.balanceOf(address(this))
                : 0
        );
    }

    /**
     * @notice Get the data hash associated with this Totem
     * @dev Returns the data hash that was set during initialization
     * @return The data hash stored in the contract
     */
    function getDataHash() external view returns (bytes memory) {
        return dataHash;
    }
}
