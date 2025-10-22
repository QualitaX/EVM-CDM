// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DateTime} from "./DateTime.sol";
import {BusinessDayAdjustments as BDAType} from "../types/CDMTypes.sol";
import {BusinessDayConventionEnum, BusinessCenterEnum} from "../types/Enums.sol";

/**
 * @title BusinessDayAdjustments
 * @notice Business day adjustment logic per ISDA conventions
 * @dev Adjusts dates that fall on weekends or holidays
 * @dev Implements ISDA standard business day conventions
 *
 * CONVENTIONS IMPLEMENTED:
 * - NONE: No adjustment
 * - FOLLOWING: Next business day
 * - MODIFIED_FOLLOWING: Next business day unless next month, then previous
 * - PRECEDING: Previous business day
 * - MODIFIED_PRECEDING: Previous business day unless previous month, then next
 * - NEAREST: Nearest business day (next if equidistant)
 *
 * HOLIDAY CALENDARS:
 * - Simplified implementation with weekend detection
 * - Full implementation requires external holiday calendar data
 * - Business centers identify which calendars to apply
 *
 * REFERENCES:
 * - ISDA 2006 Definitions Section 4.11
 * - ISDA 2021 Definitions
 * - FpML BusinessDayConvention enumeration
 *
 * @author QUalitaX Team
 */
library BusinessDayAdjustments {

    using DateTime for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Seconds per day (for date arithmetic)
    uint256 private constant SECONDS_PER_DAY = 86400;

    /// @notice Maximum adjustment attempts (prevent infinite loops)
    uint256 private constant MAX_ADJUSTMENT_ATTEMPTS = 10;

    // =============================================================================
    // ERRORS
    // =============================================================================

    error BusinessDayAdjustments__InvalidDate();
    error BusinessDayAdjustments__InvalidConvention();
    error BusinessDayAdjustments__MaxAdjustmentsExceeded();

    // =============================================================================
    // MAIN ADJUSTMENT FUNCTION
    // =============================================================================

    /**
     * @notice Adjust date according to business day convention
     * @dev Main entry point for business day adjustments
     * @param date Unadjusted date (Unix timestamp)
     * @param adjustments Business day adjustment specification
     * @return Adjusted date (Unix timestamp)
     *
     * @custom:example Saturday -> FOLLOWING -> Monday
     * @custom:example Month-end Saturday -> MODIFIED_FOLLOWING -> Previous Friday
     */
    function adjustDate(
        uint256 date,
        BDAType memory adjustments
    ) internal pure returns (uint256) {
        // If no adjustment, return original date
        if (adjustments.convention == BusinessDayConventionEnum.NONE) {
            return date;
        }

        // If already a business day, might still need adjustment based on convention
        if (isBusinessDay(date, adjustments.businessCenters)) {
            return date;
        }

        // Apply appropriate convention
        if (adjustments.convention == BusinessDayConventionEnum.FOLLOWING) {
            return applyFollowing(date, adjustments.businessCenters);

        } else if (adjustments.convention == BusinessDayConventionEnum.MODIFIED_FOLLOWING) {
            return applyModifiedFollowing(date, adjustments.businessCenters);

        } else if (adjustments.convention == BusinessDayConventionEnum.PRECEDING) {
            return applyPreceding(date, adjustments.businessCenters);

        } else if (adjustments.convention == BusinessDayConventionEnum.MODIFIED_PRECEDING) {
            return applyModifiedPreceding(date, adjustments.businessCenters);

        } else if (adjustments.convention == BusinessDayConventionEnum.NEAREST) {
            return applyNearest(date, adjustments.businessCenters);

        } else {
            revert BusinessDayAdjustments__InvalidConvention();
        }
    }

    /**
     * @notice Adjust multiple dates
     * @dev Batch adjustment for efficiency
     * @param dates Array of unadjusted dates
     * @param adjustments Business day adjustment specification
     * @return Array of adjusted dates
     */
    function adjustDates(
        uint256[] memory dates,
        BDAType memory adjustments
    ) internal pure returns (uint256[] memory) {
        uint256[] memory adjusted = new uint256[](dates.length);

        for (uint256 i = 0; i < dates.length; i++) {
            adjusted[i] = adjustDate(dates[i], adjustments);
        }

        return adjusted;
    }

    // =============================================================================
    // CONVENTION IMPLEMENTATIONS
    // =============================================================================

    /**
     * @notice Apply FOLLOWING convention
     * @dev Move to next business day
     * @param date Original date
     * @param businessCenters Business centers for holiday calendars
     * @return Next business day
     */
    function applyFollowing(
        uint256 date,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        uint256 adjustedDate = date;
        uint256 attempts = 0;

        // Move forward until we find a business day
        while (!isBusinessDay(adjustedDate, businessCenters)) {
            adjustedDate += SECONDS_PER_DAY;
            attempts++;

            if (attempts >= MAX_ADJUSTMENT_ATTEMPTS) {
                revert BusinessDayAdjustments__MaxAdjustmentsExceeded();
            }
        }

        return adjustedDate;
    }

    /**
     * @notice Apply MODIFIED_FOLLOWING convention
     * @dev Next business day, unless that moves to next month, then previous business day
     * @param date Original date
     * @param businessCenters Business centers for holiday calendars
     * @return Adjusted business day
     */
    function applyModifiedFollowing(
        uint256 date,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        // First try FOLLOWING
        uint256 followingDate = applyFollowing(date, businessCenters);

        // Check if we moved to next month
        (uint256 origYear, uint256 origMonth, ) = DateTime.parseDate(date);
        (uint256 adjYear, uint256 adjMonth, ) = DateTime.parseDate(followingDate);

        if (adjYear > origYear || (adjYear == origYear && adjMonth > origMonth)) {
            // Moved to next month, use PRECEDING instead
            return applyPreceding(date, businessCenters);
        }

        return followingDate;
    }

    /**
     * @notice Apply PRECEDING convention
     * @dev Move to previous business day
     * @param date Original date
     * @param businessCenters Business centers for holiday calendars
     * @return Previous business day
     */
    function applyPreceding(
        uint256 date,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        uint256 adjustedDate = date;
        uint256 attempts = 0;

        // Move backward until we find a business day
        while (!isBusinessDay(adjustedDate, businessCenters)) {
            adjustedDate -= SECONDS_PER_DAY;
            attempts++;

            if (attempts >= MAX_ADJUSTMENT_ATTEMPTS) {
                revert BusinessDayAdjustments__MaxAdjustmentsExceeded();
            }
        }

        return adjustedDate;
    }

    /**
     * @notice Apply MODIFIED_PRECEDING convention
     * @dev Previous business day, unless that moves to previous month, then next business day
     * @param date Original date
     * @param businessCenters Business centers for holiday calendars
     * @return Adjusted business day
     */
    function applyModifiedPreceding(
        uint256 date,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        // First try PRECEDING
        uint256 precedingDate = applyPreceding(date, businessCenters);

        // Check if we moved to previous month
        (uint256 origYear, uint256 origMonth, ) = DateTime.parseDate(date);
        (uint256 adjYear, uint256 adjMonth, ) = DateTime.parseDate(precedingDate);

        if (adjYear < origYear || (adjYear == origYear && adjMonth < origMonth)) {
            // Moved to previous month, use FOLLOWING instead
            return applyFollowing(date, businessCenters);
        }

        return precedingDate;
    }

    /**
     * @notice Apply NEAREST convention
     * @dev Nearest business day; if equidistant, choose following
     * @param date Original date
     * @param businessCenters Business centers for holiday calendars
     * @return Nearest business day
     */
    function applyNearest(
        uint256 date,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        // Get both preceding and following
        uint256 precedingDate = applyPreceding(date, businessCenters);
        uint256 followingDate = applyFollowing(date, businessCenters);

        // Calculate distances
        uint256 precedingDistance = date - precedingDate;
        uint256 followingDistance = followingDate - date;

        // Choose nearest; if equal, choose following
        if (precedingDistance < followingDistance) {
            return precedingDate;
        } else {
            return followingDate;
        }
    }

    // =============================================================================
    // BUSINESS DAY CHECKING
    // =============================================================================

    /**
     * @notice Check if date is a business day
     * @dev Currently checks weekends only; full implementation needs holiday calendars
     * @param date Date to check (Unix timestamp)
     * @param businessCenters Business centers to check (not implemented yet)
     * @return true if business day
     *
     * @custom:note This is a simplified implementation
     * @custom:note Full implementation requires external holiday calendar data
     */
    function isBusinessDay(
        uint256 date,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (bool) {
        // Check if weekend
        if (isWeekend(date)) {
            return false;
        }

        // TODO: Check against holiday calendars for specified business centers
        // This requires external data (holiday lists by business center)
        // For now, we only check weekends

        // Suppress unused parameter warning
        businessCenters;

        return true;
    }

    /**
     * @notice Check if date is a weekend (Saturday or Sunday)
     * @dev Uses Unix timestamp day-of-week calculation
     * @param date Date to check (Unix timestamp)
     * @return true if Saturday or Sunday
     */
    function isWeekend(uint256 date) internal pure returns (bool) {
        // Unix epoch (Jan 1, 1970) was a Thursday
        // Formula: (days_since_epoch + 4) % 7 gives day of week
        // 0 = Sunday, 1 = Monday, 2 = Tuesday, 3 = Wednesday, 4 = Thursday, 5 = Friday, 6 = Saturday
        uint256 dayOfWeek = ((date / SECONDS_PER_DAY) + 4) % 7;

        // Saturday = 6, Sunday = 0
        return (dayOfWeek == 6 || dayOfWeek == 0);
    }

    /**
     * @notice Get day of week for a date
     * @dev 0=Monday, 1=Tuesday, ..., 6=Sunday (ISO 8601)
     * @param date Date (Unix timestamp)
     * @return Day of week (0-6)
     */
    function getDayOfWeek(uint256 date) internal pure returns (uint256) {
        // Calculate day of week where 0=Sunday, 1=Monday, ..., 6=Saturday
        uint256 unixDayOfWeek = ((date / SECONDS_PER_DAY) + 4) % 7;

        // Convert to ISO 8601: 0=Monday, 1=Tuesday, ..., 6=Sunday
        // Unix: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
        // ISO:  0=Mon, 1=Tue, 2=Wed, 3=Thu, 4=Fri, 5=Sat, 6=Sun
        return (unixDayOfWeek + 6) % 7;
    }

    /**
     * @notice Check if date is a specific day of week
     * @param date Date to check
     * @param dayOfWeek Day of week (0=Monday, 6=Sunday)
     * @return true if matches
     */
    function isDayOfWeek(uint256 date, uint256 dayOfWeek) internal pure returns (bool) {
        return getDayOfWeek(date) == dayOfWeek;
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Count business days between two dates
     * @dev Includes start date, excludes end date
     * @param startDate Start date (inclusive)
     * @param endDate End date (exclusive)
     * @param businessCenters Business centers for holiday calendars
     * @return Number of business days
     *
     * @custom:example Mon-Fri (5 calendar days) = 5 business days
     * @custom:example Fri-Mon (3 calendar days) = 1 business day (Friday only)
     */
    function countBusinessDays(
        uint256 startDate,
        uint256 endDate,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        if (endDate <= startDate) {
            return 0;
        }

        uint256 count = 0;
        uint256 currentDate = startDate;

        while (currentDate < endDate) {
            if (isBusinessDay(currentDate, businessCenters)) {
                count++;
            }
            currentDate += SECONDS_PER_DAY;
        }

        return count;
    }

    /**
     * @notice Add business days to a date
     * @dev Skips weekends and holidays
     * @param date Starting date
     * @param businessDays Number of business days to add
     * @param businessCenters Business centers for holiday calendars
     * @return Date after adding business days
     *
     * @custom:example Friday + 1 business day = Monday
     * @custom:example Friday + 3 business days = Wednesday
     */
    function addBusinessDays(
        uint256 date,
        uint256 businessDays,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        uint256 currentDate = date;
        uint256 daysAdded = 0;

        while (daysAdded < businessDays) {
            currentDate += SECONDS_PER_DAY;

            if (isBusinessDay(currentDate, businessCenters)) {
                daysAdded++;
            }
        }

        return currentDate;
    }

    /**
     * @notice Get next business day
     * @dev Convenience function for adding 1 business day
     * @param date Current date
     * @param businessCenters Business centers for holiday calendars
     * @return Next business day
     */
    function getNextBusinessDay(
        uint256 date,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        return addBusinessDays(date, 1, businessCenters);
    }

    /**
     * @notice Get previous business day
     * @dev Convenience function for subtracting 1 business day
     * @param date Current date
     * @param businessCenters Business centers for holiday calendars
     * @return Previous business day
     */
    function getPreviousBusinessDay(
        uint256 date,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (uint256) {
        uint256 currentDate = date - SECONDS_PER_DAY;

        while (!isBusinessDay(currentDate, businessCenters)) {
            currentDate -= SECONDS_PER_DAY;
        }

        return currentDate;
    }

    // =============================================================================
    // CREATION HELPERS
    // =============================================================================

    /**
     * @notice Create business day adjustments with single center
     * @param convention Business day convention
     * @param businessCenter Business center
     * @return BusinessDayAdjustments struct
     */
    function createAdjustments(
        BusinessDayConventionEnum convention,
        BusinessCenterEnum businessCenter
    ) internal pure returns (BDAType memory) {
        BusinessCenterEnum[] memory centers = new BusinessCenterEnum[](1);
        centers[0] = businessCenter;

        return BDAType({
            convention: convention,
            businessCenters: centers
        });
    }

    /**
     * @notice Create business day adjustments with multiple centers
     * @param convention Business day convention
     * @param businessCenters Array of business centers
     * @return BusinessDayAdjustments struct
     */
    function createAdjustmentsMulti(
        BusinessDayConventionEnum convention,
        BusinessCenterEnum[] memory businessCenters
    ) internal pure returns (BDAType memory) {
        return BDAType({
            convention: convention,
            businessCenters: businessCenters
        });
    }

    /**
     * @notice Create adjustments with no adjustment (pass-through)
     * @return BusinessDayAdjustments with NONE convention
     */
    function createNoAdjustments() internal pure returns (BDAType memory) {
        return BDAType({
            convention: BusinessDayConventionEnum.NONE,
            businessCenters: new BusinessCenterEnum[](0)
        });
    }

    // =============================================================================
    // VALIDATION
    // =============================================================================

    /**
     * @notice Validate business day adjustments
     * @dev Checks for consistency
     * @param adjustments Business day adjustments to validate
     * @return true if valid
     */
    function validateAdjustments(BDAType memory adjustments) internal pure returns (bool) {
        // If convention is NONE, business centers not required
        if (adjustments.convention == BusinessDayConventionEnum.NONE) {
            return true;
        }

        // For other conventions, should have at least one business center
        // (although current implementation doesn't use them)
        return adjustments.businessCenters.length > 0;
    }

    /**
     * @notice Check if adjustments are empty (no adjustment)
     * @param adjustments Business day adjustments
     * @return true if no adjustment will be applied
     */
    function isEmpty(BDAType memory adjustments) internal pure returns (bool) {
        return adjustments.convention == BusinessDayConventionEnum.NONE;
    }
}
