// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Imports
import {MarketplaceItemToken} from "./MarketplaceItemToken.sol";
import {FeeManager} from "./FeeManager.sol";
import {MPRoles} from "./Roles.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "forge-std/console.sol";

contract MarketplaceV2opt is ReentrancyGuard, Pausable, IERC721Receiver {
    /* ==================================== */
    /*             TYPE DECLARATIONS        */
    /* ==================================== */

    struct Listing {
        uint256 listingId;
        address seller;
        address tokenAddress;
        uint256 tokenId;
        uint256 price;
        bool isSold;
    }

    struct SellerInfo {
        uint256 saleCount;
        bool isGolden;
        bool isSilver;
        uint256 withdrawAmount;
    }

    /* ==================================== */
    /*            STATE VARIABLES           */
    /* ==================================== */

    // Listing counter
    uint256 private _listingIdCount;

    // Contract references (immutable for gas savings)
    MarketplaceItemToken private immutable itemToken;
    FeeManager private immutable feeManager;
    MPRoles private immutable mpRoles;

    // Mappings for listings and seller info
    mapping(uint256 => Listing) public listings;
    mapping(address => SellerInfo) private sellers;

    // Optimization: mapping that tracks whether a given external NFT is already listed.
    // The key is keccak256(abi.encodePacked(tokenAddress, tokenId)).
    mapping(bytes32 => bool) private _isListed;

    /* ==================================== */
    /*               EVENTS                 */
    /* ==================================== */

    event ItemListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed tokenAddress,
        uint256 tokenId,
        uint256 price
    );
    event ItemRevoked(
        uint256 indexed listingId,
        address indexed seller,
        address indexed tokenAddress,
        uint256 tokenId
    );
    event ItemSold(
        uint256 indexed listingId,
        address indexed seller,
        address indexed buyer,
        address tokenAddress,
        uint256 tokenId,
        uint256 price
    );
    event SellerFundsWithdrawn(address indexed seller, uint256 indexed amount);

    /* ==================================== */
    /*             CUSTOM MODIFIERS         */
    /* ==================================== */

    modifier onlyAdmin() {
        require(
            mpRoles.hasRole(mpRoles.ADMIN_ROLE(), msg.sender),
            "MarketplaceV2opt: caller is not an admin"
        );
        _;
    }

    modifier onlyVerified() {
        require(
            mpRoles.hasRole(mpRoles.VERIFIED_ROLE(), msg.sender),
            "MarketplaceV2opt: caller is not a verified user"
        );
        _;
    }

    /* ==================================== */
    /*             CONSTRUCTOR              */
    /* ==================================== */

    constructor() {
        console.log("Deploying MarketplaceV2opt, msg.sender =", msg.sender);
        mpRoles = new MPRoles(msg.sender);
        feeManager = new FeeManager(msg.sender, msg.sender, 250, 100); // 2.5% fee, 1% revoke fee
        itemToken = new MarketplaceItemToken(msg.sender);
    }

    /* ==================================== */
    /*         EXTERNAL FUNCTIONS           */
    /* ==================================== */

    /**
     * @notice List an external ERC721 NFT for sale.
     * @param tokenAddress The external ERC721 token contract address.
     * @param tokenId The token ID to be listed.
     * @param price The sale price in wei.
     */
    function listItem(
        address tokenAddress,
        uint256 tokenId,
        uint256 price
    ) external whenNotPaused nonReentrant onlyVerified {
        require(price > 0, "Price must be greater than zero");
        require(tokenAddress != address(0), "Invalid token address");

        // Use mapping to check if this token is already listed.
        bytes32 key = keccak256(abi.encodePacked(tokenAddress, tokenId));
        require(!_isListed[key], "Token is already listed");

        require(
            IERC721(tokenAddress).ownerOf(tokenId) == msg.sender,
            "Caller is not the owner"
        );
        require(
            IERC721(tokenAddress).getApproved(tokenId) == address(this),
            "Contract is not approved to transfer token"
        );

        uint256 newListingId = _listingIdCount++;
        listings[newListingId] = Listing({
            listingId: newListingId,
            seller: msg.sender,
            tokenAddress: tokenAddress,
            tokenId: tokenId,
            price: price,
            isSold: false
        });
        // Mark token as listed for faster lookup (optimized over iterating through listings)
        _isListed[key] = true;

        // Issue a regular badge if this is the seller's first sale.
        if (sellers[msg.sender].saleCount == 0) {
            itemToken.mintRegular(msg.sender);
        }

        // Transfer the external NFT from the seller to the marketplace.
        IERC721(tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId
        );

        emit ItemListed(newListingId, msg.sender, tokenAddress, tokenId, price);
    }

    /**
     * @notice Revoke a listing and return the external NFT to the seller.
     * @param listingId The ID of the listing to revoke.
     */
    function revokeItem(
        uint256 listingId
    ) external payable whenNotPaused nonReentrant onlyVerified {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "Caller is not the seller");
        require(!listing.isSold, "Cannot revoke a sold listing");

        uint256 sale = 0;
        if (sellers[msg.sender].isGolden) {
            sale = feeManager.getRevokeFee();
        } else if (sellers[msg.sender].isSilver) {
            sale = feeManager.getRevokeFee() / 2;
        }
        uint256 revokeFee = feeManager.calculateRevokeFee(listing.price, sale);
        require(msg.value >= revokeFee, "Insufficient funds for revoke");

        // Save token info before deletion.
        bytes32 key = keccak256(
            abi.encodePacked(listing.tokenAddress, listing.tokenId)
        );
        address tokenAddress = listing.tokenAddress;
        uint256 tokenId = listing.tokenId;
        // Remove from listing mapping and mark as not listed.
        delete listings[listingId];
        _isListed[key] = false;

        // Transfer the external NFT back to the seller.
        IERC721(tokenAddress).safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
        emit ItemRevoked(listingId, msg.sender, tokenAddress, tokenId);
    }

    /**
     * @notice Buy an external NFT from the marketplace.
     * @param listingId The ID of the listing to buy.
     */
    function buyItem(
        uint256 listingId
    ) external payable whenNotPaused nonReentrant onlyVerified {
        Listing storage listing = listings[listingId];
        require(listing.seller != address(0), "Listing does not exist");
        require(!listing.isSold, "Listing is already sold");
        require(msg.value >= listing.price, "Insufficient funds");

        listing.isSold = true;
        sellers[listing.seller].saleCount++;

        // Issue badge upgrades based on sales count.
        if (
            sellers[listing.seller].saleCount >= 20 &&
            !sellers[listing.seller].isGolden
        ) {
            _issueGoldBadge(listing.seller);
        } else if (
            sellers[listing.seller].saleCount >= 10 &&
            !sellers[listing.seller].isSilver
        ) {
            _issueSilverBadge(listing.seller);
        }

        uint256 feeAmount = feeManager.calculateFee(listing.price, 0);
        uint256 sellerAmount = listing.price - feeAmount;
        sellers[listing.seller].withdrawAmount += sellerAmount;

        // Transfer external NFT to buyer.
        IERC721(listing.tokenAddress).safeTransferFrom(
            address(this),
            msg.sender,
            listing.tokenId
        );
        emit ItemSold(
            listingId,
            listing.seller,
            msg.sender,
            listing.tokenAddress,
            listing.tokenId,
            listing.price
        );
    }

    /**
     * @notice Get the total number of listings.
     */
    function getListingCount() external view returns (uint256) {
        return _listingIdCount;
    }

    /**
     * @notice Gets the withdraw amount of a seller.
     * @param sellerAddress The seller's address.
     */
    function getSellerWithdrawAmount(
        address sellerAddress
    ) external view returns (uint256) {
        return sellers[sellerAddress].withdrawAmount;
    }

    /**
     * @notice Pause the marketplace.
     */
    function pauseMarketplace() external onlyAdmin {
        _pause();
    }

    /**
     * @notice Unpause the marketplace.
     */
    function unpauseMarketplace() external onlyAdmin {
        _unpause();
    }

    /**
     * @notice Withdraw contract funds (admin only).
     * @param amount The amount to withdraw.
     */
    function withdrawFunds(uint256 amount) external onlyAdmin nonReentrant {
        require(
            amount <= address(this).balance,
            "Insufficient contract balance"
        );
        payable(msg.sender).transfer(amount);
    }

    /**
     * @notice Seller withdraws their accumulated funds.
     * @param seller The seller's address.
     * @param amount The amount to withdraw.
     */
    function witdrawSellerFunds(
        address seller,
        uint256 amount
    ) external nonReentrant onlyVerified {
        require(msg.sender == seller, "Caller is not the seller");
        require(
            amount <= sellers[seller].withdrawAmount,
            "Insufficient withdrawable amount"
        );
        sellers[seller].withdrawAmount -= amount;
        payable(seller).transfer(amount);

        emit SellerFundsWithdrawn(seller, amount);
    }

    /**
     * @notice Burn a badge token (admin only).
     * @param tokenId The ID of the token to burn.
     */
    function burnBadge(uint256 tokenId) external onlyAdmin {
        itemToken.burn(tokenId);
    }

    // The following getter functions are for testing purposes.
    function getTokenContractAddress() external view returns (address) {
        return address(itemToken);
    }

    function getFeeManagerContractAddress() external view returns (address) {
        return address(feeManager);
    }

    function getRolesContractAddress() external view returns (address) {
        return address(mpRoles);
    }

    /* ==================================== */
    /*         INTERNAL FUNCTIONS           */
    /* ==================================== */

    function _issueGoldBadge(address recipient) internal {
        itemToken.mintGold(recipient);
        sellers[recipient].isGolden = true;
    }

    function _issueSilverBadge(address recipient) internal {
        itemToken.mintSilver(recipient);
        sellers[recipient].isSilver = true;
    }

    /**
     * @notice Implementation of IERC721Receiver to allow this contract to receive ERC721 tokens.
     * @dev Returns `IERC721Receiver.onERC721Received.selector` on success.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
