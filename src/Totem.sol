// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";
import {TotemToken} from "./TotemToken.sol";

/**
 * @title Totem
 * @notice This contract represents a Totem in the MYTHO ecosystem, managing token burning and merit distribution
 *      Handles the lifecycle of a Totem, including token burning after sale period and merit distribution
 */
contract Totem is AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using SafeERC20 for TotemToken;

    // State variables - Tokens
    TotemToken private totemToken;
    IERC20 private paymentToken;
    IERC20 private liquidityToken;
    IERC20 private mythoToken;

    // State variables - Data
    bytes private dataHash;

    // State variables - Addresses
    address private treasuryAddr;
    address private totemDistributorAddr;
    address private meritManagerAddr;
    address public owner;
    address[] public collaborators;

    // State variables - Flags
    bool private isCustomToken;
    bool public salePeriodEnded;

    // Constants
    bytes32 private constant TOTEM_DISTRIBUTOR = keccak256("TOTEM_DISTRIBUTOR");

    // Events
    event TotemTokenBurned(
        address indexed user,
        uint256 totemTokenAmount,
        uint256 paymentAmount,
        uint256 mythoAmount,
        uint256 lpAmount
    );
    event SalePeriodEnded();
    event MythoCollected(address indexed user, uint256 periodNum);

    // Custom errors
    error SalePeriodNotEnded();
    error InsufficientTotemBalance();
    error NothingToDistribute();
    error ZeroAmount();
    error ZeroCirculatingSupply();
    error InvalidParams();

    /**
     * @notice Initializes the Totem contract with token addresses, data hash, and revenue pool
     *      Sets up the initial state and grants roles
     * @param _totemToken The address of the TotemToken or custom token
     * @param _dataHash The data hash associated with this Totem
     * @param _registryAddr Address of the AddressRegistry contract
     * @param _isCustomToken Flag indicating if the token is custom (not burnable)
     * @param _owner The address of the Totem owner
     * @param _collaborators Array of collaborator addresses
     */
    function initialize(
        TotemToken _totemToken,
        bytes memory _dataHash,
        address _registryAddr,
        bool _isCustomToken,
        address _owner,
        address[] memory _collaborators
    ) public initializer {
        if (
            address(_totemToken) == address(0) ||
            _registryAddr == address(0) ||
            _owner == address(0) ||
            _dataHash.length == 0
        ) revert InvalidParams();

        __AccessControl_init();

        totemToken = _totemToken;
        dataHash = _dataHash;

        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();
        totemDistributorAddr = AddressRegistry(_registryAddr)
            .getTotemTokenDistributor();
        meritManagerAddr = AddressRegistry(_registryAddr).getMeritManager();
        mythoToken = IERC20(MeritManager(meritManagerAddr).mythoToken());

        isCustomToken = _isCustomToken;
        salePeriodEnded = false; // Initially, sale period is active

        // Set owner and collaborators
        owner = _owner;
        collaborators = _collaborators;

        if (_isCustomToken) {
            paymentToken = IERC20(
                TotemTokenDistributor(totemDistributorAddr).getPaymentToken()
            );
        }

        _grantRole(TOTEM_DISTRIBUTOR, totemDistributorAddr);
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Allows TotemToken holders to burn or transfer their tokens and receive proportional shares of assets
     *      After the sale period ends, burns TotemTokens for standard tokens or transfers custom tokens to treasuryAddr.
     *      User receives proportional shares of payment tokens, MYTHO tokens, and LP tokens based on circulating supply.
     * @param _totemTokenAmount The amount of TotemToken to burn or transfer
     */
    function burnTotemTokens(uint256 _totemTokenAmount) external {
        if (!isCustomToken && !salePeriodEnded) revert SalePeriodNotEnded();
        if (totemToken.balanceOf(msg.sender) < _totemTokenAmount)
            revert InsufficientTotemBalance();
        if (_totemTokenAmount == 0) revert ZeroAmount();

        // Get the circulating supply using the dedicated function
        uint256 circulatingSupply = getCirculatingSupply();
        if (circulatingSupply == 0) revert ZeroCirculatingSupply();

        // Check balances of all token types
        uint256 paymentTokenBalance = address(paymentToken) != address(0)
            ? paymentToken.balanceOf(address(this))
            : 0;
        uint256 mythoBalance = mythoToken.balanceOf(address(this));
        uint256 lpBalance = address(liquidityToken) != address(0)
            ? liquidityToken.balanceOf(address(this))
            : 0;

        // Check if all balances are zero
        if (paymentTokenBalance == 0 && mythoBalance == 0 && lpBalance == 0) {
            revert NothingToDistribute();
        }

        // Calculate user share for each token type based on circulating supply
        uint256 paymentAmount = (paymentTokenBalance * _totemTokenAmount) /
            circulatingSupply;
        uint256 mythoAmount = (mythoBalance * _totemTokenAmount) /
            circulatingSupply;
        uint256 lpAmount = (lpBalance * _totemTokenAmount) / circulatingSupply;

        // Take TotemTokens from the caller
        totemToken.safeTransferFrom(
            msg.sender,
            address(this),
            _totemTokenAmount
        );

        // Handle token disposal based on whether it's a custom token
        if (isCustomToken) {
            // For custom tokens, transfer to treasuryAddr instead of burning
            totemToken.safeTransfer(treasuryAddr, _totemTokenAmount);
        } else {
            // For standard TotemTokens, burn them
            totemToken.burn(_totemTokenAmount);
        }

        // Transfer the proportional payment tokens to the caller if there are any
        if (paymentAmount > 0) {
            paymentToken.safeTransfer(msg.sender, paymentAmount);
        }

        // Transfer MYTHO tokens if there are any
        if (mythoAmount > 0) {
            mythoToken.safeTransfer(msg.sender, mythoAmount);
        }

        // Transfer LP tokens if there are any
        if (lpAmount > 0 && address(liquidityToken) != address(0)) {
            liquidityToken.safeTransfer(msg.sender, lpAmount);
        }

        emit TotemTokenBurned(
            msg.sender,
            _totemTokenAmount,
            paymentAmount,
            mythoAmount,
            lpAmount
        );
    }

    /**
     * @notice Collects accumulated MYTHO from MeritManager for a specific period
     * @param _periodNum The period number to collect rewards for
     */
    function collectMYTH(uint256 _periodNum) public {
        MeritManager(meritManagerAddr).claimMytho(_periodNum);
        emit MythoCollected(msg.sender, _periodNum);
    }

    /**
     * @notice Sets the payment token and liquidity token addresses and ends the sale period
     *      Should be called by TotemTokenDistributor after sale period ends
     * @param _paymentToken The address of the payment token contract
     * @param _liquidityToken The address of the liquidity token (LP token)
     */
    function closeSalePeriod(
        IERC20 _paymentToken,
        IERC20 _liquidityToken
    ) external onlyRole(TOTEM_DISTRIBUTOR) {
        paymentToken = _paymentToken;
        liquidityToken = _liquidityToken;
        salePeriodEnded = true;

        emit SalePeriodEnded();
    }

    // VIEW FUNCTIONS

    /**
     * @notice Get the data hash associated with this Totem
     *      Returns the data hash that was set during initialization
     * @return The data hash stored in the contract
     */
    function getDataHash() external view returns (bytes memory) {
        return dataHash;
    }

    /**
     * @notice Get the addresses of tokens associated with this Totem
     * @return totemTokenAddr The address of the Totem token
     * @return paymentTokenAddr The address of the payment token
     * @return liquidityTokenAddr The address of the liquidity token
     */
    function getTokenAddresses()
        external
        view
        returns (
            address totemTokenAddr,
            address paymentTokenAddr,
            address liquidityTokenAddr
        )
    {
        return (
            address(totemToken),
            address(paymentToken),
            address(liquidityToken)
        );
    }

    /**
     * @notice Get all token balances of this Totem
     * @return totemBalance The balance of Totem tokens
     * @return paymentBalance The balance of payment tokens
     * @return liquidityBalance The balance of liquidity tokens
     * @return mythoBalance The balance of MYTHO tokens
     */
    function getAllBalances()
        external
        view
        returns (
            uint256 totemBalance,
            uint256 paymentBalance,
            uint256 liquidityBalance,
            uint256 mythoBalance
        )
    {
        totemBalance = totemToken.balanceOf(address(this));
        paymentBalance = address(paymentToken) != address(0)
            ? paymentToken.balanceOf(address(this))
            : 0;
        liquidityBalance = address(liquidityToken) != address(0)
            ? liquidityToken.balanceOf(address(this))
            : 0;

        address mythoAddr = MeritManager(meritManagerAddr).mythoToken();
        mythoBalance = mythoAddr != address(0)
            ? IERC20(mythoAddr).balanceOf(address(this))
            : 0;

        return (totemBalance, paymentBalance, liquidityBalance, mythoBalance);
    }

    /**
     * @notice Check if this is a custom token Totem
     * @return True if this is a custom token Totem, false otherwise
     */
    function isCustomTotemToken() external view returns (bool) {
        return isCustomToken;
    }

    /**
     * @notice Get the circulating supply of the TotemToken
     * @return The circulating supply (total supply minus tokens held by Totem and Treasury for custom tokens)
     */
    function getCirculatingSupply() public view returns (uint256) {
        uint256 totalSupply = totemToken.totalSupply();
        uint256 totemBalance = totemToken.balanceOf(address(this));
        uint256 treasuryBalance = isCustomToken
            ? totemToken.balanceOf(treasuryAddr)
            : 0;
        return totalSupply - totemBalance - treasuryBalance;
    }
}
