// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Marketplace.sol";
import "../src/MarketplaceV2opt.sol";
import "../mocks/MyTestToken.sol";
import "../src/FeeManager.sol";
import "../src/Roles.sol";

contract MarketplaceTest is Test {
    /* ========== STATE VARIABLES ========== */
    Marketplace marketplace;
    MarketplaceItemToken itemToken;
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

        address itemTokenAddr = marketplace.getTokenContractAddress();
        itemToken = MarketplaceItemToken(itemTokenAddr);

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

    function testWithdrawFunds() public {
        // Simulate a sale so that the contract accrues fees
        vm.startPrank(admin);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), buyer);
        vm.stopPrank();

        // Seller lists an NFT
        vm.startPrank(seller);
        mintedTokenId = token.mint(seller);
        token.approve(address(marketplace), mintedTokenId);
        marketplace.listItem(address(token), mintedTokenId, TEST_PRICE);
        vm.stopPrank();

        // Buyer purchases the NFT
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        marketplace.buyItem{value: TEST_PRICE}(0);

        // Expected fee amount is calculated by FeeManager (assume no discount)
        uint256 feeAmount = feeManager.calculateFee(TEST_PRICE, 0);
        // Ensure contract balance includes at least the fee
        uint256 contractBalance = address(marketplace).balance;
        assertGe(contractBalance, feeAmount);

        // Capture admin's balance before withdrawal
        uint256 adminBalanceBefore = admin.balance;

        // Admin withdraws the fee amount
        vm.prank(admin);
        marketplace.withdrawFunds(feeAmount);

        // Check that admin's balance increased by at least the withdrawn amount
        uint256 adminBalanceAfter = admin.balance;
        assertGe(adminBalanceAfter, adminBalanceBefore + feeAmount);
    }

    function testWitdrawSellerFunds_Success() public {
        // Grant seller the VERIFIED_ROLE.
        vm.startPrank(admin);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), buyer);
        vm.stopPrank();

        // Seller lists an NFT
        vm.startPrank(seller);
        mintedTokenId = token.mint(seller);
        token.approve(address(marketplace), mintedTokenId);
        marketplace.listItem(address(token), mintedTokenId, TEST_PRICE);
        vm.stopPrank();

        // Buyer purchases the NFT
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        marketplace.buyItem{value: TEST_PRICE}(0);

        // Calculate expected seller funds (sale price minus fee)
        uint256 feeAmount = feeManager.calculateFee(TEST_PRICE, 0);
        uint256 expectedSellerFunds = TEST_PRICE - feeAmount;
        uint256 sellerFunds = marketplace.getSellerWithdrawAmount(seller);
        assertEq(sellerFunds, expectedSellerFunds);

        // Seller withdraws funds
        vm.prank(seller);
        marketplace.witdrawSellerFunds(seller, expectedSellerFunds);
        // After withdrawal, seller's withdrawable funds should be zero
        sellerFunds = marketplace.getSellerWithdrawAmount(seller);
        assertEq(sellerFunds, 0);
    }

    function testBurnBadge() public {
        // Admin mints a badge (for example, using mintGold)
        vm.startPrank(admin);
        marketplace._issueGoldBadge(admin);
        // Check that the badge exists: ownerOf(0) should be admin.
        assertEq(itemToken.ownerOf(0), admin);
        // Admin burns the badge via Marketplace
        marketplace.burnBadge(0);

        // After burning, calling ownerOf(1) should revert.
        vm.expectRevert();
        itemToken.ownerOf(0);
    }

    function testListItemRevertsIfNotOwner() public {
        // Grant seller the VERIFIED_ROLE.
        vm.startPrank(admin);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);

        // Mint an NFT to seller.
        mintedTokenId = token.mint(seller);
        vm.stopPrank();

        // Attempt to list the NFT from buyer (who is not the owner)
        vm.prank(buyer);
        vm.deal(buyer, 0.5 ether); // less than TEST_PRICE
        vm.expectRevert("Marketplace: caller is not a verified user");
        marketplace.listItem(address(token), mintedTokenId, TEST_PRICE);
    }

    function testBuyItemRevertsInsufficientFunds() public {
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

        // Buyer with insufficient funds attempts to purchase.
        vm.deal(buyer, 0.5 ether); // less than TEST_PRICE
        vm.prank(buyer);
        vm.expectRevert("Insufficient funds");
        marketplace.buyItem{value: 0.5 ether}(0);
    }

    /* ========== DIFFERENTIAL TESTING ========== */
    function testDifferentialListing() public {
        vm.startPrank(admin);
        Marketplace original = new Marketplace();
        MarketplaceV2opt optimized = new MarketplaceV2opt();

        // Grant roles on both contracts
        MPRoles mpRolesOrig = MPRoles(original.getRolesContractAddress());
        mpRolesOrig.grantRole(mpRolesOrig.VERIFIED_ROLE(), seller);
        MPRoles mpRolesOpt = MPRoles(optimized.getRolesContractAddress());
        mpRolesOpt.grantRole(mpRolesOpt.VERIFIED_ROLE(), seller);

        vm.stopPrank();

        // Mint and approve an NFT for the seller externally.
        {
            vm.startPrank(seller);
            uint256 t1id = token.mint(seller);
            token.approve(address(original), t1id);
            uint256 t2id = token.mint(seller);
            token.approve(address(optimized), t2id);

            // List the NFT on both contracts with the same parameters.
            // For simplicity, assume tokenAddress is the same for both contracts.
            address tokenAddress = address(token);
            original.listItem(tokenAddress, t1id, TEST_PRICE);
            optimized.listItem(tokenAddress, t2id, TEST_PRICE);
            vm.stopPrank();
        }

        // Retrieve listing from both and compare.
        (
            uint256 listingIdOrig,
            address sellerOrig,
            address tokenAddrOrig,
            uint256 tokenIdOrig,
            uint256 priceOrig,
            bool isSoldOrig
        ) = original.listings(0);

        (
            uint256 listingIdOpt,
            address sellerOpt,
            address tokenAddrOpt,
            uint256 tokenIdOpt,
            uint256 priceOpt,
            bool isSoldOpt
        ) = optimized.listings(0);

        assertEq(listingIdOrig, listingIdOpt);
        assertEq(sellerOrig, sellerOpt);
        assertEq(tokenAddrOrig, tokenAddrOpt);
        //assertEq(tokenIdOrig, tokenIdOpt); when we use same token, id's cannot be the same
        assertEq(priceOrig, priceOpt);
        assertEq(isSoldOrig, isSoldOpt);
    }

    /* ========== FUZZ TESTING ========== */

    /// @notice Fuzz test for listing an NFT with a variable price.
    function testFuzzListItem(uint256 price) public {
        // Fuzz price should be non-zero; if zero, we expect a revert.
        vm.startPrank(admin);
        mpRoles.grantRole(mpRoles.VERIFIED_ROLE(), seller);
        vm.stopPrank();

        vm.startPrank(seller);
        mintedTokenId = token.mint(seller);
        token.approve(address(marketplace), mintedTokenId);
        if (price == 0) {
            vm.expectRevert("Price must be greater than zero");
            marketplace.listItem(address(token), mintedTokenId, price);
        } else {
            marketplace.listItem(address(token), mintedTokenId, price);
            (
                uint256 listingId,
                ,
                ,
                uint256 tokenIdListed,
                uint256 listedPrice,
                bool isSold
            ) = marketplace.listings(0);
            assertEq(listingId, 0);
            assertEq(tokenIdListed, mintedTokenId);
            assertEq(listedPrice, price);
            assertFalse(isSold);
        }
        vm.stopPrank();
    }
}
