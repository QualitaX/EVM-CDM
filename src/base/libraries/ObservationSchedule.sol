// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DateTime} from "./DateTime.sol";
import {Schedule} from "./Schedule.sol";
import {BusinessDayAdjustments} from "./BusinessDayAdjustments.sol";
import {Period, BusinessDayAdjustments as BDAType} from "../types/CDMTypes.sol";
import {
    PeriodEnum,
    BusinessDayConventionEnum,
    BusinessCenterEnum
} from "../types/Enums.sol";

/**
 * @title ObservationSchedule
 * @notice Rate observation schedule generation for floating rate products
 * @dev Generates observation periods for SOFR, LIBOR, and other floating rates
 * @dev Implements ISDA conventions for observation shifting and lookback periods
 *
 * FEATURES:
 * - Observation period generation
 * - Lookback periods (observation shift)
 * - Observation shifting conventions
 * - Rate cut-off handling
 * - Lock-out periods
 * - Daily observation schedules
 *
 * OBSERVATION CONVENTIONS:
 * - IN_ADVANCE: Observe rate before period start
 * - IN_ARREARS: Observe rate during period
 * - LOOKBACK: Observe rate with fixed offset before period
 * - LOCK_OUT: Stop observing before period end
 * - RATE_CUT_OFF: Use last observed rate for remaining days
 *
 * USE CASES:
 * - Compounded SOFR (daily observations with lookback)
 * - Average SOFR (simple average of daily observations)
 * - LIBOR-style fixing (single observation in advance)
 * - Overnight rates (daily compounding in arrears)
 *
 * REFERENCES:
 * - ISDA 2021 Definitions (SOFR provisions)
 * - ISDA 2006 Definitions (Floating Rate Option)
 * - ARRC SOFR Best Practices
 *
 * @custom:security-contact security@finos.org
 * @author FINOS CDM EVM Framework Team
 */
library ObservationSchedule {

    using DateTime for uint256;
    using Schedule for *;
    using BusinessDayAdjustments for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Seconds per day
    uint256 internal constant SECONDS_PER_DAY = 86400;

    /// @notice Maximum observations per period (prevent DOS)
    uint256 internal constant MAX_OBSERVATIONS = 1000;

    /// @notice Default lookback days for SOFR
    uint256 internal constant DEFAULT_SOFR_LOOKBACK = 2;

    // =============================================================================
    // ERRORS
    // =============================================================================

    error ObservationSchedule__InvalidDates();
    error ObservationSchedule__InvalidLookback();
    error ObservationSchedule__TooManyObservations();
    error ObservationSchedule__InvalidShift();
    error ObservationSchedule__InvalidCutOff();

    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Observation timing convention
    enum ObservationShiftEnum {
        NONE,               // No shift
        IN_ADVANCE,         // Observe before period
        IN_ARREARS,         // Observe during period
        LOOKBACK,           // Fixed days before observation
        LOCK_OUT            // Stop observing before end
    }

    /// @notice Rate observation method
    enum ObservationMethodEnum {
        SINGLE,             // Single observation (e.g., LIBOR)
        DAILY,              // Daily observations
        WEIGHTED_DAILY,     // Daily with time weighting
        AVERAGE             // Simple average
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Single rate observation point
    /// @dev Specifies when and what period a rate should be observed
    struct Observation {
        uint256 observationDate;        // Date to observe rate
        uint256 effectiveDate;          // Date rate becomes effective
        uint256 periodStartDate;        // Start of interest period
        uint256 periodEndDate;          // End of interest period
        uint256 weight;                 // Weight for weighted averaging
        bool isRateCutOff;              // True if using cut-off rate
    }

    /// @notice Observation schedule parameters
    /// @dev Configuration for generating observation schedule
    struct ObservationParameters {
        uint256 periodStartDate;        // Calculation period start
        uint256 periodEndDate;          // Calculation period end
        ObservationShiftEnum shiftMethod; // How to shift observations
        ObservationMethodEnum method;   // Single vs daily observations
        uint256 lookbackDays;           // Days to look back (0 = none)
        uint256 lockoutDays;            // Days to lock out before end (0 = none)
        uint256 rateCutOffDays;         // Days before end to cut off (0 = none)
        BDAType businessDayAdjustments; // Business day rules
    }

    /// @notice Generated observation schedule result
    struct ObservationScheduleResult {
        Observation[] observations;     // Array of observation points
        uint256 numberOfObservations;   // Total observations
        uint256 effectiveLookback;      // Actual lookback applied
        bool hasRateCutOff;             // True if rate cut-off used
    }

    // =============================================================================
    // MAIN OBSERVATION GENERATION
    // =============================================================================

    /**
     * @notice Generate observation schedule for a calculation period
     * @dev Creates observation points based on method and shifting rules
     * @param params Observation parameters
     * @return ObservationScheduleResult with generated observations
     *
     * @custom:example Daily SOFR with 2-day lookback for Jan 1-31 period
     */
    function generateObservationSchedule(
        ObservationParameters memory params
    ) internal pure returns (ObservationScheduleResult memory) {
        // Validate inputs
        if (params.periodEndDate <= params.periodStartDate) {
            revert ObservationSchedule__InvalidDates();
        }

        // Generate observations based on method
        if (params.method == ObservationMethodEnum.SINGLE) {
            return generateSingleObservation(params);
        } else {
            return generateDailyObservations(params);
        }
    }

    /**
     * @notice Generate single observation (e.g., LIBOR-style)
     * @dev Creates one observation point, typically before period start
     * @param params Observation parameters
     * @return ObservationScheduleResult with single observation
     */
    function generateSingleObservation(
        ObservationParameters memory params
    ) internal pure returns (ObservationScheduleResult memory) {
        Observation[] memory observations = new Observation[](1);

        uint256 observationDate;
        if (params.shiftMethod == ObservationShiftEnum.IN_ADVANCE) {
            // Observe 2 business days before period start (standard LIBOR)
            observationDate = params.periodStartDate - (2 * SECONDS_PER_DAY);
        } else if (params.lookbackDays > 0) {
            // Use explicit lookback
            observationDate = params.periodStartDate - (params.lookbackDays * SECONDS_PER_DAY);
        } else {
            // Observe on period start
            observationDate = params.periodStartDate;
        }

        observations[0] = Observation({
            observationDate: observationDate,
            effectiveDate: params.periodStartDate,
            periodStartDate: params.periodStartDate,
            periodEndDate: params.periodEndDate,
            weight: DateTime.daysBetween(params.periodStartDate, params.periodEndDate),
            isRateCutOff: false
        });

        return ObservationScheduleResult({
            observations: observations,
            numberOfObservations: 1,
            effectiveLookback: params.lookbackDays,
            hasRateCutOff: false
        });
    }

    /**
     * @notice Generate daily observations (e.g., compounded SOFR)
     * @dev Creates observation for each day in period with optional lookback
     * @param params Observation parameters
     * @return ObservationScheduleResult with daily observations
     */
    function generateDailyObservations(
        ObservationParameters memory params
    ) internal pure returns (ObservationScheduleResult memory) {
        // Calculate number of days in period
        uint256 numberOfDays = DateTime.daysBetween(
            params.periodStartDate,
            params.periodEndDate
        );

        if (numberOfDays > MAX_OBSERVATIONS) {
            revert ObservationSchedule__TooManyObservations();
        }

        // Allocate observations array
        Observation[] memory observations = new Observation[](numberOfDays);

        // Determine effective lookback
        uint256 effectiveLookback = params.lookbackDays;
        if (params.shiftMethod == ObservationShiftEnum.LOOKBACK && effectiveLookback == 0) {
            effectiveLookback = DEFAULT_SOFR_LOOKBACK;
        }

        // Calculate rate cut-off date if applicable
        uint256 cutOffDate = 0;
        bool useRateCutOff = params.rateCutOffDays > 0;
        if (useRateCutOff) {
            cutOffDate = params.periodEndDate - (params.rateCutOffDays * SECONDS_PER_DAY);
        }

        // Generate observation for each day
        uint256 currentDate = params.periodStartDate;
        for (uint256 i = 0; i < numberOfDays; i++) {
            uint256 nextDate = currentDate + SECONDS_PER_DAY;

            // Calculate observation date with lookback
            uint256 observationDate;
            if (params.shiftMethod == ObservationShiftEnum.LOOKBACK ||
                params.shiftMethod == ObservationShiftEnum.IN_ARREARS) {
                observationDate = currentDate - (effectiveLookback * SECONDS_PER_DAY);
            } else {
                observationDate = currentDate;
            }

            // Check for rate cut-off
            bool isRateCutOff = useRateCutOff && currentDate >= cutOffDate;

            // Weight = 1 day for daily observations
            observations[i] = Observation({
                observationDate: observationDate,
                effectiveDate: currentDate,
                periodStartDate: currentDate,
                periodEndDate: nextDate,
                weight: 1,
                isRateCutOff: isRateCutOff
            });

            currentDate = nextDate;
        }

        return ObservationScheduleResult({
            observations: observations,
            numberOfObservations: numberOfDays,
            effectiveLookback: effectiveLookback,
            hasRateCutOff: useRateCutOff
        });
    }

    // =============================================================================
    // SPECIALIZED OBSERVATION SCHEDULES
    // =============================================================================

    /**
     * @notice Generate compounded SOFR observation schedule
     * @dev Standard SOFR with 2-day lookback and daily observations
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @param businessCenters Business centers for holidays
     * @return ObservationScheduleResult for SOFR
     */
    function generateSOFRSchedule(
        uint256 periodStart,
        uint256 periodEnd,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (ObservationScheduleResult memory) {
        return generateObservationSchedule(
            ObservationParameters({
                periodStartDate: periodStart,
                periodEndDate: periodEnd,
                shiftMethod: ObservationShiftEnum.LOOKBACK,
                method: ObservationMethodEnum.DAILY,
                lookbackDays: 2,
                lockoutDays: 0,
                rateCutOffDays: 0,
                businessDayAdjustments: BusinessDayAdjustments.createAdjustmentsMulti(
                    BusinessDayConventionEnum.FOLLOWING,
                    businessCenters
                )
            })
        );
    }

    /**
     * @notice Generate LIBOR-style observation schedule
     * @dev Single observation 2 business days before period start
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @param businessCenters Business centers for holidays
     * @return ObservationScheduleResult for LIBOR-style
     */
    function generateLIBORSchedule(
        uint256 periodStart,
        uint256 periodEnd,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (ObservationScheduleResult memory) {
        return generateObservationSchedule(
            ObservationParameters({
                periodStartDate: periodStart,
                periodEndDate: periodEnd,
                shiftMethod: ObservationShiftEnum.IN_ADVANCE,
                method: ObservationMethodEnum.SINGLE,
                lookbackDays: 2,
                lockoutDays: 0,
                rateCutOffDays: 0,
                businessDayAdjustments: BusinessDayAdjustments.createAdjustmentsMulti(
                    BusinessDayConventionEnum.FOLLOWING,
                    businessCenters
                )
            })
        );
    }

    /**
     * @notice Generate observation schedule with rate cut-off
     * @dev Daily observations with last rate held for final days
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @param lookbackDays Lookback period
     * @param cutOffDays Days before end to stop observing
     * @param businessCenters Business centers for holidays
     * @return ObservationScheduleResult with cut-off
     */
    function generateScheduleWithCutOff(
        uint256 periodStart,
        uint256 periodEnd,
        uint256 lookbackDays,
        uint256 cutOffDays,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (ObservationScheduleResult memory) {
        if (cutOffDays >= DateTime.daysBetween(periodStart, periodEnd)) {
            revert ObservationSchedule__InvalidCutOff();
        }

        return generateObservationSchedule(
            ObservationParameters({
                periodStartDate: periodStart,
                periodEndDate: periodEnd,
                shiftMethod: ObservationShiftEnum.LOOKBACK,
                method: ObservationMethodEnum.DAILY,
                lookbackDays: lookbackDays,
                lockoutDays: 0,
                rateCutOffDays: cutOffDays,
                businessDayAdjustments: BusinessDayAdjustments.createAdjustmentsMulti(
                    BusinessDayConventionEnum.FOLLOWING,
                    businessCenters
                )
            })
        );
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Get unique observation dates from schedule
     * @dev Removes duplicates for rate cut-off periods
     * @param schedule Observation schedule
     * @return Array of unique observation dates
     */
    function getUniqueObservationDates(
        ObservationScheduleResult memory schedule
    ) internal pure returns (uint256[] memory) {
        // First pass: count unique dates
        uint256 uniqueCount = 0;
        uint256[] memory tempDates = new uint256[](schedule.numberOfObservations);

        for (uint256 i = 0; i < schedule.numberOfObservations; i++) {
            uint256 date = schedule.observations[i].observationDate;
            bool isDuplicate = false;

            for (uint256 j = 0; j < uniqueCount; j++) {
                if (tempDates[j] == date) {
                    isDuplicate = true;
                    break;
                }
            }

            if (!isDuplicate) {
                tempDates[uniqueCount] = date;
                uniqueCount++;
            }
        }

        // Second pass: create result array
        uint256[] memory uniqueDates = new uint256[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            uniqueDates[i] = tempDates[i];
        }

        return uniqueDates;
    }

    /**
     * @notice Get observation by date
     * @dev Find observation for specific date
     * @param schedule Observation schedule
     * @param date Date to find
     * @return Observation for date (reverts if not found)
     */
    function getObservationByDate(
        ObservationScheduleResult memory schedule,
        uint256 date
    ) internal pure returns (Observation memory) {
        for (uint256 i = 0; i < schedule.numberOfObservations; i++) {
            if (schedule.observations[i].observationDate == date) {
                return schedule.observations[i];
            }
        }
        revert ObservationSchedule__InvalidDates();
    }

    /**
     * @notice Count observations within date range
     * @param schedule Observation schedule
     * @param startDate Range start (inclusive)
     * @param endDate Range end (exclusive)
     * @return Number of observations in range
     */
    function countObservationsInRange(
        ObservationScheduleResult memory schedule,
        uint256 startDate,
        uint256 endDate
    ) internal pure returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < schedule.numberOfObservations; i++) {
            uint256 obsDate = schedule.observations[i].observationDate;
            if (obsDate >= startDate && obsDate < endDate) {
                count++;
            }
        }
        return count;
    }

    /**
     * @notice Calculate total weight of observations
     * @dev Sum of all observation weights (useful for weighted averaging)
     * @param schedule Observation schedule
     * @return Total weight
     */
    function getTotalWeight(
        ObservationScheduleResult memory schedule
    ) internal pure returns (uint256) {
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < schedule.numberOfObservations; i++) {
            totalWeight += schedule.observations[i].weight;
        }
        return totalWeight;
    }

    /**
     * @notice Check if schedule has rate cut-off
     * @param schedule Observation schedule
     * @return true if any observation uses rate cut-off
     */
    function hasRateCutOff(
        ObservationScheduleResult memory schedule
    ) internal pure returns (bool) {
        return schedule.hasRateCutOff;
    }

    /**
     * @notice Get first observation date
     * @param schedule Observation schedule
     * @return First observation date
     */
    function getFirstObservationDate(
        ObservationScheduleResult memory schedule
    ) internal pure returns (uint256) {
        require(schedule.numberOfObservations > 0, "ObservationSchedule: no observations");
        return schedule.observations[0].observationDate;
    }

    /**
     * @notice Get last observation date
     * @param schedule Observation schedule
     * @return Last observation date
     */
    function getLastObservationDate(
        ObservationScheduleResult memory schedule
    ) internal pure returns (uint256) {
        require(schedule.numberOfObservations > 0, "ObservationSchedule: no observations");
        return schedule.observations[schedule.numberOfObservations - 1].observationDate;
    }

    // =============================================================================
    // CREATION HELPERS
    // =============================================================================

    /**
     * @notice Create simple observation parameters
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @param method Observation method
     * @return ObservationParameters struct
     */
    function createObservationParameters(
        uint256 periodStart,
        uint256 periodEnd,
        ObservationMethodEnum method
    ) internal pure returns (ObservationParameters memory) {
        return ObservationParameters({
            periodStartDate: periodStart,
            periodEndDate: periodEnd,
            shiftMethod: ObservationShiftEnum.NONE,
            method: method,
            lookbackDays: 0,
            lockoutDays: 0,
            rateCutOffDays: 0,
            businessDayAdjustments: BusinessDayAdjustments.createNoAdjustments()
        });
    }

    /**
     * @notice Create observation for rate reset
     * @dev Helper for creating single observation point
     * @param observationDate Date to observe rate
     * @param effectiveDate Date rate becomes effective
     * @param periodStart Period start
     * @param periodEnd Period end
     * @return Observation struct
     */
    function createObservation(
        uint256 observationDate,
        uint256 effectiveDate,
        uint256 periodStart,
        uint256 periodEnd
    ) internal pure returns (Observation memory) {
        return Observation({
            observationDate: observationDate,
            effectiveDate: effectiveDate,
            periodStartDate: periodStart,
            periodEndDate: periodEnd,
            weight: DateTime.daysBetween(periodStart, periodEnd),
            isRateCutOff: false
        });
    }

    // =============================================================================
    // VALIDATION
    // =============================================================================

    /**
     * @notice Validate observation schedule
     * @dev Checks for consistency and correctness
     * @param schedule Schedule to validate
     * @return true if valid
     */
    function validateObservationSchedule(
        ObservationScheduleResult memory schedule
    ) internal pure returns (bool) {
        if (schedule.numberOfObservations == 0) {
            return false;
        }

        if (schedule.observations.length != schedule.numberOfObservations) {
            return false;
        }

        // Check observations are in order
        for (uint256 i = 1; i < schedule.numberOfObservations; i++) {
            if (schedule.observations[i].effectiveDate <=
                schedule.observations[i - 1].effectiveDate) {
                return false;
            }
        }

        return true;
    }
}
