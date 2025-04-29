// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

contract TokenHoldersOracle is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public lastRequestId;
    address public lastQueriedToken;
    uint64 public subscriptionId;
    uint32 public gasLimit;

    struct TokenInfo {
        uint256 holdersCount;
        uint256 lastUpdateTimestamp;
    }
    mapping(address => TokenInfo) public tokenHolders;

    bytes32 public constant donId = 0x66756e2d736f6e6569756d2d6d61696e6e65742d310000000000000000000000;

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

    event HoldersCountUpdated(address indexed token, uint256 count, uint256 timestamp);
    event RequestFailed(bytes32 requestId, string reason);

    constructor(address router) FunctionsClient(router) ConfirmedOwner(msg.sender) {}

    function setSubscriptionId(uint64 _subscriptionId) external onlyOwner {
        subscriptionId = _subscriptionId;
    }

    function setGasLimit(uint32 _gasLimit) external onlyOwner {
        gasLimit = _gasLimit;
    }

    function requestHoldersCount(address _tokenAddress) external onlyOwner returns (bytes32 requestId) {
        lastQueriedToken = _tokenAddress;

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source);

        string[] memory args = new string[](1);
        args[0] = toString(_tokenAddress);

        req.setArgs(args);

        lastRequestId = _sendRequest(req.encodeCBOR(), subscriptionId, gasLimit, donId);
        return lastRequestId;
    }

    function getHoldersCount(address _tokenAddress) external view returns (uint256 count, uint256 lastUpdate) {
        TokenInfo memory info = tokenHolders[_tokenAddress];
        return (info.holdersCount, info.lastUpdateTimestamp);
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (err.length > 0) {
            emit RequestFailed(requestId, string(err));
            return;
        }
        
        uint256 count = abi.decode(response, (uint256));
        uint256 timestamp = block.timestamp;
        
        tokenHolders[lastQueriedToken] = TokenInfo({
            holdersCount: count,
            lastUpdateTimestamp: timestamp
        });

        emit HoldersCountUpdated(lastQueriedToken, count, timestamp);
    }

    function toString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}