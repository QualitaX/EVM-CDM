// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Schedule} from "../../../src/base/libraries/Schedule.sol";
import {DateTime} from "../../../src/base/libraries/DateTime.sol";
import {Period, BusinessDayAdjustments} from "../../../src/base/types/CDMTypes.sol";
import {PeriodEnum, BusinessDayConventionEnum, BusinessCenterEnum} from "../../../src/base/types/Enums.sol";

contract ScheduleTest is Test {
    using Schedule for *;

    // Test dates
    uint256 constant JAN_1_2024 = 1704067200;  // Jan 1, 2024 00:00:00 UTC
    uint256 constant JAN_1_2025 = 1735689600;  // Jan 1, 2025 00:00:00 UTC
    uint256 constant APR_1_2024 = 1711929600;  // Apr 1, 2024 00:00:00 UTC
    uint256 constant JUL_1_2024 = 1719792000;  // Jul 1, 2024 00:00:00 UTC
    uint256 constant OCT_1_2024 = 1727740800;  // Oct 1, 2024 00:00:00 UTC
    uint256 constant DEC_31_2024 = 1735603200; // Dec 31, 2024 00:00:00 UTC

    // =============================================================================
    // BASIC SCHEDULE GENERATION TESTS
    // =============================================================================

    function test_GenerateSchedule_Quarterly() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createQuarterlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 4, "Should have 4 quarterly periods");
        assertFalse(result.hasStub, "No stub period");

        // Verify first period
        assertEq(result.periods[0].startDate, JAN_1_2024, "First period start");
        assertEq(result.periods[0].endDate, APR_1_2024, "First period end");

        // Verify last period ends at termination
        assertEq(result.periods[3].endDate, JAN_1_2025, "Last period ends at termination");
    }

    function test_GenerateSchedule_SemiAnnual() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createSemiAnnualPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 2, "Should have 2 semi-annual periods");
        assertEq(result.periods[0].endDate, JUL_1_2024, "First period ends July 1");
        assertEq(result.periods[1].startDate, JUL_1_2024, "Second period starts July 1");
    }

    function test_GenerateSchedule_Annual() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createAnnualPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 1, "Should have 1 annual period");
        assertEq(result.periods[0].startDate, JAN_1_2024, "Period start");
        assertEq(result.periods[0].endDate, JAN_1_2025, "Period end");
    }

    function test_GenerateSchedule_Monthly() public {
        uint256 threeMonthsLater = JAN_1_2024 + 90 days;

        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            threeMonthsLater,
            Schedule.createMonthlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 3, "Should have 3 monthly periods");
    }

    function test_GenerateSchedule_TwoYears() public {
        uint256 jan1_2026 = JAN_1_2025 + 365 days;

        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            jan1_2026,
            Schedule.createQuarterlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 8, "Should have 8 quarterly periods in 2 years");
    }

    // =============================================================================
    // STUB PERIOD TESTS
    // =============================================================================

    function test_GenerateSchedule_ShortFirstStub() public {
        Schedule.ScheduleParameters memory params = Schedule.ScheduleParameters({
            effectiveDate: JAN_1_2024,
            terminationDate: JAN_1_2025,
            frequency: Schedule.createQuarterlyPeriod(),
            rollConvention: Schedule.RollConventionEnum.NONE,
            rollDay: 0,
            stubType: Schedule.StubTypeEnum.SHORT_FIRST,
            adjustments: createNoAdjustments()
        });

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertTrue(result.hasStub, "Should have stub period");
        assertTrue(result.periods[0].isStub, "First period should be stub");
        assertFalse(result.periods[1].isStub, "Second period not stub");
    }

    function test_GenerateSchedule_ShortLastStub() public {
        Schedule.ScheduleParameters memory params = Schedule.ScheduleParameters({
            effectiveDate: JAN_1_2024,
            terminationDate: JAN_1_2025,
            frequency: Schedule.createQuarterlyPeriod(),
            rollConvention: Schedule.RollConventionEnum.NONE,
            rollDay: 0,
            stubType: Schedule.StubTypeEnum.SHORT_LAST,
            adjustments: createNoAdjustments()
        });

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertTrue(result.hasStub, "Should have stub period");
        assertTrue(result.periods[result.numberOfPeriods - 1].isStub, "Last period should be stub");
    }

    function test_GenerateSchedule_NoStub() public {
        Schedule.ScheduleParameters memory params = Schedule.ScheduleParameters({
            effectiveDate: JAN_1_2024,
            terminationDate: JAN_1_2025,
            frequency: Schedule.createQuarterlyPeriod(),
            rollConvention: Schedule.RollConventionEnum.NONE,
            rollDay: 0,
            stubType: Schedule.StubTypeEnum.NONE,
            adjustments: createNoAdjustments()
        });

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertFalse(result.hasStub, "Should not have stub period");
        for (uint256 i = 0; i < result.numberOfPeriods; i++) {
            assertFalse(result.periods[i].isStub, "No period should be stub");
        }
    }

    // =============================================================================
    // ROLL CONVENTION TESTS
    // =============================================================================

    function test_AddPeriod_EndOfMonth() public {
        // Jan 31, 2024 + 1 month with EOM roll = Feb 29, 2024 (leap year)
        uint256 jan31 = DateTime.toTimestamp(2024, 1, 31);
        Period memory oneMonth = Schedule.createPeriod(1, PeriodEnum.MONTH);

        uint256 result = Schedule.addPeriod(
            jan31,
            oneMonth,
            Schedule.RollConventionEnum.END_OF_MONTH,
            0
        );

        // Should roll to end of February (Feb 29 in leap year)
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year 2024");
        assertEq(month, 2, "Month February");
        assertEq(day, 29, "Day 29 (leap year end of month)");
    }

    function test_AddPeriod_DayOfMonth() public {
        // Jan 15, 2024 + 1 month with day-of-month 15 roll = Feb 15, 2024
        uint256 jan15 = DateTime.toTimestamp(2024, 1, 15);
        Period memory oneMonth = Schedule.createPeriod(1, PeriodEnum.MONTH);

        uint256 result = Schedule.addPeriod(
            jan15,
            oneMonth,
            Schedule.RollConventionEnum.DAY_OF_MONTH,
            15
        );

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year 2024");
        assertEq(month, 2, "Month February");
        assertEq(day, 15, "Day 15");
    }

    function test_AddPeriod_DayOfMonth_ClampToMonthEnd() public {
        // Jan 31, 2024 + 1 month with day-of-month 31 roll = Feb 29, 2024
        // (Feb only has 29 days in 2024, so clamps to end of month)
        uint256 jan31 = DateTime.toTimestamp(2024, 1, 31);
        Period memory oneMonth = Schedule.createPeriod(1, PeriodEnum.MONTH);

        uint256 result = Schedule.addPeriod(
            jan31,
            oneMonth,
            Schedule.RollConventionEnum.DAY_OF_MONTH,
            31
        );

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year 2024");
        assertEq(month, 2, "Month February");
        assertEq(day, 29, "Day 29 (clamped to month end)");
    }

    function test_AddPeriod_NoRollConvention() public {
        uint256 jan15 = DateTime.toTimestamp(2024, 1, 15);
        Period memory oneMonth = Schedule.createPeriod(1, PeriodEnum.MONTH);

        uint256 result = Schedule.addPeriod(
            jan15,
            oneMonth,
            Schedule.RollConventionEnum.NONE,
            0
        );

        // Should just add 1 month without any roll adjustment
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year 2024");
        assertEq(month, 2, "Month February");
        assertEq(day, 15, "Day 15 (no roll adjustment)");
    }

    // =============================================================================
    // PERIOD ADDITION TESTS
    // =============================================================================

    function test_AddPeriod_Days() public {
        Period memory tenDays = Schedule.createPeriod(10, PeriodEnum.DAY);

        uint256 result = Schedule.addPeriod(
            JAN_1_2024,
            tenDays,
            Schedule.RollConventionEnum.NONE,
            0
        );

        assertEq(result, JAN_1_2024 + 10 days, "Should add 10 days");
    }

    function test_AddPeriod_Weeks() public {
        Period memory twoWeeks = Schedule.createPeriod(2, PeriodEnum.WEEK);

        uint256 result = Schedule.addPeriod(
            JAN_1_2024,
            twoWeeks,
            Schedule.RollConventionEnum.NONE,
            0
        );

        assertEq(result, JAN_1_2024 + 14 days, "Should add 14 days (2 weeks)");
    }

    function test_AddPeriod_Months() public {
        Period memory threeMonths = Schedule.createPeriod(3, PeriodEnum.MONTH);

        uint256 result = Schedule.addPeriod(
            JAN_1_2024,
            threeMonths,
            Schedule.RollConventionEnum.NONE,
            0
        );

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year 2024");
        assertEq(month, 4, "Month April");
        assertEq(day, 1, "Day 1");
    }

    function test_AddPeriod_Years() public {
        Period memory oneYear = Schedule.createPeriod(1, PeriodEnum.YEAR);

        uint256 result = Schedule.addPeriod(
            JAN_1_2024,
            oneYear,
            Schedule.RollConventionEnum.NONE,
            0
        );

        assertEq(result, JAN_1_2025, "Should add 1 year");
    }

    // =============================================================================
    // HELPER FUNCTION TESTS
    // =============================================================================

    function test_CreatePeriod() public {
        Period memory period = Schedule.createPeriod(3, PeriodEnum.MONTH);

        assertEq(period.periodMultiplier, 3, "Multiplier is 3");
        assertTrue(uint8(period.period) == uint8(PeriodEnum.MONTH), "Period is MONTH");
    }

    function test_CreateQuarterlyPeriod() public {
        Period memory period = Schedule.createQuarterlyPeriod();

        assertEq(period.periodMultiplier, 3, "Quarterly = 3 months");
        assertTrue(uint8(period.period) == uint8(PeriodEnum.MONTH), "Period is MONTH");
    }

    function test_CreateSemiAnnualPeriod() public {
        Period memory period = Schedule.createSemiAnnualPeriod();

        assertEq(period.periodMultiplier, 6, "Semi-annual = 6 months");
        assertTrue(uint8(period.period) == uint8(PeriodEnum.MONTH), "Period is MONTH");
    }

    function test_CreateAnnualPeriod() public {
        Period memory period = Schedule.createAnnualPeriod();

        assertEq(period.periodMultiplier, 12, "Annual = 12 months");
        assertTrue(uint8(period.period) == uint8(PeriodEnum.MONTH), "Period is MONTH");
    }

    function test_CreateMonthlyPeriod() public {
        Period memory period = Schedule.createMonthlyPeriod();

        assertEq(period.periodMultiplier, 1, "Monthly = 1 month");
        assertTrue(uint8(period.period) == uint8(PeriodEnum.MONTH), "Period is MONTH");
    }

    function test_GetTotalDays() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createQuarterlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);
        uint256 totalDays = Schedule.getTotalDays(result);

        // Should be approximately 366 days (2024 is leap year)
        assertTrue(totalDays >= 365 && totalDays <= 367, "Total days in range");
    }

    function test_GetFirstPeriod() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createQuarterlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);
        Schedule.CalculationPeriod memory firstPeriod = Schedule.getFirstPeriod(result);

        assertEq(firstPeriod.startDate, JAN_1_2024, "First period starts at effective date");
    }

    function test_GetLastPeriod() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createQuarterlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);
        Schedule.CalculationPeriod memory lastPeriod = Schedule.getLastPeriod(result);

        assertEq(lastPeriod.endDate, JAN_1_2025, "Last period ends at termination date");
    }

    function test_IsRegularPeriod() public {
        Schedule.CalculationPeriod memory period = Schedule.CalculationPeriod({
            startDate: JAN_1_2024,
            endDate: APR_1_2024,
            unadjustedStartDate: JAN_1_2024,
            unadjustedEndDate: APR_1_2024,
            numberOfDays: 91,
            isStub: false
        });

        assertTrue(Schedule.isRegularPeriod(period), "Regular period (not stub)");
    }

    function test_ValidateSchedule() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createQuarterlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertTrue(Schedule.validateSchedule(result), "Schedule should be valid");
    }

    // =============================================================================
    // REAL-WORLD SCENARIOS
    // =============================================================================

    function test_RealWorld_FiveYearSwapQuarterly() public {
        // 5-year IRS with quarterly payments
        uint256 effectiveDate = JAN_1_2024;
        uint256 terminationDate = JAN_1_2024 + (5 * 365 days);

        Schedule.ScheduleParameters memory params = createBasicParams(
            effectiveDate,
            terminationDate,
            Schedule.createQuarterlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 20, "5 years * 4 quarters = 20 periods");

        // Verify periods are contiguous
        for (uint256 i = 0; i < result.numberOfPeriods - 1; i++) {
            assertEq(
                result.periods[i].endDate,
                result.periods[i + 1].startDate,
                "Periods should be contiguous"
            );
        }
    }

    function test_RealWorld_BondSemiAnnual() public {
        // 10-year bond with semi-annual coupons
        uint256 effectiveDate = JAN_1_2024;
        uint256 terminationDate = JAN_1_2024 + (10 * 365 days);

        Schedule.ScheduleParameters memory params = createBasicParams(
            effectiveDate,
            terminationDate,
            Schedule.createSemiAnnualPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 20, "10 years * 2 = 20 semi-annual periods");
    }

    function test_RealWorld_MonthlyPayments() public {
        // 1-year loan with monthly payments
        uint256 effectiveDate = JAN_1_2024;
        uint256 terminationDate = JAN_1_2025;

        Schedule.ScheduleParameters memory params = createBasicParams(
            effectiveDate,
            terminationDate,
            Schedule.createMonthlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 12, "12 monthly periods in 1 year");
    }

    function test_RealWorld_EndOfMonthRoll() public {
        // Schedule starting at month end with EOM roll convention
        uint256 jan31 = DateTime.toTimestamp(2024, 1, 31);
        uint256 apr30 = DateTime.toTimestamp(2024, 4, 30);

        Schedule.ScheduleParameters memory params = Schedule.ScheduleParameters({
            effectiveDate: jan31,
            terminationDate: apr30,
            frequency: Schedule.createMonthlyPeriod(),
            rollConvention: Schedule.RollConventionEnum.END_OF_MONTH,
            rollDay: 0,
            stubType: Schedule.StubTypeEnum.NONE,
            adjustments: createNoAdjustments()
        });

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        // Should roll to end of each month: Jan 31 -> Feb 29 -> Mar 31 -> Apr 30
        assertEq(result.numberOfPeriods, 3, "3 monthly periods");

        // Check February period ends on Feb 29 (leap year)
        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result.periods[0].endDate);
        assertEq(month, 2, "First period ends in February");
        assertEq(day, 29, "February 29 (leap year end of month)");
    }

    // =============================================================================
    // EDGE CASES
    // =============================================================================

    function test_EdgeCase_SinglePeriod() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            APR_1_2024,
            Schedule.createQuarterlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 1, "Single period");
        assertEq(result.periods[0].startDate, JAN_1_2024, "Starts at effective");
        assertEq(result.periods[0].endDate, APR_1_2024, "Ends at termination");
    }

    function test_EdgeCase_VeryShortPeriod() public {
        uint256 twoDaysLater = JAN_1_2024 + 2 days;

        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            twoDaysLater,
            Schedule.createPeriod(1, PeriodEnum.DAY)
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        assertEq(result.numberOfPeriods, 2, "2 daily periods");
    }

    function test_EdgeCase_LeapYearFebruary() public {
        // Schedule crossing leap day
        uint256 feb1 = DateTime.toTimestamp(2024, 2, 1);
        uint256 mar1 = DateTime.toTimestamp(2024, 3, 1);

        Schedule.ScheduleParameters memory params = createBasicParams(
            feb1,
            mar1,
            Schedule.createMonthlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        // February 2024 has 29 days (leap year)
        assertEq(result.numberOfPeriods, 1, "1 monthly period");
        assertEq(result.periods[0].numberOfDays, 29, "29 days in February 2024");
    }

    function test_EdgeCase_YearBoundary() public {
        uint256 dec15_2024 = DateTime.toTimestamp(2024, 12, 15);
        uint256 jan15_2025 = DateTime.toTimestamp(2025, 1, 15);

        Schedule.ScheduleParameters memory params = createBasicParams(
            dec15_2024,
            jan15_2025,
            Schedule.createMonthlyPeriod()
        );

        Schedule.ScheduleResult memory result = Schedule.generateSchedule(params);

        // Should handle year boundary correctly
        assertEq(result.numberOfPeriods, 1, "1 period crossing year boundary");
    }

    function test_GetEndOfMonth_January() public {
        uint256 jan15 = DateTime.toTimestamp(2024, 1, 15);
        uint256 result = Schedule.getEndOfMonth(jan15);

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year 2024");
        assertEq(month, 1, "Month January");
        assertEq(day, 31, "Day 31 (end of January)");
    }

    function test_GetEndOfMonth_February() public {
        uint256 feb15 = DateTime.toTimestamp(2024, 2, 15);
        uint256 result = Schedule.getEndOfMonth(feb15);

        (uint256 year, uint256 month, uint256 day) = DateTime.parseDate(result);
        assertEq(year, 2024, "Year 2024");
        assertEq(month, 2, "Month February");
        assertEq(day, 29, "Day 29 (leap year)");
    }

    function test_EstimateNumberOfPeriods() public {
        uint256 estimate = Schedule.estimateNumberOfPeriods(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createQuarterlyPeriod()
        );

        // Should estimate around 4 quarterly periods
        assertTrue(estimate >= 4 && estimate <= 5, "Estimate should be close to 4");
    }

    // =============================================================================
    // ERROR CASES
    // =============================================================================

    // External wrappers for revert testing
    function externalGenerateSchedule(
        Schedule.ScheduleParameters memory params
    ) external pure returns (Schedule.ScheduleResult memory) {
        return Schedule.generateSchedule(params);
    }

    function externalAdjustToRollDay(
        uint256 date,
        uint8 rollDay
    ) external pure returns (uint256) {
        return Schedule.adjustToRollDay(date, rollDay);
    }

    function test_RevertWhen_InvalidDates() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2025,  // End before start
            JAN_1_2024,
            Schedule.createQuarterlyPeriod()
        );

        try this.externalGenerateSchedule(params) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, Schedule.Schedule__InvalidDates.selector, "Wrong error");
        }
    }

    function test_RevertWhen_ZeroFrequency() public {
        Schedule.ScheduleParameters memory params = createBasicParams(
            JAN_1_2024,
            JAN_1_2025,
            Schedule.createPeriod(0, PeriodEnum.MONTH)  // Zero multiplier
        );

        try this.externalGenerateSchedule(params) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, Schedule.Schedule__InvalidFrequency.selector, "Wrong error");
        }
    }

    function test_RevertWhen_InvalidRollDay() public {
        uint256 jan15 = DateTime.toTimestamp(2024, 1, 15);

        // Test roll day 0 (invalid)
        try this.externalAdjustToRollDay(jan15, 0) {
            fail("Expected revert for roll day 0");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, Schedule.Schedule__InvalidRollDay.selector, "Wrong error for roll day 0");
        }

        // Test roll day 32 (invalid)
        try this.externalAdjustToRollDay(jan15, 32) {
            fail("Expected revert for roll day 32");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, Schedule.Schedule__InvalidRollDay.selector, "Wrong error for roll day 32");
        }
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function createBasicParams(
        uint256 effectiveDate,
        uint256 terminationDate,
        Period memory frequency
    ) internal pure returns (Schedule.ScheduleParameters memory) {
        return Schedule.ScheduleParameters({
            effectiveDate: effectiveDate,
            terminationDate: terminationDate,
            frequency: frequency,
            rollConvention: Schedule.RollConventionEnum.NONE,
            rollDay: 0,
            stubType: Schedule.StubTypeEnum.NONE,
            adjustments: createNoAdjustments()
        });
    }

    function createNoAdjustments() internal pure returns (BusinessDayAdjustments memory) {
        return BusinessDayAdjustments({
            convention: BusinessDayConventionEnum.NONE,
            businessCenters: new BusinessCenterEnum[](0)
        });
    }
}
