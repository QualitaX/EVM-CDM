// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CompoundingMethodEnum} from "../types/Enums.sol";
import {FixedPoint} from "./FixedPoint.sol";

/**
 * @title CompoundingLib
 * @notice Compound and averaging calculations for interest rates
 * @dev Used for floating rate calculations with various compounding methods
 * @dev All rates are in fixed-point (18 decimals)
 *
 * COMPOUNDING METHODS:
 * - NONE/FLAT: No compounding (simple average)
 * - STRAIGHT: Geometric compounding (1+r1)*(1+r2)*...-1
 * - SPREAD_EXCLUSIVE: Spread exclusive compounding
 *
 * REFERENCES:
 * - ISDA 2006 Definitions
 * - OpenGamma Strata (reference implementation)
 * - Market conventions for floating rate calculations
 *
 * @custom:security-contact security@finos.org
 * @author FINOS CDM EVM Framework Team
 */
library CompoundingLib {

    using FixedPoint for uint256;

    // =============================================================================
    // ERRORS
    // =============================================================================

    error CompoundingLib__EmptyRatesArray();
    error CompoundingLib__ArrayLengthMismatch();
    error CompoundingLib__UnsupportedMethod();
    error CompoundingLib__InvalidWeights();

    // =============================================================================
    // COMPOUNDING FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate compounded rate from array of rates
     * @dev Routes to appropriate compounding method
     * @param rates Array of rates (fixed-point, e.g., 0.05e18 for 5%)
     * @param method Compounding method
     * @return Compounded rate (fixed-point)
     *
     * @custom:example rates = [0.05e18, 0.06e18], FLAT => 0.055e18 (5.5%)
     * @custom:example rates = [0.05e18, 0.06e18], STRAIGHT => ~0.053e18 (5.3%)
     */
    function compound(
        uint256[] memory rates,
        CompoundingMethodEnum method
    ) internal pure returns (uint256) {
        // Validate input
        if (rates.length == 0) {
            revert CompoundingLib__EmptyRatesArray();
        }

        // Single rate - no compounding needed
        if (rates.length == 1) {
            return rates[0];
        }

        // Route to appropriate method
        if (method == CompoundingMethodEnum.NONE || method == CompoundingMethodEnum.FLAT) {
            return simpleAverage(rates);

        } else if (method == CompoundingMethodEnum.STRAIGHT) {
            return geometricCompounding(rates);

        } else if (method == CompoundingMethodEnum.SPREAD_EXCLUSIVE) {
            return spreadExclusiveCompounding(rates);

        } else {
            revert CompoundingLib__UnsupportedMethod();
        }
    }

    // =============================================================================
    // SIMPLE AVERAGE (FLAT COMPOUNDING)
    // =============================================================================

    /**
     * @notice Calculate simple average of rates
     * @dev Arithmetic mean: (r1 + r2 + ... + rn) / n
     * @param rates Array of rates (fixed-point)
     * @return Average rate (fixed-point)
     *
     * @custom:example [0.05e18, 0.06e18] => 0.055e18 (5.5%)
     */
    function simpleAverage(uint256[] memory rates) internal pure returns (uint256) {
        if (rates.length == 0) {
            revert CompoundingLib__EmptyRatesArray();
        }

        uint256 sum = 0;
        for (uint256 i = 0; i < rates.length; i++) {
            sum = sum.add(rates[i]);
        }

        return sum / rates.length;
    }

    // =============================================================================
    // GEOMETRIC COMPOUNDING (STRAIGHT)
    // =============================================================================

    /**
     * @notice Calculate geometric compounded rate
     * @dev Formula: (1+r1) * (1+r2) * ... * (1+rn) - 1
     * @dev This is the mathematically correct way to compound rates
     * @param rates Array of rates (fixed-point)
     * @return Compounded rate (fixed-point)
     *
     * @custom:example [0.05e18, 0.06e18] => ~0.053e18
     * @custom:explanation (1.05) * (1.06) - 1 = 1.113 - 1 = 0.113 = 11.3%
     * @custom:explanation But for daily rates: (1.0001369)^2 - 1
     */
    function geometricCompounding(uint256[] memory rates) internal pure returns (uint256) {
        if (rates.length == 0) {
            revert CompoundingLib__EmptyRatesArray();
        }

        // Start with 1.0
        uint256 product = FixedPoint.ONE;

        // Multiply (1 + rate) for each rate
        for (uint256 i = 0; i < rates.length; i++) {
            // (1 + rate)
            uint256 onePlusRate = FixedPoint.ONE.add(rates[i]);

            // Multiply accumulated product
            product = product.mul(onePlusRate);
        }

        // Subtract 1.0 to get compounded rate
        return product.sub(FixedPoint.ONE);
    }

    // =============================================================================
    // SPREAD EXCLUSIVE COMPOUNDING
    // =============================================================================

    /**
     * @notice Calculate spread exclusive compounded rate
     * @dev Used when spread is applied after compounding
     * @dev Formula: ((1+r1) * (1+r2) * ... * (1+rn))^(1/n) - 1
     * @param rates Array of rates (fixed-point)
     * @return Compounded rate (fixed-point)
     *
     * @custom:note This is a simplified implementation
     * @custom:note Full implementation requires nth root calculation
     */
    function spreadExclusiveCompounding(
        uint256[] memory rates
    ) internal pure returns (uint256) {
        if (rates.length == 0) {
            revert CompoundingLib__EmptyRatesArray();
        }

        // Simplified: use geometric mean approximation
        // For small rates, geometric compounding ≈ arithmetic average
        // Full implementation would calculate nth root

        uint256 product = geometricCompounding(rates);

        // Approximate nth root by dividing by number of periods
        // This is a simplification; exact nth root is complex
        return product / rates.length;
    }

    // =============================================================================
    // WEIGHTED AVERAGE
    // =============================================================================

    /**
     * @notice Calculate weighted average of rates
     * @dev Weights must sum to 1.0 (in fixed-point)
     * @param rates Array of rates (fixed-point)
     * @param weights Array of weights (fixed-point, must sum to 1.0)
     * @return Weighted average rate (fixed-point)
     *
     * @custom:example rates = [0.05e18, 0.06e18], weights = [0.6e18, 0.4e18]
     * @custom:explanation => 0.05*0.6 + 0.06*0.4 = 0.03 + 0.024 = 0.054 = 5.4%
     */
    function weightedAverage(
        uint256[] memory rates,
        uint256[] memory weights
    ) internal pure returns (uint256) {
        // Validate input
        if (rates.length == 0) {
            revert CompoundingLib__EmptyRatesArray();
        }
        if (rates.length != weights.length) {
            revert CompoundingLib__ArrayLengthMismatch();
        }

        // Validate weights sum to 1.0 (with small tolerance)
        uint256 weightSum = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            weightSum = weightSum.add(weights[i]);
        }

        // Allow small rounding error (0.01%)
        if (weightSum < FixedPoint.ONE - 1e14 || weightSum > FixedPoint.ONE + 1e14) {
            revert CompoundingLib__InvalidWeights();
        }

        // Calculate weighted sum
        uint256 sum = 0;
        for (uint256 i = 0; i < rates.length; i++) {
            sum = sum.add(rates[i].mul(weights[i]));
        }

        return sum;
    }

    // =============================================================================
    // TIME-WEIGHTED COMPOUNDING
    // =============================================================================

    /**
     * @notice Calculate time-weighted average rate
     * @dev Each rate is weighted by its time period
     * @param rates Array of rates (fixed-point)
     * @param daysCounts Array of days for each rate
     * @return Time-weighted average rate (fixed-point)
     *
     * @custom:example rates = [0.05e18, 0.06e18], daysCounts = [10, 20]
     * @custom:explanation => (0.05*10 + 0.06*20) / 30 = (0.5 + 1.2) / 30 = 0.0567
     */
    function timeWeightedAverage(
        uint256[] memory rates,
        uint256[] memory daysCounts
    ) internal pure returns (uint256) {
        // Validate input
        if (rates.length == 0) {
            revert CompoundingLib__EmptyRatesArray();
        }
        if (rates.length != daysCounts.length) {
            revert CompoundingLib__ArrayLengthMismatch();
        }

        // Calculate total days
        uint256 totalDays = 0;
        for (uint256 i = 0; i < daysCounts.length; i++) {
            totalDays += daysCounts[i];
        }

        if (totalDays == 0) {
            revert CompoundingLib__EmptyRatesArray();
        }

        // Calculate weighted sum
        uint256 sum = 0;
        for (uint256 i = 0; i < rates.length; i++) {
            // rate * daysCounts (in fixed-point)
            uint256 weightedRate = rates[i].mul(FixedPoint.fromUint(daysCounts[i]));
            sum = sum.add(weightedRate);
        }

        // Divide by total days
        return sum.div(FixedPoint.fromUint(totalDays));
    }

    // =============================================================================
    // UTILITY FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate accrual factor for a rate over a period
     * @dev Accrual factor = 1 + rate * time_fraction
     * @param rate Interest rate (fixed-point)
     * @param timeFraction Time fraction from day count calculation (fixed-point)
     * @return Accrual factor (fixed-point)
     *
     * @custom:example rate = 0.05e18 (5%), timeFraction = 0.25e18 (3 months)
     * @custom:explanation => 1 + 0.05 * 0.25 = 1.0125 (1.25% accrual)
     */
    function accrualFactor(
        uint256 rate,
        uint256 timeFraction
    ) internal pure returns (uint256) {
        // 1 + rate * timeFraction
        return FixedPoint.ONE.add(rate.mul(timeFraction));
    }

    /**
     * @notice Calculate discount factor for a rate over a period
     * @dev Discount factor = 1 / (1 + rate * time_fraction)
     * @param rate Interest rate (fixed-point)
     * @param timeFraction Time fraction from day count calculation (fixed-point)
     * @return Discount factor (fixed-point)
     *
     * @custom:example rate = 0.05e18 (5%), timeFraction = 1e18 (1 year)
     * @custom:explanation => 1 / (1 + 0.05) = 1 / 1.05 = 0.9524 (95.24%)
     */
    function discountFactor(
        uint256 rate,
        uint256 timeFraction
    ) internal pure returns (uint256) {
        // 1 / (1 + rate * timeFraction)
        uint256 onePlusRateTime = FixedPoint.ONE.add(rate.mul(timeFraction));
        return FixedPoint.div(FixedPoint.ONE, onePlusRateTime);
    }

    /**
     * @notice Calculate continuously compounded rate
     * @dev Formula: e^(r*t) - 1
     * @dev Simplified approximation for small r*t: r*t + (r*t)^2/2
     * @param rate Interest rate (fixed-point)
     * @param timeFraction Time fraction (fixed-point)
     * @return Continuously compounded rate (fixed-point)
     *
     * @custom:note This is an approximation suitable for small rates
     * @custom:note Full implementation would require exponential function
     */
    function continuousCompounding(
        uint256 rate,
        uint256 timeFraction
    ) internal pure returns (uint256) {
        // For small x: e^x ≈ 1 + x + x^2/2
        uint256 rt = rate.mul(timeFraction);

        // First order: r*t
        uint256 firstOrder = rt;

        // Second order: (r*t)^2 / 2
        uint256 rtSquared = rt.mul(rt);
        uint256 secondOrder = rtSquared / 2;

        // e^(r*t) - 1 ≈ r*t + (r*t)^2/2
        return firstOrder.add(secondOrder);
    }

    /**
     * @notice Convert annual rate to rate for given frequency
     * @dev Divides annual rate by frequency
     * @param annualRate Annual rate (fixed-point)
     * @param frequency Payments per year (e.g., 4 for quarterly)
     * @return Period rate (fixed-point)
     *
     * @custom:example annualRate = 0.06e18 (6%), frequency = 4 (quarterly)
     * @custom:explanation => 0.06 / 4 = 0.015 (1.5% per quarter)
     */
    function annualToPeriodRate(
        uint256 annualRate,
        uint256 frequency
    ) internal pure returns (uint256) {
        require(frequency > 0, "Frequency must be > 0");
        return annualRate / frequency;
    }

    /**
     * @notice Convert period rate to annual rate
     * @dev Multiplies period rate by frequency
     * @param periodRate Period rate (fixed-point)
     * @param frequency Payments per year
     * @return Annual rate (fixed-point)
     */
    function periodToAnnualRate(
        uint256 periodRate,
        uint256 frequency
    ) internal pure returns (uint256) {
        require(frequency > 0, "Frequency must be > 0");
        return periodRate * frequency;
    }
}
