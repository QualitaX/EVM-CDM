// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FixedPoint} from "./FixedPoint.sol";
import {DayCount} from "./DayCount.sol";
import {CompoundingLib} from "./CompoundingLib.sol";
import {DateTime} from "./DateTime.sol";
import {Price, Reset, Period} from "../types/CDMTypes.sol";
import {
    PriceTypeEnum,
    CompoundingMethodEnum,
    DayCountFractionEnum,
    PeriodEnum,
    ArithmeticOperatorEnum
} from "../types/Enums.sol";

/**
 * @title InterestRate
 * @notice Interest rate calculations for fixed and floating rates
 * @dev Handles rate observations, resets, spread adjustments, and compounding
 * @dev All rates in fixed-point (18 decimals, e.g., 0.05e18 for 5%)
 *
 * FEATURES:
 * - Fixed rate calculations
 * - Floating rate calculations with observations
 * - Spread and multiplier adjustments
 * - Multiple compounding methods
 * - Rate reset handling
 * - Forward rate calculations
 *
 * REFERENCES:
 * - ISDA 2006 Definitions
 * - ISDA 2021 Definitions
 * - Market conventions for floating rate products
 *
 * @author QualitaX Team
 */
library InterestRate {

    using FixedPoint for uint256;
    using DayCount for *;
    using DateTime for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Zero rate constant
    uint256 internal constant ZERO_RATE = 0;

    /// @notice One hundred percent (for percentage calculations)
    uint256 internal constant ONE_HUNDRED_PERCENT = 100e18;

    // =============================================================================
    // ERRORS
    // =============================================================================

    error InterestRate__InvalidRate();
    error InterestRate__InvalidSpread();
    error InterestRate__InvalidMultiplier();
    error InterestRate__NoObservations();
    error InterestRate__InvalidPeriod();
    error InterestRate__NegativeRate();

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Fixed rate specification
    /// @dev Simple fixed rate for entire period
    struct FixedRate {
        uint256 rate;                       // Fixed rate (fixed-point, e.g., 0.05e18 for 5%)
        DayCountFractionEnum dayCountFraction; // Day count convention
    }

    /// @notice Floating rate specification
    /// @dev Rate determined by observations of a reference rate
    struct FloatingRate {
        bytes32 floatingRateIndex;          // Reference rate index (e.g., "SOFR", "LIBOR")
        uint256 spread;                     // Spread over reference (fixed-point, can be 0)
        uint256 multiplier;                 // Multiplier (fixed-point, default 1e18)
        DayCountFractionEnum dayCountFraction; // Day count convention
        CompoundingMethodEnum compoundingMethod; // How to compound observations
        bool spreadExclusive;               // If true, spread applied after compounding
    }

    /// @notice Rate observation
    /// @dev Single observation of a floating rate
    struct RateObservation {
        uint256 observationDate;            // Date rate was observed
        uint256 effectiveDate;              // Date from which rate is effective
        uint256 rate;                       // Observed rate (fixed-point)
        uint256 weight;                     // Weight for weighted averaging (optional)
    }

    /// @notice Calculated rate result
    /// @dev Result of rate calculation including all adjustments
    struct CalculatedRate {
        uint256 baseRate;                   // Base rate before adjustments
        uint256 spread;                     // Applied spread
        uint256 multiplier;                 // Applied multiplier
        uint256 finalRate;                  // Final rate after all adjustments
        uint256 dayCountFraction;           // Day count fraction for period
        uint256 interest;                   // Calculated interest amount
    }

    // =============================================================================
    // FIXED RATE FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate interest for a fixed rate
     * @dev Interest = principal * rate * dayCountFraction
     * @param principal Principal amount (fixed-point)
     * @param rate Fixed rate per annum (fixed-point)
     * @param startDate Start date of interest period
     * @param endDate End date of interest period
     * @param dayCountFraction Day count convention
     * @return Interest amount (fixed-point)
     *
     * @custom:example principal=1000000e18, rate=0.05e18 (5%), 365 days => ~50000e18
     */
    function calculateFixedRateInterest(
        uint256 principal,
        uint256 rate,
        uint256 startDate,
        uint256 endDate,
        DayCountFractionEnum dayCountFraction
    ) internal pure returns (uint256) {
        // Validate inputs
        if (rate < 0) revert InterestRate__NegativeRate();
        if (endDate < startDate) revert InterestRate__InvalidPeriod();

        // Calculate day count fraction
        uint256 dcf = DayCount.calculate(
            dayCountFraction,
            startDate,
            endDate,
            0,  // terminationDate (not needed for most conventions)
            0   // frequency (not needed for most conventions)
        );

        // Interest = principal * rate * dayCountFraction
        uint256 rateTimeFraction = rate.mul(dcf);
        return principal.mul(rateTimeFraction);
    }

    /**
     * @notice Calculate fixed rate payment
     * @dev Simplified version without notional scheduling
     * @param principal Principal amount
     * @param fixedRate Fixed rate specification
     * @param startDate Period start date
     * @param endDate Period end date
     * @return Payment amount
     */
    function calculateFixedPayment(
        uint256 principal,
        FixedRate memory fixedRate,
        uint256 startDate,
        uint256 endDate
    ) internal pure returns (uint256) {
        return calculateFixedRateInterest(
            principal,
            fixedRate.rate,
            startDate,
            endDate,
            fixedRate.dayCountFraction
        );
    }

    // =============================================================================
    // FLOATING RATE FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate interest for floating rate with single observation
     * @dev Handles spread and multiplier adjustments
     * @param principal Principal amount
     * @param observedRate Observed reference rate
     * @param spread Spread over reference rate
     * @param multiplier Rate multiplier
     * @param startDate Period start date
     * @param endDate Period end date
     * @param dayCountFraction Day count convention
     * @return Interest amount
     */
    function calculateFloatingRateInterest(
        uint256 principal,
        uint256 observedRate,
        uint256 spread,
        uint256 multiplier,
        uint256 startDate,
        uint256 endDate,
        DayCountFractionEnum dayCountFraction
    ) internal pure returns (uint256) {
        // Calculate day count fraction
        uint256 dcf = DayCount.calculate(
            dayCountFraction,
            startDate,
            endDate,
            0,
            0
        );

        // Apply adjustments: (observedRate * multiplier) + spread
        uint256 adjustedRate = observedRate.mul(multiplier).add(spread);

        // Interest = principal * adjustedRate * dayCountFraction
        uint256 rateTimeFraction = adjustedRate.mul(dcf);
        return principal.mul(rateTimeFraction);
    }

    /**
     * @notice Calculate compounded floating rate from multiple observations
     * @dev Supports various compounding methods per ISDA definitions
     * @param observations Array of rate observations
     * @param compoundingMethod How to compound rates
     * @return Compounded rate (fixed-point)
     */
    function calculateCompoundedRate(
        RateObservation[] memory observations,
        CompoundingMethodEnum compoundingMethod
    ) internal pure returns (uint256) {
        if (observations.length == 0) {
            revert InterestRate__NoObservations();
        }

        // Single observation - no compounding needed
        if (observations.length == 1) {
            return observations[0].rate;
        }

        // Extract rates into array
        uint256[] memory rates = new uint256[](observations.length);
        for (uint256 i = 0; i < observations.length; i++) {
            rates[i] = observations[i].rate;
        }

        // Compound using CompoundingLib
        return CompoundingLib.compound(rates, compoundingMethod);
    }

    /**
     * @notice Calculate weighted average of rate observations
     * @dev Uses weights from observations (e.g., time-based)
     * @param observations Array of rate observations with weights
     * @return Weighted average rate
     */
    function calculateWeightedAverageRate(
        RateObservation[] memory observations
    ) internal pure returns (uint256) {
        if (observations.length == 0) {
            revert InterestRate__NoObservations();
        }

        if (observations.length == 1) {
            return observations[0].rate;
        }

        // Extract rates and weights
        uint256[] memory rates = new uint256[](observations.length);
        uint256[] memory weights = new uint256[](observations.length);

        for (uint256 i = 0; i < observations.length; i++) {
            rates[i] = observations[i].rate;
            weights[i] = observations[i].weight;
        }

        // Use CompoundingLib weighted average
        return CompoundingLib.weightedAverage(rates, weights);
    }

    // =============================================================================
    // SPREAD AND MULTIPLIER ADJUSTMENTS
    // =============================================================================

    /**
     * @notice Apply spread to a rate
     * @dev Spread can be positive or negative
     * @param rate Base rate
     * @param spread Spread to add (fixed-point, can be negative via subtraction)
     * @return Rate with spread applied
     */
    function applySpread(uint256 rate, uint256 spread) internal pure returns (uint256) {
        return rate.add(spread);
    }

    /**
     * @notice Apply multiplier to a rate
     * @dev Multiplier allows for leverage (>1) or discount (<1)
     * @param rate Base rate
     * @param multiplier Multiplier (fixed-point, 1e18 = 1.0)
     * @return Rate with multiplier applied
     */
    function applyMultiplier(uint256 rate, uint256 multiplier) internal pure returns (uint256) {
        if (multiplier == 0) revert InterestRate__InvalidMultiplier();
        return rate.mul(multiplier);
    }

    /**
     * @notice Apply spread and multiplier to rate
     * @dev Standard order: (rate * multiplier) + spread
     * @param rate Base rate
     * @param multiplier Rate multiplier
     * @param spread Spread to add
     * @return Adjusted rate
     */
    function applyAdjustments(
        uint256 rate,
        uint256 multiplier,
        uint256 spread
    ) internal pure returns (uint256) {
        // Standard convention: multiply first, then add spread
        uint256 multipliedRate = rate.mul(multiplier);
        return multipliedRate.add(spread);
    }

    /**
     * @notice Apply spread exclusive adjustment
     * @dev Spread applied after compounding: compound(rates) + spread
     * @param compoundedRate Already compounded rate
     * @param spread Spread to add after compounding
     * @return Final rate
     */
    function applySpreadExclusive(
        uint256 compoundedRate,
        uint256 spread
    ) internal pure returns (uint256) {
        return compoundedRate.add(spread);
    }

    // =============================================================================
    // RESET HANDLING
    // =============================================================================

    /**
     * @notice Extract rate from Reset structure
     * @dev Reset is CDM structure for rate resets
     * @param reset Reset data
     * @return Rate value (fixed-point)
     */
    function getRateFromReset(Reset memory reset) internal pure returns (uint256) {
        // Reset.resetValue is a Price with rate stored in amount.value
        return reset.resetValue.amount.value;
    }

    /**
     * @notice Create rate observation from Reset
     * @dev Converts CDM Reset to RateObservation
     * @param reset Reset data
     * @return RateObservation struct
     */
    function resetToObservation(Reset memory reset) internal pure returns (RateObservation memory) {
        return RateObservation({
            observationDate: reset.rateRecordDate,
            effectiveDate: reset.resetDate,
            rate: getRateFromReset(reset),
            weight: FixedPoint.ONE // Default weight
        });
    }

    /**
     * @notice Convert multiple resets to observations
     * @param resets Array of resets
     * @return Array of observations
     */
    function resetsToObservations(
        Reset[] memory resets
    ) internal pure returns (RateObservation[] memory) {
        RateObservation[] memory observations = new RateObservation[](resets.length);

        for (uint256 i = 0; i < resets.length; i++) {
            observations[i] = resetToObservation(resets[i]);
        }

        return observations;
    }

    // =============================================================================
    // RATE CONVERSION FUNCTIONS
    // =============================================================================

    /**
     * @notice Convert annual rate to period rate
     * @dev Divides annual rate by frequency
     * @param annualRate Annual rate (fixed-point)
     * @param paymentsPerYear Number of payments per year (e.g., 4 for quarterly)
     * @return Period rate
     */
    function annualToPeriodRate(
        uint256 annualRate,
        uint256 paymentsPerYear
    ) internal pure returns (uint256) {
        return CompoundingLib.annualToPeriodRate(annualRate, paymentsPerYear);
    }

    /**
     * @notice Convert period rate to annual rate
     * @dev Multiplies period rate by frequency
     * @param periodRate Period rate (fixed-point)
     * @param paymentsPerYear Number of payments per year
     * @return Annual rate
     */
    function periodToAnnualRate(
        uint256 periodRate,
        uint256 paymentsPerYear
    ) internal pure returns (uint256) {
        return CompoundingLib.periodToAnnualRate(periodRate, paymentsPerYear);
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Check if rate is within valid range
     * @dev Rates should be >= 0 and typically < 200% (2.0)
     * @param rate Rate to validate
     * @return true if valid
     */
    function isValidRate(uint256 rate) internal pure returns (bool) {
        // Rate should be non-negative and reasonable
        // Allow up to 200% (2.0) for extreme cases
        return rate >= 0 && rate <= 2e18;
    }

    /**
     * @notice Calculate effective rate including all adjustments
     * @dev Full calculation with compounding, spread, multiplier
     * @param observations Rate observations
     * @param floatingRate Floating rate specification
     * @return Calculated rate details
     */
    function calculateEffectiveRate(
        RateObservation[] memory observations,
        FloatingRate memory floatingRate
    ) internal pure returns (CalculatedRate memory) {
        // Calculate base rate (compounded if multiple observations)
        uint256 baseRate;
        if (observations.length == 1) {
            baseRate = observations[0].rate;
        } else {
            baseRate = calculateCompoundedRate(observations, floatingRate.compoundingMethod);
        }

        // Apply adjustments
        uint256 finalRate;
        if (floatingRate.spreadExclusive) {
            // Spread exclusive: (rate * multiplier) then compound, then + spread
            uint256 multipliedRate = applyMultiplier(baseRate, floatingRate.multiplier);
            finalRate = applySpreadExclusive(multipliedRate, floatingRate.spread);
        } else {
            // Standard: (rate * multiplier) + spread
            finalRate = applyAdjustments(baseRate, floatingRate.multiplier, floatingRate.spread);
        }

        return CalculatedRate({
            baseRate: baseRate,
            spread: floatingRate.spread,
            multiplier: floatingRate.multiplier,
            finalRate: finalRate,
            dayCountFraction: 0,  // Calculated separately with dates
            interest: 0           // Calculated separately with principal
        });
    }

    /**
     * @notice Create simple fixed rate
     * @param rate Rate value
     * @param dayCountFraction Day count convention
     * @return FixedRate struct
     */
    function createFixedRate(
        uint256 rate,
        DayCountFractionEnum dayCountFraction
    ) internal pure returns (FixedRate memory) {
        return FixedRate({
            rate: rate,
            dayCountFraction: dayCountFraction
        });
    }

    /**
     * @notice Create simple floating rate
     * @param floatingRateIndex Reference rate index
     * @param spread Spread over reference
     * @param dayCountFraction Day count convention
     * @return FloatingRate struct
     */
    function createFloatingRate(
        bytes32 floatingRateIndex,
        uint256 spread,
        DayCountFractionEnum dayCountFraction
    ) internal pure returns (FloatingRate memory) {
        return FloatingRate({
            floatingRateIndex: floatingRateIndex,
            spread: spread,
            multiplier: FixedPoint.ONE,  // Default multiplier = 1.0
            dayCountFraction: dayCountFraction,
            compoundingMethod: CompoundingMethodEnum.NONE,
            spreadExclusive: false
        });
    }

    /**
     * @notice Create rate observation
     * @param observationDate Date observed
     * @param effectiveDate Date effective from
     * @param rate Observed rate
     * @return RateObservation struct
     */
    function createObservation(
        uint256 observationDate,
        uint256 effectiveDate,
        uint256 rate
    ) internal pure returns (RateObservation memory) {
        return RateObservation({
            observationDate: observationDate,
            effectiveDate: effectiveDate,
            rate: rate,
            weight: FixedPoint.ONE
        });
    }
}
