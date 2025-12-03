// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

contract MythoPatriarch is ERC721, AccessControl {
    bytes32 public constant MANAGER = keccak256("MANAGER");
    
    string private _baseTokenURI;
    uint256 private _tokenIdCounter;
    
    event TokenURIUpdated(string newURI);
    event TokenMinted(address indexed to, uint256 indexed tokenId);

    constructor(string memory baseURI) ERC721("Mytho Patriach", "") {
        _baseTokenURI = baseURI;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER, msg.sender);
    }

    /**
     * @dev Mint NFT to specified address (only manager)
     * @param to Address to mint to
     */
    function mint(address to) external onlyRole(MANAGER) {
        require(to != address(0), "Invalid address");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(to, tokenId);
        emit TokenMinted(to, tokenId);
    }

    /**
     * @dev Batch mint NFTs to multiple addresses (only manager)
     * @param addresses Array of addresses to mint to
     */
    function batchMint(address[] calldata addresses) external onlyRole(MANAGER) {
        require(addresses.length > 0, "Empty array");
        require(addresses.length <= 100, "Too many addresses");
        
        for (uint256 i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "Invalid address");
            
            uint256 tokenId = _tokenIdCounter;
            _tokenIdCounter++;
            
            _safeMint(addresses[i], tokenId);
            emit TokenMinted(addresses[i], tokenId);
        }
    }

    /**
     * @dev Update base token URI (only admin)
     * @param newURI New base URI
     */
    function setTokenURI(string calldata newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newURI;
        emit TokenURIUpdated(newURI);
    }

    /**
     * @dev Get token URI for any token ID
     * @param tokenId Token ID
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        return _baseTokenURI;
    }



    /**
     * @dev Get current token ID counter
     */
    function getTokenIdCounter() external view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @dev Support for AccessControl interface
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC721, AccessControl) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
}