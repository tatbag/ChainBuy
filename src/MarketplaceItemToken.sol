// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

// Imports
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "forge-std/console.sol";

contract MarketplaceItemToken is ERC721, ERC721URIStorage, Ownable {
    /* ========== STATE VARIABLES ========== */
    uint256 private _nextTokenId;

    // Predefined URIs for different badges
    string public constant GOLD_BADGE_URI = "ipfs://QmGoldBadgeMetadata";
    string public constant SILVER_BADGE_URI = "ipfs://QmSilverBadgeMetadata";
    string public constant BRONZE_BADGE_URI = "ipfs://QmBronzeBadgeMetadata";

    /* ========== EVENTS ========== */
    event TokenMinted(
        uint256 indexed tokenId,
        address indexed recipient,
        string tokenURI
    );

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address _owner
    ) ERC721("MarketplaceItem", "MI") Ownable(_owner) {
        console.log("MarketplaceItemToken deployed: owner is %s", _owner);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function burn(uint256 tokenId) external {
        console.log("burning token msg.sender: %s", msg.sender);
        _burn(tokenId);
    }

    function updateTokenURI(
        uint256 tokenId,
        string memory newTokenURI
    ) external onlyOwner {
        require(ownerOf(tokenId) != address(0), "Token does not exist");
        _setTokenURI(tokenId, newTokenURI);
    }

    /* ========== PUBLIC FUNCTIONS ========== */
    function mintGold(address to) public onlyOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, GOLD_BADGE_URI);
        emit TokenMinted(tokenId, to, GOLD_BADGE_URI);
    }

    function mintSilver(address to) public onlyOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, SILVER_BADGE_URI);
        emit TokenMinted(tokenId, to, SILVER_BADGE_URI);
    }

    function mintRegular(address to) public {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, BRONZE_BADGE_URI);
        emit TokenMinted(tokenId, to, BRONZE_BADGE_URI);
    }

    /* ========== VIEW FUNCTIONS ========== */
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
