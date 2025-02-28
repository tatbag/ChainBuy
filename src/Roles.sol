// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Imports
import "@openzeppelin/contracts/access/AccessControl.sol";
import "forge-std/console.sol";

contract MPRoles is AccessControl {
    /* ========== STATE VARIABLES ========== */
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VERIFIED_ROLE = keccak256("VERIFIED_ROLE"); //users need to go through KYC so sell/buy

    /* ========== CONSTRUCTOR ========== */
    constructor(address _admin) {
        // Grant the contract deployer the default admin role and admin role
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(VERIFIED_ROLE, _admin);
        _setRoleAdmin(VERIFIED_ROLE, ADMIN_ROLE);
    }

    function grantRole(
        bytes32 role,
        address account
    ) public override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /* ========== EXTERNAL / PUBLIC FUNCTIONS ========== */
    // Functions to manage roles here if needed.
}
