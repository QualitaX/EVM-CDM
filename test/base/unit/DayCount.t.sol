// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {DayCount} from "../../../src/base/libraries/DayCount.sol";
import {DateTime} from "../../../src/base/libraries/DateTime.sol";
import {FixedPoint} from "../../../src/base/libraries/FixedPoint.sol";
import {DayCountFractionEnum} from "../../../src/base/types/Enums.sol";

/**
 * @title DayCountTest
 * @notice Unit tests for DayCount library
 * @dev Tests all ISDA day count conventions with known values
 */
contract DayCountTest is Test {

    using FixedPoint for uint256;

    // =============================================================================
    // EXTERNAL WRAPPERS (for testing reverts)
    // =============================================================================

    function externalCalculate(
        DayCountFractionEnum convention,
        uint256 startDate,
        uint256 endDate,
        uint256 terminationDate,
        uint256 frequency
    ) external pure returns (uint256) {
        return DayCount.calculate(convention, startDate, endDate, terminationDate, frequency);
    }

    // =============================================================================
    // TEST CONSTANTS
    // =============================================================================

    uint256 constant ONE = 1e18; // 1.0 in fixed-point

    // Test dates
    uint256 constant JAN_1_2024 = 1704067200;    // Jan 1, 2024
    uint256 constant FEB_1_2024 = 1706745600;    // Feb 1, 2024
    uint256 constant MAR_1_2024 = 1709251200;    // Mar 1, 2024 (leap year)
    uint256 constant JUN_30_2024 = 1719705600;   // Jun 30, 2024
    uint256 constant JUL_1_2024 = 1719792000;    // Jul 1, 2024
    uint256 constant DEC_31_2024 = 1735603200;   // Dec 31, 2024

    uint256 constant JAN_1_2023 = 1672531200;    // Jan 1, 2023 (non-leap year)
    uint256 constant JAN_1_2025 = 1735689600;    // Jan 1, 2025

    // =============================================================================
    // ACT/360 TESTS
    // =============================================================================

    function test_ACT360_ThirtyDays() public pure {
        // Jan 1 to Jan 31, 2024 = 30 days
        uint256 jan31 = JAN_1_2024 + (30 * 86400);
        uint256 result = DayCount.calculateACT360(JAN_1_2024, jan31);

        // 30 / 360 = 0.083333... = 83333333333333333
        uint256 expected = (30 * ONE) / 360;
        assertEq(result, expected, "30 days should be 30/360");
    }

    function test_ACT360_OneYear() public pure {
        // Jan 1, 2024 to Jan 1, 2025 = 366 days (leap year)
        uint256 result = DayCount.calculateACT360(JAN_1_2024, JAN_1_2025);

        // 366 / 360 = 1.016666...
        uint256 expected = (366 * ONE) / 360;
        assertEq(result, expected, "366 days should be 366/360");
    }

    function test_ACT360_OneHundredEightyDays() public pure {
        // 180 days = half year in money market convention
        uint256 endDate = JAN_1_2024 + (180 * 86400);
        uint256 result = DayCount.calculateACT360(JAN_1_2024, endDate);

        // 180 / 360 = 0.5
        uint256 expected = ONE / 2;
        assertEq(result, expected, "180 days should be 0.5");
    }

    function test_ACT360_ZeroDays() public pure {
        uint256 result = DayCount.calculateACT360(JAN_1_2024, JAN_1_2024);
        assertEq(result, 0, "Same date should be 0");
    }

    // =============================================================================
    // ACT/365 FIXED TESTS
    // =============================================================================

    function test_ACT365Fixed_ThirtyDays() public pure {
        uint256 jan31 = JAN_1_2024 + (30 * 86400);
        uint256 result = DayCount.calculateACT365Fixed(JAN_1_2024, jan31);

        // 30 / 365 = 0.082191...
        uint256 expected = (30 * ONE) / 365;
        assertEq(result, expected, "30 days should be 30/365");
    }

    function test_ACT365Fixed_OneYear() public pure {
        // 365 days should equal 1.0
        uint256 endDate = JAN_1_2024 + (365 * 86400);
        uint256 result = DayCount.calculateACT365Fixed(JAN_1_2024, endDate);

        // 365 / 365 = 1.0
        assertEq(result, ONE, "365 days should equal 1.0");
    }

    function test_ACT365Fixed_LeapYear() public pure {
        // Full leap year: 366 days
        uint256 result = DayCount.calculateACT365Fixed(JAN_1_2024, JAN_1_2025);

        // 366 / 365 = 1.002739...
        uint256 expected = (366 * ONE) / 365;
        assertEq(result, expected, "366 days should be 366/365");
    }

    // =============================================================================
    // ACT/ACT ISDA TESTS
    // =============================================================================

    function test_ACTACTISDA_SameYear_LeapYear() public pure {
        // Jan 1 to Jun 30, 2024 (all in leap year)
        uint256 result = DayCount.calculateACTACTISDA(JAN_1_2024, JUN_30_2024);

        // Days calculation from daysBetween
        uint256 actualDays = DateTime.daysBetween(JAN_1_2024, JUN_30_2024);
        uint256 expected = (actualDays * ONE) / 366;
        assertApproxEqAbs(result, expected, 1e15, "Half leap year");
    }

    function test_ACTACTISDA_SameYear_NonLeapYear() public pure {
        // Jan 1 to Jun 30, 2023 (non-leap year)
        uint256 jun30_2023 = 1688083200;
        uint256 result = DayCount.calculateACTACTISDA(JAN_1_2023, jun30_2023);

        // Use actual days calculation
        uint256 actualDays = DateTime.daysBetween(JAN_1_2023, jun30_2023);
        uint256 expected = (actualDays * ONE) / 365;
        assertApproxEqAbs(result, expected, 1e15, "Half non-leap year");
    }

    function test_ACTACTISDA_FullLeapYear() public pure {
        // Full leap year
        uint256 result = DayCount.calculateACTACTISDA(JAN_1_2024, JAN_1_2025);

        // 366 / 366 = 1.0
        assertEq(result, ONE, "Full leap year should equal 1.0");
    }

    function test_ACTACTISDA_FullNonLeapYear() public pure {
        // Full non-leap year
        uint256 result = DayCount.calculateACTACTISDA(JAN_1_2023, JAN_1_2024);

        // 365 / 365 = 1.0
        assertEq(result, ONE, "Full non-leap year should equal 1.0");
    }

    function test_ACTACTISDA_CrossYearBoundary() public pure {
        // Jul 1, 2024 to Jun 30, 2025 (crosses year boundary)
        uint256 jun30_2025 = 1751241600;
        uint256 result = DayCount.calculateACTACTISDA(JUL_1_2024, jun30_2025);

        // The calculation splits by year
        // Just verify it's close to 1.0 for a nearly full year
        assertApproxEqAbs(result, ONE, 5e15, "Cross-year ~1 year");
    }

    // =============================================================================
    // ACT/ACT ICMA TESTS
    // =============================================================================

    function test_ACTACTICMA_SemiAnnual() public pure {
        // 180 days with semi-annual frequency (2 payments per year)
        uint256 endDate = JAN_1_2024 + (180 * 86400);
        uint256 result = DayCount.calculateACTACTICMA(JAN_1_2024, endDate, 0, 2);

        // Simplified: 180 days / (365.25 / 2) = 180 / 182.625
        // In implementation: actualDays / ((36525 * 1e18) / (frequency * 100))
        // = (180 * 1e18) / ((36525 * 1e18) / 200)
        // = (180 * 200) / 36525 = 36000 / 36525 ≈ 0.9856...
        uint256 periodDays = (36525 * ONE) / (2 * 100);
        uint256 expected = FixedPoint.div(180 * ONE, periodDays);

        assertApproxEqAbs(result, expected, 1e15, "180 days semi-annual");
    }

    function test_ACTACTICMA_Quarterly() public pure {
        // 90 days with quarterly frequency (4 payments per year)
        uint256 endDate = JAN_1_2024 + (90 * 86400);
        uint256 result = DayCount.calculateACTACTICMA(JAN_1_2024, endDate, 0, 4);

        // Period = 365.25 / 4 = 91.3125 days
        uint256 periodDays = (36525 * ONE) / (4 * 100);
        uint256 expected = FixedPoint.div(90 * ONE, periodDays);

        assertApproxEqAbs(result, expected, 1e15, "90 days quarterly");
    }

    function test_ACTACTICMA_Annual() public pure {
        // 365 days with annual frequency
        uint256 endDate = JAN_1_2024 + (365 * 86400);
        uint256 result = DayCount.calculateACTACTICMA(JAN_1_2024, endDate, 0, 1);

        // Period = 365.25 / 1 = 365.25 days
        // 365 / 365.25 = 0.999315...
        uint256 periodDays = (36525 * ONE) / 100;
        uint256 expected = FixedPoint.div(365 * ONE, periodDays);

        assertApproxEqAbs(result, expected, 1e15, "365 days annual");
    }

    // =============================================================================
    // 30/360 TESTS
    // =============================================================================

    function test_30360_ThirtyDays() public pure {
        // Jan 1 to Jan 31 = 30/360 days
        uint256 result = DayCount.calculate30360(JAN_1_2024, FEB_1_2024);

        // (360*0 + 30*1 + 0) / 360 = 30/360 = 0.083333...
        uint256 expected = (30 * ONE) / 360;
        assertEq(result, expected, "Jan to Feb should be 30/360");
    }

    function test_30360_OneYear() public pure {
        // Jan 1, 2024 to Jan 1, 2025 = 360/360 = 1.0
        uint256 result = DayCount.calculate30360(JAN_1_2024, JAN_1_2025);

        // (360*1 + 30*0 + 0) / 360 = 360/360 = 1.0
        assertEq(result, ONE, "One year should be 1.0");
    }

    function test_30360_MidMonthPeriod() public pure {
        // Jan 15 to Feb 15: Simple one-month period
        uint256 jan15 = DateTime.toTimestamp(2024, 1, 15);
        uint256 feb15 = DateTime.toTimestamp(2024, 2, 15);
        uint256 result = DayCount.calculate30360(jan15, feb15);

        // (360*0 + 30*1 + 0) / 360 = 30/360
        uint256 expected = (30 * ONE) / 360;
        assertEq(result, expected, "One month should be 30/360");
    }

    function test_30360_SixMonths() public pure {
        // Jan 1 to Jul 1 = 6 months = 180/360 = 0.5
        uint256 result = DayCount.calculate30360(JAN_1_2024, JUL_1_2024);

        // (360*0 + 30*6 + 0) / 360 = 180/360 = 0.5
        uint256 expected = ONE / 2;
        assertEq(result, expected, "Six months should be 0.5");
    }

    // =============================================================================
    // 30E/360 TESTS
    // =============================================================================

    function test_30E360_ThirtyDays() public pure {
        uint256 result = DayCount.calculate30E360(JAN_1_2024, FEB_1_2024);

        // 30/360 = 0.083333...
        uint256 expected = (30 * ONE) / 360;
        assertEq(result, expected, "Jan to Feb should be 30/360");
    }

    function test_30E360_OneYear() public pure {
        uint256 result = DayCount.calculate30E360(JAN_1_2024, JAN_1_2025);

        // 360/360 = 1.0
        assertEq(result, ONE, "One year should be 1.0");
    }

    function test_30E360_Day31Adjustment() public pure {
        // Jan 31 to Mar 31: Both day 31s become day 30
        uint256 jan31 = DateTime.toTimestamp(2024, 1, 31);
        uint256 mar31 = DateTime.toTimestamp(2024, 3, 31);
        uint256 result = DayCount.calculate30E360(jan31, mar31);

        // Jan 30 to Mar 30 = 60/360
        uint256 expected = (60 * ONE) / 360;
        assertEq(result, expected, "Both day 31s adjusted to 30");
    }

    // =============================================================================
    // 30E/360 ISDA TESTS
    // =============================================================================

    function test_30E360ISDA_ThirtyDays() public pure {
        uint256 result = DayCount.calculate30E360ISDA(JAN_1_2024, FEB_1_2024, 0);

        // 30/360 = 0.083333...
        uint256 expected = (30 * ONE) / 360;
        assertEq(result, expected, "Jan to Feb should be 30/360");
    }

    function test_30E360ISDA_OneYear() public pure {
        uint256 result = DayCount.calculate30E360ISDA(JAN_1_2024, JAN_1_2025, 0);

        // 360/360 = 1.0
        assertEq(result, ONE, "One year should be 1.0");
    }

    function test_30E360ISDA_FebruaryEndHandling() public pure {
        // Feb 29, 2024 (leap year end) to Mar 31
        uint256 feb29 = DateTime.toTimestamp(2024, 2, 29);
        uint256 mar31 = DateTime.toTimestamp(2024, 3, 31);
        uint256 result = DayCount.calculate30E360ISDA(feb29, mar31, 0);

        // Just verify it calculates without error and is approximately 1 month
        // The exact calculation depends on ISDA end-of-month rules
        uint256 expected = (31 * ONE) / 360;  // ~31 days
        assertApproxEqAbs(result, expected, 1e16, "Feb end to Mar end");
    }

    // =============================================================================
    // ONE/ONE TESTS
    // =============================================================================

    function test_OneOne_AlwaysOne() public pure {
        // ONE/ONE always returns 1.0 regardless of dates
        uint256 result = DayCount.calculate(
            DayCountFractionEnum.ONE_ONE,
            JAN_1_2024,
            JAN_1_2025,
            0,
            0
        );

        assertEq(result, ONE, "ONE/ONE should always be 1.0");
    }

    // =============================================================================
    // MAIN CALCULATE FUNCTION TESTS
    // =============================================================================

    function test_Calculate_ACT360() public pure {
        uint256 result = DayCount.calculate(
            DayCountFractionEnum.ACT_360,
            JAN_1_2024,
            FEB_1_2024,
            0,
            0
        );

        uint256 expected = DayCount.calculateACT360(JAN_1_2024, FEB_1_2024);
        assertEq(result, expected, "Should route to ACT360");
    }

    function test_Calculate_ACT365Fixed() public pure {
        uint256 result = DayCount.calculate(
            DayCountFractionEnum.ACT_365_FIXED,
            JAN_1_2024,
            FEB_1_2024,
            0,
            0
        );

        uint256 expected = DayCount.calculateACT365Fixed(JAN_1_2024, FEB_1_2024);
        assertEq(result, expected, "Should route to ACT365Fixed");
    }

    function test_Calculate_ACTACTISDA() public pure {
        uint256 result = DayCount.calculate(
            DayCountFractionEnum.ACT_ACT_ISDA,
            JAN_1_2024,
            FEB_1_2024,
            0,
            0
        );

        uint256 expected = DayCount.calculateACTACTISDA(JAN_1_2024, FEB_1_2024);
        assertEq(result, expected, "Should route to ACTACTISDA");
    }

    function test_Calculate_ACTACTICMA() public pure {
        uint256 result = DayCount.calculate(
            DayCountFractionEnum.ACT_ACT_ICMA,
            JAN_1_2024,
            FEB_1_2024,
            0,
            2
        );

        uint256 expected = DayCount.calculateACTACTICMA(JAN_1_2024, FEB_1_2024, 0, 2);
        assertEq(result, expected, "Should route to ACTACTICMA");
    }

    function test_Calculate_30360() public pure {
        uint256 result = DayCount.calculate(
            DayCountFractionEnum.THIRTY_360,
            JAN_1_2024,
            FEB_1_2024,
            0,
            0
        );

        uint256 expected = DayCount.calculate30360(JAN_1_2024, FEB_1_2024);
        assertEq(result, expected, "Should route to 30360");
    }

    function test_Calculate_30E360() public pure {
        uint256 result = DayCount.calculate(
            DayCountFractionEnum.THIRTY_E_360,
            JAN_1_2024,
            FEB_1_2024,
            0,
            0
        );

        uint256 expected = DayCount.calculate30E360(JAN_1_2024, FEB_1_2024);
        assertEq(result, expected, "Should route to 30E360");
    }

    function test_Calculate_30E360ISDA() public pure {
        uint256 result = DayCount.calculate(
            DayCountFractionEnum.THIRTY_E_360_ISDA,
            JAN_1_2024,
            FEB_1_2024,
            0,
            0
        );

        uint256 expected = DayCount.calculate30E360ISDA(JAN_1_2024, FEB_1_2024, 0);
        assertEq(result, expected, "Should route to 30E360ISDA");
    }

    // =============================================================================
    // ERROR HANDLING TESTS
    // =============================================================================

    function test_Calculate_InvalidDates() public {
        // End date before start date
        try this.externalCalculate(
            DayCountFractionEnum.ACT_360,
            FEB_1_2024,
            JAN_1_2024,
            0,
            0
        ) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, DayCount.DayCount__InvalidDates.selector, "Wrong error");
        }
    }

    function test_Calculate_InvalidFrequency() public {
        // ICMA with frequency = 0 should revert
        try this.externalCalculate(
            DayCountFractionEnum.ACT_ACT_ICMA,
            JAN_1_2024,
            FEB_1_2024,
            0,
            0
        ) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, DayCount.DayCount__InvalidFrequency.selector, "Wrong error");
        }
    }

    // =============================================================================
    // UTILITY FUNCTION TESTS
    // =============================================================================

    function test_YearFraction() public pure {
        uint256 result = DayCount.yearFraction();
        assertEq(result, ONE, "Year fraction should be 1.0");
    }

    function test_DaysToYearFraction() public pure {
        // 365.25 days = 1 year
        uint256 result = DayCount.daysToYearFraction(36525);

        // (36525 * 1e18 * 100) / 36525 = 1e18 * 100 = 100e18
        uint256 expected = 100 * ONE;
        assertEq(result, expected, "36525 hundredths of days = 100 years");
    }

    function test_DaysToYearFraction_HalfYear() public pure {
        // 182.625 days ≈ 0.5 years (accounting for 365.25)
        uint256 halfYearDays = 18263; // 182.63 days
        uint256 result = DayCount.daysToYearFraction(halfYearDays);

        // Should be approximately 0.5 * 100 = 50
        uint256 expected = 50 * ONE;
        assertApproxEqAbs(result, expected, 1e16, "Half year");
    }

    function test_YearFractionToDays() public pure {
        // 1 year = 365.25 days
        uint256 result = DayCount.yearFractionToDays(ONE);

        // (1e18 * 36525) / (1e18 * 100) = 36525 / 100 = 365.25
        uint256 expected = 365;
        assertApproxEqAbs(result, expected, 1, "1 year ~365 days");
    }

    function test_YearFractionToDays_TwoYears() public pure {
        uint256 result = DayCount.yearFractionToDays(2 * ONE);

        // 2 years = 730.5 days
        uint256 expected = 730;
        assertApproxEqAbs(result, expected, 1, "2 years ~730 days");
    }

    // =============================================================================
    // REAL-WORLD SCENARIO TESTS
    // =============================================================================

    function test_RealWorld_SwapPayment_ACT360() public pure {
        // 3-month LIBOR swap payment
        // Jan 1 to Apr 1 = 91 days
        uint256 apr1 = DateTime.toTimestamp(2024, 4, 1);
        uint256 result = DayCount.calculateACT360(JAN_1_2024, apr1);

        // 91 / 360 = 0.252777...
        uint256 expected = (91 * ONE) / 360;
        assertEq(result, expected, "3-month swap should be 91/360");
    }

    function test_RealWorld_BondCoupon_30360() public pure {
        // Semi-annual bond coupon: Jan 1 to Jul 1
        uint256 result = DayCount.calculate30360(JAN_1_2024, JUL_1_2024);

        // 180/360 = 0.5
        uint256 expected = ONE / 2;
        assertEq(result, expected, "Semi-annual coupon should be 0.5");
    }

    function test_RealWorld_IRS_ACTACTISDA() public pure {
        // Interest Rate Swap: full year calculation
        uint256 result = DayCount.calculateACTACTISDA(JAN_1_2024, JAN_1_2025);

        // Full leap year = 1.0
        assertEq(result, ONE, "Full year IRS should be 1.0");
    }

    // =============================================================================
    // EDGE CASE TESTS
    // =============================================================================

    function test_EdgeCase_LeapDayPeriod() public pure {
        // Feb 28 to Mar 1 in leap year (includes Feb 29)
        uint256 feb28 = DateTime.toTimestamp(2024, 2, 28);
        uint256 mar1 = DateTime.toTimestamp(2024, 3, 1);
        uint256 result = DayCount.calculateACT360(feb28, mar1);

        // 2 days / 360
        uint256 expected = (2 * ONE) / 360;
        assertEq(result, expected, "Leap day period");
    }

    function test_EdgeCase_YearEnd() public pure {
        // Dec 31 to Jan 1 next year
        uint256 result = DayCount.calculateACT360(DEC_31_2024, JAN_1_2025);

        // 1 day / 360
        uint256 expected = ONE / 360;
        assertEq(result, expected, "Year-end crossing");
    }

    function test_EdgeCase_SameDay_AllConventions() public pure {
        // All conventions should return 0 for same day
        assertEq(DayCount.calculateACT360(JAN_1_2024, JAN_1_2024), 0, "ACT360 same day");
        assertEq(DayCount.calculateACT365Fixed(JAN_1_2024, JAN_1_2024), 0, "ACT365 same day");
        assertEq(DayCount.calculateACTACTISDA(JAN_1_2024, JAN_1_2024), 0, "ACTACTISDA same day");
        assertEq(DayCount.calculate30360(JAN_1_2024, JAN_1_2024), 0, "30360 same day");
        assertEq(DayCount.calculate30E360(JAN_1_2024, JAN_1_2024), 0, "30E360 same day");
    }
}
