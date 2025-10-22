// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DateTime
 * @notice Date and time utility library for Unix timestamps
 * @dev Simplified implementation for CDM date calculations
 * @dev All dates are Unix timestamps (seconds since epoch)
 * @dev Production should integrate BokkyPooBah's DateTime Library for full functionality
 *
 * IMPORTANT: This is a simplified implementation for MVP
 * - Handles common cases for day count calculations
 * - Does not handle all edge cases (e.g., time zones, leap seconds)
 * - For production, use battle-tested libraries
 *
 * @author QualitaX Team
 */
library DateTime {

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    uint256 private constant SECONDS_PER_DAY = 86400;
    uint256 private constant SECONDS_PER_HOUR = 3600;
    uint256 private constant SECONDS_PER_MINUTE = 60;

    // Days in month (non-leap year)
    uint256 private constant DAYS_IN_JANUARY = 31;
    uint256 private constant DAYS_IN_FEBRUARY = 28;
    uint256 private constant DAYS_IN_MARCH = 31;
    uint256 private constant DAYS_IN_APRIL = 30;
    uint256 private constant DAYS_IN_MAY = 31;
    uint256 private constant DAYS_IN_JUNE = 30;
    uint256 private constant DAYS_IN_JULY = 31;
    uint256 private constant DAYS_IN_AUGUST = 31;
    uint256 private constant DAYS_IN_SEPTEMBER = 30;
    uint256 private constant DAYS_IN_OCTOBER = 31;
    uint256 private constant DAYS_IN_NOVEMBER = 30;
    uint256 private constant DAYS_IN_DECEMBER = 31;

    // Epoch
    uint256 private constant EPOCH_YEAR = 1970;

    // =============================================================================
    // ERRORS
    // =============================================================================

    error DateTime__InvalidDate();
    error DateTime__InvalidMonth();
    error DateTime__InvalidDay();

    // =============================================================================
    // DATE COMPONENT FUNCTIONS
    // =============================================================================

    /**
     * @notice Get year from Unix timestamp
     * @dev Simplified algorithm for years 1970-2100
     * @param timestamp Unix timestamp
     * @return year Year (e.g., 2024)
     */
    function getYear(uint256 timestamp) internal pure returns (uint256 year) {
        uint256 secondsAccountedFor = 0;
        year = EPOCH_YEAR;

        // Approximate year (365.25 days per year)
        uint256 numYears = timestamp / (365.25 days);
        year += numYears;
        secondsAccountedFor = numYears * 365 days;

        // Adjust for leap years
        uint256 leapYears = (year - EPOCH_YEAR) / 4;
        secondsAccountedFor += leapYears * 1 days;

        // Fine-tune
        while (secondsAccountedFor > timestamp) {
            if (isLeapYear(year - 1)) {
                secondsAccountedFor -= 366 days;
            } else {
                secondsAccountedFor -= 365 days;
            }
            year -= 1;
        }

        uint256 daysInYear = isLeapYear(year) ? 366 : 365;
        while (secondsAccountedFor + (daysInYear * 1 days) <= timestamp) {
            secondsAccountedFor += daysInYear * 1 days;
            year += 1;
            daysInYear = isLeapYear(year) ? 366 : 365;
        }
    }

    /**
     * @notice Get month from Unix timestamp (1-12)
     * @param timestamp Unix timestamp
     * @return month Month (1 = January, 12 = December)
     */
    function getMonth(uint256 timestamp) internal pure returns (uint256 month) {
        uint256 year = getYear(timestamp);
        uint256 yearStart = getYearStart(year);
        uint256 daysSinceYearStart = (timestamp - yearStart) / SECONDS_PER_DAY;

        month = 1;
        uint256 daysAccounted = 0;

        while (month <= 12) {
            uint256 daysInMonth = getDaysInMonth(month, year);
            if (daysSinceYearStart < daysAccounted + daysInMonth) {
                break;
            }
            daysAccounted += daysInMonth;
            month++;
        }

        if (month > 12) month = 12;
    }

    /**
     * @notice Get day of month from Unix timestamp (1-31)
     * @param timestamp Unix timestamp
     * @return day Day of month
     */
    function getDay(uint256 timestamp) internal pure returns (uint256 day) {
        uint256 year = getYear(timestamp);
        uint256 month = getMonth(timestamp);
        uint256 monthStart = getMonthStart(year, month);

        day = ((timestamp - monthStart) / SECONDS_PER_DAY) + 1;
    }

    /**
     * @notice Parse date into year, month, day components
     * @param timestamp Unix timestamp
     * @return year Year
     * @return month Month (1-12)
     * @return day Day of month (1-31)
     */
    function parseDate(uint256 timestamp) internal pure returns (
        uint256 year,
        uint256 month,
        uint256 day
    ) {
        year = getYear(timestamp);
        month = getMonth(timestamp);
        day = getDay(timestamp);
    }

    // =============================================================================
    // LEAP YEAR FUNCTIONS
    // =============================================================================

    /**
     * @notice Check if year is a leap year
     * @dev Leap year rules:
     *      - Divisible by 4: leap year
     *      - Divisible by 100: not leap year
     *      - Divisible by 400: leap year
     * @param year Year to check
     * @return true if leap year
     */
    function isLeapYear(uint256 year) internal pure returns (bool) {
        if (year % 4 != 0) return false;
        if (year % 100 != 0) return true;
        if (year % 400 != 0) return false;
        return true;
    }

    /**
     * @notice Get number of days in a year
     * @param year Year
     * @return Number of days (365 or 366)
     */
    function getDaysInYear(uint256 year) internal pure returns (uint256) {
        return isLeapYear(year) ? 366 : 365;
    }

    /**
     * @notice Get number of days in a month
     * @param month Month (1-12)
     * @param year Year (for February leap year calculation)
     * @return Number of days in month
     */
    function getDaysInMonth(uint256 month, uint256 year) internal pure returns (uint256) {
        if (month == 1) return DAYS_IN_JANUARY;
        if (month == 2) return isLeapYear(year) ? 29 : DAYS_IN_FEBRUARY;
        if (month == 3) return DAYS_IN_MARCH;
        if (month == 4) return DAYS_IN_APRIL;
        if (month == 5) return DAYS_IN_MAY;
        if (month == 6) return DAYS_IN_JUNE;
        if (month == 7) return DAYS_IN_JULY;
        if (month == 8) return DAYS_IN_AUGUST;
        if (month == 9) return DAYS_IN_SEPTEMBER;
        if (month == 10) return DAYS_IN_OCTOBER;
        if (month == 11) return DAYS_IN_NOVEMBER;
        if (month == 12) return DAYS_IN_DECEMBER;

        revert DateTime__InvalidMonth();
    }

    // =============================================================================
    // DATE CONSTRUCTION FUNCTIONS
    // =============================================================================

    /**
     * @notice Get Unix timestamp for start of year
     * @param year Year
     * @return Unix timestamp for January 1, 00:00:00
     */
    function getYearStart(uint256 year) internal pure returns (uint256) {
        require(year >= EPOCH_YEAR, "Year must be >= 1970");

        uint256 timestamp = 0;
        for (uint256 y = EPOCH_YEAR; y < year; y++) {
            timestamp += getDaysInYear(y) * SECONDS_PER_DAY;
        }
        return timestamp;
    }

    /**
     * @notice Get Unix timestamp for end of year
     * @param year Year
     * @return Unix timestamp for December 31, 23:59:59
     */
    function getYearEnd(uint256 year) internal pure returns (uint256) {
        return getYearStart(year + 1) - 1;
    }

    /**
     * @notice Get Unix timestamp for start of month
     * @param year Year
     * @param month Month (1-12)
     * @return Unix timestamp for month start
     */
    function getMonthStart(uint256 year, uint256 month) internal pure returns (uint256) {
        require(month >= 1 && month <= 12, "Invalid month");

        uint256 timestamp = getYearStart(year);

        for (uint256 m = 1; m < month; m++) {
            timestamp += getDaysInMonth(m, year) * SECONDS_PER_DAY;
        }

        return timestamp;
    }

    // =============================================================================
    // DATE ARITHMETIC FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate number of days between two dates
     * @param startDate Start date (Unix timestamp)
     * @param endDate End date (Unix timestamp)
     * @return Number of days (can be fractional in fixed-point if needed)
     */
    function daysBetween(uint256 startDate, uint256 endDate) internal pure returns (uint256) {
        require(endDate >= startDate, "End date must be >= start date");
        return (endDate - startDate) / SECONDS_PER_DAY;
    }

    /**
     * @notice Add days to a date
     * @param timestamp Starting timestamp
     * @param daysToAdd Number of days to add
     * @return New timestamp
     */
    function addDays(uint256 timestamp, uint256 daysToAdd) internal pure returns (uint256) {
        return timestamp + (daysToAdd * SECONDS_PER_DAY);
    }

    /**
     * @notice Add months to a date
     * @dev Preserves day of month where possible
     * @param timestamp Starting timestamp
     * @param monthsToAdd Number of months to add
     * @return New timestamp
     */
    function addMonths(uint256 timestamp, uint256 monthsToAdd) internal pure returns (uint256) {
        (uint256 year, uint256 month, uint256 day) = parseDate(timestamp);

        // Add months
        month += monthsToAdd;

        // Handle year overflow
        while (month > 12) {
            month -= 12;
            year += 1;
        }

        // Adjust day if it exceeds days in new month
        uint256 daysInNewMonth = getDaysInMonth(month, year);
        if (day > daysInNewMonth) {
            day = daysInNewMonth;
        }

        // Reconstruct timestamp
        uint256 newTimestamp = getMonthStart(year, month);
        newTimestamp += (day - 1) * SECONDS_PER_DAY;

        return newTimestamp;
    }

    /**
     * @notice Add years to a date
     * @param timestamp Starting timestamp
     * @param yearsToAdd Number of years to add
     * @return New timestamp
     */
    function addYears(uint256 timestamp, uint256 yearsToAdd) internal pure returns (uint256) {
        (uint256 year, uint256 month, uint256 day) = parseDate(timestamp);

        year += yearsToAdd;

        // Adjust for leap year (Feb 29 -> Feb 28 in non-leap year)
        if (month == 2 && day == 29 && !isLeapYear(year)) {
            day = 28;
        }

        uint256 newTimestamp = getMonthStart(year, month);
        newTimestamp += (day - 1) * SECONDS_PER_DAY;

        return newTimestamp;
    }

    // =============================================================================
    // VALIDATION FUNCTIONS
    // =============================================================================

    /**
     * @notice Validate date is within reasonable range
     * @param timestamp Unix timestamp to validate
     * @return true if valid
     */
    function isValidDate(uint256 timestamp) internal view returns (bool) {
        // Check not before epoch
        if (timestamp < 0) return false;

        // Check not too far in future (year 2100)
        if (timestamp > 4102444800) return false;

        // Check not in past before 1970
        if (timestamp < 0) return false;

        return true;
    }

    /**
     * @notice Check if date1 is before date2
     * @param date1 First date
     * @param date2 Second date
     * @return true if date1 < date2
     */
    function isBefore(uint256 date1, uint256 date2) internal pure returns (bool) {
        return date1 < date2;
    }

    /**
     * @notice Check if date1 is after date2
     * @param date1 First date
     * @param date2 Second date
     * @return true if date1 > date2
     */
    function isAfter(uint256 date1, uint256 date2) internal pure returns (bool) {
        return date1 > date2;
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get current timestamp (block.timestamp)
     * @return Current Unix timestamp
     */
    function now_() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Convert date components to Unix timestamp
     * @dev Simplified - assumes 00:00:00 time
     * @param year Year
     * @param month Month (1-12)
     * @param day Day (1-31)
     * @return Unix timestamp
     */
    function toTimestamp(
        uint256 year,
        uint256 month,
        uint256 day
    ) internal pure returns (uint256) {
        require(year >= EPOCH_YEAR, "Year must be >= 1970");
        require(month >= 1 && month <= 12, "Invalid month");
        require(day >= 1 && day <= 31, "Invalid day");
        require(day <= getDaysInMonth(month, year), "Day exceeds month");

        uint256 timestamp = getMonthStart(year, month);
        timestamp += (day - 1) * SECONDS_PER_DAY;

        return timestamp;
    }
}
