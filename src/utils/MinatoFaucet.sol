// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockToken} from "../../test/mocks/MockToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MinatoFaucet is Ownable {
    MockToken public token;
    uint256 public mintAmount;
    uint256 public constant COOLDOWN_PERIOD = 1 days;
    
    // Mapping to track the last time an address requested tokens
    mapping(address => uint256) public lastRequestTime;
    
    event TokenAddressChanged(address indexed oldToken, address indexed newToken);
    event MintAmountChanged(uint256 oldAmount, uint256 newAmount);
    event TokensMinted(address indexed recipient, uint256 amount);
    event RequestDenied(address indexed requester, uint256 nextAvailableTime);

    constructor(address _tokenAddr, uint256 _initialMintAmount) Ownable(msg.sender) {
        token = MockToken(_tokenAddr);
        mintAmount = _initialMintAmount;
    }
    
    /**
     * @notice Mints a fixed amount of tokens to the caller
     * @dev Can only be called once per day (24 hours) per address
     */
    function requestTokens() external {
        uint256 lastRequest = lastRequestTime[msg.sender];
        uint256 currentTime = block.timestamp;
        
        // Check if the cooldown period has passed
        require(
            lastRequest == 0 || currentTime >= lastRequest + COOLDOWN_PERIOD,
            "MinatoFaucet: You can only request tokens once per day"
        );
        
        // Update the last request time
        lastRequestTime[msg.sender] = currentTime;
        
        // Mint tokens to the caller
        token.mint(msg.sender, mintAmount);
        emit TokensMinted(msg.sender, mintAmount);
    }
    
    /**
     * @notice Checks if an address can request tokens
     * @param _user Address to check
     * @return canRequest Whether the user can request tokens
     * @return timeRemaining Time remaining until the user can request tokens again (0 if they can request now)
     */
    function canRequestTokens(address _user) external view returns (bool canRequest, uint256 timeRemaining) {
        uint256 lastRequest = lastRequestTime[_user];
        
        // If the user has never requested tokens, they can request now
        if (lastRequest == 0) {
            return (true, 0);
        }
        
        uint256 nextAvailableTime = lastRequest + COOLDOWN_PERIOD;
        
        // If the cooldown period has passed, they can request now
        if (block.timestamp >= nextAvailableTime) {
            return (true, 0);
        }
        
        // Otherwise, they need to wait
        return (false, nextAvailableTime - block.timestamp);
    }
    
    /**
     * @notice Changes the amount of tokens to mint
     * @param _newMintAmount New amount of tokens to mint
     */
    function setMintAmount(uint256 _newMintAmount) external onlyOwner {
        uint256 oldAmount = mintAmount;
        mintAmount = _newMintAmount;
        emit MintAmountChanged(oldAmount, _newMintAmount);
    }
    
    /**
     * @notice Changes the token address
     * @param _newTokenAddr New token address
     */
    function setTokenAddress(address _newTokenAddr) external onlyOwner {
        address oldToken = address(token);
        token = MockToken(_newTokenAddr);
        emit TokenAddressChanged(oldToken, _newTokenAddr);
    }
}