// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DateTime} from "../../../src/base/libraries/DateTime.sol";

/**
 * @title DateTimeTest
 * @notice Unit tests for DateTime library
 * @dev Tests date parsing, arithmetic, and validation functions
 */
contract DateTimeTest is Test {

    // =============================================================================
    // EXTERNAL WRAPPERS (for testing reverts with try/catch)
    // =============================================================================

    function externalGetDaysInMonth(uint256 month, uint256 year) external pure returns (uint256) {
        return DateTime.getDaysInMonth(month, year);
    }

    function externalToTimestamp(uint256 year, uint256 month, uint256 day) external pure returns (uint256) {
        return DateTime.toTimestamp(year, month, day);
    }

    // =============================================================================
    // TEST CONSTANTS - Known Timestamps
    // =============================================================================

    // January 1, 2024, 00:00:00 UTC
    uint256 constant JAN_1_2024 = 1704067200;

    // February 29, 2024, 00:00:00 UTC (leap year)
    uint256 constant FEB_29_2024 = 1709164800;

    // December 31, 2024, 00:00:00 UTC
    uint256 constant DEC_31_2024 = 1735603200;

    // March 15, 2023, 00:00:00 UTC
    uint256 constant MAR_15_2023 = 1678838400;

    // January 1, 2000, 00:00:00 UTC (leap year)
    uint256 constant JAN_1_2000 = 946684800;

    // January 1, 1970, 00:00:00 UTC (epoch)
    uint256 constant EPOCH = 0;

    // =============================================================================
    // DATE COMPONENT TESTS
    // =============================================================================

    function test_GetYear_Epoch() public pure {
        uint256 year = DateTime.getYear(EPOCH);
        assertEq(year, 1970, "Epoch should be year 1970");
    }

    function test_GetYear_2024() public pure {
        uint256 year = DateTime.getYear(JAN_1_2024);
        assertEq(year, 2024, "Should be year 2024");
    }

    function test_GetYear_2000() public pure {
        uint256 year = DateTime.getYear(JAN_1_2000);
        assertEq(year, 2000, "Should be year 2000");
    }

    function test_GetYear_2023() public pure {
        uint256 year = DateTime.getYear(MAR_15_2023);
        assertEq(year, 2023, "Should be year 2023");
    }

    function test_GetMonth_January() public pure {
        uint256 month = DateTime.getMonth(JAN_1_2024);
        assertEq(month, 1, "Should be January (1)");
    }

    function test_GetMonth_February() public pure {
        uint256 month = DateTime.getMonth(FEB_29_2024);
        assertEq(month, 2, "Should be February (2)");
    }

    function test_GetMonth_March() public pure {
        uint256 month = DateTime.getMonth(MAR_15_2023);
        assertEq(month, 3, "Should be March (3)");
    }

    function test_GetMonth_December() public pure {
        uint256 month = DateTime.getMonth(DEC_31_2024);
        assertEq(month, 12, "Should be December (12)");
    }

    function test_GetDay_FirstOfMonth() public pure {
        uint256 day = DateTime.getDay(JAN_1_2024);
        assertEq(day, 1, "Should be day 1");
    }

    function test_GetDay_MidMonth() public pure {
        uint256 day = DateTime.getDay(MAR_15_2023);
        assertEq(day, 15, "Should be day 15");
    }

    function test_GetDay_LeapDay() public pure {
        uint256 day = DateTime.getDay(FEB_29_2024);
        assertEq(day, 29, "Should be day 29");
    }

    function test_GetDay_EndOfMonth() public pure {
        uint256 day = DateTime.getDay(DEC_31_2024);
        assertEq(day, 31, "Should be day 31");
    }

    function test_ParseDate_Jan1_2024() public pure {
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(JAN_1_2024);
        assertEq(year, 2024, "Year should be 2024");
        assertEq(month, 1, "Month should be 1");
        assertEq(day, 1, "Day should be 1");
    }

    function test_ParseDate_Feb29_2024() public pure {
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(FEB_29_2024);
        assertEq(year, 2024, "Year should be 2024");
        assertEq(month, 2, "Month should be 2");
        assertEq(day, 29, "Day should be 29");
    }

    function test_ParseDate_Mar15_2023() public pure {
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(MAR_15_2023);
        assertEq(year, 2023, "Year should be 2023");
        assertEq(month, 3, "Month should be 3");
        assertEq(day, 15, "Day should be 15");
    }

    // =============================================================================
    // LEAP YEAR TESTS
    // =============================================================================

    function test_IsLeapYear_2024() public pure {
        assertTrue(DateTime.isLeapYear(2024), "2024 should be leap year");
    }

    function test_IsLeapYear_2000() public pure {
        assertTrue(DateTime.isLeapYear(2000), "2000 should be leap year (divisible by 400)");
    }

    function test_IsLeapYear_2023_NotLeap() public pure {
        assertFalse(DateTime.isLeapYear(2023), "2023 should not be leap year");
    }

    function test_IsLeapYear_1900_NotLeap() public pure {
        assertFalse(DateTime.isLeapYear(1900), "1900 should not be leap year (divisible by 100 but not 400)");
    }

    function test_IsLeapYear_2100_NotLeap() public pure {
        assertFalse(DateTime.isLeapYear(2100), "2100 should not be leap year");
    }

    function test_GetDaysInYear_LeapYear() public pure {
        assertEq(DateTime.getDaysInYear(2024), 366, "Leap year should have 366 days");
    }

    function test_GetDaysInYear_NonLeapYear() public pure {
        assertEq(DateTime.getDaysInYear(2023), 365, "Non-leap year should have 365 days");
    }

    function test_GetDaysInMonth_January() public pure {
        assertEq(DateTime.getDaysInMonth(1, 2024), 31, "January should have 31 days");
    }

    function test_GetDaysInMonth_February_LeapYear() public pure {
        assertEq(DateTime.getDaysInMonth(2, 2024), 29, "February in leap year should have 29 days");
    }

    function test_GetDaysInMonth_February_NonLeapYear() public pure {
        assertEq(DateTime.getDaysInMonth(2, 2023), 28, "February in non-leap year should have 28 days");
    }

    function test_GetDaysInMonth_April() public pure {
        assertEq(DateTime.getDaysInMonth(4, 2024), 30, "April should have 30 days");
    }

    function test_GetDaysInMonth_December() public pure {
        assertEq(DateTime.getDaysInMonth(12, 2024), 31, "December should have 31 days");
    }

    function test_GetDaysInMonth_InvalidMonth() public {
        try this.externalGetDaysInMonth(13, 2024) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, DateTime.DateTime__InvalidMonth.selector, "Wrong error selector");
        }
    }

    // =============================================================================
    // DATE CONSTRUCTION TESTS
    // =============================================================================

    function test_GetYearStart_2024() public pure {
        uint256 timestamp = DateTime.getYearStart(2024);
        assertEq(timestamp, JAN_1_2024, "Should return Jan 1, 2024");
    }

    function test_GetYearStart_2000() public pure {
        uint256 timestamp = DateTime.getYearStart(2000);
        assertEq(timestamp, JAN_1_2000, "Should return Jan 1, 2000");
    }

    function test_GetYearStart_1970() public pure {
        uint256 timestamp = DateTime.getYearStart(1970);
        assertEq(timestamp, EPOCH, "Should return epoch");
    }

    function test_GetYearEnd_2024() public pure {
        uint256 timestamp = DateTime.getYearEnd(2024);
        // Should be one second before Jan 1, 2025
        uint256 jan1_2025 = DateTime.getYearStart(2025);
        assertEq(timestamp, jan1_2025 - 1, "Should be Dec 31, 2024 23:59:59");
    }

    function test_GetMonthStart_January() public pure {
        uint256 timestamp = DateTime.getMonthStart(2024, 1);
        assertEq(timestamp, JAN_1_2024, "Should be Jan 1, 2024");
    }

    function test_GetMonthStart_February() public pure {
        uint256 timestamp = DateTime.getMonthStart(2024, 2);
        // Jan has 31 days, so Feb 1 = Jan 1 + 31 days
        uint256 expected = JAN_1_2024 + (31 * 86400);
        assertEq(timestamp, expected, "Should be Feb 1, 2024");
    }

    function test_GetMonthStart_December() public pure {
        uint256 timestamp = DateTime.getMonthStart(2024, 12);
        // Dec 1, 2024 (not Dec 31)
        uint256 dec1_2024 = 1733011200;
        assertEq(timestamp, dec1_2024, "Should be Dec 1, 2024");
    }

    // =============================================================================
    // DATE ARITHMETIC TESTS
    // =============================================================================

    function test_DaysBetween_SameDay() public pure {
        uint256 numDays = DateTime.daysBetween(JAN_1_2024, JAN_1_2024);
        assertEq(numDays, 0, "Same day should be 0 days");
    }

    function test_DaysBetween_OneDay() public pure {
        uint256 jan2 = JAN_1_2024 + 86400;
        uint256 numDays = DateTime.daysBetween(JAN_1_2024, jan2);
        assertEq(numDays, 1, "Should be 1 day");
    }

    function test_DaysBetween_ThirtyDays() public pure {
        uint256 jan31 = JAN_1_2024 + (30 * 86400);
        uint256 numDays = DateTime.daysBetween(JAN_1_2024, jan31);
        assertEq(numDays, 30, "Should be 30 days");
    }

    function test_DaysBetween_FullYear() public pure {
        uint256 jan1_2025 = DateTime.getYearStart(2025);
        uint256 numDays = DateTime.daysBetween(JAN_1_2024, jan1_2025);
        assertEq(numDays, 366, "2024 is leap year, should be 366 days");
    }

    function test_AddDays_OneDay() public pure {
        uint256 result = DateTime.addDays(JAN_1_2024, 1);
        uint256 expected = JAN_1_2024 + 86400;
        assertEq(result, expected, "Should add 1 day");
    }

    function test_AddDays_ThirtyDays() public pure {
        uint256 result = DateTime.addDays(JAN_1_2024, 30);
        uint256 expected = JAN_1_2024 + (30 * 86400);
        assertEq(result, expected, "Should add 30 days");
    }

    function test_AddDays_ZeroDays() public pure {
        uint256 result = DateTime.addDays(JAN_1_2024, 0);
        assertEq(result, JAN_1_2024, "Adding 0 days should return same date");
    }

    function test_AddMonths_OneMonth() public pure {
        uint256 result = DateTime.addMonths(JAN_1_2024, 1);
        // Should be Feb 1, 2024
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year should be 2024");
        assertEq(month, 2, "Month should be February");
        assertEq(day, 1, "Day should be 1");
    }

    function test_AddMonths_TwelveMonths() public pure {
        uint256 result = DateTime.addMonths(JAN_1_2024, 12);
        // Should be Jan 1, 2025
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2025, "Year should be 2025");
        assertEq(month, 1, "Month should be January");
        assertEq(day, 1, "Day should be 1");
    }

    function test_AddMonths_CrossYearBoundary() public pure {
        // Dec 15, 2023 + 2 months = Feb 15, 2024
        uint256 dec15_2023 = DateTime.toTimestamp(2023, 12, 15);
        uint256 result = DateTime.addMonths(dec15_2023, 2);

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year should be 2024");
        assertEq(month, 2, "Month should be February");
        assertEq(day, 15, "Day should be 15");
    }

    function test_AddMonths_DayAdjustment() public pure {
        // Jan 31 + 1 month should be Feb 29 (2024 is leap year)
        uint256 jan31_2024 = DateTime.toTimestamp(2024, 1, 31);
        uint256 result = DateTime.addMonths(jan31_2024, 1);

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year should be 2024");
        assertEq(month, 2, "Month should be February");
        assertEq(day, 29, "Day should be adjusted to 29 (Feb has 29 days in 2024)");
    }

    function test_AddYears_OneYear() public pure {
        uint256 result = DateTime.addYears(JAN_1_2024, 1);

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2025, "Year should be 2025");
        assertEq(month, 1, "Month should be January");
        assertEq(day, 1, "Day should be 1");
    }

    function test_AddYears_LeapDayAdjustment() public pure {
        // Feb 29, 2024 + 1 year = Feb 28, 2025 (2025 is not leap year)
        uint256 result = DateTime.addYears(FEB_29_2024, 1);

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2025, "Year should be 2025");
        assertEq(month, 2, "Month should be February");
        assertEq(day, 28, "Day should be adjusted to 28");
    }

    function test_AddYears_TenYears() public pure {
        uint256 result = DateTime.addYears(JAN_1_2024, 10);

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2034, "Year should be 2034");
        assertEq(month, 1, "Month should be January");
        assertEq(day, 1, "Day should be 1");
    }

    // =============================================================================
    // VALIDATION TESTS
    // =============================================================================

    function test_IsValidDate_ValidDate() public {
        assertTrue(DateTime.isValidDate(JAN_1_2024), "2024 date should be valid");
    }

    function test_IsValidDate_Epoch() public {
        assertTrue(DateTime.isValidDate(EPOCH), "Epoch should be valid");
    }

    function test_IsValidDate_FutureDate() public {
        // Year 2099
        uint256 futureDate = 4070908800;
        assertTrue(DateTime.isValidDate(futureDate), "2099 should be valid");
    }

    function test_IsBefore_True() public pure {
        assertTrue(DateTime.isBefore(JAN_1_2024, FEB_29_2024), "Jan should be before Feb");
    }

    function test_IsBefore_False() public pure {
        assertFalse(DateTime.isBefore(FEB_29_2024, JAN_1_2024), "Feb should not be before Jan");
    }

    function test_IsBefore_SameDate() public pure {
        assertFalse(DateTime.isBefore(JAN_1_2024, JAN_1_2024), "Same date should not be before itself");
    }

    function test_IsAfter_True() public pure {
        assertTrue(DateTime.isAfter(FEB_29_2024, JAN_1_2024), "Feb should be after Jan");
    }

    function test_IsAfter_False() public pure {
        assertFalse(DateTime.isAfter(JAN_1_2024, FEB_29_2024), "Jan should not be after Feb");
    }

    function test_IsAfter_SameDate() public pure {
        assertFalse(DateTime.isAfter(JAN_1_2024, JAN_1_2024), "Same date should not be after itself");
    }

    // =============================================================================
    // UTILITY TESTS
    // =============================================================================

    function test_Now() public {
        // Set block timestamp to a known value
        vm.warp(JAN_1_2024);
        uint256 timestamp = DateTime.now_();
        assertEq(timestamp, JAN_1_2024, "Should return current block timestamp");
    }

    function test_ToTimestamp_Jan1_2024() public pure {
        uint256 timestamp = DateTime.toTimestamp(2024, 1, 1);
        assertEq(timestamp, JAN_1_2024, "Should create Jan 1, 2024");
    }

    function test_ToTimestamp_Feb29_2024() public pure {
        uint256 timestamp = DateTime.toTimestamp(2024, 2, 29);
        assertEq(timestamp, FEB_29_2024, "Should create Feb 29, 2024");
    }

    function test_ToTimestamp_Mar15_2023() public pure {
        uint256 timestamp = DateTime.toTimestamp(2023, 3, 15);
        assertEq(timestamp, MAR_15_2023, "Should create Mar 15, 2023");
    }

    function test_ToTimestamp_InvalidMonth() public {
        try this.externalToTimestamp(2024, 13, 1) {
            fail("Expected revert");
        } catch {
            // Should revert with "Invalid month"
        }
    }

    function test_ToTimestamp_InvalidDay() public {
        try this.externalToTimestamp(2024, 1, 32) {
            fail("Expected revert");
        } catch {
            // Should revert with "Invalid day" or "Day exceeds month"
        }
    }

    function test_ToTimestamp_InvalidLeapDay() public {
        // Feb 29 in non-leap year
        try this.externalToTimestamp(2023, 2, 29) {
            fail("Expected revert");
        } catch {
            // Should revert with "Day exceeds month"
        }
    }

    function test_ToTimestamp_InvalidYearBefore1970() public {
        try this.externalToTimestamp(1969, 1, 1) {
            fail("Expected revert");
        } catch {
            // Should revert with "Year must be >= 1970"
        }
    }

    // =============================================================================
    // ROUND-TRIP TESTS
    // =============================================================================

    function test_RoundTrip_ParseAndConstruct() public pure {
        // Parse a known date
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(MAR_15_2023);

        // Reconstruct it
        uint256 reconstructed = DateTime.toTimestamp(year, month, day);

        // Should match original
        assertEq(reconstructed, MAR_15_2023, "Round-trip should preserve date");
    }

    function test_RoundTrip_LeapYear() public pure {
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(FEB_29_2024);
        uint256 reconstructed = DateTime.toTimestamp(year, month, day);
        assertEq(reconstructed, FEB_29_2024, "Leap day round-trip should work");
    }

    // =============================================================================
    // EDGE CASE TESTS
    // =============================================================================

    function test_EdgeCase_LastDayOfYear() public pure {
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(DEC_31_2024);
        assertEq(year, 2024, "Year should be 2024");
        assertEq(month, 12, "Month should be December");
        assertEq(day, 31, "Day should be 31");
    }

    function test_EdgeCase_FirstDayAfterLeapDay() public pure {
        // March 1, 2024
        uint256 mar1_2024 = FEB_29_2024 + 86400;
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(mar1_2024);
        assertEq(year, 2024, "Year should be 2024");
        assertEq(month, 3, "Month should be March");
        assertEq(day, 1, "Day should be 1");
    }

    function test_EdgeCase_AddMonthsToEndOfMonth() public pure {
        // May 31 + 1 month = June 30 (June has 30 days)
        uint256 may31_2024 = DateTime.toTimestamp(2024, 5, 31);
        uint256 result = DateTime.addMonths(may31_2024, 1);

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year should be 2024");
        assertEq(month, 6, "Month should be June");
        assertEq(day, 30, "Day should be adjusted to 30");
    }

    function test_EdgeCase_CenturyYear() public pure {
        // Year 2000 is divisible by 400, so it's a leap year
        assertTrue(DateTime.isLeapYear(2000), "2000 should be leap year");
        assertEq(DateTime.getDaysInMonth(2, 2000), 29, "Feb 2000 should have 29 days");
    }
}
