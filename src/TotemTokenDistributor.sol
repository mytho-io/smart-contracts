// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
 * @dev This contract manages the distribution of Totem tokens during and after sales periods.
 * It handles:
 * - Registration of new totems from the TotemFactory
 * - Buying and selling totems during the sales period
 * - Distribution of collected payment tokens after the sales period ends
 * - Adding liquidity to AMM pools
 * - Burning totem tokens
 */

contract TotemTokenDistributor is AccessControlUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    TotemFactory private factory;
    MeritManager private meritManager;
    IERC20 private mytho;

    uint256 private maxTokensPerAddress;
    uint256 private oneTotemPriceInUsd;

    // contract address for revenue in payment tokens
    address private treasuryAddr;

    // address of payment token
    address private paymentTokenAddr;

    // Uniswap V2 router address
    address private uniswapV2RouterAddr;

    // Mapping from token address to Chainlink price feed address
    mapping(address => address) private priceFeedAddresses;

    /// @dev General info about totems
    mapping(address totemTokenAddr => TotemData TotemData) private totems;

    /// @dev Number of sale positions are eq to the used paymentTokens by address
    mapping(address userAddress => mapping(address totemTokenAddr => SalePosInToken))
        private salePositions;

    bytes32 private constant MANAGER = keccak256("MANAGER");

    uint256 private constant POOL_INITIAL_SUPPLY = 200_000_000 ether;
    uint256 private constant REVENUE_PAYMENT_TOKEN_SHARE = 250; // 2.5%
    uint256 private constant TOTEM_CREATOR_PAYMENT_TOKEN_SHARE = 50; // 0.5%
    uint256 private constant POOL_PAYMENT_TOKEN_SHARE = 2857; // 28.57%
    uint256 private constant VAULT_PAYMENT_TOKEN_SHARE = 6843; // 68.43%
    uint256 private constant PRECISION = 10000;

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
        uint256 totemTokenAmount
    );
    event TotemTokensSold(
        address buyer,
        address paymentTokenAddr,
        address totemTokenAddr,
        uint256 totemTokenAmount
    );
    event TotemRegistered(
        address totemAddr,
        address creator,
        address totemTokenAddr
    );

    // Custom errors
    error AlreadyRegistered(address totemTokenAddr);
    error NotAllowedForCustomTokens();
    error UnknownTotemToken(address tokenAddr);
    error WrongAmount(uint256 tokenAmount);
    error NotPaymentToken(address tokenAddr);
    error OnlyInSalePeriod();
    error NotAllowedInSalePeriod();
    error WrongPaymentTokenAmount(uint256 paymentTokenAmount);
    error OnlyForTotem();
    error AlreadySet();

    function initialize(address _registryAddr) public initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);

        mytho = IERC20(AddressRegistry(_registryAddr).getMythoToken());
        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();
        meritManager = MeritManager(AddressRegistry(_registryAddr).getMeritManager());

        maxTokensPerAddress = 5_000_000 ether;
        oneTotemPriceInUsd = 0.00004 ether;
    }

    modifier whenSalePeriod(address _totemTokenAddr) {
        if (!totems[_totemTokenAddr].isSalePeriod) revert OnlyInSalePeriod();
        _;
    }

    /// @notice Being called by TotemFactory during totem creation
    function register() external {
        // get info about the totem being created
        TotemFactory.TotemData memory totemDataFromFactory = factory
            .getTotemData(factory.getLastId() - 1);

        if (totemDataFromFactory.isCustomToken)
            revert NotAllowedForCustomTokens();
        if (totems[totemDataFromFactory.tokenAddr].registered)
            revert AlreadyRegistered(totemDataFromFactory.tokenAddr);

        totems[totemDataFromFactory.tokenAddr] = TotemData(
            totemDataFromFactory.totemAddr,
            totemDataFromFactory.creator,
            paymentTokenAddr,
            true,
            true,
            0
        );

        TotemToken token = TotemToken(totemDataFromFactory.tokenAddr);
        token.transfer(totemDataFromFactory.creator, 250_000 ether);
        token.transfer(totemDataFromFactory.totemAddr, 100_000_000 ether);

        emit TotemRegistered(
            totemDataFromFactory.totemAddr,
            totemDataFromFactory.creator,
            totemDataFromFactory.tokenAddr
        );
    }

    /// @notice Buy totems for allowed payment tokens
    function buy(
        address _totemTokenAddr,
        uint256 _totemTokenAmount
    ) external whenSalePeriod(_totemTokenAddr) {
        if (!totems[_totemTokenAddr].registered)
            revert UnknownTotemToken(_totemTokenAddr);
        if (
            // check if contract has enough totem tokens + initial pool supply
            IERC20(_totemTokenAddr).balanceOf(address(this)) <
            _totemTokenAmount + POOL_INITIAL_SUPPLY ||
            // check if user has no more than maxTokensPerAddress
            IERC20(_totemTokenAddr).balanceOf(msg.sender) + _totemTokenAmount >
            maxTokensPerAddress
        ) revert WrongAmount(_totemTokenAmount);

        uint256 paymentTokenAmount = _totemsToPaymentToken(
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

        IERC20(paymentTokenAddr).transferFrom(
            msg.sender,
            address(this),
            paymentTokenAmount
        );
        IERC20(_totemTokenAddr).transfer(msg.sender, _totemTokenAmount);

        emit TotemTokensBought(
            msg.sender,
            paymentTokenAddr,
            _totemTokenAddr,
            _totemTokenAmount
        );
    }

    /// @notice Sell totems for used payment token in sale period
    function sell(
        address _totemTokenAddr,
        uint256 _totemTokenAmount
    ) external whenSalePeriod(_totemTokenAddr) {
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
        /// @custom:check for correct calculation
        uint256 paymentTokensBack = (position.paymentTokenAmount *
            _totemTokenAmount) / position.totemTokenAmount;

        // update totems payment token amount
        totems[_totemTokenAddr].collectedPaymentTokens -= paymentTokensBack;

        // update user sale position
        position.totemTokenAmount -= _totemTokenAmount;
        position.paymentTokenAmount -= paymentTokensBack;

        // send payment tokens and take totem tokens
        IERC20(_totemTokenAddr).transferFrom(
            msg.sender,
            address(this),
            _totemTokenAmount
        );
        IERC20(_paymentTokenAddr).transfer(msg.sender, paymentTokensBack);

        // when all tokens are sold sale period is closed
        if (IERC20(_totemTokenAddr).balanceOf(address(this)) == 0) {
            _closeSalePeriod(_totemTokenAddr);
        }

        emit TotemTokensSold(
            msg.sender,
            _paymentTokenAddr,
            _totemTokenAddr,
            _totemTokenAmount
        );
    }

    function burnTotemTokens(
        address _totemTokenAddr,
        uint256 _totemTokenAmount
    ) external {
        if (msg.sender != totems[_totemTokenAddr].totemAddr)
            revert OnlyForTotem();
        TotemToken(_totemTokenAddr).burn(msg.sender, _totemTokenAmount);
    }

    /// INTERNAL LOGIC

    function _closeSalePeriod(address _totemTokenAddr) internal {
        // close sale period and open burn functionality for totem token
        totems[_totemTokenAddr].isSalePeriod = false;

        // open transfers for totem token
        TotemToken(_totemTokenAddr).openTransfers();

        // register totem in MeritManager and activate merit distribution for it
        meritManager.register(totems[_totemTokenAddr].totemAddr);

        // distrubute collected payment tokens
        uint256 paymentTokenAmount = totems[_totemTokenAddr]
            .collectedPaymentTokens;
        address _paymentTokenAddr = totems[_totemTokenAddr].paymentToken;

        // calculate revenue share
        uint256 revenueShare = (paymentTokenAmount *
            REVENUE_PAYMENT_TOKEN_SHARE) / PRECISION;
        IERC20(_paymentTokenAddr).transfer(treasuryAddr, revenueShare);

        // calculate totem creator share
        uint256 creatorShare = (paymentTokenAmount *
            TOTEM_CREATOR_PAYMENT_TOKEN_SHARE) / PRECISION;
        IERC20(_paymentTokenAddr).transfer(
            totems[_totemTokenAddr].creator,
            creatorShare
        );

        // calculate totem vault share
        uint256 vaultShare = (paymentTokenAmount * VAULT_PAYMENT_TOKEN_SHARE) /
            PRECISION;
        IERC20(_paymentTokenAddr).transfer(
            totems[_totemTokenAddr].totemAddr,
            vaultShare
        );

        // calculate totem pool share
        uint256 poolShare = (paymentTokenAmount * POOL_PAYMENT_TOKEN_SHARE) /
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

        IERC20(liquidityToken).transfer(
            totems[_totemTokenAddr].totemAddr,
            liquidity
        );
    }

    /**
     * @notice Adds liquidity to a Uniswap V2 pool
     * @dev Approves tokens for the router and adds liquidity to the pool
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
        if (uniswapV2RouterAddr == address(0)) revert("Uniswap router not set");

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapV2RouterAddr);

        // Get the factory address
        address factoryAddr = router.factory();
        IUniswapV2Factory factory_ = IUniswapV2Factory(factoryAddr);

        // Get or create the pair
        liquidityToken = factory_.getPair(_totemTokenAddr, _paymentTokenAddr);
        if (liquidityToken == address(0)) {
            liquidityToken = factory_.createPair(
                _totemTokenAddr,
                _paymentTokenAddr
            );
        }

        // Approve tokens for the router
        IERC20(_totemTokenAddr).approve(uniswapV2RouterAddr, _totemTokenAmount);
        IERC20(_paymentTokenAddr).approve(
            uniswapV2RouterAddr,
            _paymentTokenAmount
        );

        // Add liquidity
        (, , liquidity) = router.addLiquidity(
            _totemTokenAddr,
            _paymentTokenAddr,
            _totemTokenAmount,
            _paymentTokenAmount,
            0, // Accept any amount of token A
            0, // Accept any amount of token B
            address(this), // Send LP tokens to this contract
            block.timestamp + 600 // Deadline: 10 minutes from now
        );

        return (liquidity, liquidityToken);
    }

    /// ADMIN LOGIC

    function setPaymentToken(
        address _paymentTokenAddr
    ) external onlyRole(MANAGER) {
        paymentTokenAddr = _paymentTokenAddr;
    }

    function setTotemFactory(address _registryAddr) external onlyRole(MANAGER) {
        if (address(factory) != address(0)) revert AlreadySet();
        factory = TotemFactory(AddressRegistry(_registryAddr).getTotemFactory());
    }

    function setMaxTotemTokensPerAddress(
        uint256 _amount
    ) external onlyRole(MANAGER) {
        maxTokensPerAddress = _amount;
    }

    /**
     * @notice Sets the Uniswap V2 router address
     * @param _routerAddr Address of the Uniswap V2 router
     */
    function setUniswapV2Router(
        address _routerAddr
    ) external onlyRole(MANAGER) {
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
        priceFeedAddresses[_tokenAddr] = _priceFeedAddr;
    }

    /// READERS

    function _totemsToPaymentToken(
        address _tokenAddr,
        uint256 _totemsAmount
    ) public view returns (uint256) {
        return (_totemsAmount * oneTotemPriceInUsd) / getPrice(_tokenAddr);
    }

    function _paymentTokenToTotems(
        address _tokenAddr,
        uint256 _paymentTokenAmount
    ) public view returns (uint256) {
        return
            (_paymentTokenAmount * getPrice(_tokenAddr)) / oneTotemPriceInUsd;
    }

    /**
     * @notice Returns the price of a given token in USD
     * @dev Uses Chainlink price feeds to get the token price in USD
     * @param _tokenAddr Address of the token to get the price for
     * @return Amount of tokens equivalent to 1 USD
     */
    function getPrice(address _tokenAddr) public view returns (uint256) {
        address priceFeedAddr = priceFeedAddresses[_tokenAddr];

        if (priceFeedAddr == address(0)) {
            // If no price feed is set for this token, return a default value
            return 0.05 * 1e18;
        }

        // Get the latest price from Chainlink
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeedAddr);
        (, int256 price, , , ) = priceFeed.latestRoundData();

        if (price <= 0) {
            // If price is invalid, return a default value
            return 0.05 * 1e18;
        }

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

    function getPaymentToken() external view returns (address) {
        return paymentTokenAddr;
    }

    function getPosition(
        address _addr,
        address _totemTokenAddr
    ) external view returns (SalePosInToken memory) {
        return salePositions[_addr][_totemTokenAddr];
    }
}
