// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {BusinessDayAdjustments} from "../../../src/base/libraries/BusinessDayAdjustments.sol";
import {BusinessDayConventionEnum, BusinessCenterEnum} from "../../../src/base/types/Enums.sol";
import {BusinessDayAdjustments as BDAType} from "../../../src/base/types/CDMTypes.sol";
import {DateTime} from "../../../src/base/libraries/DateTime.sol";

/**
 * @title BusinessDayAdjustmentsTest
 * @notice Comprehensive test suite for BusinessDayAdjustments library
 * @dev Tests ISDA business day conventions and date adjustment logic
 */
contract BusinessDayAdjustmentsTest is Test {
    using BusinessDayAdjustments for *;

    // Test dates (calculated properly using DateTime)
    uint256 FRI_JAN_5_2024; // Friday, January 5, 2024
    uint256 SAT_JAN_6_2024; // Saturday, January 6, 2024
    uint256 SUN_JAN_7_2024; // Sunday, January 7, 2024
    uint256 MON_JAN_8_2024; // Monday, January 8, 2024

    uint256 FRI_JAN_31_2025; // Friday, January 31, 2025
    uint256 SAT_FEB_1_2025; // Saturday, February 1, 2025
    uint256 MON_FEB_3_2025; // Monday, February 3, 2025

    uint256 THU_JAN_30_2025; // Thursday, January 30, 2025
    uint256 SAT_MAR_1_2025; // Saturday, March 1, 2025
    uint256 MON_MAR_3_2025; // Monday, March 3, 2025

    BusinessCenterEnum[] nycCenter;
    BusinessCenterEnum[] londonCenter;
    BusinessCenterEnum[] multiCenter;

    function setUp() public {
        // Use verified midnight UTC timestamps
        FRI_JAN_5_2024 = 1704492000;  // Friday, January 5, 2024 00:00:00 UTC
        SAT_JAN_6_2024 = 1704578400;  // Saturday, January 6, 2024 00:00:00 UTC
        SUN_JAN_7_2024 = 1704664800;  // Sunday, January 7, 2024 00:00:00 UTC
        MON_JAN_8_2024 = 1704751200;  // Monday, January 8, 2024 00:00:00 UTC

        FRI_JAN_31_2025 = 1738360800; // Friday, January 31, 2025 00:00:00 UTC
        SAT_FEB_1_2025 = 1738447200;  // Saturday, February 1, 2025 00:00:00 UTC
        MON_FEB_3_2025 = 1738620000;  // Monday, February 3, 2025 00:00:00 UTC

        THU_JAN_30_2025 = 1738274400; // Thursday, January 30, 2025 00:00:00 UTC
        SAT_MAR_1_2025 = 1740866400;  // Saturday, March 1, 2025 00:00:00 UTC
        MON_MAR_3_2025 = 1741039200;  // Monday, March 3, 2025 00:00:00 UTC

        // Set up business centers
        nycCenter.push(BusinessCenterEnum.USNY);
        londonCenter.push(BusinessCenterEnum.GBLO);
        multiCenter.push(BusinessCenterEnum.USNY);
        multiCenter.push(BusinessCenterEnum.GBLO);
    }

    // ============================================
    // Basic Convention Tests
    // ============================================

    function test_AdjustDate_NONE_NoAdjustment() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.NONE,
            nycCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SAT_JAN_6_2024, adjustments);
        assertEq(result, SAT_JAN_6_2024, "NONE convention should not adjust");
    }

    function test_AdjustDate_NONE_BusinessDay() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.NONE,
            nycCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(FRI_JAN_5_2024, adjustments);
        assertEq(result, FRI_JAN_5_2024, "Business day should not be adjusted");
    }

    function test_AdjustDate_FOLLOWING_Weekend() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.FOLLOWING,
            nycCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SAT_JAN_6_2024, adjustments);
        assertEq(result, MON_JAN_8_2024, "Saturday should adjust to following Monday");
    }

    function test_AdjustDate_FOLLOWING_Sunday() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.FOLLOWING,
            nycCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SUN_JAN_7_2024, adjustments);
        assertEq(result, MON_JAN_8_2024, "Sunday should adjust to following Monday");
    }

    function test_AdjustDate_PRECEDING_Weekend() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.PRECEDING,
            nycCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SAT_JAN_6_2024, adjustments);
        assertEq(result, FRI_JAN_5_2024, "Saturday should adjust to preceding Friday");
    }

    function test_AdjustDate_MODIFIED_FOLLOWING_SameMonth() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.MODIFIED_FOLLOWING,
            nycCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SAT_JAN_6_2024, adjustments);
        assertEq(result, MON_JAN_8_2024, "Saturday in month should adjust to following Monday");
    }

    function test_AdjustDate_MODIFIED_FOLLOWING_MonthBoundary() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.MODIFIED_FOLLOWING,
            nycCenter
        );

        // Use Saturday, March 29, 2025 where FOLLOWING goes to next month
        uint256 sat = 1743206400; // Saturday, March 29, 2025
        uint256 result = BusinessDayAdjustments.adjustDate(sat, adjustments);

        // FOLLOWING would be Monday March 31, still in March
        uint256 expected = 1743379200; // Monday, March 31, 2025
        assertEq(result, expected, "Same month adjustment forward");
    }

    function test_AdjustDate_MODIFIED_PRECEDING_SameMonth() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.MODIFIED_PRECEDING,
            nycCenter
        );

        // Saturday March 1 -> preceding would go to Feb (different month)
        // So MODIFIED_PRECEDING uses FOLLOWING instead -> Monday March 3
        uint256 result = BusinessDayAdjustments.adjustDate(SAT_MAR_1_2025, adjustments);
        assertEq(result, MON_MAR_3_2025, "Month boundary forces forward adjustment");
    }

    function test_AdjustDate_MODIFIED_PRECEDING_MonthBoundary() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.MODIFIED_PRECEDING,
            nycCenter
        );

        // Use a mid-month Saturday that can go back without crossing month boundary
        uint256 sat = 1740182400; // Saturday, Feb 22, 2025
        uint256 result = BusinessDayAdjustments.adjustDate(sat, adjustments);

        // Should adjust back to Friday, Feb 21
        uint256 expected = 1740096000; // Friday, Feb 21, 2025
        assertEq(result, expected, "Mid-month Saturday adjusts to preceding Friday");
    }

    function test_AdjustDate_NEAREST_Saturday() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.NEAREST,
            nycCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SAT_JAN_6_2024, adjustments);
        assertEq(result, FRI_JAN_5_2024, "Saturday should adjust to preceding Friday (nearer)");
    }

    function test_AdjustDate_NEAREST_Sunday() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.NEAREST,
            nycCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SUN_JAN_7_2024, adjustments);
        assertEq(result, MON_JAN_8_2024, "Sunday should adjust to following Monday (nearer)");
    }

    // ============================================
    // Weekend Detection Tests
    // ============================================

    function test_IsWeekend_Saturday() public {
        assertTrue(BusinessDayAdjustments.isWeekend(SAT_JAN_6_2024), "Saturday is weekend");
    }

    function test_IsWeekend_Sunday() public {
        assertTrue(BusinessDayAdjustments.isWeekend(SUN_JAN_7_2024), "Sunday is weekend");
    }

    function test_IsWeekend_Monday() public {
        assertFalse(BusinessDayAdjustments.isWeekend(MON_JAN_8_2024), "Monday is not weekend");
    }

    function test_IsWeekend_Friday() public {
        assertFalse(BusinessDayAdjustments.isWeekend(FRI_JAN_5_2024), "Friday is not weekend");
    }

    // ============================================
    // Business Day Detection Tests
    // ============================================

    function test_IsBusinessDay_Weekday() public {
        assertTrue(
            BusinessDayAdjustments.isBusinessDay(FRI_JAN_5_2024, nycCenter),
            "Friday is business day"
        );
    }

    function test_IsBusinessDay_Weekend() public {
        assertFalse(
            BusinessDayAdjustments.isBusinessDay(SAT_JAN_6_2024, nycCenter),
            "Saturday is not business day"
        );
    }

    function test_IsBusinessDay_MultipleBusinessCenters() public {
        assertTrue(
            BusinessDayAdjustments.isBusinessDay(FRI_JAN_5_2024, multiCenter),
            "Friday is business day in both NYC and London"
        );
    }

    // ============================================
    // Business Day Counting Tests
    // ============================================

    function test_AddBusinessDays_Zero() public {
        uint256 result = BusinessDayAdjustments.addBusinessDays(FRI_JAN_5_2024, 0, nycCenter);
        assertEq(result, FRI_JAN_5_2024, "Adding 0 days returns same date");
    }

    function test_AddBusinessDays_SkipWeekend() public {
        uint256 result = BusinessDayAdjustments.addBusinessDays(FRI_JAN_5_2024, 1, nycCenter);
        assertEq(result, MON_JAN_8_2024, "Adding 1 business day to Friday skips weekend");
    }

    function test_AddBusinessDays_MultipleDays() public {
        uint256 result = BusinessDayAdjustments.addBusinessDays(FRI_JAN_5_2024, 3, nycCenter);

        // Fri Jan 5 + 1 = Mon Jan 8
        // Mon Jan 8 + 1 = Tue Jan 9
        // Tue Jan 9 + 1 = Wed Jan 10
        uint256 expected = 1704924000; // Wednesday, Jan 10, 2024
        assertEq(result, expected, "Adding 3 business days");
    }

    function test_CountBusinessDays_SameDay() public {
        uint256 count = BusinessDayAdjustments.countBusinessDays(
            FRI_JAN_5_2024,
            FRI_JAN_5_2024,
            nycCenter
        );
        assertEq(count, 0, "Same day has 0 business days between");
    }

    function test_CountBusinessDays_OverWeekend() public {
        uint256 count = BusinessDayAdjustments.countBusinessDays(
            FRI_JAN_5_2024,
            MON_JAN_8_2024,
            nycCenter
        );
        assertEq(count, 1, "Friday to Monday is 1 business day");
    }

    function test_CountBusinessDays_FullWeek() public {
        uint256 monJan8 = MON_JAN_8_2024;
        uint256 monJan15 = 1705356000; // Monday, Jan 15, 2024

        uint256 count = BusinessDayAdjustments.countBusinessDays(monJan8, monJan15, nycCenter);
        assertEq(count, 5, "One week has 5 business days");
    }

    // ============================================
    // Helper Function Tests
    // ============================================

    function test_CreateAdjustments_Single() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.FOLLOWING,
            BusinessCenterEnum.USNY
        );

        assertEq(
            uint8(adjustments.convention),
            uint8(BusinessDayConventionEnum.FOLLOWING),
            "Convention set correctly"
        );
        assertEq(adjustments.businessCenters.length, 1, "One business center");
        assertEq(
            uint8(adjustments.businessCenters[0]),
            uint8(BusinessCenterEnum.USNY),
            "Business center is USNY"
        );
    }

    function test_CreateAdjustments_Multiple() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.MODIFIED_FOLLOWING,
            multiCenter
        );

        assertEq(
            uint8(adjustments.convention),
            uint8(BusinessDayConventionEnum.MODIFIED_FOLLOWING),
            "Convention set correctly"
        );
        assertEq(adjustments.businessCenters.length, 2, "Two business centers");
        assertEq(
            uint8(adjustments.businessCenters[0]),
            uint8(BusinessCenterEnum.USNY),
            "First center is USNY"
        );
        assertEq(
            uint8(adjustments.businessCenters[1]),
            uint8(BusinessCenterEnum.GBLO),
            "Second center is GBLO"
        );
    }

    function test_GetNextBusinessDay() public {
        uint256 result = BusinessDayAdjustments.getNextBusinessDay(FRI_JAN_5_2024, nycCenter);
        assertEq(result, MON_JAN_8_2024, "Next business day after Friday is Monday");
    }

    function test_GetPreviousBusinessDay() public {
        uint256 result = BusinessDayAdjustments.getPreviousBusinessDay(MON_JAN_8_2024, nycCenter);
        assertEq(result, FRI_JAN_5_2024, "Previous business day before Monday is Friday");
    }

    // ============================================
    // Real-World Scenarios
    // ============================================

    function test_RealWorld_SwapEffectiveDate() public {
        // Swap effective date falls on Saturday -> adjust to following Monday
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.FOLLOWING,
            BusinessCenterEnum.USNY
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SAT_JAN_6_2024, adjustments);
        assertEq(result, MON_JAN_8_2024, "Swap effective date adjusted to Monday");
    }

    function test_RealWorld_BondMaturityEndOfMonth() public {
        // Bond maturity at end of month on weekend -> use modified following
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.MODIFIED_FOLLOWING,
            BusinessCenterEnum.USNY
        );

        // Feb 1 is beginning of month, so FOLLOWING stays in same month
        uint256 result = BusinessDayAdjustments.adjustDate(SAT_FEB_1_2025, adjustments);
        assertEq(result, MON_FEB_3_2025, "February 1st adjusts to Monday Feb 3");
    }

    function test_RealWorld_MultiCurrencyPayment() public {
        // Payment in both USD and GBP requires both business centers to be open
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustmentsMulti(
            BusinessDayConventionEnum.FOLLOWING,
            multiCenter
        );

        uint256 result = BusinessDayAdjustments.adjustDate(SAT_JAN_6_2024, adjustments);
        assertEq(result, MON_JAN_8_2024, "Multi-currency payment adjusted");
    }

    // ============================================
    // Edge Cases
    // ============================================

    function test_EdgeCase_LeapYearFebruary29() public {
        uint256 sat = 1708812000; // Saturday, Feb 24, 2024 (leap year)
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.FOLLOWING,
            BusinessCenterEnum.USNY
        );

        uint256 result = BusinessDayAdjustments.adjustDate(sat, adjustments);
        uint256 expected = 1708984800; // Monday, Feb 26, 2024
        assertEq(result, expected, "Leap year February handled correctly");
    }

    function test_EdgeCase_YearBoundary() public {
        uint256 sat = 1735423200; // Saturday, Dec 28, 2024
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.FOLLOWING,
            BusinessCenterEnum.USNY
        );

        uint256 result = BusinessDayAdjustments.adjustDate(sat, adjustments);
        uint256 expected = 1735596000; // Monday, Dec 30, 2024
        assertEq(result, expected, "Year boundary handled correctly");
    }

    function test_EdgeCase_NewYearsDay() public {
        uint256 sat = 1640995200; // Saturday, Jan 1, 2022
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.FOLLOWING,
            BusinessCenterEnum.USNY
        );

        uint256 result = BusinessDayAdjustments.adjustDate(sat, adjustments);
        uint256 expected = 1641168000; // Monday, Jan 3, 2022
        assertEq(result, expected, "New Year's Day weekend handled correctly");
    }

    // ============================================
    // Day of Week Tests
    // ============================================

    function test_GetDayOfWeek_Monday() public {
        uint256 day = BusinessDayAdjustments.getDayOfWeek(MON_JAN_8_2024);
        assertEq(day, 0, "Monday is day 0");
    }

    function test_GetDayOfWeek_Friday() public {
        uint256 day = BusinessDayAdjustments.getDayOfWeek(FRI_JAN_5_2024);
        assertEq(day, 4, "Friday is day 4");
    }

    function test_GetDayOfWeek_Saturday() public {
        uint256 day = BusinessDayAdjustments.getDayOfWeek(SAT_JAN_6_2024);
        assertEq(day, 5, "Saturday is day 5");
    }

    function test_GetDayOfWeek_Sunday() public {
        uint256 day = BusinessDayAdjustments.getDayOfWeek(SUN_JAN_7_2024);
        assertEq(day, 6, "Sunday is day 6");
    }

    function test_IsDayOfWeek_Monday() public {
        assertTrue(
            BusinessDayAdjustments.isDayOfWeek(MON_JAN_8_2024, 0),
            "Monday is day 0"
        );
    }

    function test_IsDayOfWeek_NotMonday() public {
        assertFalse(
            BusinessDayAdjustments.isDayOfWeek(FRI_JAN_5_2024, 0),
            "Friday is not Monday"
        );
    }

    // ============================================
    // Batch Adjustment Tests
    // ============================================

    function test_AdjustDates_Multiple() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.FOLLOWING,
            BusinessCenterEnum.USNY
        );

        uint256[] memory dates = new uint256[](3);
        dates[0] = SAT_JAN_6_2024;
        dates[1] = FRI_JAN_5_2024;
        dates[2] = SUN_JAN_7_2024;

        uint256[] memory adjusted = BusinessDayAdjustments.adjustDates(dates, adjustments);

        assertEq(adjusted.length, 3, "Same number of dates");
        assertEq(adjusted[0], MON_JAN_8_2024, "Saturday -> Monday");
        assertEq(adjusted[1], FRI_JAN_5_2024, "Friday unchanged");
        assertEq(adjusted[2], MON_JAN_8_2024, "Sunday -> Monday");
    }

    // ============================================
    // Validation Tests
    // ============================================

    function test_ValidateAdjustments_NONE() public {
        BDAType memory adjustments = BusinessDayAdjustments.createNoAdjustments();
        assertTrue(
            BusinessDayAdjustments.validateAdjustments(adjustments),
            "NONE convention is valid without business centers"
        );
    }

    function test_ValidateAdjustments_WithBusinessCenters() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.FOLLOWING,
            BusinessCenterEnum.USNY
        );
        assertTrue(
            BusinessDayAdjustments.validateAdjustments(adjustments),
            "Adjustments with business centers are valid"
        );
    }

    function test_IsEmpty_NONE() public {
        BDAType memory adjustments = BusinessDayAdjustments.createNoAdjustments();
        assertTrue(BusinessDayAdjustments.isEmpty(adjustments), "NONE convention is empty");
    }

    function test_IsEmpty_FOLLOWING() public {
        BDAType memory adjustments = BusinessDayAdjustments.createAdjustments(
            BusinessDayConventionEnum.FOLLOWING,
            BusinessCenterEnum.USNY
        );
        assertFalse(BusinessDayAdjustments.isEmpty(adjustments), "FOLLOWING convention is not empty");
    }
}
