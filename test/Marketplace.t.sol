// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Marketplace.sol";
import "../mocks/MyTestToken.sol";
import "../src/FeeManager.sol";
import "../src/Roles.sol";

contract MarketplaceTest is Test {
    /* ========== STATE VARIABLES ========== */
    Marketplace marketplace;
    MyTestToken token;
    MPRoles mpRoles;
    FeeManager feeManager;

    // Test addresses for different roles (using Anvil's default accounts)
    address admin = vm.addr(1);
    address seller = vm.addr(2);
    address buyer = vm.addr(3);

    // Example sale price for tests
    uint256 constant TEST_PRICE = 1 ether;
    uint256 mintedTokenId; // to store the minted token ID

    /* ========== SETUP ========== */
    function setUp() public {
        // Deploy token separately with a base URI.
        vm.startPrank(admin);

        token = new MyTestToken("ipfs://baseURI/{id}.json");
        // Deploy the Marketplace contract.
        marketplace = new Marketplace();

        // Retrieve the Roles contract deployed by the Marketplace.
        address rolesAddress = marketplace.getRolesContractAddress();
        mpRoles = MPRoles(rolesAddress);

        address feeManagerAddress = marketplace.getFeeManagerContractAddress();
        feeManager = FeeManager(feeManagerAddress);

        bool adminHasRole = mpRoles.hasRole(mpRoles.ADMIN_ROLE(), admin);
        console.log("Admin has ADMIN_ROLE:", adminHasRole);

        vm.stopPrank();
    }

    /* ========== LISTING TESTS ========== */
    function testListItem() public {
        // Grant seller the VERIFIED_ROLE via the external Roles contract.
        vm.startPrank(admin);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);
        vm.stopPrank();

        // Seller sets approval for the Marketplace contract to manage their tokens.
        vm.startPrank(seller);
        // Mint a test ERC1155 token to the seller.
        mintedTokenId = token.mint(seller);
        assertEq(mintedTokenId, 1);
        token.approve(address(marketplace), mintedTokenId);
        marketplace.listItem(address(token), mintedTokenId, TEST_PRICE);

        // Check that the listing exists with correct details.
        (
            uint256 listingId,
            address _seller,
            address _tokenAddress,
            uint256 tokenId,
            uint256 price,
            bool isSold
        ) = marketplace.listings(0);
        assertEq(listingId, 0);
        assertEq(_seller, seller);
        assertEq(_tokenAddress, address(token));
        assertEq(tokenId, mintedTokenId);
        assertEq(price, TEST_PRICE);
        assertFalse(isSold);

        // Check that the Marketplace contract holds the token (using ERC1155 balanceOf).
        uint256 marketplaceBalance = token.balanceOf(address(marketplace));
        assertEq(marketplaceBalance, 1);
        vm.stopPrank();
    }

    /* ========== BUYING TESTS ========== */
    function testBuyItem() public {
        // Setup: Grant seller role and list an item.
        vm.startPrank(admin);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), buyer);
        vm.stopPrank();

        vm.startPrank(seller);
        mintedTokenId = token.mint(seller);
        token.approve(address(marketplace), mintedTokenId);
        marketplace.listItem(address(token), mintedTokenId, TEST_PRICE);
        vm.stopPrank();

        // Simulate buyer with sufficient funds buying the item.
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        marketplace.buyItem{value: TEST_PRICE}(0);

        // Verify that the token is now owned by the buyer.
        uint256 buyerBalance = token.balanceOf(buyer);
        assertEq(buyerBalance, 1);
    }

    /* ========== REVOKE TESTS ========== */
    function testRevokeItem() public {
        // Setup: Grant seller role and list an item.
        vm.startPrank(admin);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);
        vm.stopPrank();

        vm.startPrank(seller);
        mintedTokenId = token.mint(seller);
        token.approve(address(marketplace), mintedTokenId);
        marketplace.listItem(address(token), mintedTokenId, TEST_PRICE);

        // Seller revokes the listing.
        vm.expectRevert("Insufficient funds for revoke");
        marketplace.revokeItem(0);

        // Now  give them some $s
        vm.deal(seller, 3 ether);
        marketplace.revokeItem{value: 3 ether}(0);

        // Verify that the listing is removed and the token is returned to the seller.
        uint256 sellerBalance = token.balanceOf(seller);
        assertEq(sellerBalance, 1);
    }

    /* ========== PAUSE/UNPAUSE TESTS ========== */
    function testPauseAndUnpause() public {
        // Admin pauses the marketplace.
        vm.startPrank(admin);
        marketplace.pauseMarketplace();

        // Grant seller role.
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);
        vm.stopPrank();

        // Listing should revert when marketplace is paused.
        vm.prank(seller);
        vm.expectRevert();
        marketplace.listItem(address(0x1234), 1, TEST_PRICE);

        // Admin unpauses the marketplace.
        vm.prank(admin);
        marketplace.unpauseMarketplace();

        // After unpausing, listing should succeed.
        vm.startPrank(seller);
        mintedTokenId = token.mint(seller);
        token.approve(address(marketplace), mintedTokenId);
        marketplace.listItem(address(token), mintedTokenId, TEST_PRICE);
    }

    /* ========== FEE CALCULATION TESTS ========== */
    function testFeeCalculation() public {
        // Grant seller the VERIFIED_ROLE using MPRoles.
        vm.startPrank(admin);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), buyer);

        // Mint a test NFT for listing.
        vm.startPrank(seller);
        mintedTokenId = token.mint(seller);
        token.approve(address(marketplace), mintedTokenId);

        // Seller lists the NFT with a sale price of 1 ether.
        marketplace.listItem(address(token), mintedTokenId, TEST_PRICE);

        // Simulate buyer purchasing the NFT.
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        marketplace.buyItem{value: TEST_PRICE}(0);

        // Calculate the expected fee and seller amount.
        uint256 expectedFee = feeManager.calculateFee(TEST_PRICE, 0); // Assuming no discount for revoke fee here.
        uint256 expectedSellerAmount = TEST_PRICE - expectedFee;

        // Retrieve the seller's withdrawable funds from Marketplace.
        uint256 sellerWithdrawAmount = marketplace.getSellerWithdrawAmount(
            seller
        );
        assertEq(sellerWithdrawAmount, expectedSellerAmount);
    }
}
