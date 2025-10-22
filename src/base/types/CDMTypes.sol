// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    IdentifierTypeEnum,
    AssignedIdentifierTypeEnum,
    PartyIdentifierTypeEnum,
    ProductIdSourceEnum,
    PartyTypeEnum,
    PartyRoleEnum,
    AccountTypeEnum,
    UnitEnum,
    QuantityTypeEnum,
    PriceTypeEnum,
    ArithmeticOperatorEnum,
    RoundingDirectionEnum,
    RoundingModeEnum,
    BusinessDayConventionEnum,
    DayCountFractionEnum,
    BusinessCenterEnum,
    PeriodEnum,
    TaxonomySourceEnum,
    ClosedStateEnum,
    PositionStatusEnum
} from "./Enums.sol";

/**
 * @title CDMTypes
 * @notice Core type definitions for FINOS CDM on EVM
 * @dev Maps cdm.base.* Rosetta types to Solidity structs
 * @dev All types use gas-optimized field ordering and packing where possible
 *
 * IMPORTANT: Types are designed to be immutable once created
 * - This aligns with CDM's immutability principle
 * - State transitions create new instances rather than modifying existing
 *
 * @custom:security-contact security@finos.org
 * @author FINOS CDM EVM Framework Team
 */

// =============================================================================
// IDENTIFIER TYPES
// =============================================================================

/// @notice Generic identifier with type classification
/// @dev Corresponds to cdm.base.staticdata.identifier.AssignedIdentifier
/// @dev Storage: 3 slots (32 + 32 + 32 bytes)
struct Identifier {
    bytes32 value;                     // Identifier value (packed string or hash)
    IdentifierTypeEnum identifierType; // Type of identifier
    bytes32 issuerScheme;              // Optional: Issuer/scheme authority (0 if unused)
}

/// @notice Asset-specific identifier
/// @dev Corresponds to cdm.base.staticdata.asset.AssetIdentifier
/// @dev Storage: 4 slots
struct AssetIdentifier {
    Identifier identifier;                              // Base identifier
    AssignedIdentifierTypeEnum assignedIdentifierType; // Asset classification
}

/// @notice Product identifier
/// @dev Storage: 4 slots
struct ProductIdentifier {
    Identifier identifier;          // Base identifier
    ProductIdSourceEnum source;     // Product ID source/taxonomy
}

/// @notice Party identifier (LEI, BIC, etc.)
/// @dev Storage: 4 slots
struct PartyIdentifier {
    Identifier identifier;              // Base identifier
    PartyIdentifierTypeEnum partyIdType; // LEI, BIC, etc.
}

// =============================================================================
// PARTY TYPES
// =============================================================================

/// @notice Represents a party to a financial transaction
/// @dev Maps to cdm.base.staticdata.party.Party
/// @dev Storage: Variable (due to dynamic array)
/// @dev OPTIMIZATION: Pack account + partyType in single slot (20 + 1 bytes)
struct Party {
    bytes32 partyId;                // Unique party identifier (hash)
    address account;                // On-chain account address (0x0 if off-chain only)
    PartyTypeEnum partyType;        // Natural person or legal entity (packed with account)
    bytes32 nameHash;               // Hash of party name (full name stored off-chain)
    bytes32 metaKey;                // Metadata key for referencing (CDM global key)
    PartyIdentifier[] identifiers;  // External identifiers (LEI, BIC, etc.)
}

/// @notice Party role in a transaction
/// @dev Maps to cdm.base.staticdata.party.PartyRole
/// @dev Storage: 2 slots
struct PartyRole {
    bytes32 partyReference;     // Reference to Party via metaKey
    PartyRoleEnum role;         // Role classification
}

/// @notice Account information
/// @dev Storage: 4 slots
struct Account {
    bytes32 accountId;          // Account identifier
    bytes32 partyReference;     // Party owning the account
    AccountTypeEnum accountType; // Account classification
    bytes32 servicerReference;   // Account servicer/custodian reference
}

// =============================================================================
// MATHEMATICAL TYPES
// =============================================================================

/// @notice Measure with value and unit
/// @dev Maps to cdm.base.math.Measure
/// @dev All decimal values use 18 decimal fixed-point (1e18 = 1.0)
/// @dev Storage: 2 slots (uint256 + enum + bytes3 = 32 + 32 bytes)
struct Measure {
    uint256 value;           // Value in fixed-point (18 decimals)
    UnitEnum unit;           // Unit of measure
    bytes3 currencyCode;     // ISO 4217 currency code (if unit == CURRENCY)
}

/// @notice Quantity representation
/// @dev Maps to cdm.base.math.Quantity
/// @dev Storage: 3 slots
struct Quantity {
    Measure amount;              // Quantity amount
    QuantityTypeEnum quantityType; // Classification
}

/// @notice Price representation
/// @dev Normalized across all asset classes per CDM design
/// @dev Storage: 3 slots
struct Price {
    Measure amount;                      // Price amount
    PriceTypeEnum priceType;             // Price classification
    ArithmeticOperatorEnum operator;     // Optional operator for rates
}

/// @notice Rounding specification
/// @dev Storage: 1 slot (1 + 1 + 1 bytes, rest unused)
struct Rounding {
    RoundingDirectionEnum direction;  // Rounding direction
    RoundingModeEnum mode;            // Rounding mode
    uint8 precision;                  // Number of decimal places (if applicable)
}

// =============================================================================
// DATE/TIME TYPES
// =============================================================================

/// @notice Business day adjustments
/// @dev Storage: Variable (due to dynamic array)
struct BusinessDayAdjustments {
    BusinessDayConventionEnum convention;           // Convention for adjustment
    BusinessCenterEnum[] businessCenters;           // Financial centers for holidays
}

/// @notice Adjustable date (date with potential business day adjustment)
/// @dev Maps to cdm.base.datetime.AdjustableDate
/// @dev Dates stored as Unix timestamps (seconds since epoch)
/// @dev Storage: Variable
struct AdjustableDate {
    uint256 unadjustedDate;                         // Unix timestamp of unadjusted date
    BusinessDayAdjustments adjustments;             // How to adjust if non-business day
    uint256 adjustedDate;                           // Cached adjusted date (0 if not calculated)
}

/// @notice Period specification (e.g., "3M" for 3 months)
/// @dev Maps to cdm.base.datetime.Period
/// @dev Storage: 1 slot (2 + 1 bytes, rest unused)
struct Period {
    uint16 periodMultiplier;  // Number of periods
    PeriodEnum period;        // Period unit
}

/// @notice Date relative to another date
/// @dev Storage: Variable
struct RelativeDate {
    uint256 baseDate;                   // Reference date (Unix timestamp)
    Period offset;                      // Offset from base date
    BusinessDayAdjustments adjustments; // Adjustment rules
}

/// @notice Calculation period dates (for scheduled payments)
/// @dev Simplified version - full CDM has more attributes
struct CalculationPeriodDates {
    AdjustableDate effectiveDate;       // Start of first calculation period
    AdjustableDate terminationDate;     // End of last calculation period
    Period calculationPeriodFrequency;  // Frequency of calculation periods
}

/// @notice Payment dates specification
struct PaymentDates {
    Period paymentFrequency;            // Frequency of payments
    BusinessDayAdjustments adjustments; // Payment date adjustments
}

// =============================================================================
// REFERENCE AND METADATA TYPES
// =============================================================================

/// @notice Reference to another object via hash
/// @dev Corresponds to ReferenceWithMeta pattern in CDM
/// @dev Storage: 3 slots
struct Reference {
    bytes32 globalKey;        // Global key of referenced object (CDM hash)
    bytes32 externalKey;      // External reference (if applicable)
    address scope;            // Scope of reference (contract address)
}

/// @notice Metadata for global key generation
/// @dev Maps to CDM metadata framework
/// @dev Storage: 2 slots
struct MetaFields {
    bytes32 globalKey;        // Global hash of object (keccak256)
    bytes32 externalKey;      // External system reference
}

/// @notice Taxonomy classification
/// @dev Maps to cdm.base.staticdata.asset.Taxonomy
/// @dev Storage: 2 slots
struct Taxonomy {
    bytes32 value;                    // Taxonomy value
    TaxonomySourceEnum source;        // Taxonomy source
}

// =============================================================================
// OBSERVABLE TYPES (Preview - full implementation in Layer 2)
// =============================================================================

/// @notice Price observation
/// @dev Will be expanded in Layer 2 (Observable)
struct Observation {
    bytes32 observationId;    // Unique observation identifier
    Price observedValue;      // Observed price
    uint256 observationDate;  // Date of observation (Unix timestamp)
}

// =============================================================================
// TRADE STATE TYPES (Preview - full implementation in Layer 4)
// =============================================================================

/// @notice State of a trade at a point in its lifecycle
/// @dev Maps to cdm.event.common.State
/// @dev Storage: 1 slot (1 + 1 bytes, rest unused)
struct State {
    ClosedStateEnum closedState;       // Closed state (if closed)
    PositionStatusEnum positionState;  // Position status
}

/// @notice Reset information for floating rates
/// @dev Maps to cdm.event.common.Reset
/// @dev Storage: Variable
struct Reset {
    bytes32 resetId;          // Unique reset identifier
    Price resetValue;         // Reset rate/price
    uint256 resetDate;        // Date from which rate applies
    uint256 rateRecordDate;   // Date rate was observed
}

/// @notice Transfer of assets between parties
/// @dev Maps to cdm.event.common.Transfer
/// @dev Storage: Variable
struct Transfer {
    bytes32 transferId;       // Unique transfer identifier
    bytes32 payerReference;   // Payer party reference
    bytes32 receiverReference; // Receiver party reference
    Quantity quantity;        // Quantity being transferred
    uint256 settlementDate;   // Settlement date
}

// =============================================================================
// EXECUTION DETAILS (Preview - full implementation in Layer 4)
// =============================================================================

/// @notice Execution type classification
enum ExecutionTypeEnum {
    ELECTRONIC,      // Electronic execution
    OFF_FACILITY,    // Off-facility (OTC)
    ON_FACILITY      // On-facility (exchange)
}

/// @notice Execution details for a trade
/// @dev Maps to cdm.event.common.ExecutionDetails
struct ExecutionDetails {
    ExecutionTypeEnum executionType;  // Type of execution
    bytes32 executionVenueReference;  // Reference to execution venue
    bytes32 packageReference;         // Package reference (if part of package)
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * @title CDMTypeHelpers
 * @notice Helper functions for working with CDM types
 * @dev Pure functions for type manipulation
 */
library CDMTypeHelpers {

    /**
     * @notice Create an empty Identifier
     * @return Empty identifier struct
     */
    function emptyIdentifier() internal pure returns (Identifier memory) {
        return Identifier({
            value: bytes32(0),
            identifierType: IdentifierTypeEnum.INTERNAL,
            issuerScheme: bytes32(0)
        });
    }

    /**
     * @notice Check if identifier is empty
     * @param id Identifier to check
     * @return true if empty
     */
    function isEmptyIdentifier(Identifier memory id) internal pure returns (bool) {
        return id.value == bytes32(0);
    }

    /**
     * @notice Create a simple identifier from bytes32
     * @param value Identifier value
     * @param idType Identifier type
     * @return Identifier struct
     */
    function createIdentifier(
        bytes32 value,
        IdentifierTypeEnum idType
    ) internal pure returns (Identifier memory) {
        return Identifier({
            value: value,
            identifierType: idType,
            issuerScheme: bytes32(0)
        });
    }

    /**
     * @notice Create a measure from value and unit
     * @param value Value in fixed-point (18 decimals)
     * @param unit Unit of measure
     * @return Measure struct
     */
    function createMeasure(
        uint256 value,
        UnitEnum unit
    ) internal pure returns (Measure memory) {
        return Measure({
            value: value,
            unit: unit,
            currencyCode: bytes3(0)
        });
    }

    /**
     * @notice Create a currency measure
     * @param value Value in fixed-point (18 decimals)
     * @param currency ISO 4217 currency code (e.g., "USD")
     * @return Measure struct
     */
    function createCurrencyMeasure(
        uint256 value,
        bytes3 currency
    ) internal pure returns (Measure memory) {
        return Measure({
            value: value,
            unit: UnitEnum.CURRENCY,
            currencyCode: currency
        });
    }

    /**
     * @notice Create a quantity
     * @param value Value in fixed-point
     * @param unit Unit of measure
     * @param qType Quantity type
     * @return Quantity struct
     */
    function createQuantity(
        uint256 value,
        UnitEnum unit,
        QuantityTypeEnum qType
    ) internal pure returns (Quantity memory) {
        return Quantity({
            amount: createMeasure(value, unit),
            quantityType: qType
        });
    }

    /**
     * @notice Create a price
     * @param value Value in fixed-point
     * @param unit Unit of measure
     * @param pType Price type
     * @return Price struct
     */
    function createPrice(
        uint256 value,
        UnitEnum unit,
        PriceTypeEnum pType
    ) internal pure returns (Price memory) {
        return Price({
            amount: createMeasure(value, unit),
            priceType: pType,
            operator: ArithmeticOperatorEnum.ADD
        });
    }

    /**
     * @notice Create a period
     * @param multiplier Number of periods
     * @param periodUnit Period unit
     * @return Period struct
     */
    function createPeriod(
        uint16 multiplier,
        PeriodEnum periodUnit
    ) internal pure returns (Period memory) {
        return Period({
            periodMultiplier: multiplier,
            period: periodUnit
        });
    }
}
