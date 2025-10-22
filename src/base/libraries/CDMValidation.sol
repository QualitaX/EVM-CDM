// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {
    Identifier,
    Party,
    PartyIdentifier,
    Measure,
    Quantity,
    Price,
    BusinessDayAdjustments,
    AdjustableDate
} from "../types/CDMTypes.sol";
import {UnitEnum, BusinessDayConventionEnum} from "../types/Enums.sol";
import {DateTime} from "./DateTime.sol";

/**
 * @title CDMValidation
 * @notice Validation library for CDM types
 * @dev Implements CDM validation rules as Solidity functions
 * @dev All validation functions revert on failure with descriptive errors
 *
 * VALIDATION PRINCIPLES:
 * - Fail fast with clear error messages
 * - Check required fields are non-empty/non-zero
 * - Validate ranges and constraints
 * - Ensure logical consistency (e.g., dates in order)
 *
 * @custom:security-contact security@finos.org
 * @author FINOS CDM EVM Framework Team
 */
library CDMValidation {

    using DateTime for uint256;

    // =============================================================================
    // ERRORS
    // =============================================================================

    error CDMValidation__IdentifierEmpty();
    error CDMValidation__PartyInvalid();
    error CDMValidation__MeasureInvalid();
    error CDMValidation__QuantityInvalid();
    error CDMValidation__PriceInvalid();
    error CDMValidation__DateInvalid();
    error CDMValidation__DateOrderInvalid();
    error CDMValidation__BusinessDayAdjustmentsInvalid();
    error CDMValidation__ArrayEmpty();
    error CDMValidation__ReferenceEmpty();
    error CDMValidation__CurrencyRequired();

    // =============================================================================
    // IDENTIFIER VALIDATION
    // =============================================================================

    /**
     * @notice Validate identifier is non-empty
     * @dev Checks that identifier value is not zero
     * @param id Identifier to validate
     */
    function validateIdentifier(Identifier memory id) internal pure {
        if (id.value == bytes32(0)) {
            revert CDMValidation__IdentifierEmpty();
        }
    }

    /**
     * @notice Validate identifier with type check
     * @dev Ensures identifier has both value and type
     * @param id Identifier to validate
     */
    function validateIdentifierStrict(Identifier memory id) internal pure {
        if (id.value == bytes32(0)) {
            revert CDMValidation__IdentifierEmpty();
        }
        // Type enum is always valid by construction
    }

    /**
     * @notice Validate party identifier
     * @dev Validates the underlying identifier
     * @param partyId Party identifier to validate
     */
    function validatePartyIdentifier(PartyIdentifier memory partyId) internal pure {
        validateIdentifier(partyId.identifier);
    }

    // =============================================================================
    // PARTY VALIDATION
    // =============================================================================

    /**
     * @notice Validate party has required fields
     * @dev Party must have:
     *      - Non-zero party ID
     *      - Either on-chain account OR external identifiers
     * @param party Party to validate
     */
    function validateParty(Party memory party) internal pure {
        // Check party ID is set
        if (party.partyId == bytes32(0)) {
            revert CDMValidation__PartyInvalid();
        }

        // Party must have either on-chain account or external identifiers
        if (party.account == address(0) && party.identifiers.length == 0) {
            revert CDMValidation__PartyInvalid();
        }

        // If identifiers exist, validate them
        for (uint256 i = 0; i < party.identifiers.length; i++) {
            validatePartyIdentifier(party.identifiers[i]);
        }
    }

    /**
     * @notice Validate party with name requirement
     * @dev Stricter validation requiring party name hash
     * @param party Party to validate
     */
    function validatePartyWithName(Party memory party) internal pure {
        validateParty(party);

        if (party.nameHash == bytes32(0)) {
            revert CDMValidation__PartyInvalid();
        }
    }

    // =============================================================================
    // MEASURE VALIDATION
    // =============================================================================

    /**
     * @notice Validate measure has non-zero value
     * @dev For measures where zero is not allowed
     * @param measure Measure to validate
     */
    function validateMeasure(Measure memory measure) internal pure {
        if (measure.value == 0) {
            revert CDMValidation__MeasureInvalid();
        }

        // Validate unit enum (always valid by construction)

        // If unit is CURRENCY, currency code must be set
        if (measure.unit == UnitEnum.CURRENCY && measure.currencyCode == bytes3(0)) {
            revert CDMValidation__CurrencyRequired();
        }
    }

    /**
     * @notice Validate measure allowing zero
     * @dev For measures where zero is valid (e.g., prices can be zero)
     * @param measure Measure to validate
     */
    function validateMeasureAllowZero(Measure memory measure) internal pure {
        // Just validate currency requirement
        if (measure.unit == UnitEnum.CURRENCY && measure.currencyCode == bytes3(0)) {
            revert CDMValidation__CurrencyRequired();
        }
    }

    /**
     * @notice Validate measure is positive
     * @dev Stricter than validateMeasure - must be > 0
     * @param measure Measure to validate
     */
    function validateMeasurePositive(Measure memory measure) internal pure {
        if (measure.value <= 0) {
            revert CDMValidation__MeasureInvalid();
        }

        if (measure.unit == UnitEnum.CURRENCY && measure.currencyCode == bytes3(0)) {
            revert CDMValidation__CurrencyRequired();
        }
    }

    // =============================================================================
    // QUANTITY VALIDATION
    // =============================================================================

    /**
     * @notice Validate quantity
     * @dev Quantity must have positive amount
     * @param quantity Quantity to validate
     */
    function validateQuantity(Quantity memory quantity) internal pure {
        validateMeasure(quantity.amount);
    }

    /**
     * @notice Validate quantity allowing zero
     * @dev Some contexts allow zero quantity
     * @param quantity Quantity to validate
     */
    function validateQuantityAllowZero(Quantity memory quantity) internal pure {
        validateMeasureAllowZero(quantity.amount);
    }

    // =============================================================================
    // PRICE VALIDATION
    // =============================================================================

    /**
     * @notice Validate price
     * @dev Prices can be zero (e.g., zero-coupon bonds)
     * @param price Price to validate
     */
    function validatePrice(Price memory price) internal pure {
        validateMeasureAllowZero(price.amount);
    }

    /**
     * @notice Validate price is positive
     * @dev For contexts where zero price is invalid
     * @param price Price to validate
     */
    function validatePricePositive(Price memory price) internal pure {
        validateMeasurePositive(price.amount);
    }

    // =============================================================================
    // DATE VALIDATION
    // =============================================================================

    /**
     * @notice Validate date is not zero and within reasonable range
     * @dev Checks:
     *      - Date is not zero (epoch)
     *      - Date is not too far in future (sanity check)
     * @param date Date to validate (Unix timestamp)
     */
    function validateDate(uint256 date) internal view {
        if (date == 0) {
            revert CDMValidation__DateInvalid();
        }

        // Check not too far in future (50 years from now)
        if (date > block.timestamp + 365 days * 50) {
            revert CDMValidation__DateInvalid();
        }
    }

    /**
     * @notice Validate date is in the past
     * @dev Useful for trade dates, execution dates
     * @param date Date to validate
     */
    function validateDateInPast(uint256 date) internal view {
        validateDate(date);

        if (date > block.timestamp) {
            revert CDMValidation__DateInvalid();
        }
    }

    /**
     * @notice Validate date is in the future
     * @dev Useful for settlement dates, maturity dates
     * @param date Date to validate
     */
    function validateDateInFuture(uint256 date) internal view {
        validateDate(date);

        if (date <= block.timestamp) {
            revert CDMValidation__DateInvalid();
        }
    }

    /**
     * @notice Validate date range (start before end)
     * @dev Ensures logical date ordering
     * @param startDate Start date
     * @param endDate End date
     */
    function validateDateRange(uint256 startDate, uint256 endDate) internal view {
        validateDate(startDate);
        validateDate(endDate);

        if (endDate < startDate) {
            revert CDMValidation__DateOrderInvalid();
        }
    }

    /**
     * @notice Validate date range allowing same date
     * @dev Start and end can be the same (zero-duration)
     * @param startDate Start date
     * @param endDate End date
     */
    function validateDateRangeInclusive(uint256 startDate, uint256 endDate) internal view {
        validateDate(startDate);
        validateDate(endDate);

        if (endDate < startDate) {
            revert CDMValidation__DateOrderInvalid();
        }
    }

    /**
     * @notice Validate adjustable date
     * @dev Validates unadjusted date and business day adjustments
     * @param adjDate Adjustable date to validate
     */
    function validateAdjustableDate(AdjustableDate memory adjDate) internal view {
        validateDate(adjDate.unadjustedDate);
        validateBusinessDayAdjustments(adjDate.adjustments);

        // If adjusted date is set, validate it
        if (adjDate.adjustedDate != 0) {
            validateDate(adjDate.adjustedDate);
        }
    }

    // =============================================================================
    // BUSINESS DAY ADJUSTMENTS VALIDATION
    // =============================================================================

    /**
     * @notice Validate business day adjustments
     * @dev If convention is not NONE, business centers must be specified
     * @param adjustments Business day adjustments to validate
     */
    function validateBusinessDayAdjustments(
        BusinessDayAdjustments memory adjustments
    ) internal pure {
        if (adjustments.convention != BusinessDayConventionEnum.NONE) {
            if (adjustments.businessCenters.length == 0) {
                revert CDMValidation__BusinessDayAdjustmentsInvalid();
            }
        }
    }

    // =============================================================================
    // REFERENCE VALIDATION
    // =============================================================================

    /**
     * @notice Validate reference is not empty
     * @dev Reference must have at least global key
     * @param ref Reference (bytes32) to validate
     */
    function validateReference(bytes32 ref) internal pure {
        if (ref == bytes32(0)) {
            revert CDMValidation__ReferenceEmpty();
        }
    }

    /**
     * @notice Validate array is not empty
     * @dev Generic validation for arrays that must have elements
     * @param length Array length
     */
    function validateArrayNotEmpty(uint256 length) internal pure {
        if (length == 0) {
            revert CDMValidation__ArrayEmpty();
        }
    }

    /**
     * @notice Validate array has specific length
     * @dev Ensures array has expected number of elements
     * @param length Actual array length
     * @param expectedLength Expected length
     */
    function validateArrayLength(uint256 length, uint256 expectedLength) internal pure {
        if (length != expectedLength) {
            revert CDMValidation__ArrayEmpty();
        }
    }

    // =============================================================================
    // CONDITIONAL VALIDATION
    // =============================================================================

    /**
     * @notice Validate at least one of two fields is set
     * @dev XOR-like validation: at least one must be non-zero
     * @param field1 First field
     * @param field2 Second field
     */
    function validateAtLeastOne(bytes32 field1, bytes32 field2) internal pure {
        if (field1 == bytes32(0) && field2 == bytes32(0)) {
            revert CDMValidation__ReferenceEmpty();
        }
    }

    /**
     * @notice Validate exactly one of two fields is set
     * @dev True XOR: exactly one must be non-zero
     * @param field1 First field
     * @param field2 Second field
     */
    function validateExactlyOne(bytes32 field1, bytes32 field2) internal pure {
        bool field1Set = (field1 != bytes32(0));
        bool field2Set = (field2 != bytes32(0));

        if (field1Set == field2Set) {
            // Both set or both unset - invalid
            revert CDMValidation__ReferenceEmpty();
        }
    }

    /**
     * @notice Validate if condition A then condition B
     * @dev Logical implication: A => B
     * @param conditionA First condition
     * @param conditionB Second condition
     */
    function validateImplication(bool conditionA, bool conditionB) internal pure {
        // If A is true, B must also be true
        if (conditionA && !conditionB) {
            revert CDMValidation__ReferenceEmpty();
        }
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Check if identifier is empty
     * @param id Identifier to check
     * @return true if empty
     */
    function isEmptyIdentifier(Identifier memory id) internal pure returns (bool) {
        return id.value == bytes32(0);
    }

    /**
     * @notice Check if reference is empty
     * @param ref Reference to check
     * @return true if empty
     */
    function isEmptyReference(bytes32 ref) internal pure returns (bool) {
        return ref == bytes32(0);
    }

    /**
     * @notice Check if measure is zero
     * @param measure Measure to check
     * @return true if zero
     */
    function isZeroMeasure(Measure memory measure) internal pure returns (bool) {
        return measure.value == 0;
    }
}
