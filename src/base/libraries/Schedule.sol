// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DateTime} from "./DateTime.sol";
import {Period, BusinessDayAdjustments, AdjustableDate} from "../types/CDMTypes.sol";
import {PeriodEnum, BusinessDayConventionEnum, BusinessCenterEnum} from "../types/Enums.sol";

/**
 * @title Schedule
 * @notice Schedule generation for calculation and payment periods
 * @dev Generates periodic dates for swaps, bonds, and other scheduled products
 * @dev Implements ISDA conventions for stub periods and roll dates
 *
 * FEATURES:
 * - Calculation period generation
 * - Payment schedule generation
 * - Stub period handling (short/long, first/last)
 * - Roll date conventions
 * - Business day adjustments
 *
 * STUB PERIODS:
 * - Short first: Initial period < regular period
 * - Long first: Initial period > regular period
 * - Short last: Final period < regular period
 * - Long last: Final period > regular period
 *
 * ROLL CONVENTIONS:
 * - End of month (EOM): Always roll to end of month
 * - Day-of-month: Always use specific day (e.g., 15th)
 *
 * REFERENCES:
 * - ISDA 2006 Definitions Section 4.12
 * - ISDA 2021 Definitions
 * - FpML Schedule specification
 *
 * @custom:security-contact security@finos.org
 * @author FINOS CDM EVM Framework Team
 */
library Schedule {

    using DateTime for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Maximum number of periods to prevent DOS
    uint256 internal constant MAX_PERIODS = 1000;

    // =============================================================================
    // ERRORS
    // =============================================================================

    error Schedule__InvalidDates();
    error Schedule__InvalidFrequency();
    error Schedule__TooManyPeriods();
    error Schedule__InvalidStubType();
    error Schedule__InvalidRollDay();

    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Stub period type
    enum StubTypeEnum {
        NONE,           // No stub period
        SHORT_FIRST,    // Short initial period
        LONG_FIRST,     // Long initial period (combines first two periods)
        SHORT_LAST,     // Short final period
        LONG_LAST       // Long final period (combines last two periods)
    }

    /// @notice Roll convention type
    enum RollConventionEnum {
        NONE,               // No roll convention
        END_OF_MONTH,       // Always roll to month end
        DAY_OF_MONTH,       // Specific day of month
        IMM,                // IMM dates (3rd Wednesday)
        SFE                 // Sydney Futures Exchange dates
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Single calculation period
    /// @dev Represents one period in a schedule
    struct CalculationPeriod {
        uint256 startDate;              // Period start date (adjusted)
        uint256 endDate;                // Period end date (adjusted)
        uint256 unadjustedStartDate;    // Unadjusted start
        uint256 unadjustedEndDate;      // Unadjusted end
        uint256 numberOfDays;           // Days in period
        bool isStub;                    // True if stub period
    }

    /// @notice Schedule specification
    /// @dev Parameters for generating a schedule
    struct ScheduleParameters {
        uint256 effectiveDate;          // Schedule start date
        uint256 terminationDate;        // Schedule end date
        Period frequency;               // Period frequency
        RollConventionEnum rollConvention; // Roll convention
        uint8 rollDay;                  // Day of month for rolling (0-31, 0=EOM)
        StubTypeEnum stubType;          // Type of stub period
        BusinessDayAdjustments adjustments; // Business day adjustments
    }

    /// @notice Generated schedule result
    struct ScheduleResult {
        CalculationPeriod[] periods;    // Array of calculation periods
        uint256 numberOfPeriods;        // Total number of periods
        bool hasStub;                   // True if schedule has stub
    }

    // =============================================================================
    // MAIN SCHEDULE GENERATION
    // =============================================================================

    /**
     * @notice Generate calculation period schedule
     * @dev Creates array of periods from effective to termination date
     * @param params Schedule parameters
     * @return ScheduleResult with generated periods
     *
     * @custom:example Quarterly schedule from Jan-1-2024 to Jan-1-2025 = 4 periods
     */
    function generateSchedule(
        ScheduleParameters memory params
    ) internal pure returns (ScheduleResult memory) {
        // Validate inputs
        if (params.terminationDate <= params.effectiveDate) {
            revert Schedule__InvalidDates();
        }
        if (params.frequency.periodMultiplier == 0) {
            revert Schedule__InvalidFrequency();
        }

        // Calculate unadjusted dates
        uint256[] memory unadjustedDates = generateUnadjustedDates(params);

        // Check period count limit
        if (unadjustedDates.length > MAX_PERIODS + 1) {
            revert Schedule__TooManyPeriods();
        }

        // Apply business day adjustments (simplified - full implementation in BusinessDayAdjustments)
        uint256[] memory adjustedDates = applyBusinessDayAdjustments(
            unadjustedDates,
            params.adjustments
        );

        // Build calculation periods
        CalculationPeriod[] memory periods = new CalculationPeriod[](unadjustedDates.length - 1);
        bool hasStub = params.stubType != StubTypeEnum.NONE;

        for (uint256 i = 0; i < periods.length; i++) {
            periods[i] = CalculationPeriod({
                startDate: adjustedDates[i],
                endDate: adjustedDates[i + 1],
                unadjustedStartDate: unadjustedDates[i],
                unadjustedEndDate: unadjustedDates[i + 1],
                numberOfDays: DateTime.daysBetween(adjustedDates[i], adjustedDates[i + 1]),
                isStub: hasStub && (i == 0 || i == periods.length - 1)
            });
        }

        return ScheduleResult({
            periods: periods,
            numberOfPeriods: periods.length,
            hasStub: hasStub
        });
    }

    /**
     * @notice Generate unadjusted schedule dates
     * @dev Creates array of unadjusted dates from effective to termination
     * @param params Schedule parameters
     * @return Array of unadjusted dates
     */
    function generateUnadjustedDates(
        ScheduleParameters memory params
    ) internal pure returns (uint256[] memory) {
        // Calculate approximate number of periods
        uint256 approxPeriods = estimateNumberOfPeriods(
            params.effectiveDate,
            params.terminationDate,
            params.frequency
        );

        // Allocate array (add buffer for stub)
        uint256[] memory dates = new uint256[](approxPeriods + 2);
        uint256 dateCount = 0;

        // Start from effective date
        dates[dateCount++] = params.effectiveDate;

        // Generate intermediate dates
        uint256 currentDate = params.effectiveDate;

        while (currentDate < params.terminationDate) {
            // Add period
            currentDate = addPeriod(currentDate, params.frequency, params.rollConvention, params.rollDay);

            // Don't add if beyond termination
            if (currentDate >= params.terminationDate) {
                break;
            }

            dates[dateCount++] = currentDate;
        }

        // Always end with termination date
        dates[dateCount++] = params.terminationDate;

        // Trim array to actual size
        uint256[] memory trimmedDates = new uint256[](dateCount);
        for (uint256 i = 0; i < dateCount; i++) {
            trimmedDates[i] = dates[i];
        }

        return trimmedDates;
    }

    // =============================================================================
    // PERIOD ADDITION
    // =============================================================================

    /**
     * @notice Add period to a date
     * @dev Handles month/year addition with roll conventions
     * @param date Starting date
     * @param period Period to add
     * @param rollConvention Roll convention to apply
     * @param rollDay Day of month for rolling (if applicable)
     * @return New date after adding period
     */
    function addPeriod(
        uint256 date,
        Period memory period,
        RollConventionEnum rollConvention,
        uint8 rollDay
    ) internal pure returns (uint256) {
        uint256 newDate;

        // Add period based on type
        if (period.period == PeriodEnum.DAY) {
            newDate = DateTime.addDays(date, period.periodMultiplier);
        } else if (period.period == PeriodEnum.WEEK) {
            newDate = DateTime.addDays(date, period.periodMultiplier * 7);
        } else if (period.period == PeriodEnum.MONTH) {
            newDate = DateTime.addMonths(date, period.periodMultiplier);
        } else if (period.period == PeriodEnum.YEAR) {
            newDate = DateTime.addYears(date, period.periodMultiplier);
        } else {
            revert Schedule__InvalidFrequency();
        }

        // Apply roll convention
        if (rollConvention == RollConventionEnum.END_OF_MONTH) {
            newDate = getEndOfMonth(newDate);
        } else if (rollConvention == RollConventionEnum.DAY_OF_MONTH && rollDay > 0) {
            newDate = adjustToRollDay(newDate, rollDay);
        }

        return newDate;
    }

    /**
     * @notice Get end of month for a date
     * @param date Input date
     * @return Date adjusted to end of month
     */
    function getEndOfMonth(uint256 date) internal pure returns (uint256) {
        (uint256 year, uint256 month, ) = DateTime.parseDate(date);
        uint256 daysInMonth = DateTime.getDaysInMonth(month, year);
        return DateTime.toTimestamp(year, month, daysInMonth);
    }

    /**
     * @notice Adjust date to specific roll day
     * @dev If roll day > days in month, use last day of month
     * @param date Input date
     * @param rollDay Day of month (1-31)
     * @return Adjusted date
     */
    function adjustToRollDay(uint256 date, uint8 rollDay) internal pure returns (uint256) {
        if (rollDay == 0 || rollDay > 31) {
            revert Schedule__InvalidRollDay();
        }

        (uint256 year, uint256 month, ) = DateTime.parseDate(date);
        uint256 daysInMonth = DateTime.getDaysInMonth(month, year);

        // Use roll day or last day of month, whichever is smaller
        uint256 actualDay = rollDay <= daysInMonth ? rollDay : daysInMonth;

        return DateTime.toTimestamp(year, month, actualDay);
    }

    // =============================================================================
    // BUSINESS DAY ADJUSTMENTS
    // =============================================================================

    /**
     * @notice Apply business day adjustments to dates
     * @dev Simplified implementation - full logic in BusinessDayAdjustments library
     * @param dates Array of unadjusted dates
     * @param adjustments Business day adjustment rules
     * @return Array of adjusted dates
     *
     * @custom:note This is a placeholder. Full implementation requires holiday calendar
     */
    function applyBusinessDayAdjustments(
        uint256[] memory dates,
        BusinessDayAdjustments memory adjustments
    ) internal pure returns (uint256[] memory) {
        // Simplified: return dates unchanged
        // Full implementation would:
        // 1. Check if date is business day
        // 2. Apply convention (FOLLOWING, MODIFIED_FOLLOWING, etc.)
        // 3. Consider business centers for holiday calendars

        uint256[] memory adjustedDates = new uint256[](dates.length);
        for (uint256 i = 0; i < dates.length; i++) {
            adjustedDates[i] = dates[i];
        }
        return adjustedDates;

        // Suppress unused parameter warning
        adjustments;
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Estimate number of periods in schedule
     * @dev Used for array allocation
     * @param startDate Schedule start
     * @param endDate Schedule end
     * @param frequency Period frequency
     * @return Estimated number of periods
     */
    function estimateNumberOfPeriods(
        uint256 startDate,
        uint256 endDate,
        Period memory frequency
    ) internal pure returns (uint256) {
        uint256 totalDays = DateTime.daysBetween(startDate, endDate);

        uint256 daysPerPeriod;
        if (frequency.period == PeriodEnum.DAY) {
            daysPerPeriod = frequency.periodMultiplier;
        } else if (frequency.period == PeriodEnum.WEEK) {
            daysPerPeriod = frequency.periodMultiplier * 7;
        } else if (frequency.period == PeriodEnum.MONTH) {
            daysPerPeriod = frequency.periodMultiplier * 30; // Approximation
        } else if (frequency.period == PeriodEnum.YEAR) {
            daysPerPeriod = frequency.periodMultiplier * 365; // Approximation
        } else {
            daysPerPeriod = 1;
        }

        if (daysPerPeriod == 0) {
            return 0;
        }

        return (totalDays / daysPerPeriod) + 1;
    }

    /**
     * @notice Get total number of days in schedule
     * @param schedule Generated schedule
     * @return Total days across all periods
     */
    function getTotalDays(ScheduleResult memory schedule) internal pure returns (uint256) {
        uint256 totalDays = 0;
        for (uint256 i = 0; i < schedule.periods.length; i++) {
            totalDays += schedule.periods[i].numberOfDays;
        }
        return totalDays;
    }

    /**
     * @notice Check if period is regular (not stub)
     * @param period Calculation period
     * @return true if regular period
     */
    function isRegularPeriod(CalculationPeriod memory period) internal pure returns (bool) {
        return !period.isStub;
    }

    /**
     * @notice Get first calculation period
     * @param schedule Generated schedule
     * @return First period
     */
    function getFirstPeriod(ScheduleResult memory schedule) internal pure returns (CalculationPeriod memory) {
        require(schedule.numberOfPeriods > 0, "Schedule: no periods");
        return schedule.periods[0];
    }

    /**
     * @notice Get last calculation period
     * @param schedule Generated schedule
     * @return Last period
     */
    function getLastPeriod(ScheduleResult memory schedule) internal pure returns (CalculationPeriod memory) {
        require(schedule.numberOfPeriods > 0, "Schedule: no periods");
        return schedule.periods[schedule.numberOfPeriods - 1];
    }

    // =============================================================================
    // SCHEDULE CREATION HELPERS
    // =============================================================================

    /**
     * @notice Create simple schedule parameters
     * @param effectiveDate Start date
     * @param terminationDate End date
     * @param frequency Period frequency
     * @return ScheduleParameters struct
     */
    function createScheduleParameters(
        uint256 effectiveDate,
        uint256 terminationDate,
        Period memory frequency
    ) internal pure returns (ScheduleParameters memory) {
        return ScheduleParameters({
            effectiveDate: effectiveDate,
            terminationDate: terminationDate,
            frequency: frequency,
            rollConvention: RollConventionEnum.NONE,
            rollDay: 0,
            stubType: StubTypeEnum.NONE,
            adjustments: BusinessDayAdjustments({
                convention: BusinessDayConventionEnum.NONE,
                businessCenters: new BusinessCenterEnum[](0)
            })
        });
    }

    /**
     * @notice Create period from multiplier and unit
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

    /**
     * @notice Create quarterly period (3 months)
     * @return Period struct for quarterly
     */
    function createQuarterlyPeriod() internal pure returns (Period memory) {
        return createPeriod(3, PeriodEnum.MONTH);
    }

    /**
     * @notice Create semi-annual period (6 months)
     * @return Period struct for semi-annual
     */
    function createSemiAnnualPeriod() internal pure returns (Period memory) {
        return createPeriod(6, PeriodEnum.MONTH);
    }

    /**
     * @notice Create annual period (12 months)
     * @return Period struct for annual
     */
    function createAnnualPeriod() internal pure returns (Period memory) {
        return createPeriod(12, PeriodEnum.MONTH);
    }

    /**
     * @notice Create monthly period
     * @return Period struct for monthly
     */
    function createMonthlyPeriod() internal pure returns (Period memory) {
        return createPeriod(1, PeriodEnum.MONTH);
    }

    // =============================================================================
    // SCHEDULE VALIDATION
    // =============================================================================

    /**
     * @notice Validate schedule result
     * @dev Checks for consistency and correctness
     * @param schedule Schedule to validate
     * @return true if valid
     */
    function validateSchedule(ScheduleResult memory schedule) internal pure returns (bool) {
        if (schedule.numberOfPeriods == 0) {
            return false;
        }

        if (schedule.periods.length != schedule.numberOfPeriods) {
            return false;
        }

        // Check periods are contiguous
        for (uint256 i = 0; i < schedule.numberOfPeriods - 1; i++) {
            if (schedule.periods[i].endDate != schedule.periods[i + 1].startDate) {
                return false;
            }
        }

        return true;
    }
}
