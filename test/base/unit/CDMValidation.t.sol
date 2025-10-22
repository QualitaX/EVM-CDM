// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {CDMValidation} from "../../../src/base/libraries/CDMValidation.sol";
import {
    Identifier,
    PartyIdentifier,
    Party,
    Measure,
    Quantity,
    Price,
    AdjustableDate,
    BusinessDayAdjustments
} from "../../../src/base/types/CDMTypes.sol";
import {
    IdentifierTypeEnum,
    PartyIdentifierTypeEnum,
    PartyTypeEnum,
    UnitEnum,
    BusinessDayConventionEnum,
    QuantityTypeEnum,
    PriceTypeEnum,
    ArithmeticOperatorEnum
} from "../../../src/base/types/Enums.sol";

/**
 * @title CDMValidationTest
 * @notice Unit tests for CDMValidation library
 * @dev Tests all validation functions with valid and invalid inputs
 */
contract CDMValidationTest is Test {

    // =============================================================================
    // EXTERNAL WRAPPERS (for testing reverts)
    // =============================================================================

    function externalValidateIdentifier(Identifier memory id) external pure {
        CDMValidation.validateIdentifier(id);
    }

    function externalValidatePartyIdentifier(PartyIdentifier memory partyId) external pure {
        CDMValidation.validatePartyIdentifier(partyId);
    }

    function externalValidateParty(Party memory party) external pure {
        CDMValidation.validateParty(party);
    }

    function externalValidatePartyWithName(Party memory party) external pure {
        CDMValidation.validatePartyWithName(party);
    }

    function externalValidateMeasure(Measure memory measure) external pure {
        CDMValidation.validateMeasure(measure);
    }

    function externalValidateMeasurePositive(Measure memory measure) external pure {
        CDMValidation.validateMeasurePositive(measure);
    }

    function externalValidateQuantity(Quantity memory quantity) external pure {
        CDMValidation.validateQuantity(quantity);
    }

    function externalValidatePrice(Price memory price) external pure {
        CDMValidation.validatePrice(price);
    }

    function externalValidatePricePositive(Price memory price) external pure {
        CDMValidation.validatePricePositive(price);
    }

    function externalValidateDate(uint256 date) external view {
        CDMValidation.validateDate(date);
    }

    function externalValidateDateInPast(uint256 date) external view {
        CDMValidation.validateDateInPast(date);
    }

    function externalValidateDateInFuture(uint256 date) external view {
        CDMValidation.validateDateInFuture(date);
    }

    function externalValidateDateRange(uint256 startDate, uint256 endDate) external view {
        CDMValidation.validateDateRange(startDate, endDate);
    }

    function externalValidateReference(bytes32 ref) external pure {
        CDMValidation.validateReference(ref);
    }

    function externalValidateArrayNotEmpty(uint256 length) external pure {
        CDMValidation.validateArrayNotEmpty(length);
    }

    function externalValidateArrayLength(uint256 actual, uint256 expected) external pure {
        CDMValidation.validateArrayLength(actual, expected);
    }

    function externalValidateAtLeastOne(bytes32 field1, bytes32 field2) external pure {
        CDMValidation.validateAtLeastOne(field1, field2);
    }

    function externalValidateExactlyOne(bytes32 field1, bytes32 field2) external pure {
        CDMValidation.validateExactlyOne(field1, field2);
    }

    function externalValidateImplication(bool conditionA, bool conditionB) external pure {
        CDMValidation.validateImplication(conditionA, conditionB);
    }

    // =============================================================================
    // IDENTIFIER VALIDATION TESTS
    // =============================================================================

    function test_ValidateIdentifier_Valid() public pure {
        Identifier memory id = Identifier({
            value: keccak256("TEST123"),
            identifierType: IdentifierTypeEnum.ISIN,
            issuerScheme: bytes32(0)
        });

        CDMValidation.validateIdentifier(id);
        // Should not revert
    }

    function test_ValidateIdentifier_Empty() public {
        Identifier memory id = Identifier({
            value: bytes32(0),
            identifierType: IdentifierTypeEnum.ISIN,
            issuerScheme: bytes32(0)
        });

        try this.externalValidateIdentifier(id) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__IdentifierEmpty.selector, "Wrong error");
        }
    }

    // =============================================================================
    // PARTY IDENTIFIER VALIDATION TESTS
    // =============================================================================

    function test_ValidatePartyIdentifier_Valid() public pure {
        PartyIdentifier memory partyId = PartyIdentifier({
            identifier: Identifier({
                value: keccak256("LEI123"),
                identifierType: IdentifierTypeEnum.LEI,
                issuerScheme: bytes32(0)
            }),
            partyIdType: PartyIdentifierTypeEnum.LEI
        });

        CDMValidation.validatePartyIdentifier(partyId);
        // Should not revert
    }

    function test_ValidatePartyIdentifier_EmptyIdentifier() public {
        PartyIdentifier memory partyId = PartyIdentifier({
            identifier: Identifier({
                value: bytes32(0),
                identifierType: IdentifierTypeEnum.LEI,
                issuerScheme: bytes32(0)
            }),
            partyIdType: PartyIdentifierTypeEnum.LEI
        });

        try this.externalValidatePartyIdentifier(partyId) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__IdentifierEmpty.selector, "Wrong error");
        }
    }

    // =============================================================================
    // PARTY VALIDATION TESTS
    // =============================================================================

    function test_ValidateParty_Valid() public pure {
        PartyIdentifier[] memory identifiers = new PartyIdentifier[](1);
        identifiers[0] = PartyIdentifier({
            identifier: Identifier({
                value: keccak256("LEI123"),
                identifierType: IdentifierTypeEnum.LEI,
                issuerScheme: bytes32(0)
            }),
            partyIdType: PartyIdentifierTypeEnum.LEI
        });

        Party memory party = Party({
            partyId: keccak256("PARTY1"),
            account: address(0x123),
            partyType: PartyTypeEnum.LEGAL_ENTITY,
            nameHash: keccak256("Test Party"),
            metaKey: bytes32(0),
            identifiers: identifiers
        });

        CDMValidation.validateParty(party);
        // Should not revert
    }

    function test_ValidateParty_EmptyPartyId() public {
        PartyIdentifier[] memory identifiers = new PartyIdentifier[](0);

        Party memory party = Party({
            partyId: bytes32(0),
            account: address(0x123),
            partyType: PartyTypeEnum.LEGAL_ENTITY,
            nameHash: keccak256("Test Party"),
            metaKey: bytes32(0),
            identifiers: identifiers
        });

        try this.externalValidateParty(party) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__PartyInvalid.selector, "Wrong error");
        }
    }

    function test_ValidatePartyWithName_Valid() public pure {
        PartyIdentifier[] memory identifiers = new PartyIdentifier[](1);
        identifiers[0] = PartyIdentifier({
            identifier: Identifier({
                value: keccak256("LEI123"),
                identifierType: IdentifierTypeEnum.LEI,
                issuerScheme: bytes32(0)
            }),
            partyIdType: PartyIdentifierTypeEnum.LEI
        });

        Party memory party = Party({
            partyId: keccak256("PARTY1"),
            account: address(0x123),
            partyType: PartyTypeEnum.LEGAL_ENTITY,
            nameHash: keccak256("Test Party"),
            metaKey: bytes32(0),
            identifiers: identifiers
        });

        CDMValidation.validatePartyWithName(party);
        // Should not revert
    }

    function test_ValidatePartyWithName_EmptyName() public {
        PartyIdentifier[] memory identifiers = new PartyIdentifier[](1);
        identifiers[0] = PartyIdentifier({
            identifier: Identifier({
                value: keccak256("LEI123"),
                identifierType: IdentifierTypeEnum.LEI,
                issuerScheme: bytes32(0)
            }),
            partyIdType: PartyIdentifierTypeEnum.LEI
        });

        Party memory party = Party({
            partyId: keccak256("PARTY1"),
            account: address(0x123),
            partyType: PartyTypeEnum.LEGAL_ENTITY,
            nameHash: bytes32(0), // Empty name
            metaKey: bytes32(0),
            identifiers: identifiers
        });

        try this.externalValidatePartyWithName(party) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__PartyInvalid.selector, "Wrong error");
        }
    }

    // =============================================================================
    // MEASURE VALIDATION TESTS
    // =============================================================================

    function test_ValidateMeasure_Valid() public pure {
        Measure memory measure = Measure({
            value: 1000e18,
            unit: UnitEnum.CURRENCY,
            currencyCode: bytes3("USD")
        });

        CDMValidation.validateMeasure(measure);
        // Should not revert
    }

    function test_ValidateMeasure_ZeroValue() public {
        Measure memory measure = Measure({
            value: 0,
            unit: UnitEnum.CURRENCY,
            currencyCode: bytes3("USD")
        });

        try this.externalValidateMeasure(measure) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__MeasureInvalid.selector, "Wrong error");
        }
    }

    function test_ValidateMeasure_NoCurrencyCode() public {
        Measure memory measure = Measure({
            value: 1000e18,
            unit: UnitEnum.CURRENCY,
            currencyCode: bytes3(0)
        });

        try this.externalValidateMeasure(measure) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__CurrencyRequired.selector, "Wrong error");
        }
    }

    function test_ValidateMeasurePositive_Valid() public pure {
        Measure memory measure = Measure({
            value: 1000e18,
            unit: UnitEnum.CURRENCY,
            currencyCode: bytes3("USD")
        });

        CDMValidation.validateMeasurePositive(measure);
        // Should not revert
    }

    function test_ValidateMeasurePositive_ZeroValue() public {
        Measure memory measure = Measure({
            value: 0,
            unit: UnitEnum.CURRENCY,
            currencyCode: bytes3("USD")
        });

        try this.externalValidateMeasurePositive(measure) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__MeasureInvalid.selector, "Wrong error");
        }
    }

    // =============================================================================
    // QUANTITY VALIDATION TESTS
    // =============================================================================

    function test_ValidateQuantity_Valid() public pure {
        Quantity memory quantity = Quantity({
            amount: Measure({
                value: 1000e18,
                unit: UnitEnum.SHARES,
                currencyCode: bytes3(0)
            }),
            quantityType: QuantityTypeEnum.NOTIONAL
        });

        CDMValidation.validateQuantity(quantity);
        // Should not revert
    }

    function test_ValidateQuantity_ZeroAmount() public {
        Quantity memory quantity = Quantity({
            amount: Measure({
                value: 0,
                unit: UnitEnum.SHARES,
                currencyCode: bytes3(0)
            }),
            quantityType: QuantityTypeEnum.NOTIONAL
        });

        try this.externalValidateQuantity(quantity) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__MeasureInvalid.selector, "Wrong error");
        }
    }

    // =============================================================================
    // PRICE VALIDATION TESTS
    // =============================================================================

    function test_ValidatePrice_Valid() public pure {
        Price memory price = Price({
            amount: Measure({
                value: 100e18,
                unit: UnitEnum.CURRENCY,
                currencyCode: bytes3("USD")
            }),
            priceType: PriceTypeEnum.ASSET_PRICE,
            operator: ArithmeticOperatorEnum.ADD
        });

        CDMValidation.validatePrice(price);
        // Should not revert
    }

    function test_ValidatePricePositive_Valid() public pure {
        Price memory price = Price({
            amount: Measure({
                value: 100e18,
                unit: UnitEnum.CURRENCY,
                currencyCode: bytes3("USD")
            }),
            priceType: PriceTypeEnum.ASSET_PRICE,
            operator: ArithmeticOperatorEnum.ADD
        });

        CDMValidation.validatePricePositive(price);
        // Should not revert
    }

    function test_ValidatePricePositive_ZeroPrice() public {
        Price memory price = Price({
            amount: Measure({
                value: 0,
                unit: UnitEnum.CURRENCY,
                currencyCode: bytes3("USD")
            }),
            priceType: PriceTypeEnum.ASSET_PRICE,
            operator: ArithmeticOperatorEnum.ADD
        });

        try this.externalValidatePricePositive(price) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__MeasureInvalid.selector, "Wrong error");
        }
    }

    // =============================================================================
    // DATE VALIDATION TESTS
    // =============================================================================

    function test_ValidateDate_Valid() public {
        uint256 validDate = block.timestamp + 1 days;
        CDMValidation.validateDate(validDate);
        // Should not revert
    }

    function test_ValidateDate_Zero() public {
        try this.externalValidateDate(0) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__DateInvalid.selector, "Wrong error");
        }
    }

    function test_ValidateDateInPast_Valid() public {
        vm.warp(1704067200); // Jan 1, 2024
        uint256 pastDate = block.timestamp - 1 days;
        CDMValidation.validateDateInPast(pastDate);
        // Should not revert
    }

    function test_ValidateDateInPast_FutureDate() public {
        uint256 futureDate = block.timestamp + 1 days;

        try this.externalValidateDateInPast(futureDate) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__DateInvalid.selector, "Wrong error");
        }
    }

    function test_ValidateDateInFuture_Valid() public {
        uint256 futureDate = block.timestamp + 1 days;
        CDMValidation.validateDateInFuture(futureDate);
        // Should not revert
    }

    function test_ValidateDateInFuture_PastDate() public {
        vm.warp(1704067200); // Jan 1, 2024
        uint256 pastDate = block.timestamp - 1 days;

        try this.externalValidateDateInFuture(pastDate) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__DateInvalid.selector, "Wrong error");
        }
    }

    function test_ValidateDateRange_Valid() public {
        uint256 startDate = block.timestamp + 1 days;
        uint256 endDate = block.timestamp + 30 days;

        CDMValidation.validateDateRange(startDate, endDate);
        // Should not revert
    }

    function test_ValidateDateRange_InvalidOrder() public {
        uint256 startDate = block.timestamp + 30 days;
        uint256 endDate = block.timestamp + 1 days;

        try this.externalValidateDateRange(startDate, endDate) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__DateOrderInvalid.selector, "Wrong error");
        }
    }

    function test_ValidateDateRange_SameDate() public {
        uint256 date = block.timestamp + 1 days;

        // Same date should pass (inclusive range)
        CDMValidation.validateDateRangeInclusive(date, date);
        // Should not revert
    }

    // =============================================================================
    // REFERENCE VALIDATION TESTS
    // =============================================================================

    function test_ValidateReference_Valid() public pure {
        bytes32 ref = keccak256("REFERENCE");
        CDMValidation.validateReference(ref);
        // Should not revert
    }

    function test_ValidateReference_Empty() public {
        try this.externalValidateReference(bytes32(0)) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__ReferenceEmpty.selector, "Wrong error");
        }
    }

    // =============================================================================
    // ARRAY VALIDATION TESTS
    // =============================================================================

    function test_ValidateArrayNotEmpty_Valid() public pure {
        CDMValidation.validateArrayNotEmpty(5);
        // Should not revert
    }

    function test_ValidateArrayNotEmpty_Empty() public {
        try this.externalValidateArrayNotEmpty(0) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__ArrayEmpty.selector, "Wrong error");
        }
    }

    function test_ValidateArrayLength_Valid() public pure {
        CDMValidation.validateArrayLength(5, 5);
        // Should not revert
    }

    function test_ValidateArrayLength_Mismatch() public {
        // Should revert but uses same error as array empty
        try this.externalValidateArrayLength(5, 10) {
            fail("Expected revert");
        } catch {
            // Expected to revert
        }
    }

    // =============================================================================
    // CONDITIONAL VALIDATION TESTS
    // =============================================================================

    function test_ValidateAtLeastOne_BothSet() public pure {
        bytes32 field1 = keccak256("FIELD1");
        bytes32 field2 = keccak256("FIELD2");

        CDMValidation.validateAtLeastOne(field1, field2);
        // Should not revert
    }

    function test_ValidateAtLeastOne_OneSet() public pure {
        bytes32 field1 = keccak256("FIELD1");
        bytes32 field2 = bytes32(0);

        CDMValidation.validateAtLeastOne(field1, field2);
        // Should not revert
    }

    function test_ValidateAtLeastOne_NoneSet() public {
        bytes32 field1 = bytes32(0);
        bytes32 field2 = bytes32(0);

        try this.externalValidateAtLeastOne(field1, field2) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__ReferenceEmpty.selector, "Wrong error");
        }
    }

    function test_ValidateExactlyOne_OnlyField1() public pure {
        bytes32 field1 = keccak256("FIELD1");
        bytes32 field2 = bytes32(0);

        CDMValidation.validateExactlyOne(field1, field2);
        // Should not revert
    }

    function test_ValidateExactlyOne_OnlyField2() public pure {
        bytes32 field1 = bytes32(0);
        bytes32 field2 = keccak256("FIELD2");

        CDMValidation.validateExactlyOne(field1, field2);
        // Should not revert
    }

    function test_ValidateExactlyOne_BothSet() public {
        bytes32 field1 = keccak256("FIELD1");
        bytes32 field2 = keccak256("FIELD2");

        try this.externalValidateExactlyOne(field1, field2) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__ReferenceEmpty.selector, "Wrong error");
        }
    }

    function test_ValidateExactlyOne_NoneSet() public {
        bytes32 field1 = bytes32(0);
        bytes32 field2 = bytes32(0);

        try this.externalValidateExactlyOne(field1, field2) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__ReferenceEmpty.selector, "Wrong error");
        }
    }

    function test_ValidateImplication_Valid() public pure {
        // A=false, B=false: Valid (A implies B is vacuously true)
        CDMValidation.validateImplication(false, false);

        // A=false, B=true: Valid
        CDMValidation.validateImplication(false, true);

        // A=true, B=true: Valid (A implies B is satisfied)
        CDMValidation.validateImplication(true, true);
        // Should not revert
    }

    function test_ValidateImplication_Invalid() public {
        // A=true, B=false: Invalid (A is true but B is not)
        try this.externalValidateImplication(true, false) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CDMValidation.CDMValidation__ReferenceEmpty.selector, "Wrong error");
        }
    }

    // =============================================================================
    // REAL-WORLD SCENARIO TESTS
    // =============================================================================

    function test_RealWorld_ValidTrade() public pure {
        // Valid party
        PartyIdentifier[] memory identifiers = new PartyIdentifier[](1);
        identifiers[0] = PartyIdentifier({
            identifier: Identifier({
                value: keccak256("LEI_COUNTERPARTY"),
                identifierType: IdentifierTypeEnum.LEI,
                issuerScheme: bytes32(0)
            }),
            partyIdType: PartyIdentifierTypeEnum.LEI
        });

        Party memory counterparty = Party({
            partyId: keccak256("COUNTERPARTY1"),
            account: address(0x123),
            partyType: PartyTypeEnum.LEGAL_ENTITY,
            nameHash: keccak256("Test Counterparty"),
            metaKey: bytes32(0),
            identifiers: identifiers
        });

        // Valid quantity
        Quantity memory quantity = Quantity({
            amount: Measure({
                value: 1000e18,
                unit: UnitEnum.SHARES,
                currencyCode: bytes3(0)
            }),
            quantityType: QuantityTypeEnum.NOTIONAL
        });

        // Valid price
        Price memory price = Price({
            amount: Measure({
                value: 100e18,
                unit: UnitEnum.CURRENCY,
                currencyCode: bytes3("USD")
            }),
            priceType: PriceTypeEnum.ASSET_PRICE,
            operator: ArithmeticOperatorEnum.ADD
        });

        // All validations should pass
        CDMValidation.validateParty(counterparty);
        CDMValidation.validateQuantity(quantity);
        CDMValidation.validatePricePositive(price);
    }

    function test_RealWorld_SwapWithDates() public {
        uint256 effectiveDate = block.timestamp + 1 days;
        uint256 terminationDate = block.timestamp + 365 days;

        CDMValidation.validateDateRange(effectiveDate, terminationDate);
        CDMValidation.validateDateInFuture(effectiveDate);
        // Should not revert
    }

    // =============================================================================
    // EDGE CASE TESTS
    // =============================================================================

    function test_EdgeCase_MaximumValues() public pure {
        Measure memory measure = Measure({
            value: type(uint256).max,
            unit: UnitEnum.SHARES,
            currencyCode: bytes3(0)
        });

        CDMValidation.validateMeasure(measure);
        // Should not revert
    }

    function test_EdgeCase_MinimumPositiveValue() public pure {
        Measure memory measure = Measure({
            value: 1,
            unit: UnitEnum.SHARES,
            currencyCode: bytes3(0)
        });

        CDMValidation.validateMeasurePositive(measure);
        // Should not revert
    }

    function test_EdgeCase_CurrentTimestamp() public {
        // Current timestamp should pass validateDate
        CDMValidation.validateDate(block.timestamp);
        // Should not revert
    }
}
