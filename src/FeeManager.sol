// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// Imports
import "@openzeppelin/contracts/access/Ownable.sol";
import "forge-std/console.sol";

contract FeeManager is Ownable {
    /* ========== STATE VARIABLES ========== */
    // Fee in basis points, e.g., 250 means 2.5%
    uint256 private marketplaceFee;
    uint256 private immutable revokeFee;
    address private feeRecipient;

    /* ========== EVENTS ========== */
    event FeeUpdated(uint256 newFee);
    event FeeRecipientUpdated(address newRecipient);

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address _owner,
        address _feeRecipient,
        uint256 _marketplaceFee,
        uint256 _revokefee
    ) Ownable(_owner) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        marketplaceFee = _marketplaceFee;
        revokeFee = _revokefee;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function updateMarketplaceFee(uint256 newFee) external onlyOwner {
        // Restrict fee to 10% max (1000 basis points)
        require(newFee <= 1000, "Fee cannot exceed 10%");
        marketplaceFee = newFee;
        emit FeeUpdated(newFee);
    }

    function updateFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(newRecipient);
    }

    function getRevokeFee() external view returns (uint256) {
        return revokeFee;
    }

    /* ========== VIEW FUNCTIONS ========== */
    function calculateFee(
        uint256 salePrice,
        uint256 discount
    ) external view returns (uint256) {
        return _calculateFee(salePrice, marketplaceFee, discount);
    }

    function calculateRevokeFee(
        uint256 salePrice,
        uint256 discount
    ) external view returns (uint256) {
        return _calculateFee(salePrice, revokeFee, discount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _calculateFee(
        uint256 salePrice,
        uint256 fee,
        uint256 discount
    ) internal pure returns (uint256) {
        if (discount >= fee) {
            return 0;
        }
        uint256 newFee = fee - discount;
        if (salePrice > type(uint256).max / newFee) {
            return 0;
        }
        return (salePrice * newFee) / 10000;
    }
}
