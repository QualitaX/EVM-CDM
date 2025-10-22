// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RoundingDirectionEnum} from "../types/Enums.sol";

/**
 * @title FixedPoint
 * @notice Fixed-point arithmetic library for financial calculations
 * @dev Uses 18 decimal precision (1e18 = 1.0) - same as Ether wei
 * @dev Optimized for CDM financial calculations with proper rounding
 * @dev Inspired by PRBMath but tailored for CDM use cases
 *
 * PRECISION: All values use 18 decimals
 * - 1.0 = 1_000_000_000_000_000_000 (1e18)
 * - 0.5 = 500_000_000_000_000_000 (5e17)
 * - 0.01 (1%) = 10_000_000_000_000_000 (1e16)
 *
 * SAFETY:
 * - All operations check for overflow/underflow
 * - Uses Solidity 0.8+ built-in checks
 * - Additional validation for division by zero
 *
 * @custom:security-contact security@finos.org
 * @author FINOS CDM EVM Framework Team
 */
library FixedPoint {

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Scaling factor (18 decimals) - same as 1 ether in wei
    uint256 internal constant SCALE = 1e18;

    /// @notice Half scale for rounding (0.5 in fixed-point)
    uint256 internal constant HALF_SCALE = 5e17;

    /// @notice Maximum value to prevent overflow in multiplication
    uint256 internal constant MAX_UINT256 = type(uint256).max;

    /// @notice Minimum positive value (smallest representable: 1 wei)
    uint256 internal constant MIN_VALUE = 1;

    /// @notice One in fixed-point (1.0)
    uint256 internal constant ONE = SCALE;

    /// @notice Zero in fixed-point
    uint256 internal constant ZERO = 0;

    // Useful constants for financial calculations
    /// @notice One basis point (0.01%) in fixed-point
    uint256 internal constant ONE_BASIS_POINT = 1e14; // 0.0001 * 1e18

    /// @notice One percent (1%) in fixed-point
    uint256 internal constant ONE_PERCENT = 1e16; // 0.01 * 1e18

    // =============================================================================
    // ERRORS
    // =============================================================================

    /// @notice Thrown when multiplication would overflow
    error FixedPoint__Overflow();

    /// @notice Thrown when attempting division by zero
    error FixedPoint__DivisionByZero();

    /// @notice Thrown when subtraction would underflow
    error FixedPoint__Underflow();

    /// @notice Thrown when input is negative (in signed context)
    error FixedPoint__NegativeValue();

    // =============================================================================
    // CORE ARITHMETIC OPERATIONS
    // =============================================================================

    /**
     * @notice Multiply two fixed-point numbers
     * @dev Result = (a * b) / SCALE
     * @dev Rounds to nearest (adds HALF_SCALE before division)
     * @param a First fixed-point number
     * @param b Second fixed-point number
     * @return Result in fixed-point
     *
     * @custom:example mul(2e18, 3e18) = 6e18 (2.0 * 3.0 = 6.0)
     * @custom:example mul(15e17, 2e18) = 3e18 (1.5 * 2.0 = 3.0)
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: if either is zero, return zero
        if (a == 0 || b == 0) {
            return 0;
        }

        // Check for overflow: a * b must fit in uint256
        // Rearranged to: a <= MAX_UINT256 / b
        if (a > MAX_UINT256 / b) {
            revert FixedPoint__Overflow();
        }

        uint256 c = a * b;

        // Add half scale for proper rounding, then divide by scale
        // unchecked is safe here because we've already checked overflow above
        unchecked {
            return (c + HALF_SCALE) / SCALE;
        }
    }

    /**
     * @notice Divide two fixed-point numbers
     * @dev Result = (a * SCALE) / b
     * @dev Rounds to nearest (adds b/2 before division)
     * @param a Numerator (fixed-point)
     * @param b Denominator (fixed-point)
     * @return Result in fixed-point
     *
     * @custom:example div(6e18, 2e18) = 3e18 (6.0 / 2.0 = 3.0)
     * @custom:example div(1e18, 3e18) = 333333333333333333 (1.0 / 3.0 ≈ 0.333...)
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Check for division by zero
        if (b == 0) {
            revert FixedPoint__DivisionByZero();
        }

        // Gas optimization: if numerator is zero, return zero
        if (a == 0) {
            return 0;
        }

        // Scale up numerator
        uint256 c = a * SCALE;

        // Check that scaling didn't overflow
        if (c / SCALE != a) {
            revert FixedPoint__Overflow();
        }

        // Add half denominator for proper rounding, then divide
        unchecked {
            return (c + (b / 2)) / b;
        }
    }

    /**
     * @notice Add two fixed-point numbers
     * @dev Built-in Solidity 0.8+ overflow protection
     * @param a First number
     * @param b Second number
     * @return Sum
     *
     * @custom:example add(1e18, 2e18) = 3e18 (1.0 + 2.0 = 3.0)
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b; // Overflow checked by Solidity 0.8+
    }

    /**
     * @notice Subtract two fixed-point numbers
     * @dev Built-in Solidity 0.8+ underflow protection
     * @param a Minuend
     * @param b Subtrahend
     * @return Difference
     *
     * @custom:example sub(5e18, 2e18) = 3e18 (5.0 - 2.0 = 3.0)
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b > a) {
            revert FixedPoint__Underflow();
        }
        return a - b;
    }

    // =============================================================================
    // CONVERSION FUNCTIONS
    // =============================================================================

    /**
     * @notice Convert from regular integer to fixed-point
     * @dev Multiplies by SCALE (1e18)
     * @param a Integer value
     * @return Fixed-point value
     *
     * @custom:example fromUint(5) = 5e18 (5 -> 5.0)
     * @custom:example fromUint(100) = 100e18 (100 -> 100.0)
     */
    function fromUint(uint256 a) internal pure returns (uint256) {
        // Check for overflow
        if (a > MAX_UINT256 / SCALE) {
            revert FixedPoint__Overflow();
        }
        return a * SCALE;
    }

    /**
     * @notice Convert from fixed-point to integer (truncating decimals)
     * @dev Divides by SCALE (1e18)
     * @param a Fixed-point value
     * @return Integer value (decimals truncated)
     *
     * @custom:example toUint(5e18) = 5 (5.0 -> 5)
     * @custom:example toUint(5.7e18) = 5 (5.7 -> 5, truncated)
     */
    function toUint(uint256 a) internal pure returns (uint256) {
        return a / SCALE;
    }

    /**
     * @notice Convert from fixed-point to integer (rounding)
     * @dev Rounds to nearest integer
     * @param a Fixed-point value
     * @return Integer value (rounded)
     *
     * @custom:example toUintRounded(5.4e18) = 5 (5.4 -> 5)
     * @custom:example toUintRounded(5.6e18) = 6 (5.6 -> 6)
     */
    function toUintRounded(uint256 a) internal pure returns (uint256) {
        return (a + HALF_SCALE) / SCALE;
    }

    // =============================================================================
    // ROUNDING FUNCTIONS
    // =============================================================================

    /**
     * @notice Round fixed-point number to specified decimal places
     * @param value Value to round
     * @param decimals Number of decimal places (0-18)
     * @param direction Rounding direction
     * @return Rounded value
     *
     * @custom:example round(1.234e18, 2, DOWN) = 1.23e18
     * @custom:example round(1.235e18, 2, NEAREST) = 1.24e18 (rounds up)
     * @custom:example round(1.234e18, 2, UP) = 1.24e18
     */
    function round(
        uint256 value,
        uint8 decimals,
        RoundingDirectionEnum direction
    ) internal pure returns (uint256) {
        require(decimals <= 18, "FixedPoint: max 18 decimals");

        // If rounding to 18 decimals, return as-is
        if (decimals == 18) {
            return value;
        }

        // Calculate rounding factor (10^(18-decimals))
        uint256 factor = 10 ** (18 - decimals);
        uint256 remainder = value % factor;
        uint256 truncated = value - remainder;

        if (direction == RoundingDirectionEnum.DOWN) {
            // Round down (floor)
            return truncated;

        } else if (direction == RoundingDirectionEnum.UP) {
            // Round up (ceiling)
            return remainder > 0 ? truncated + factor : truncated;

        } else {
            // Round to nearest
            return remainder >= factor / 2 ? truncated + factor : truncated;
        }
    }

    // =============================================================================
    // COMPARISON FUNCTIONS
    // =============================================================================

    /**
     * @notice Check if a equals b (fixed-point)
     * @param a First value
     * @param b Second value
     * @return true if equal
     */
    function eq(uint256 a, uint256 b) internal pure returns (bool) {
        return a == b;
    }

    /**
     * @notice Check if a is greater than b
     * @param a First value
     * @param b Second value
     * @return true if a > b
     */
    function gt(uint256 a, uint256 b) internal pure returns (bool) {
        return a > b;
    }

    /**
     * @notice Check if a is greater than or equal to b
     * @param a First value
     * @param b Second value
     * @return true if a >= b
     */
    function gte(uint256 a, uint256 b) internal pure returns (bool) {
        return a >= b;
    }

    /**
     * @notice Check if a is less than b
     * @param a First value
     * @param b Second value
     * @return true if a < b
     */
    function lt(uint256 a, uint256 b) internal pure returns (bool) {
        return a < b;
    }

    /**
     * @notice Check if a is less than or equal to b
     * @param a First value
     * @param b Second value
     * @return true if a <= b
     */
    function lte(uint256 a, uint256 b) internal pure returns (bool) {
        return a <= b;
    }

    // =============================================================================
    // ADVANCED MATHEMATICAL OPERATIONS
    // =============================================================================

    /**
     * @notice Calculate average of two fixed-point numbers
     * @dev Handles overflow by dividing before adding
     * @param a First value
     * @param b Second value
     * @return Average value
     */
    function avg(uint256 a, uint256 b) internal pure returns (uint256) {
        // Technique to avoid overflow: (a/2) + (b/2) + ((a%2 + b%2)/2)
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }

    /**
     * @notice Return minimum of two values
     * @param a First value
     * @param b Second value
     * @return Minimum value
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Return maximum of two values
     * @param a First value
     * @param b Second value
     * @return Maximum value
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Calculate power: base^exponent (for integer exponents only)
     * @dev Exponent must be small to avoid overflow
     * @param base Base value (fixed-point)
     * @param exponent Exponent (integer, not fixed-point)
     * @return Result (fixed-point)
     *
     * @custom:example pow(2e18, 3) = 8e18 (2.0^3 = 8.0)
     */
    function pow(uint256 base, uint256 exponent) internal pure returns (uint256) {
        if (exponent == 0) {
            return ONE; // x^0 = 1
        }
        if (base == 0) {
            return ZERO; // 0^x = 0 (for x > 0)
        }
        if (exponent == 1) {
            return base; // x^1 = x
        }

        uint256 result = ONE;
        uint256 baseTemp = base;

        // Exponentiation by squaring
        while (exponent > 0) {
            if (exponent % 2 == 1) {
                result = mul(result, baseTemp);
            }
            baseTemp = mul(baseTemp, baseTemp);
            exponent /= 2;
        }

        return result;
    }

    // =============================================================================
    // FINANCIAL HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Convert basis points to fixed-point percentage
     * @dev 1 bp = 0.01% = 0.0001
     * @param basisPoints Basis points (e.g., 100 = 1%)
     * @return Fixed-point percentage
     *
     * @custom:example fromBasisPoints(100) = 0.01e18 (100bp = 1%)
     * @custom:example fromBasisPoints(25) = 0.0025e18 (25bp = 0.25%)
     */
    function fromBasisPoints(uint256 basisPoints) internal pure returns (uint256) {
        return basisPoints * ONE_BASIS_POINT;
    }

    /**
     * @notice Convert fixed-point percentage to basis points
     * @param percentage Fixed-point percentage
     * @return Basis points
     *
     * @custom:example toBasisPoints(0.01e18) = 100 (1% = 100bp)
     */
    function toBasisPoints(uint256 percentage) internal pure returns (uint256) {
        return percentage / ONE_BASIS_POINT;
    }

    /**
     * @notice Apply percentage to a value
     * @dev result = value * (percentage / 100)
     * @param value Value to apply percentage to
     * @param percentage Percentage in fixed-point (e.g., 5e16 for 5%)
     * @return Result
     *
     * @custom:example applyPercentage(1000e18, 5e16) = 50e18 (5% of 1000 = 50)
     */
    function applyPercentage(uint256 value, uint256 percentage) internal pure returns (uint256) {
        return mul(value, percentage) / ONE_PERCENT / 100;
    }

    /**
     * @notice Calculate percentage change between two values
     * @dev Returns ((newValue - oldValue) / oldValue) * 100
     * @param oldValue Original value
     * @param newValue New value
     * @return Percentage change (fixed-point, can be negative if newValue < oldValue)
     *
     * @custom:example percentageChange(100e18, 110e18) = 10e16 (10% increase)
     */
    function percentageChange(
        uint256 oldValue,
        uint256 newValue
    ) internal pure returns (uint256) {
        if (oldValue == 0) {
            revert FixedPoint__DivisionByZero();
        }

        if (newValue >= oldValue) {
            // Positive change
            uint256 change = newValue - oldValue;
            return mul(div(change, oldValue), fromUint(100));
        } else {
            // Negative change - in unsigned context, we can't represent negative
            // Caller should compare newValue vs oldValue to determine direction
            uint256 change = oldValue - newValue;
            return mul(div(change, oldValue), fromUint(100));
        }
    }
}
