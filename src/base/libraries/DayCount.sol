// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DayCountFractionEnum} from "../types/Enums.sol";
import {FixedPoint} from "./FixedPoint.sol";
import {DateTime} from "./DateTime.sol";

/**
 * @title DayCount
 * @notice Day count fraction calculations per ISDA and market conventions
 * @dev Implements all major day count conventions used in financial markets
 * @dev Critical for accurate interest rate calculations
 *
 * CONVENTIONS IMPLEMENTED:
 * - ACT/360: Actual days / 360 (money market basis)
 * - ACT/365 Fixed: Actual days / 365
 * - ACT/ACT ISDA: Actual/Actual ISDA (most accurate)
 * - ACT/ACT ICMA: Actual/Actual ICMA (bond market)
 * - 30/360: 30/360 Bond Basis (US corporate bonds)
 * - 30E/360: 30E/360 Eurobond Basis
 * - 30E/360 ISDA: 30E/360 ISDA variant
 * - ONE/ONE: No accrual (always 1.0)
 *
 * REFERENCES:
 * - ISDA 2006 Definitions
 * - ISDA EMU Protocol
 * - ICMA Rule Book
 * - OpenGamma Strata (reference implementation)
 *
 * @author QualitaX Team
 */
library DayCount {

    using FixedPoint for uint256;
    using DateTime for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Seconds per day
    uint256 private constant SECONDS_PER_DAY = 86400;

    // =============================================================================
    // ERRORS
    // =============================================================================

    error DayCount__InvalidDates();
    error DayCount__UnsupportedConvention();
    error DayCount__InvalidFrequency();

    // =============================================================================
    // MAIN CALCULATION FUNCTION
    // =============================================================================

    /**
     * @notice Calculate day count fraction between two dates
     * @dev Returns fraction in fixed-point (18 decimals)
     * @param convention Day count convention to use
     * @param startDate Start date (Unix timestamp)
     * @param endDate End date (Unix timestamp)
     * @param terminationDate Termination date (for some conventions, 0 if not applicable)
     * @param frequency Payment frequency per year (for ICMA convention, 0 if not applicable)
     * @return Day count fraction (fixed-point, 18 decimals)
     *
     * @custom:example For 30 days with ACT/360: returns 30/360 = 0.083333... = 83333333333333333
     */
    function calculate(
        DayCountFractionEnum convention,
        uint256 startDate,
        uint256 endDate,
        uint256 terminationDate,
        uint256 frequency
    ) internal pure returns (uint256) {
        // Validate dates
        if (endDate < startDate) {
            revert DayCount__InvalidDates();
        }

        // Route to appropriate convention
        if (convention == DayCountFractionEnum.ACT_360) {
            return calculateACT360(startDate, endDate);

        } else if (convention == DayCountFractionEnum.ACT_365_FIXED) {
            return calculateACT365Fixed(startDate, endDate);

        } else if (convention == DayCountFractionEnum.ACT_ACT_ISDA) {
            return calculateACTACTISDA(startDate, endDate);

        } else if (convention == DayCountFractionEnum.ACT_ACT_ICMA) {
            if (frequency == 0) revert DayCount__InvalidFrequency();
            return calculateACTACTICMA(startDate, endDate, terminationDate, frequency);

        } else if (convention == DayCountFractionEnum.THIRTY_360) {
            return calculate30360(startDate, endDate);

        } else if (convention == DayCountFractionEnum.THIRTY_E_360) {
            return calculate30E360(startDate, endDate);

        } else if (convention == DayCountFractionEnum.THIRTY_E_360_ISDA) {
            return calculate30E360ISDA(startDate, endDate, terminationDate);

        } else if (convention == DayCountFractionEnum.ONE_ONE) {
            return FixedPoint.ONE; // Always 1.0

        } else {
            revert DayCount__UnsupportedConvention();
        }
    }

    // =============================================================================
    // ACT/360 - ACTUAL/360
    // =============================================================================

    /**
     * @notice Calculate ACT/360 day count fraction
     * @dev Used in money markets and some floating rate notes
     * @dev Formula: actual_days / 360
     * @param startDate Start date
     * @param endDate End date
     * @return Day count fraction (fixed-point)
     *
     * @custom:example 30 days: 30/360 = 0.083333... = 83333333333333333
     */
    function calculateACT360(
        uint256 startDate,
        uint256 endDate
    ) internal pure returns (uint256) {
        uint256 actualDays = DateTime.daysBetween(startDate, endDate);

        // actualDays / 360 in fixed-point
        // = (actualDays * 1e18) / 360
        return (actualDays * FixedPoint.SCALE) / 360;
    }

    // =============================================================================
    // ACT/365 FIXED - ACTUAL/365 FIXED
    // =============================================================================

    /**
     * @notice Calculate ACT/365 Fixed day count fraction
     * @dev Used in some GBP and commodity markets
     * @dev Formula: actual_days / 365
     * @param startDate Start date
     * @param endDate End date
     * @return Day count fraction (fixed-point)
     *
     * @custom:example 365 days: 365/365 = 1.0 = 1e18
     */
    function calculateACT365Fixed(
        uint256 startDate,
        uint256 endDate
    ) internal pure returns (uint256) {
        uint256 actualDays = DateTime.daysBetween(startDate, endDate);

        // actualDays / 365 in fixed-point
        return (actualDays * FixedPoint.SCALE) / 365;
    }

    // =============================================================================
    // ACT/ACT ISDA - ACTUAL/ACTUAL ISDA
    // =============================================================================

    /**
     * @notice Calculate ACT/ACT ISDA day count fraction
     * @dev Most accurate method, used in many swap markets
     * @dev Splits period by year, accounting for leap years
     * @dev Formula: sum of (days_in_year_i / days_in_year_i) for each year
     * @param startDate Start date
     * @param endDate End date
     * @return Day count fraction (fixed-point)
     *
     * @custom:example Full leap year (366 days): 366/366 = 1.0
     * @custom:example Full non-leap year (365 days): 365/365 = 1.0
     */
    function calculateACTACTISDA(
        uint256 startDate,
        uint256 endDate
    ) internal pure returns (uint256) {
        uint256 startYear = DateTime.getYear(startDate);
        uint256 endYear = DateTime.getYear(endDate);

        // Same year - simple case
        if (startYear == endYear) {
            uint256 actualDays = DateTime.daysBetween(startDate, endDate);
            uint256 daysInYear = DateTime.getDaysInYear(startYear);
            return (actualDays * FixedPoint.SCALE) / daysInYear;
        }

        // Multiple years - split calculation
        uint256 totalFraction = 0;

        // Days in start year
        uint256 endOfStartYear = DateTime.getYearEnd(startYear);
        uint256 daysInStartYear = DateTime.daysBetween(startDate, endOfStartYear) + 1;
        uint256 startYearDays = DateTime.getDaysInYear(startYear);
        totalFraction = totalFraction.add(
            (daysInStartYear * FixedPoint.SCALE) / startYearDays
        );

        // Full years in between
        for (uint256 year = startYear + 1; year < endYear; year++) {
            totalFraction = totalFraction.add(FixedPoint.ONE); // Full year = 1.0
        }

        // Days in end year
        uint256 startOfEndYear = DateTime.getYearStart(endYear);
        uint256 daysInEndYear = DateTime.daysBetween(startOfEndYear, endDate);
        uint256 endYearDays = DateTime.getDaysInYear(endYear);
        totalFraction = totalFraction.add(
            (daysInEndYear * FixedPoint.SCALE) / endYearDays
        );

        return totalFraction;
    }

    // =============================================================================
    // ACT/ACT ICMA - ACTUAL/ACTUAL ICMA
    // =============================================================================

    /**
     * @notice Calculate ACT/ACT ICMA day count fraction
     * @dev Used for bonds, accounts for payment frequency
     * @dev Formula: actual_days / (days_in_period * frequency)
     * @param startDate Start date
     * @param endDate End date
     * @param frequency Payment frequency per year (1, 2, 4, 12)
     * @return Day count fraction (fixed-point)
     *
     * @custom:example Semi-annual: frequency = 2, period = 182.5 days
     * @custom:note terminationDate parameter omitted in simplified version
     */
    function calculateACTACTICMA(
        uint256 startDate,
        uint256 endDate,
        uint256 /* terminationDate */,
        uint256 frequency
    ) internal pure returns (uint256) {
        require(frequency > 0, "Frequency must be > 0");

        uint256 actualDays = DateTime.daysBetween(startDate, endDate);

        // Simplified: assume 365.25 days per year
        // Period days = 365.25 / frequency
        uint256 periodDays = (36525 * FixedPoint.SCALE) / (frequency * 100);

        // actualDays / periodDays
        return FixedPoint.div(
            actualDays * FixedPoint.SCALE,
            periodDays
        );
    }

    // =============================================================================
    // 30/360 - 30/360 BOND BASIS (US)
    // =============================================================================

    /**
     * @notice Calculate 30/360 day count fraction (Bond Basis)
     * @dev Each month assumed to have 30 days, year has 360 days
     * @dev Used in US corporate and municipal bonds
     * @dev Formula: (360*(Y2-Y1) + 30*(M2-M1) + (D2-D1)) / 360
     * @param startDate Start date
     * @param endDate End date
     * @return Day count fraction (fixed-point)
     *
     * @custom:example Jan 1 to Feb 1: 30/360 = 0.083333...
     */
    function calculate30360(
        uint256 startDate,
        uint256 endDate
    ) internal pure returns (uint256) {
        (uint256 y1, uint256 m1, uint256 d1) = DateTime.parseDate(startDate);
        (uint256 y2, uint256 m2, uint256 d2) = DateTime.parseDate(endDate);

        // Adjust day 31 to 30
        if (d1 == 31) {
            d1 = 30;
        }
        if (d2 == 31 && d1 >= 30) {
            d2 = 30;
        }

        // Calculate difference in "30/360" days
        uint256 daysDiff = (360 * (y2 - y1)) + (30 * (m2 - m1)) + (d2 - d1);

        // daysDiff / 360 in fixed-point
        return (daysDiff * FixedPoint.SCALE) / 360;
    }

    // =============================================================================
    // 30E/360 - 30E/360 EUROBOND BASIS
    // =============================================================================

    /**
     * @notice Calculate 30E/360 day count fraction (Eurobond Basis)
     * @dev European variant of 30/360
     * @dev Any day 31 becomes 30 (both start and end)
     * @dev Formula: (360*(Y2-Y1) + 30*(M2-M1) + (D2-D1)) / 360
     * @param startDate Start date
     * @param endDate End date
     * @return Day count fraction (fixed-point)
     */
    function calculate30E360(
        uint256 startDate,
        uint256 endDate
    ) internal pure returns (uint256) {
        (uint256 y1, uint256 m1, uint256 d1) = DateTime.parseDate(startDate);
        (uint256 y2, uint256 m2, uint256 d2) = DateTime.parseDate(endDate);

        // Eurobond convention: any day 31 becomes 30
        if (d1 == 31) {
            d1 = 30;
        }
        if (d2 == 31) {
            d2 = 30;
        }

        uint256 daysDiff = (360 * (y2 - y1)) + (30 * (m2 - m1)) + (d2 - d1);

        return (daysDiff * FixedPoint.SCALE) / 360;
    }

    // =============================================================================
    // 30E/360 ISDA - 30E/360 ISDA VARIANT
    // =============================================================================

    /**
     * @notice Calculate 30E/360 ISDA day count fraction
     * @dev ISDA variant with special end-of-month handling
     * @dev If end date is last day of February, no adjustment
     * @param startDate Start date
     * @param endDate End date
     * @param terminationDate Termination date (for maturity check)
     * @return Day count fraction (fixed-point)
     */
    function calculate30E360ISDA(
        uint256 startDate,
        uint256 endDate,
        uint256 terminationDate
    ) internal pure returns (uint256) {
        (uint256 y1, uint256 m1, uint256 d1) = DateTime.parseDate(startDate);
        (uint256 y2, uint256 m2, uint256 d2) = DateTime.parseDate(endDate);

        // ISDA specific adjustments
        if (d1 == 31) {
            d1 = 30;
        }

        // Special handling for February end
        bool isEndFeb = (m2 == 2 && d2 == DateTime.getDaysInMonth(2, y2));
        bool isTermination = (terminationDate > 0 && endDate == terminationDate);

        if (d2 == 31 || (isEndFeb && !isTermination)) {
            d2 = 30;
        }

        uint256 daysDiff = (360 * (y2 - y1)) + (30 * (m2 - m1)) + (d2 - d1);

        return (daysDiff * FixedPoint.SCALE) / 360;
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get year fraction for a full year
     * @dev Always returns 1.0 in fixed-point
     * @return 1.0 (1e18)
     */
    function yearFraction() internal pure returns (uint256) {
        return FixedPoint.ONE;
    }

    /**
     * @notice Calculate year fraction from number of days
     * @dev Simple calculation assuming 365.25 days per year
     * @param numDays Number of days
     * @return Year fraction (fixed-point)
     */
    function daysToYearFraction(uint256 numDays) internal pure returns (uint256) {
        // numDays / 365.25
        // = (numDays * 1e18 * 100) / 36525
        return (numDays * FixedPoint.SCALE * 100) / 36525;
    }

    /**
     * @notice Calculate days from year fraction
     * @dev Inverse of daysToYearFraction
     * @param yearFrac Year fraction (fixed-point)
     * @return Number of days
     */
    function yearFractionToDays(uint256 yearFrac) internal pure returns (uint256) {
        // yearFrac * 365.25
        // = (yearFrac * 36525) / (1e18 * 100)
        return (yearFrac * 36525) / (FixedPoint.SCALE * 100);
    }
}
