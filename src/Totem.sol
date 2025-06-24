// SPDX-License-Identifier: BUSL-1.1
// Copyright 2025 Mytho. All Rights Reserved.
pragma solidity ^0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {TotemTokenDistributor} from "./TotemTokenDistributor.sol";
import {MeritManager} from "./MeritManager.sol";
import {AddressRegistry} from "./AddressRegistry.sol";
import {TotemToken} from "./TotemToken.sol";
import {TokenHoldersOracle} from "./utils/TokenHoldersOracle.sol";

/**
 * @title Totem
 * @notice This contract represents a Totem in the MYTHO ecosystem, managing token redemption and merit distribution
 *      Handles the lifecycle of a Totem, including token redemption after sale period and merit distribution
 */
contract Totem is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // Enum for token types
    enum TokenType {
        STANDARD,  // 0: Standard (non-custom) token
        ERC20,     // 1: Custom ERC20 token
        ERC721     // 2: Custom ERC721 token
    }

    // State variables - Tokens
    address private totemTokenAddr; // Address of the totem token (can be ERC20 or ERC721)
    IERC20 private paymentToken;
    IERC20 private liquidityToken;
    IERC20 private mythoToken;

    // State variables - Data
    bytes private dataHash;

    // State variables - Addresses
    address private treasuryAddr;
    address private totemDistributorAddr;
    address private meritManagerAddr;
    address private owner;
    address[] private collaborators;
    address private registryAddr;

    // State variables - Flags
    bool private salePeriodEnded;
    TokenType private tokenType;

    // Constants
    bytes32 private constant TOTEM_DISTRIBUTOR = keccak256("TOTEM_DISTRIBUTOR");

    // Events
    event TotemTokenRedeemed(
        address indexed user,
        uint256 totemTokenAmount,
        uint256 paymentAmount,
        uint256 mythoAmount,
        uint256 lpAmount
    );
    event SalePeriodEnded();
    event MythoCollected(address indexed user, uint256 periodNum);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    // Custom errors
    error SalePeriodNotEnded();
    error InsufficientTotemBalance();
    error NothingToDistribute();
    error ZeroAmount();
    error ZeroCirculatingSupply();
    error InvalidParams();
    error TotemsPaused();
    error EcosystemPaused();
    error StaleOracleData();
    error UnsupportedTokenType();
    error NotMultisigWallet();

    /**
     * @notice Modifier to check if Totems are paused or if the ecosystem is paused in the AddressRegistry
     */
    modifier whenNotPaused() {
        if (AddressRegistry(registryAddr).areTotemsPaused())
            revert TotemsPaused();
        if (AddressRegistry(registryAddr).isEcosystemPaused())
            revert EcosystemPaused();
        _;
    }

    /**
     * @notice Initializes the Totem contract with token addresses, data hash, and revenue pool
     *      Sets up the initial state and grants roles
     * @param _totemToken The address of the TotemToken or custom token
     * @param _dataHash The data hash associated with this Totem
     * @param _registryAddr Address of the AddressRegistry contract
     * @param _owner The address of the Totem owner
     * @param _collaborators Array of collaborator addresses
     * @param _tokenType Type of token (STANDARD, ERC20, ERC721)
     */
    function initialize(
        address _totemToken,
        bytes memory _dataHash,
        address _registryAddr,
        address _owner,
        address[] memory _collaborators,
        uint8 _tokenType
    ) public initializer {
        if (
            _totemToken == address(0) ||
            _registryAddr == address(0) ||
            _owner == address(0) ||
            _dataHash.length == 0
        ) revert InvalidParams();

        __AccessControl_init();
        __ReentrancyGuard_init();

        totemTokenAddr = _totemToken;
        dataHash = _dataHash;

        treasuryAddr = AddressRegistry(_registryAddr).getMythoTreasury();
        totemDistributorAddr = AddressRegistry(_registryAddr)
            .getTotemTokenDistributor();
        meritManagerAddr = AddressRegistry(_registryAddr).getMeritManager();
        mythoToken = IERC20(AddressRegistry(_registryAddr).getMythoToken());
        tokenType = TokenType(_tokenType);
        registryAddr = _registryAddr;

        owner = _owner;
        collaborators = _collaborators;

        // Only set payment token if this is a standard token
        // Custom tokens don't use the payment token from the distributor
        if (!isCustomToken()) {
            paymentToken = IERC20(
                TotemTokenDistributor(totemDistributorAddr).getPaymentToken()
            );
        }

        _grantRole(TOTEM_DISTRIBUTOR, totemDistributorAddr);
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Allows TotemToken holders to redeem or transfer their tokens and receive proportional shares of assets
     *      After the sale period ends, burns TotemTokens for standard tokens or transfers custom tokens to treasuryAddr.
     *      User receives proportional shares of payment tokens, MYTHO tokens, and LP tokens based on circulating supply.
     * @param _tokenAmountOrId For ERC20 tokens: the amount of tokens to burn/transfer.
     *                         For ERC721 tokens: the ID of the NFT to transfer.
     */
    function redeemTotemTokens(uint256 _tokenAmountOrId) external whenNotPaused nonReentrant {
        if (tokenType == TokenType.STANDARD && !salePeriodEnded) revert SalePeriodNotEnded();

        // Check if there are MYTHO tokens to claim in the current period
        uint256 currentPeriod = MeritManager(meritManagerAddr).currentPeriod();
        uint256 pendingReward = MeritManager(meritManagerAddr).getPendingReward(address(this), currentPeriod);
        if (pendingReward > 0)
            MeritManager(meritManagerAddr).claimMytho(currentPeriod);

        // Handle differently based on token type
        if (tokenType == TokenType.ERC721) {
            // For NFT tokens - pass the NFT ID
            _redeemNFTTokens(_tokenAmountOrId);
        } else {
            // For regular or ERC20 custom tokens - pass the token amount
            _redeemERC20Tokens(_tokenAmountOrId);
        }
    }

    /**
     * @notice Internal function to handle redeeming NFT tokens
     * @param _nftTokenId The ID of the NFT token to transfer to treasury
     */
    function _redeemNFTTokens(uint256 _nftTokenId) internal {
        // Verify the user owns the NFT
        if (IERC721(totemTokenAddr).ownerOf(_nftTokenId) != msg.sender)
            revert InsufficientTotemBalance();

        TokenHoldersOracle oracle = TokenHoldersOracle(AddressRegistry(registryAddr).getTokenHoldersOracle());

        // Verify data is not stale using the oracle's isDataFresh function
        if (!oracle.isDataFresh(totemTokenAddr)) revert StaleOracleData();

        // Get circulating supply
        uint256 circulatingSupply = getCirculatingSupply();
        if (circulatingSupply == 0) revert ZeroCirculatingSupply();

        // Get balances to distribute
        (
            ,
            ,
            ,
            uint256 mythoBalance
        ) = getAllBalances();

        // Check if there's MYTHO to distribute
        if (mythoBalance == 0) {
            revert NothingToDistribute();
        }

        // Calculate user share based on circulating supply (1 NFT = 1 token)
        uint256 mythoAmount = mythoBalance / circulatingSupply;

        // Transfer NFT to treasury
        IERC721(totemTokenAddr).transferFrom(
            msg.sender,
            treasuryAddr,
            _nftTokenId
        );

        // Transfer MYTHO tokens to user
        mythoToken.safeTransfer(msg.sender, mythoAmount);

        emit TotemTokenRedeemed(
            msg.sender,
            1, // For NFTs, we consider it as 1 token
            0, // No payment tokens for NFT totems
            mythoAmount,
            0  // No LP tokens for NFT totems
        );
    }

    /**
     * @notice Internal function to handle redeeming ERC20 tokens
     * @param _tokenAmount The amount of ERC20 tokens to redeem
     */
    function _redeemERC20Tokens(uint256 _tokenAmount) internal {
        if (IERC20(totemTokenAddr).balanceOf(msg.sender) < _tokenAmount)
            revert InsufficientTotemBalance();
        if (_tokenAmount == 0) revert ZeroAmount();

        // Get circulating supply
        uint256 circulatingSupply = getCirculatingSupply();
        if (circulatingSupply == 0) revert ZeroCirculatingSupply();

        // Get balances to distribute
        (
            ,
            uint256 paymentTokenBalance,
            uint256 lpBalance,
            uint256 mythoBalance
        ) = getAllBalances();

        // Check if all balances are zero
        if (paymentTokenBalance == 0 && mythoBalance == 0 && lpBalance == 0) {
            revert NothingToDistribute();
        }

        // Calculate user share for each token type based on circulating supply
        uint256 paymentAmount = (paymentTokenBalance * _tokenAmount) /
            circulatingSupply;
        uint256 mythoAmount = (mythoBalance * _tokenAmount) / circulatingSupply;
        uint256 lpAmount = (lpBalance * _tokenAmount) / circulatingSupply;

        // Burn or transfer tokens based on token type
        if (isCustomToken()) {
            // Transfer custom tokens to treasury
            SafeERC20.safeTransferFrom(
                IERC20(totemTokenAddr),
                msg.sender,
                treasuryAddr,
                _tokenAmount
            );
        } else {
            // Burn standard tokens
            TotemToken(totemTokenAddr).burnFrom(msg.sender, _tokenAmount);
        }

        // Transfer payment tokens if there are any
        if (paymentAmount > 0) {
            paymentToken.safeTransfer(msg.sender, paymentAmount);
        }

        // Transfer MYTHO tokens if there are any
        if (mythoAmount > 0) {
            mythoToken.safeTransfer(msg.sender, mythoAmount);
        }

        // Transfer LP tokens if there are any
        if (lpAmount > 0) {
            liquidityToken.safeTransfer(msg.sender, lpAmount);
        }

        emit TotemTokenRedeemed(
            msg.sender,
            _tokenAmount,
            paymentAmount,
            mythoAmount,
            lpAmount
        );
    }

    /**
     * @notice Collects accumulated MYTHO from MeritManager for a specific period
     * @param _periodNum The period number to collect rewards for
     */
    function collectMYTH(uint256 _periodNum) external whenNotPaused {
        MeritManager(meritManagerAddr).claimMytho(_periodNum);
        emit MythoCollected(msg.sender, _periodNum);
    }

    /**
     * @notice Allows the multisig wallet to withdraw any ERC20 token from the contract balance
     *         This function is intended for distributing tokens from the Totem's treasury 
     *         while the governance system is not yet implemented. Once governance is in place,
     *         this functionality should be moved to a governance-controlled mechanism.
     * @param _token The address of the ERC20 token to withdraw
     * @param _to The address to send the tokens to
     * @param _amount The amount of tokens to withdraw
     */
    function withdrawToken(
        address _token,
        address _to,
        uint256 _amount
    ) external nonReentrant {
        // Check if caller is the multisig wallet
        address multisigWallet = AddressRegistry(registryAddr).getMultisigWallet();
        if (msg.sender != multisigWallet) revert NotMultisigWallet();
        
        if (_token == address(0)) revert InvalidParams();
        if (_to == address(0)) revert InvalidParams();
        if (_amount == 0) revert ZeroAmount();

        IERC20 token = IERC20(_token);
        uint256 contractBalance = token.balanceOf(address(this));
        
        if (contractBalance < _amount) revert InsufficientTotemBalance();

        token.safeTransfer(_to, _amount);
        
        emit TokenWithdrawn(_token, _to, _amount);
    }

    /**
     * @notice Called by TotemTokenDistributor to end the sale period and set final token balances
     *      Should be called by TotemTokenDistributor after sale period ends
     * @param _paymentToken The payment token address
     * @param _liquidityToken The liquidity token address
     */
    function endSalePeriod(
        IERC20 _paymentToken,
        IERC20 _liquidityToken
    ) external onlyRole(TOTEM_DISTRIBUTOR) {
        paymentToken = _paymentToken;
        liquidityToken = _liquidityToken;
        salePeriodEnded = true;

        emit SalePeriodEnded();
    }

    /**
     * @notice Checks if this token is a custom token (ERC20 or ERC721)
     * @return True if the token is custom, false if it's a standard token
     */
    function isCustomToken() public view returns (bool) {
        return tokenType != TokenType.STANDARD;
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
     * @return _totemTokenAddr The address of the Totem token
     * @return _paymentTokenAddr The address of the payment token
     * @return _liquidityTokenAddr The address of the liquidity token
     */
    function getTokenAddresses()
        external
        view
        returns (
            address _totemTokenAddr,
            address _paymentTokenAddr,
            address _liquidityTokenAddr
        )
    {
        return (totemTokenAddr, address(paymentToken), address(liquidityToken));
    }

    /**
     * @notice Get all token balances of this Totem
     * @return totemBalance The balance of Totem tokens
     * @return paymentBalance The balance of payment tokens
     * @return liquidityBalance The balance of liquidity tokens
     * @return mythoBalance The balance of MYTHO tokens
     */
    function getAllBalances()
        public
        view
        returns (
            uint256 totemBalance,
            uint256 paymentBalance,
            uint256 liquidityBalance,
            uint256 mythoBalance
        )
    {
        totemBalance = IERC20(totemTokenAddr).balanceOf(address(this));
        paymentBalance = address(paymentToken) != address(0)
            ? paymentToken.balanceOf(address(this))
            : 0;
        liquidityBalance = address(liquidityToken) != address(0)
            ? liquidityToken.balanceOf(address(this))
            : 0;

        address mythoAddr = AddressRegistry(registryAddr).getMythoToken();
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
        return isCustomToken();
    }

    /**
     * @notice Get the token type
     * @return The type of token (STANDARD, ERC20, ERC721)
     */
    function getTokenType() external view returns (TokenType) {
        return tokenType;
    }

    /**
     * @notice Get the owner of this Totem
     * @return The address of the Totem owner
     */
    function getOwner() external view returns (address) {
        return owner;
    }

    /**
     * @notice Get the collaborator at the specified index
     * @param _index Index in the collaborators array
     * @return The address of the collaborator
     */
    function getCollaborator(uint256 _index) external view returns (address) {
        require(_index < collaborators.length, "Index out of bounds");
        return collaborators[_index];
    }

    /**
     * @notice Get all collaborators of this Totem
     * @return Array of collaborator addresses
     */
    function getAllCollaborators() external view returns (address[] memory) {
        return collaborators;
    }

    /**
     * @notice Check if the sale period has ended
     * @return True if the sale period has ended, false otherwise
     */
    function isSalePeriodEnded() external view returns (bool) {
        return salePeriodEnded;
    }

    /**
     * @notice Get the circulating supply of the TotemToken
     * @return The circulating supply (total supply minus tokens held by Totem and Treasury for custom tokens)
     */
    function getCirculatingSupply() public view returns (uint256) {
        uint256 totemBalance = IERC20(totemTokenAddr).balanceOf(address(this));
        uint256 treasuryBalance = isCustomToken()
            ? IERC20(totemTokenAddr).balanceOf(treasuryAddr)
            : 0;
        uint256 totalSupply;

        if (tokenType == TokenType.ERC721) {
            TokenHoldersOracle oracle = TokenHoldersOracle(AddressRegistry(registryAddr).getTokenHoldersOracle());
            // For NFTs, get holder count from oracle
            if (address(oracle) != address(0)) {
                (totalSupply, ) = oracle.getNFTCount(totemTokenAddr);
            } else {
                return 0; // No oracle data available
            }
        } else {
            // For ERC20 tokens
            totalSupply = IERC20(totemTokenAddr).totalSupply();
        }

        // Calculate circulating supply
        return totalSupply - totemBalance - treasuryBalance;
    }

    /**
     * @notice Calculates the amount of tokens a user would receive if they redeemed their totem tokens
     * @param _tokenAmount The amount of ERC20 tokens to redeem (ignored for NFT tokens)
     * @return paymentAmount The amount of payment tokens the user would receive
     * @return mythoAmount The amount of MYTHO tokens the user would receive
     * @return lpAmount The amount of LP tokens the user would receive
     */
    function estimateRedeemRewards(uint256 _tokenAmount) external view returns (
        uint256 paymentAmount,
        uint256 mythoAmount,
        uint256 lpAmount
    ) {
        // Check if sale period has ended for standard tokens
        if (tokenType == TokenType.STANDARD && !salePeriodEnded) {
            return (0, 0, 0);
        }
        
        // Get circulating supply
        uint256 circulatingSupply = getCirculatingSupply();
        if (circulatingSupply == 0) {
            return (0, 0, 0);
        }
        
        // Get balances to distribute
        (
            ,
            uint256 paymentTokenBalance,
            uint256 lpBalance,
            uint256 mythoBalance
        ) = getAllBalances();
        
        // Check if there are MYTHO tokens to claim in the current period
        uint256 currentPeriod = MeritManager(meritManagerAddr).currentPeriod();
        uint256 pendingReward = MeritManager(meritManagerAddr).getPendingReward(address(this), currentPeriod);
        mythoBalance += pendingReward; // Add pending rewards to MYTHO balance
        
        // Check that the amount is not zero
        if (_tokenAmount == 0) {
            return (0, 0, 0);
        }
        
        // For NFT always use 1 token, regardless of the value passed
        uint256 effectiveAmount = tokenType == TokenType.ERC721 ? 1 : _tokenAmount;
        
        // Calculate user share for each token type based on circulating supply
        paymentAmount = (paymentTokenBalance * effectiveAmount) / circulatingSupply;
        mythoAmount = (mythoBalance * effectiveAmount) / circulatingSupply;
        lpAmount = (lpBalance * effectiveAmount) / circulatingSupply;

        if (tokenType == TokenType.ERC721) {
            paymentAmount = 0;
            lpAmount = 0;
        }
        
        return (paymentAmount, mythoAmount, lpAmount);
    }
}
