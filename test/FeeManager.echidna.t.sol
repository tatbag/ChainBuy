// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../src/FeeManager.sol";

contract FeeManagerEchidnaTest is FeeManager {
    uint256 public salePrice;
    uint256 public discount;

    // Construct the FeeManager with initial fees: 250 basis points for marketplace fee and 100 for revoke fee.
    constructor() FeeManager(msg.sender, msg.sender, 250, 100) {}

    /// @notice Invariant: The fee calculated (without discount) should never exceed salePrice.
    function echidna_fee_under_salePrice() public view returns (bool) {
        // Calculate fee with discount applied.
        uint256 feeCalculated = this.calculateFee(salePrice, discount);
        return feeCalculated <= salePrice;
    }

    /// @notice Invariant: If discount >= fee with no discount, fee should be 0; otherwise, fee equals fee without discount minus discount.
    function echidna_discount_behavior() public view returns (bool) {
        uint256 feeNoDiscount = this.calculateFee(salePrice, 0);
        uint256 feeWithDiscount = this.calculateFee(salePrice, discount);
        if (discount >= feeNoDiscount) {
            return feeWithDiscount == 0;
        } else {
            return feeWithDiscount == feeNoDiscount - discount;
        }
    }

    /// @notice Invariant: The revoke fee should also never exceed the sale price.
    function echidna_revokeFee_under_salePrice() public view returns (bool) {
        uint256 revokeFeeCalculated = this.calculateRevokeFee(
            salePrice,
            discount
        );
        return revokeFeeCalculated <= salePrice;
    }
}
