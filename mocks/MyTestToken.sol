// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

/**
 * @title MyTest1155Token
 * @dev A simple ERC1155 token contract to act as a mock for testing purposes.
 */
contract MyTestToken is ERC721 {
    uint256 public currentTokenID;

    // The constructor accepts a base URI (e.g., "ipfs://<CID>/{id}.json")
    constructor(string memory baseURI) ERC721("TEST TOKEN", "TT") {}

    /**
     * @notice Mint a new ERC721 token.
     * @param account The address to receive the tokens.
     * @return tokenId The new token id.
     */
    function mint(address account) public returns (uint256 tokenId) {
        currentTokenID++;
        tokenId = currentTokenID;
        _mint(account, tokenId);
    }
}
