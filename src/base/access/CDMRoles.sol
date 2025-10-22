// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CDMRoles
 * @notice Centralized role definitions for FINOS CDM EVM Framework
 * @dev All contracts should import roles from here for consistency
 * @dev Uses keccak256 hashing for role identifiers per OpenZeppelin standard
 *
 * ROLE HIERARCHY:
 * - ADMIN_ROLE: Super admin (can grant/revoke all roles)
 * - GOVERNANCE_ROLE: Governance operations
 * - Operational roles: Product creation, trade execution, etc.
 * - Oracle roles: Price feed management
 * - Reporting roles: Regulatory reporting
 *
 * @author QualitaX Team
 */
library CDMRoles {

    // =============================================================================
    // ADMINISTRATIVE ROLES
    // =============================================================================

    /// @notice Super admin role (can grant/revoke all roles)
    /// @dev Should be held by multi-signature wallet or DAO
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Governance role (can execute governance actions)
    /// @dev Can upgrade contracts, change parameters
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    /// @notice Pause guardian (can pause contracts in emergency)
    /// @dev Should be held by security team or automated monitoring
    bytes32 public constant PAUSE_GUARDIAN_ROLE = keccak256("PAUSE_GUARDIAN_ROLE");

    /// @notice Upgrader role (can upgrade proxy implementations)
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // =============================================================================
    // DATA MANAGEMENT ROLES
    // =============================================================================

    /// @notice Can register/update parties in registry
    bytes32 public constant PARTY_MANAGER_ROLE = keccak256("PARTY_MANAGER_ROLE");

    /// @notice Can register/update assets in registry
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

    /// @notice Can register/update indices
    bytes32 public constant INDEX_MANAGER_ROLE = keccak256("INDEX_MANAGER_ROLE");

    // =============================================================================
    // PRODUCT & TRADING ROLES
    // =============================================================================

    /// @notice Can create new products
    bytes32 public constant PRODUCT_CREATOR_ROLE = keccak256("PRODUCT_CREATOR_ROLE");

    /// @notice Can execute trades
    bytes32 public constant TRADE_EXECUTOR_ROLE = keccak256("TRADE_EXECUTOR_ROLE");

    /// @notice Can process lifecycle events
    bytes32 public constant EVENT_PROCESSOR_ROLE = keccak256("EVENT_PROCESSOR_ROLE");

    /// @notice Can settle transfers
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    /// @notice Can exercise options
    bytes32 public constant EXERCISE_ROLE = keccak256("EXERCISE_ROLE");

    // =============================================================================
    // ORACLE ROLES
    // =============================================================================

    /// @notice Can update price feeds
    bytes32 public constant ORACLE_UPDATER_ROLE = keccak256("ORACLE_UPDATER_ROLE");

    /// @notice Can register new oracles
    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    // =============================================================================
    // REPORTING & COMPLIANCE ROLES
    // =============================================================================

    /// @notice Can submit regulatory reports
    bytes32 public constant REPORTING_ROLE = keccak256("REPORTING_ROLE");

    /// @notice Can validate reports
    bytes32 public constant REPORT_VALIDATOR_ROLE = keccak256("REPORT_VALIDATOR_ROLE");

    /// @notice Can manage collateral
    bytes32 public constant COLLATERAL_MANAGER_ROLE = keccak256("COLLATERAL_MANAGER_ROLE");

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Get all defined roles
     * @return Array of all role identifiers
     * @dev Useful for initialization and documentation
     */
    function getAllRoles() internal pure returns (bytes32[] memory) {
        bytes32[] memory roles = new bytes32[](15);

        roles[0] = ADMIN_ROLE;
        roles[1] = GOVERNANCE_ROLE;
        roles[2] = PAUSE_GUARDIAN_ROLE;
        roles[3] = UPGRADER_ROLE;
        roles[4] = PARTY_MANAGER_ROLE;
        roles[5] = ASSET_MANAGER_ROLE;
        roles[6] = INDEX_MANAGER_ROLE;
        roles[7] = PRODUCT_CREATOR_ROLE;
        roles[8] = TRADE_EXECUTOR_ROLE;
        roles[9] = EVENT_PROCESSOR_ROLE;
        roles[10] = SETTLEMENT_ROLE;
        roles[11] = ORACLE_UPDATER_ROLE;
        roles[12] = ORACLE_MANAGER_ROLE;
        roles[13] = REPORTING_ROLE;
        roles[14] = COLLATERAL_MANAGER_ROLE;

        return roles;
    }

    /**
     * @notice Get role name for a given role hash
     * @param role Role identifier
     * @return Human-readable role name
     * @dev Useful for logging and UIs
     */
    function getRoleName(bytes32 role) internal pure returns (string memory) {
        if (role == ADMIN_ROLE) return "ADMIN_ROLE";
        if (role == GOVERNANCE_ROLE) return "GOVERNANCE_ROLE";
        if (role == PAUSE_GUARDIAN_ROLE) return "PAUSE_GUARDIAN_ROLE";
        if (role == UPGRADER_ROLE) return "UPGRADER_ROLE";
        if (role == PARTY_MANAGER_ROLE) return "PARTY_MANAGER_ROLE";
        if (role == ASSET_MANAGER_ROLE) return "ASSET_MANAGER_ROLE";
        if (role == INDEX_MANAGER_ROLE) return "INDEX_MANAGER_ROLE";
        if (role == PRODUCT_CREATOR_ROLE) return "PRODUCT_CREATOR_ROLE";
        if (role == TRADE_EXECUTOR_ROLE) return "TRADE_EXECUTOR_ROLE";
        if (role == EVENT_PROCESSOR_ROLE) return "EVENT_PROCESSOR_ROLE";
        if (role == SETTLEMENT_ROLE) return "SETTLEMENT_ROLE";
        if (role == ORACLE_UPDATER_ROLE) return "ORACLE_UPDATER_ROLE";
        if (role == ORACLE_MANAGER_ROLE) return "ORACLE_MANAGER_ROLE";
        if (role == REPORTING_ROLE) return "REPORTING_ROLE";
        if (role == COLLATERAL_MANAGER_ROLE) return "COLLATERAL_MANAGER_ROLE";

        return "UNKNOWN_ROLE";
    }
}
