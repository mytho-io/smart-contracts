// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFV2PlusClient} from "@ccip/vrf/dev/libraries/VRFV2PlusClient.sol";

// Mock VRF Coordinator for testing
contract MockVRFCoordinator {
    uint256 private _requestIdCounter = 1;
    mapping(uint256 => address) public requestConsumers;
    mapping(uint256 => uint256[]) public storedRandomWords;
    
    function requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest memory req
    ) external returns (uint256) {
        uint256 requestId = _requestIdCounter++;
        
        // Store the consumer and generate random words
        requestConsumers[requestId] = msg.sender;
        uint256[] memory randomWords = new uint256[](req.numWords);
        for (uint256 i = 0; i < req.numWords; i++) {
            randomWords[i] = uint256(keccak256(abi.encode(requestId, i, block.timestamp)));
        }
        storedRandomWords[requestId] = randomWords;
        
        // Don't automatically fulfill - let the test do it manually
        return requestId;
    }
    
    function fulfillRandomWords(uint256 requestId) public {
        address consumer = requestConsumers[requestId];
        uint256[] memory randomWords = storedRandomWords[requestId];
        
        // Call the fulfillRandomWords function on the consumer from this contract
        (bool success, ) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            )
        );
        require(success, "Failed to fulfill randomness");
    }
}