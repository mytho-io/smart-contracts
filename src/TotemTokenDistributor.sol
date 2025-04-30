// SPDX-License-Identifier: BUSL-1.1
// Copyright © 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TotemFactory} from "./TotemFactory.sol";
import {TotemToken} from "./TotemToken.sol";
import {Totem} from "./Totem.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";

import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/**
 * @title TotemTokenDistributor
 * @notice This contract manages the distribution of Totem tokens during and after sales periods
 *      Handles registration of new totems, token sales, distribution of collected payment tokens,
 *      adding liquidity to AMM pools, and burning totem tokens
 */

contract TotemTokenDistributor is
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // State variables - Contracts
    TotemFactory private factory;
    MeritManager private meritManager;
    IERC20 private mytho;

    // State variables - Configuration
    uint256 private oneTotemPriceInUsd;
    uint256 public maxTokensPerAddress;
    uint256 public slippagePercentage = 500; // Default 5% slippage (500/10000)

    // State variables - Distribution shares
    uint256 public revenuePaymentTokenShare;
    uint256 public totemCreatorPaymentTokenShare;
    uint256 public poolPaymentTokenShare;
    uint256 public vaultPaymentTokenShare;

    // State variables - Addresses
    address private treasuryAddr; // contract address for revenue in payment tokens
    address private paymentTokenAddr; // address of payment token
    address private uniswapV2RouterAddr; // Uniswap V2 router address
    address private registryAddr; // address of the AddressRegistry contract

    // State variables - Mappings
    mapping(address => address) private priceFeedAddresses; // Mapping from token address to Chainlink price feed address
    mapping(address totemTokenAddr => TotemData TotemData) private totems; // General info about totems
    mapping(address userAddress => mapping(address totemTokenAddr => SalePosInToken))
        private salePositions;

    // Constants
    uint256 private constant PRECISION = 10000;
    uint256 private constant POOL_INITIAL_SUPPLY = 200_000_000 ether;
    uint256 public constant PRICE_FEED_STALE_THRESHOLD = 1 hours; // Maximum age of price feed data before it's considered stale (1 hour)

    bytes32 private constant MANAGER = keccak256("MANAGER");

    // Structs
    struct TotemData {
        address totemAddr;
        address creator;
        address paymentToken;
        bool registered;
        bool isSalePeriod;
        uint256 collectedPaymentTokens;
    }

    struct SalePosInToken {
        // Payment tokens which spent on totems
        uint256 paymentTokenAmount;
        // Totem tokens which bought for payment tokens
        uint256 totemTokenAmount;
    }

    // Events
    event TotemTokensBought(
        address buyer,
        address paymentTokenAddr,
        address totemTokenAddr,
        uint256 totemTokenAmount,
        uint256 paymentTokenAmount
    );
    event TotemTokensSold(
        address buyer,
        address paymentTokenAddr,
        address totemTokenAddr,
        uint256 totemTokenAmount,
        uint256 paymentTokenAmount
    );
    event TotemRegistered(
        address totemAddr,
        address creator,
        address totemTokenAddr
    );
    event SalePeriodClosed(address totemTokenAddr, uint256 totalCollected);
    event LiquidityAdded(
        address totemTokenAddr,
        address paymentTokenAddr,
        uint256 totemAmount,
        uint256 paymentAmount,
        uint256 liquidity
    );
    event TokenDistributionSharesUpdated(
        uint256 revenueShare,
        uint256 creatorShare,
        uint256 poolShare,
        uint256 vaultShare
    );
    event PriceFeedSet(address tokenAddr, address priceFeedAddr);

    // Custom errors
    error AlreadyRegistered(address totemTokenAddr);
    error UnknownTotemToken(address tokenAddr);
    error WrongAmount(uint256 tokenAmount);
    error SalePeriodAlreadyEnded();
    error WrongPaymentTokenAmount(uint256 paymentTokenAmount);
    error AlreadySet();
    error OnlyFactory();
    error ZeroAddress();
    error InvalidShares();
    error NoPriceFeedSet(address tokenAddr);
    error InvalidPrice(address tokenAddr);
    error StalePrice(address tokenAddr);
    error LiquidityAdditionFailed();
    error UniswapRouterNotSet();
    error EcosystemPaused();

    /**
     * @notice Initializes the TotemTokenDistributor contract
     *      Sets up initial roles and configuration
     * @param _registryAddr Address of the AddressRegistry contract
     */
    function initialize(address _registryAddr) public initializer {
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        if (_registryAddr == address(0)) revert ZeroAddress();

        registryAddr = _registryAddr;
        AddressRegistry registry = AddressRegistry(_registryAddr);
        mytho = IERC20(registry.getMythoToken());
        treasuryAddr = registry.getMythoTreasury();
        meritManager = MeritManager(registry.getMeritManager());

        maxTokensPerAddress = 5_000_000 ether;
        oneTotemPriceInUsd = 0.00004 ether;

        // Initialize distribution shares
        revenuePaymentTokenShare = 250; // 2.5%
        totemCreatorPaymentTokenShare = 50; // 0.5%
        poolPaymentTokenShare = 2857; // 28.57%
        vaultPaymentTokenShare = 6843; // 68.43%
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Being called by TotemFactory during totem creation
     *      Registers a new totem and distributes initial tokens
     */
    function register() external whenNotPaused {
        if (address(factory) == address(0)) revert AlreadySet();
        if (msg.sender != address(factory)) revert OnlyFactory();
        if (paymentTokenAddr == address(0)) revert ZeroAddress();

        // get info about the totem being created
        TotemFactory.TotemData memory totemDataFromFactory = factory
            .getTotemData(factory.getLastId() - 1);

        if (totems[totemDataFromFactory.totemTokenAddr].registered)
            revert AlreadyRegistered(totemDataFromFactory.totemTokenAddr);

        totems[totemDataFromFactory.totemTokenAddr] = TotemData(
            totemDataFromFactory.totemAddr,
            totemDataFromFactory.creator,
            paymentTokenAddr,
            true,
            true,
            0
        );

        TotemToken token = TotemToken(totemDataFromFactory.totemTokenAddr);
        token.transfer(totemDataFromFactory.creator, 250_000 ether);
        token.transfer(totemDataFromFactory.totemAddr, 100_000_000 ether);

        emit TotemRegistered(
            totemDataFromFactory.totemAddr,
            totemDataFromFactory.creator,
            totemDataFromFactory.totemTokenAddr
        );
    }

    /**
     * @notice Buy totem tokens for allowed payment tokens
     * @param _totemTokenAddr Address of the totem token to buy
     * @param _totemTokenAmount Amount of totem tokens to buy
     */
    function buy(
        address _totemTokenAddr,
        uint256 _totemTokenAmount
    ) external whenNotPaused {
        if (!totems[_totemTokenAddr].registered)
            revert UnknownTotemToken(_totemTokenAddr);
        if (!totems[_totemTokenAddr].isSalePeriod)
            revert SalePeriodAlreadyEnded();
        if (
            // check if contract has enough totem tokens + initial pool supply
            IERC20(_totemTokenAddr).balanceOf(address(this)) <
            _totemTokenAmount + POOL_INITIAL_SUPPLY ||
            // check if user has no more than maxTokensPerAddress
            IERC20(_totemTokenAddr).balanceOf(msg.sender) + _totemTokenAmount >
            maxTokensPerAddress ||
            _totemTokenAmount == 0
        ) revert WrongAmount(_totemTokenAmount);

        if (paymentTokenAddr == address(0)) revert ZeroAddress();

        uint256 paymentTokenAmount = totemsToPaymentToken(
            paymentTokenAddr,
            _totemTokenAmount
        );

        // check if user has enough payment tokens
        if (IERC20(paymentTokenAddr).balanceOf(msg.sender) < paymentTokenAmount)
            revert WrongPaymentTokenAmount(paymentTokenAmount);

        // update totems payment token amount
        totems[_totemTokenAddr].collectedPaymentTokens += paymentTokenAmount;

        // update user sale position
        SalePosInToken storage position = salePositions[msg.sender][
            _totemTokenAddr
        ];
        position.paymentTokenAmount += paymentTokenAmount;
        position.totemTokenAmount += _totemTokenAmount;

        // Transfer tokens using SafeERC20
        IERC20(paymentTokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            paymentTokenAmount
        );
        IERC20(_totemTokenAddr).safeTransfer(msg.sender, _totemTokenAmount);

        emit TotemTokensBought(
            msg.sender,
            paymentTokenAddr,
            _totemTokenAddr,
            _totemTokenAmount,
            paymentTokenAmount
        );

        // close sale period when the remaining tokens are exactly what's needed for the pool
        if (
            IERC20(_totemTokenAddr).balanceOf(address(this)) ==
            POOL_INITIAL_SUPPLY
        ) {
            _closeSalePeriod(_totemTokenAddr);
        }
    }

    /**
     * @notice Sell totem tokens for used payment token in sale period
     * @param _totemTokenAddr Address of the totem token to sell
     * @param _totemTokenAmount Amount of totem tokens to sell
     */
    function sell(
        address _totemTokenAddr,
        uint256 _totemTokenAmount
    ) external whenNotPaused {
        if (!totems[_totemTokenAddr].registered)
            revert UnknownTotemToken(_totemTokenAddr);
        if (!totems[_totemTokenAddr].isSalePeriod)
            revert SalePeriodAlreadyEnded();

        SalePosInToken storage position = salePositions[msg.sender][
            _totemTokenAddr
        ];
        address _paymentTokenAddr = totems[_totemTokenAddr].paymentToken;

        // check if balances are correct
        if (
            _totemTokenAmount > position.totemTokenAmount ||
            _totemTokenAmount > IERC20(_totemTokenAddr).balanceOf(msg.sender) ||
            _totemTokenAmount == 0
        ) revert WrongAmount(_totemTokenAmount);

        // calculate the right number of payment tokens according to _totemTokenAmount share in sale position
        uint256 paymentTokensBack = (position.paymentTokenAmount *
            _totemTokenAmount) / position.totemTokenAmount;

        // update totems payment token amount
        totems[_totemTokenAddr].collectedPaymentTokens -= paymentTokensBack;

        // update user sale position
        position.totemTokenAmount -= _totemTokenAmount;
        position.paymentTokenAmount -= paymentTokensBack;

        // send payment tokens and take totem tokens using SafeERC20
        IERC20(_totemTokenAddr).safeTransferFrom(
            msg.sender,
            address(this),
            _totemTokenAmount
        );
        IERC20(_paymentTokenAddr).safeTransfer(msg.sender, paymentTokensBack);

        emit TotemTokensSold(
            msg.sender,
            _paymentTokenAddr,
            _totemTokenAddr,
            _totemTokenAmount,
            paymentTokensBack
        );
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Pauses the contract
     * @dev Only callable by accounts with the MANAGER role
     */
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @notice Unpauses the contract
     * @dev Only callable by accounts with the MANAGER role
     */
    function unpause() external onlyRole(MANAGER) {
        _unpause();
    }

    /**
     * @dev Throws if the contract is paused or if the ecosystem is paused.
     */
    function _requireNotPaused() internal view virtual override {
        super._requireNotPaused();
        if (AddressRegistry(registryAddr).isEcosystemPaused()) {
            revert EcosystemPaused();
        }
    }

    /**
     * @notice Sets the payment token address
     * @param _paymentTokenAddr Address of the payment token
     */
    function setPaymentToken(
        address _paymentTokenAddr
    ) external onlyRole(MANAGER) {
        if (_paymentTokenAddr == address(0)) revert ZeroAddress();
        paymentTokenAddr = _paymentTokenAddr;
    }

    /**
     * @notice Sets the TotemFactory address from registry
     * @param _registryAddr Address of the AddressRegistry contract
     */
    function setTotemFactory(address _registryAddr) external onlyRole(MANAGER) {
        if (address(factory) != address(0)) revert AlreadySet();
        if (_registryAddr == address(0)) revert ZeroAddress();
        factory = TotemFactory(
            AddressRegistry(_registryAddr).getTotemFactory()
        );
    }

    /**
     * @notice Sets the maximum number of totem tokens per address
     * @param _amount Maximum amount of tokens
     */
    function setMaxTotemTokensPerAddress(
        uint256 _amount
    ) external onlyRole(MANAGER) {
        if (_amount == 0) revert WrongAmount(0);
        maxTokensPerAddress = _amount;
    }

    /**
     * @notice Sets the Uniswap V2 router address
     * @param _routerAddr Address of the Uniswap V2 router
     */
    function setUniswapV2Router(
        address _routerAddr
    ) external onlyRole(MANAGER) {
        if (_routerAddr == address(0)) revert ZeroAddress();
        uniswapV2RouterAddr = _routerAddr;
    }

    /**
     * @notice Sets the price feed address for a token
     * @param _tokenAddr Address of the token
     * @param _priceFeedAddr Address of the Chainlink price feed for the token/USD pair
     */
    function setPriceFeed(
        address _tokenAddr,
        address _priceFeedAddr
    ) external onlyRole(MANAGER) {
        if (_tokenAddr == address(0) || _priceFeedAddr == address(0))
            revert ZeroAddress();
        priceFeedAddresses[_tokenAddr] = _priceFeedAddr;
        emit PriceFeedSet(_tokenAddr, _priceFeedAddr);
    }

    /**
     * @notice Sets the distribution shares for payment tokens
     * @param _revenueShare Percentage going to treasury (multiplied by PRECISION)
     * @param _creatorShare Percentage going to totem creator (multiplied by PRECISION)
     * @param _poolShare Percentage going to liquidity pool (multiplied by PRECISION)
     * @param _vaultShare Percentage going to totem vault (multiplied by PRECISION)
     */
    function setDistributionShares(
        uint256 _revenueShare,
        uint256 _creatorShare,
        uint256 _poolShare,
        uint256 _vaultShare
    ) external onlyRole(MANAGER) {
        if (
            _revenueShare + _creatorShare + _poolShare + _vaultShare !=
            PRECISION
        ) revert InvalidShares();

        revenuePaymentTokenShare = _revenueShare;
        totemCreatorPaymentTokenShare = _creatorShare;
        poolPaymentTokenShare = _poolShare;
        vaultPaymentTokenShare = _vaultShare;

        emit TokenDistributionSharesUpdated(
            _revenueShare,
            _creatorShare,
            _poolShare,
            _vaultShare
        );
    }

    /**
     * @notice Sets the token price in USD
     * @param _priceInUsd New price in USD (18 decimals)
     */
    function setTotemPriceInUsd(
        uint256 _priceInUsd
    ) external onlyRole(MANAGER) {
        if (_priceInUsd == 0) revert WrongAmount(0);
        oneTotemPriceInUsd = _priceInUsd;
    }

    /// INTERNAL FUNCTIONS

    /**
     * @notice Closes the sale period for a totem token
     *      Distributes collected payment tokens and adds liquidity to AMM
     * @param _totemTokenAddr Address of the totem token
     */
    function _closeSalePeriod(address _totemTokenAddr) internal {
        // close sale period and open burn functionality for totem token
        totems[_totemTokenAddr].isSalePeriod = false;

        // open transfers for totem token
        TotemToken(_totemTokenAddr).openTransfers();

        // register totem in MeritManager and activate merit distribution for it
        meritManager.register(totems[_totemTokenAddr].totemAddr);

        // distribute collected payment tokens
        uint256 paymentTokenAmount = totems[_totemTokenAddr]
            .collectedPaymentTokens;
        address _paymentTokenAddr = totems[_totemTokenAddr].paymentToken;

        // calculate revenue share
        uint256 revenueShare = (paymentTokenAmount * revenuePaymentTokenShare) /
            PRECISION;
        IERC20(_paymentTokenAddr).safeTransfer(treasuryAddr, revenueShare);

        // calculate totem creator share
        uint256 creatorShare = (paymentTokenAmount *
            totemCreatorPaymentTokenShare) / PRECISION;
        IERC20(_paymentTokenAddr).safeTransfer(
            totems[_totemTokenAddr].creator,
            creatorShare
        );

        // calculate totem vault share
        uint256 vaultShare = (paymentTokenAmount * vaultPaymentTokenShare) /
            PRECISION;
        IERC20(_paymentTokenAddr).safeTransfer(
            totems[_totemTokenAddr].totemAddr,
            vaultShare
        );

        // calculate totem pool share
        uint256 poolShare = (paymentTokenAmount * poolPaymentTokenShare) /
            PRECISION;

        // send liquidity to AMM and relay LP tokens to Totem
        (uint256 liquidity, address liquidityToken) = _addLiquidity(
            _totemTokenAddr,
            _paymentTokenAddr,
            POOL_INITIAL_SUPPLY,
            poolShare
        );

        // set payment token for Totem and close sale period
        Totem(totems[_totemTokenAddr].totemAddr).closeSalePeriod(
            IERC20(_paymentTokenAddr),
            IERC20(liquidityToken)
        );

        IERC20(liquidityToken).safeTransfer(
            totems[_totemTokenAddr].totemAddr,
            liquidity
        );

        emit SalePeriodClosed(_totemTokenAddr, paymentTokenAmount);
    }

    /**
     * @notice Adds liquidity to a Uniswap V2 pool
     *      Approves tokens for the router and adds liquidity to the pool
     * @param _totemTokenAddr Address of the totem token
     * @param _paymentTokenAddr Address of the payment token
     * @param _totemTokenAmount Amount of totem tokens to add to the pool
     * @param _paymentTokenAmount Amount of payment tokens to add to the pool
     * @return liquidity Amount of liquidity tokens received
     * @return liquidityToken Address of the liquidity token (pair)
     */
    function _addLiquidity(
        address _totemTokenAddr,
        address _paymentTokenAddr,
        uint256 _totemTokenAmount,
        uint256 _paymentTokenAmount
    ) internal returns (uint256 liquidity, address liquidityToken) {
        if (uniswapV2RouterAddr == address(0)) revert UniswapRouterNotSet();

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2RouterAddr);

        // Get the factory address
        address factoryAddr = router.factory();
        IUniswapV2Factory factory_ = IUniswapV2Factory(factoryAddr);

        // Approve tokens for the uni router
        IERC20(_totemTokenAddr).approve(uniswapV2RouterAddr, _totemTokenAmount);
        IERC20(_paymentTokenAddr).approve(
            uniswapV2RouterAddr,
            _paymentTokenAmount
        );

        // Calculate minimum amounts based on slippage percentage
        uint256 minTotemAmount = (_totemTokenAmount * (PRECISION - slippagePercentage)) / PRECISION;
        uint256 minPaymentAmount = (_paymentTokenAmount * (PRECISION - slippagePercentage)) / PRECISION;

        // Add liquidity
        (, , liquidity) = router.addLiquidity(
            _totemTokenAddr,
            _paymentTokenAddr,
            _totemTokenAmount,
            _paymentTokenAmount,
            minTotemAmount,
            minPaymentAmount,
            address(this),
            block.timestamp + 600 // Deadline: 10 minutes from now
        );

        liquidityToken = factory_.getPair(_totemTokenAddr, _paymentTokenAddr);

        if (liquidity == 0) revert LiquidityAdditionFailed();

        emit LiquidityAdded(
            _totemTokenAddr,
            _paymentTokenAddr,
            _totemTokenAmount,
            _paymentTokenAmount,
            liquidity
        );

        return (liquidity, liquidityToken);
    }

    // VIEW FUNCTIONS

    /**
     * @notice Returns the token price in USD
     * @return The current token price in USD (18 decimals)
     */
    function getTotemPriceInUsd() external view returns (uint256) {
        return oneTotemPriceInUsd;
    }

    /**
     * @notice Converts totem tokens to payment tokens based on price
     * @param _tokenAddr Address of the payment token
     * @param _totemsAmount Amount of totem tokens
     * @return Amount of payment tokens required
     */
    function totemsToPaymentToken(
        address _tokenAddr,
        uint256 _totemsAmount
    ) public view returns (uint256) {
        uint256 amount = (_totemsAmount * oneTotemPriceInUsd) /
            getPrice(_tokenAddr);
        return amount == 0 ? 1 : amount;
    }

    /**
     * @notice Converts payment tokens to totem tokens based on price
     * @param _tokenAddr Address of the payment token
     * @param _paymentTokenAmount Amount of payment tokens
     * @return Amount of totem tokens that can be purchased
     */
    function paymentTokenToTotems(
        address _tokenAddr,
        uint256 _paymentTokenAmount
    ) public view returns (uint256) {
        uint256 amount = (_paymentTokenAmount * getPrice(_tokenAddr)) /
            oneTotemPriceInUsd;
        return amount == 0 ? 1 : amount;
    }

    /**
     * @notice Returns the price of a given token in USD
     *      Uses Chainlink price feeds to get the token price in USD
     * @param _tokenAddr Address of the token to get the price for
     * @return Amount of tokens equivalent to 1 USD
     */
    function getPrice(address _tokenAddr) public view returns (uint256) {
        address priceFeedAddr = priceFeedAddresses[_tokenAddr];

        if (priceFeedAddr == address(0)) {
            revert NoPriceFeedSet(_tokenAddr);
        }

        // Get the latest price from Chainlink
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddr);
        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        // Validate the price feed data
        if (price <= 0) revert InvalidPrice(_tokenAddr);
        if (answeredInRound < roundId) revert StalePrice(_tokenAddr);
        if (block.timestamp > updatedAt + PRICE_FEED_STALE_THRESHOLD)
            revert StalePrice(_tokenAddr);

        // Get the number of decimals in the price feed
        uint8 decimals = priceFeed.decimals();

        // Calculate how many tokens are equivalent to 1 USD
        // Price from Chainlink is in USD per token with 'decimals' decimal places
        // We want tokens per USD with 18 decimal places

        // First, normalize the price to 18 decimals
        uint256 normalizedPrice;
        if (decimals < 18) {
            normalizedPrice = uint256(price) * (10 ** (18 - decimals));
        } else {
            normalizedPrice = uint256(price) / (10 ** (decimals - 18));
        }

        // Then calculate tokens per USD: 1e36 / price
        // 1e36 = 1 USD (with 18 decimals) * 1e18 (for division precision)
        return (1e36) / normalizedPrice;
    }

    /**
     * @notice Returns the address of the current payment token
     * @return Address of the payment token
     */
    function getPaymentToken() external view returns (address) {
        return paymentTokenAddr;
    }

    /**
     * @notice Returns the sale position of a user for a specific totem token
     * @param _userAddr Address of the user
     * @param _totemTokenAddr Address of the totem token
     * @return Sale position details
     */
    function getPosition(
        address _userAddr,
        address _totemTokenAddr
    ) external view returns (SalePosInToken memory) {
        return salePositions[_userAddr][_totemTokenAddr];
    }

    /**
     * @notice Calculates the number of totem tokens available for purchase
     *      Takes into account the user's current balance and the maximum allowed tokens per address
     * @param _userAddr Address of the user
     * @param _totemTokenAddr Address of the totem token
     * @return The number of totem tokens available for purchase
     */
    function getAvailableTokensForPurchase(
        address _userAddr,
        address _totemTokenAddr
    ) external view returns (uint256) {
        if (
            !totems[_totemTokenAddr].registered ||
            !totems[_totemTokenAddr].isSalePeriod
        ) {
            return 0; // Tokens are only available for purchase during sale period
        }

        // Get user's current balance
        uint256 currentBalance = IERC20(_totemTokenAddr).balanceOf(_userAddr);

        // Calculate how many more tokens the user can buy based on the max limit
        if (currentBalance >= maxTokensPerAddress) {
            return 0; // User has reached the maximum allowed tokens
        }

        uint256 remainingAllowance = maxTokensPerAddress - currentBalance;

        // Check contract's available balance (excluding pool initial supply)
        uint256 contractBalance = IERC20(_totemTokenAddr).balanceOf(
            address(this)
        );
        uint256 availableForSale = contractBalance > POOL_INITIAL_SUPPLY
            ? contractBalance - POOL_INITIAL_SUPPLY
            : 0;

        // Return the minimum of remaining allowance and available tokens
        return
            remainingAllowance < availableForSale
                ? remainingAllowance
                : availableForSale;
    }

    /**
     * @notice Returns the TotemData for a specific totem token address
     * @param _totemTokenAddr Address of the totem token
     * @return TotemData struct containing information about the totem
     */
    function getTotemData(
        address _totemTokenAddr
    ) external view returns (TotemData memory) {
        return totems[_totemTokenAddr];
    }

    /**
     * @notice Returns the current distribution shares
     */
    function getDistributionShares()
        external
        view
        returns (uint256 revenue, uint256 creator, uint256 pool, uint256 vault)
    {
        return (
            revenuePaymentTokenShare,
            totemCreatorPaymentTokenShare,
            poolPaymentTokenShare,
            vaultPaymentTokenShare
        );
    }

    /**
     * @notice Sets the slippage percentage for liquidity addition
     * @param _slippagePercentage New slippage percentage (multiplied by PRECISION)
     * @dev For example, 50 = 0.5%, 500 = 5%, 1000 = 10%
     */
    function setSlippagePercentage(
        uint256 _slippagePercentage
    ) external onlyRole(MANAGER) {
        if (_slippagePercentage >= PRECISION) revert InvalidShares();
        slippagePercentage = _slippagePercentage;
    }

    /**
     * @notice Returns the current slippage percentage
     * @return The current slippage percentage (multiplied by PRECISION)
     */
    function getSlippagePercentage() external view returns (uint256) {
        return slippagePercentage;
    }
}
