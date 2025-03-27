// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../src/FeeManager.sol";

contract FeeManagerTest is Test {
    FeeManager feeManager;
    address owner = vm.addr(1);
    address feeRecipient = vm.addr(2);
    // Initial fees: marketplaceFee is 250 (2.5%), revokeFee is 100 (1%).
    uint256 constant initialMarketplaceFee = 250;
    uint256 constant initialRevokeFee = 100;

    function setUp() public {
        feeManager = new FeeManager(
            owner,
            feeRecipient,
            initialMarketplaceFee,
            initialRevokeFee
        );
    }

    /// @notice Test that the initial revoke fee is set correctly.
    function testInitialRevokeFee() public {
        uint256 revFee = feeManager.getRevokeFee();
        assertEq(revFee, initialRevokeFee, "Initial revoke fee mismatch");
    }

    /// @notice Test that the marketplace fee can be updated by the owner.
    function testUpdateMarketplaceFee() public {
        uint256 newFee = 500; // 5%
        vm.prank(owner);
        feeManager.updateMarketplaceFee(newFee);

        uint256 salePrice = 1 ether;
        uint256 sale = 0;
        // Expected fee = (salePrice * newFee) / 10000
        uint256 expectedFee = (salePrice * newFee) / 10000;
        uint256 calculatedFee = feeManager.calculateFee(salePrice, sale);
        assertEq(
            calculatedFee,
            expectedFee,
            "Fee calculation mismatch after update"
        );
    }

    /// @notice Test that updating marketplace fee reverts if fee > 1000 (i.e. > 10%).
    function testUpdateMarketplaceFeeReverts() public {
        uint256 invalidFee = 1500; // 15%
        vm.prank(owner);
        vm.expectRevert("Fee cannot exceed 10%");
        feeManager.updateMarketplaceFee(invalidFee);
    }

    /// @notice Test that updateFeeRecipient works (only checking for no revert).
    function testUpdateFeeRecipient() public {
        address newRecipient = vm.addr(3);
        vm.prank(owner);
        feeManager.updateFeeRecipient(newRecipient);
        // No getter exists, so we just check that the call doesn't revert.
    }

    /// @notice Fuzz test for calculateFee with variable salePrice and sale.
    function testFuzzCalculateFee(
        uint256 salePrice,
        uint256 discount,
        uint256 fee
    ) public {
        // Restrict fee to valid range: 0 <= fee <= 1000.
        fee = (fee % 1001) + 1; //avoid 0 cases
        discount = (discount % 1001);
        salePrice = salePrice % (type(uint256).max / fee);

        vm.prank(owner);
        uint256 expected = 0;
        feeManager.updateMarketplaceFee(fee);
        if (discount < fee) {
            expected = (salePrice * (fee - discount)) / 10000;
        }
        uint256 calculated = feeManager.calculateFee(salePrice, discount);
        assertEq(calculated, expected, "Fuzz: calculated fee mismatch");
    }

    /// @notice Fuzz test for calculateRevokeFee with variable salePrice and sale.
    function testFuzzCalculateRevokeFee(
        uint256 salePrice,
        uint256 discount
    ) public {
        discount = (discount % 1001);

        vm.prank(owner);
        uint256 fee = feeManager.getRevokeFee();
        salePrice = salePrice % (type(uint256).max / fee);

        uint256 expected = 0;
        if (discount < fee) {
            expected = (salePrice * (fee - discount)) / 10000;
        }
        uint256 calculated = feeManager.calculateRevokeFee(salePrice, discount);
        assertEq(calculated, expected, "Fuzz: calculated fee mismatch");
    }
}
