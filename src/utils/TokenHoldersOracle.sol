// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title TokenHoldersOracle
 * @notice Oracle contract that fetches token holder counts from Blockscout API using Chainlink Functions
 * @dev Uses Chainlink Functions to make HTTP requests to Blockscout API
 */
contract TokenHoldersOracle is FunctionsClient, ConfirmedOwner, AccessControl {
    using FunctionsRequest for FunctionsRequest.Request;

    // Request tracking variables
    bytes32 public lastRequestId;
    address public lastQueriedToken;

    // Chainlink Functions configuration
    uint64 public subscriptionId;
    uint32 public gasLimit;

    // Addresses
    address private mythoTreasuryAddr;

    /**
     * @notice Structure to store token holder information
     * @param holdersCount Number of token holders
     * @param lastUpdateTimestamp Timestamp of the last update
     */
    struct TokenInfo {
        uint256 holdersCount;
        uint256 lastUpdateTimestamp;
    }

    // Mapping from token address to its holder information
    mapping(address => TokenInfo) public tokenHolders;

    // Chainlink Functions DON ID for Soneium network
    bytes32 public constant donId =
        0x66756e2d736f6e6569756d2d6d61696e6e65742d310000000000000000000000;

    // Role for accounts that can request holder counts
    bytes32 public constant CALLER_ROLE = keccak256("CALLER_ROLE");

    // Fee for updating NFT holder count
    uint256 public updateFee;

    // Maximum age of data in seconds (default: 5 minutes)
    uint256 public maxDataAge;

    /**
     * @notice JavaScript source code for Chainlink Functions
     * @dev Makes HTTP request to Blockscout API to get token holder count
     */
    string private constant source =
        "const tokenAddress = args[0]; "
        "let holdersCount = null; "
        "try { "
        "  const response = await Functions.makeHttpRequest({ "
        "    url: `https://soneium.blockscout.com/api/v2/tokens/${tokenAddress}/counters` "
        "  }); "
        "  if (response.data && response.data.token_holders_count) { "
        "    holdersCount = parseInt(response.data.token_holders_count, 10); "
        "  } "
        "} catch (e) { "
        "  throw Error('Failed to fetch holders count from Blockscout API'); "
        "} "
        "if (holdersCount === null) { "
        "  throw Error('Invalid response from Blockscout API'); "
        "} "
        "return Functions.encodeUint256(holdersCount);";

    // Events
    event HoldersCountUpdated(
        address indexed token,
        uint256 count,
        uint256 timestamp
    );
    event RequestFailed(bytes32 requestId, string reason);
    event ManualUpdate(address indexed token, uint256 count, address updater);
    event UpdateFeeChanged(uint256 oldFee, uint256 newFee);
    event UpdateFeeCollected(
        address indexed user,
        address indexed token,
        uint256 fee
    );
    event TreasuryAddressUpdated(address oldTreasury, address newTreasury);

    // Custom errors
    error NotERC721Token();
    error InsufficientNFTBalance();
    error InsufficientFee();
    error DataAlreadyFresh();
    error TreasuryNotSet();
    error FeeTransferFailed();
    error RefundTransferFailed();
    error InvalidTokenAddress();
    error InvalidTreasuryAddress();

    constructor(
        address router,
        address _treasuryAddr
    ) FunctionsClient(router) ConfirmedOwner(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CALLER_ROLE, msg.sender);
        updateFee = 0.0003 ether; // Default fee of 0.0003 native tokens
        maxDataAge = 5 minutes;
        mythoTreasuryAddr = _treasuryAddr;
    }

    // EXTERNAL FUNCTIONS

    /**
     * @notice Requests the current holders count for a token
     * @dev Uses Chainlink Functions to fetch data from Blockscout API
     * @param _tokenAddress The address of the token to query
     * @return requestId The ID of the Chainlink Functions request
     */
    function requestHoldersCount(
        address _tokenAddress
    ) external onlyRole(CALLER_ROLE) returns (bytes32 requestId) {
        lastRequestId = _sendHoldersCountRequest(_tokenAddress);
        return lastRequestId;
    }

    /**
     * @notice Allows NFT holders to update the holder count for their NFT
     * @dev Requires payment of updateFee in native tokens
     * @param _nftAddress The address of the NFT to update
     */
    function updateNFTHoldersCount(address _nftAddress) external payable {
        // Verify the token is an NFT (ERC721)
        if (!IERC721(_nftAddress).supportsInterface(0x80ac58cd))
            revert NotERC721Token();

        // Verify caller holds at least one NFT
        if (IERC721(_nftAddress).balanceOf(msg.sender) == 0)
            revert InsufficientNFTBalance();

        // Verify correct fee is paid
        if (msg.value < updateFee) revert InsufficientFee();

        // Check if the data is already fresh
        if (isDataFresh(_nftAddress)) revert DataAlreadyFresh();

        // Send the Chainlink Functions request
        lastRequestId = _sendHoldersCountRequest(_nftAddress);

        // Transfer fee to the MYTHO treasury
        if (mythoTreasuryAddr == address(0)) revert TreasuryNotSet();
        (bool success, ) = mythoTreasuryAddr.call{value: updateFee}("");
        if (!success) revert FeeTransferFailed();

        // Emit event for tracking
        emit UpdateFeeCollected(msg.sender, _nftAddress, updateFee);

        // Refund excess fee if any
        if (msg.value > updateFee) {
            (success, ) = msg.sender.call{value: msg.value - updateFee}("");
            if (!success) revert RefundTransferFailed();
        }
    }

    // ADMIN FUNCTIONS

    /**
     * @notice Manually updates the holders count for a token (emergency use only)
     * @dev Only callable by admin, used when Chainlink Functions fails
     * @param _tokenAddress The address of the token to update
     * @param _count The number of token holders
     */
    function manuallyUpdateHoldersCount(
        address _tokenAddress,
        uint256 _count
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Validate input
        if (_tokenAddress == address(0)) revert InvalidTokenAddress();

        // Get current timestamp
        uint256 timestamp = block.timestamp;

        // Update the token holder information
        tokenHolders[_tokenAddress] = TokenInfo({
            holdersCount: _count,
            lastUpdateTimestamp: timestamp
        });

        // Emit events for tracking
        emit HoldersCountUpdated(_tokenAddress, _count, timestamp);
        emit ManualUpdate(_tokenAddress, _count, msg.sender);
    }

    /**
     * @notice Sets the Chainlink Functions subscription ID
     * @dev Only callable by admin
     * @param _subscriptionId The subscription ID to use for Chainlink Functions
     */
    function setSubscriptionId(
        uint64 _subscriptionId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        subscriptionId = _subscriptionId;
    }

    /**
     * @notice Sets the gas limit for Chainlink Functions requests
     * @dev Only callable by admin
     * @param _gasLimit The gas limit to use for Chainlink Functions
     */
    function setGasLimit(
        uint32 _gasLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gasLimit = _gasLimit;
    }

    /**
     * @notice Sets the fee for updating NFT holder counts
     * @dev Only callable by admin
     * @param _newFee The new fee amount in native tokens
     */
    function setUpdateFee(
        uint256 _newFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldFee = updateFee;
        updateFee = _newFee;
        emit UpdateFeeChanged(oldFee, _newFee);
    }

    /**
     * @notice Sets the maximum age of data in seconds
     * @dev Only callable by admin
     * @param _newMaxDataAge The new maximum age of data in seconds
     */
    function setMaxDataAge(
        uint256 _newMaxDataAge
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxDataAge = _newMaxDataAge;
    }

    /**
     * @notice Sets the MYTHO treasury address
     * @dev Only callable by admin
     * @param _treasuryAddr The new treasury address
     */
    function setTreasuryAddress(
        address _treasuryAddr
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treasuryAddr == address(0)) revert InvalidTreasuryAddress();
        address oldTreasury = mythoTreasuryAddr;
        mythoTreasuryAddr = _treasuryAddr;
        emit TreasuryAddressUpdated(oldTreasury, _treasuryAddr);
    }

    // INTERNAL FUNCTIONS

    /**
     * @notice Internal function to send a Chainlink Functions request
     * @dev Common logic for both requestHoldersCount and updateNFTHoldersCount
     * @param _tokenAddress The address of the token to query
     * @return requestId The ID of the Chainlink Functions request
     */
    function _sendHoldersCountRequest(
        address _tokenAddress
    ) internal returns (bytes32 requestId) {
        // Store the token address for use in the callback
        lastQueriedToken = _tokenAddress;

        // Initialize the Chainlink Functions request
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);

        // Set the token address as an argument for the JavaScript code
        string[] memory args = new string[](1);
        args[0] = toString(_tokenAddress);
        req.setArgs(args);

        // Send the request to Chainlink Functions
        return _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
    }

    /**
     * @notice Callback function for Chainlink Functions
     * @dev Called by the Chainlink Functions Router when a request is fulfilled
     * @param requestId The ID of the request being fulfilled
     * @param response The response from the Chainlink Functions request
     * @param err Any error that occurred during the request
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        // Handle errors from Chainlink Functions
        if (err.length > 0) {
            emit RequestFailed(requestId, string(err));
            return;
        }

        // Decode the response (holder count)
        uint256 count = abi.decode(response, (uint256));
        uint256 timestamp = block.timestamp;

        // Update the token holder information
        tokenHolders[lastQueriedToken] = TokenInfo({
            holdersCount: count,
            lastUpdateTimestamp: timestamp
        });

        // Emit event for tracking
        emit HoldersCountUpdated(lastQueriedToken, count, timestamp);
    }

    // VIEW FUNCTIONS

    /**
     * @notice Gets the current holders count and last update timestamp for a token
     * @param _tokenAddress The address of the token to query
     * @return count The number of token holders
     * @return lastUpdate The timestamp of the last update
     */
    function getHoldersCount(
        address _tokenAddress
    ) external view returns (uint256 count, uint256 lastUpdate) {
        TokenInfo memory info = tokenHolders[_tokenAddress];
        return (info.holdersCount, info.lastUpdateTimestamp);
    }

    /**
     * @notice Checks if the holder count data is fresh (less than maxDataAge old)
     * @param _tokenAddress The address of the token to check
     * @return True if the data is fresh, false otherwise
     */
    function isDataFresh(address _tokenAddress) public view returns (bool) {
        TokenInfo memory info = tokenHolders[_tokenAddress];
        return (block.timestamp - info.lastUpdateTimestamp) <= maxDataAge;
    }

    /**
     * @notice Converts an address to a string
     * @dev Used to format the token address for the Chainlink Functions request
     * @param _addr The address to convert
     * @return The string representation of the address
     */
    function toString(address _addr) internal pure returns (string memory) {
        bytes memory result = new bytes(42);
        result[0] = "0";
        result[1] = "x";

        // More efficient hex conversion
        address addr = _addr;
        for (uint256 i = 0; i < 20; i++) {
            uint8 value = uint8(uint160(addr) >> (8 * (19 - i)));
            result[2 + i * 2] = toHexChar(value >> 4);
            result[3 + i * 2] = toHexChar(value & 0x0f);
        }

        return string(result);
    }

    /**
     * @notice Converts a nibble to its hex character
     * @dev Helper function for toString
     * @param value The nibble to convert (0-15)
     * @return The hex character representation
     */
    function toHexChar(uint8 value) internal pure returns (bytes1) {
        if (value < 10) {
            return bytes1(uint8(bytes1("0")) + value);
        } else {
            return bytes1(uint8(bytes1("a")) + value - 10);
        }
    }
}
