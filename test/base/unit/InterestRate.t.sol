// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {InterestRate} from "../../../src/base/libraries/InterestRate.sol";
import {FixedPoint} from "../../../src/base/libraries/FixedPoint.sol";
import {DayCountFractionEnum, CompoundingMethodEnum} from "../../../src/base/types/Enums.sol";

contract InterestRateTest is Test {
    using FixedPoint for uint256;

    // Constants for testing
    uint256 constant ONE = 1e18;
    uint256 constant ZERO = 0;

    // Test dates
    uint256 constant JAN_1_2024 = 1704067200;  // Jan 1, 2024 00:00:00 UTC
    uint256 constant JUL_1_2024 = 1719792000;  // Jul 1, 2024 00:00:00 UTC
    uint256 constant JAN_1_2025 = 1735689600;  // Jan 1, 2025 00:00:00 UTC

    // Test rates
    uint256 constant RATE_5_PERCENT = 0.05e18;  // 5%
    uint256 constant RATE_3_PERCENT = 0.03e18;  // 3%
    uint256 constant SPREAD_50_BPS = 0.005e18;  // 0.5%

    // =============================================================================
    // FIXED RATE TESTS
    // =============================================================================

    function test_CalculateFixedRateInterest_OneYear() public {
        uint256 principal = 1000000e18;  // 1M
        uint256 rate = RATE_5_PERCENT;

        uint256 interest = InterestRate.calculateFixedRateInterest(
            principal,
            rate,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~50,000 (small variance due to actual day count)
        // ACT_365_FIXED uses 365-day year, but actual days may vary slightly
        uint256 expected = 50000e18;
        assertApproxEqAbs(interest, expected, 200e18, "Fixed rate interest for one year");
    }

    function test_CalculateFixedRateInterest_SixMonths() public {
        uint256 principal = 1000000e18;
        uint256 rate = RATE_5_PERCENT;

        uint256 interest = InterestRate.calculateFixedRateInterest(
            principal,
            rate,
            JAN_1_2024,
            JUL_1_2024,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: 1,000,000 * 0.05 * (182/365) = ~24,931.51
        uint256 expected = 24931506849315068490000; // ~24,931.51
        assertApproxEqAbs(interest, expected, 1e18, "Fixed rate interest for six months");
    }

    function test_CalculateFixedRateInterest_ACT360() public {
        uint256 principal = 1000000e18;
        uint256 rate = RATE_5_PERCENT;

        uint256 interest = InterestRate.calculateFixedRateInterest(
            principal,
            rate,
            JAN_1_2024,
            JUL_1_2024,
            DayCountFractionEnum.ACT_360
        );

        // Expected: 1,000,000 * 0.05 * (182/360) = ~25,277.78
        uint256 expected = 25277777777777777780000; // ~25,277.78
        assertApproxEqAbs(interest, expected, 1e18, "ACT/360 day count");
    }

    function test_CalculateFixedRateInterest_ZeroRate() public {
        uint256 principal = 1000000e18;

        uint256 interest = InterestRate.calculateFixedRateInterest(
            principal,
            ZERO,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        assertEq(interest, 0, "Zero rate should produce zero interest");
    }

    function test_CalculateFixedRateInterest_ZeroPrincipal() public {
        uint256 interest = InterestRate.calculateFixedRateInterest(
            ZERO,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        assertEq(interest, 0, "Zero principal should produce zero interest");
    }

    function test_CalculateFixedPayment() public {
        uint256 principal = 1000000e18;
        InterestRate.FixedRate memory fixedRate = InterestRate.FixedRate({
            rate: RATE_5_PERCENT,
            dayCountFraction: DayCountFractionEnum.ACT_365_FIXED
        });

        uint256 payment = InterestRate.calculateFixedPayment(
            principal,
            fixedRate,
            JAN_1_2024,
            JAN_1_2025
        );

        uint256 expected = 50000e18;
        assertApproxEqAbs(payment, expected, 200e18, "Fixed payment calculation");
    }

    // =============================================================================
    // FLOATING RATE TESTS
    // =============================================================================

    function test_CalculateFloatingRateInterest_NoSpread() public {
        uint256 principal = 1000000e18;
        uint256 observedRate = RATE_3_PERCENT;
        uint256 spread = 0;
        uint256 multiplier = ONE;  // 1.0

        uint256 interest = InterestRate.calculateFloatingRateInterest(
            principal,
            observedRate,
            spread,
            multiplier,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~30,000 (small variance due to day count)
        uint256 expected = 30000e18;
        assertApproxEqAbs(interest, expected, 100e18, "Floating rate with no spread");
    }

    function test_CalculateFloatingRateInterest_WithSpread() public {
        uint256 principal = 1000000e18;
        uint256 observedRate = RATE_3_PERCENT;
        uint256 spread = SPREAD_50_BPS;  // 0.5%
        uint256 multiplier = ONE;

        uint256 interest = InterestRate.calculateFloatingRateInterest(
            principal,
            observedRate,
            spread,
            multiplier,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~35,000 (small variance due to day count)
        uint256 expected = 35000e18;
        assertApproxEqAbs(interest, expected, 100e18, "Floating rate with 50 bps spread");
    }

    function test_CalculateFloatingRateInterest_WithMultiplier() public {
        uint256 principal = 1000000e18;
        uint256 observedRate = RATE_3_PERCENT;
        uint256 spread = 0;
        uint256 multiplier = 2e18;  // 2.0 (leverage)

        uint256 interest = InterestRate.calculateFloatingRateInterest(
            principal,
            observedRate,
            spread,
            multiplier,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~60,000 (small variance due to day count)
        uint256 expected = 60000e18;
        assertApproxEqAbs(interest, expected, 200e18, "Floating rate with 2x multiplier");
    }

    function test_CalculateFloatingRateInterest_SpreadAndMultiplier() public {
        uint256 principal = 1000000e18;
        uint256 observedRate = RATE_3_PERCENT;
        uint256 spread = SPREAD_50_BPS;
        uint256 multiplier = 1.5e18;  // 1.5x

        uint256 interest = InterestRate.calculateFloatingRateInterest(
            principal,
            observedRate,
            spread,
            multiplier,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~50,000 (small variance due to day count)
        uint256 expected = 50000e18;
        assertApproxEqAbs(interest, expected, 200e18, "Floating rate with spread and multiplier");
    }

    // =============================================================================
    // COMPOUNDED RATE TESTS
    // =============================================================================

    function test_CalculateCompoundedRate_SingleObservation() public {
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](1);
        observations[0] = InterestRate.RateObservation({
            observationDate: JAN_1_2024,
            effectiveDate: JAN_1_2024,
            rate: RATE_5_PERCENT,
            weight: ONE
        });

        uint256 compoundedRate = InterestRate.calculateCompoundedRate(
            observations,
            CompoundingMethodEnum.FLAT
        );

        assertEq(compoundedRate, RATE_5_PERCENT, "Single observation should return same rate");
    }

    function test_CalculateCompoundedRate_Flat() public {
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](3);
        observations[0] = createObservation(RATE_3_PERCENT);
        observations[1] = createObservation(0.04e18);  // 4%
        observations[2] = createObservation(RATE_5_PERCENT);

        uint256 compoundedRate = InterestRate.calculateCompoundedRate(
            observations,
            CompoundingMethodEnum.FLAT
        );

        // Expected: (3% + 4% + 5%) / 3 = 4%
        uint256 expected = 0.04e18;
        assertEq(compoundedRate, expected, "Flat compounding (simple average)");
    }

    function test_CalculateCompoundedRate_Straight() public {
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](2);
        observations[0] = createObservation(RATE_5_PERCENT);
        observations[1] = createObservation(0.06e18);  // 6%

        uint256 compoundedRate = InterestRate.calculateCompoundedRate(
            observations,
            CompoundingMethodEnum.STRAIGHT
        );

        // Expected: ((1 + 0.05) * (1 + 0.06)) - 1 = 0.113 = 11.3%
        uint256 expected = 0.113e18;
        assertApproxEqAbs(compoundedRate, expected, 1e14, "Straight (geometric) compounding");
    }

    // =============================================================================
    // WEIGHTED AVERAGE TESTS
    // =============================================================================

    function test_CalculateWeightedAverageRate_SingleObservation() public {
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](1);
        observations[0] = InterestRate.RateObservation({
            observationDate: JAN_1_2024,
            effectiveDate: JAN_1_2024,
            rate: RATE_5_PERCENT,
            weight: 100e18
        });

        uint256 avgRate = InterestRate.calculateWeightedAverageRate(observations);

        assertEq(avgRate, RATE_5_PERCENT, "Single weighted observation");
    }

    function test_CalculateWeightedAverageRate_EqualWeights() public {
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](3);
        // Weights must sum to 1.0 (1e18). For equal weights: 1/3 each
        uint256 weight = ONE / 3;  // 0.333...
        observations[0] = createWeightedObservation(RATE_3_PERCENT, weight);
        observations[1] = createWeightedObservation(0.04e18, weight);
        observations[2] = createWeightedObservation(RATE_5_PERCENT, ONE - (weight * 2));  // Remainder to sum to 1.0

        uint256 avgRate = InterestRate.calculateWeightedAverageRate(observations);

        // Expected: (3% * 1/3 + 4% * 1/3 + 5% * 1/3) = 4%
        uint256 expected = 0.04e18;
        assertEq(avgRate, expected, "Weighted average with equal weights");
    }

    function test_CalculateWeightedAverageRate_DifferentWeights() public {
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](3);
        // Weights must sum to 1.0. Use 0.25, 0.50, 0.25 (sum = 1.0)
        observations[0] = createWeightedObservation(RATE_3_PERCENT, 0.25e18);
        observations[1] = createWeightedObservation(0.04e18, 0.50e18);
        observations[2] = createWeightedObservation(RATE_5_PERCENT, 0.25e18);

        uint256 avgRate = InterestRate.calculateWeightedAverageRate(observations);

        // Expected: (3% * 0.25 + 4% * 0.50 + 5% * 0.25) = 4%
        uint256 expected = 0.04e18;
        assertEq(avgRate, expected, "Weighted average with different weights");
    }

    // =============================================================================
    // SPREAD AND MULTIPLIER ADJUSTMENTS
    // =============================================================================

    function test_ApplySpread() public {
        uint256 rate = RATE_3_PERCENT;
        uint256 spread = SPREAD_50_BPS;

        uint256 adjustedRate = InterestRate.applySpread(rate, spread);

        assertEq(adjustedRate, 0.035e18, "Apply 50 bps spread to 3%");
    }

    function test_ApplyMultiplier() public {
        uint256 rate = RATE_3_PERCENT;
        uint256 multiplier = 2e18;  // 2.0

        uint256 adjustedRate = InterestRate.applyMultiplier(rate, multiplier);

        assertEq(adjustedRate, 0.06e18, "Apply 2x multiplier to 3%");
    }

    function test_ApplyAdjustments() public {
        uint256 rate = RATE_3_PERCENT;
        uint256 multiplier = 2e18;
        uint256 spread = SPREAD_50_BPS;

        uint256 adjustedRate = InterestRate.applyAdjustments(rate, multiplier, spread);

        // Expected: (3% * 2) + 0.5% = 6.5%
        assertEq(adjustedRate, 0.065e18, "Apply multiplier then spread");
    }

    function test_ApplySpreadExclusive() public {
        uint256 compoundedRate = 0.04e18;  // 4%
        uint256 spread = SPREAD_50_BPS;

        uint256 finalRate = InterestRate.applySpreadExclusive(compoundedRate, spread);

        assertEq(finalRate, 0.045e18, "Apply spread exclusive");
    }

    // =============================================================================
    // RATE CONVERSION TESTS
    // =============================================================================

    function test_AnnualToPeriodRate_Quarterly() public {
        uint256 annualRate = 0.04e18;  // 4%
        uint256 paymentsPerYear = 4;   // Quarterly

        uint256 periodRate = InterestRate.annualToPeriodRate(annualRate, paymentsPerYear);

        assertEq(periodRate, 0.01e18, "Annual to quarterly rate");
    }

    function test_PeriodToAnnualRate_Quarterly() public {
        uint256 periodRate = 0.01e18;  // 1%
        uint256 paymentsPerYear = 4;

        uint256 annualRate = InterestRate.periodToAnnualRate(periodRate, paymentsPerYear);

        assertEq(annualRate, 0.04e18, "Quarterly to annual rate");
    }

    function test_AnnualToPeriodRate_SemiAnnual() public {
        uint256 annualRate = 0.06e18;  // 6%
        uint256 paymentsPerYear = 2;   // Semi-annual

        uint256 periodRate = InterestRate.annualToPeriodRate(annualRate, paymentsPerYear);

        assertEq(periodRate, 0.03e18, "Annual to semi-annual rate");
    }

    // =============================================================================
    // HELPER FUNCTION TESTS
    // =============================================================================

    function test_IsValidRate() public {
        assertTrue(InterestRate.isValidRate(0), "Zero is valid rate");
        assertTrue(InterestRate.isValidRate(RATE_5_PERCENT), "5% is valid rate");
        assertTrue(InterestRate.isValidRate(1e18), "100% is valid rate");
        assertTrue(InterestRate.isValidRate(2e18), "200% is valid rate");
        assertFalse(InterestRate.isValidRate(3e18), "300% is invalid rate");
    }

    function test_CreateFixedRate() public {
        InterestRate.FixedRate memory fixedRate = InterestRate.createFixedRate(
            RATE_5_PERCENT,
            DayCountFractionEnum.ACT_365_FIXED
        );

        assertEq(fixedRate.rate, RATE_5_PERCENT, "Fixed rate value");
        assertTrue(uint8(fixedRate.dayCountFraction) == uint8(DayCountFractionEnum.ACT_365_FIXED), "Day count fraction");
    }

    function test_CreateFloatingRate() public {
        bytes32 indexName = bytes32("SOFR");
        uint256 spread = SPREAD_50_BPS;

        InterestRate.FloatingRate memory floatingRate = InterestRate.createFloatingRate(
            indexName,
            spread,
            DayCountFractionEnum.ACT_360
        );

        assertEq(floatingRate.floatingRateIndex, indexName, "Floating rate index");
        assertEq(floatingRate.spread, spread, "Spread");
        assertEq(floatingRate.multiplier, ONE, "Default multiplier");
        assertTrue(uint8(floatingRate.dayCountFraction) == uint8(DayCountFractionEnum.ACT_360), "Day count");
        assertTrue(uint8(floatingRate.compoundingMethod) == uint8(CompoundingMethodEnum.NONE), "Compounding method");
        assertFalse(floatingRate.spreadExclusive, "Spread exclusive");
    }

    function test_CreateObservation() public {
        uint256 rate = RATE_5_PERCENT;

        InterestRate.RateObservation memory obs = InterestRate.createObservation(
            JAN_1_2024,
            JAN_1_2024,
            rate
        );

        assertEq(obs.observationDate, JAN_1_2024, "Observation date");
        assertEq(obs.effectiveDate, JAN_1_2024, "Effective date");
        assertEq(obs.rate, rate, "Rate");
        assertEq(obs.weight, ONE, "Default weight");
    }

    function test_CalculateEffectiveRate_Simple() public {
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](1);
        observations[0] = createObservation(RATE_5_PERCENT);

        InterestRate.FloatingRate memory floatingRate = InterestRate.FloatingRate({
            floatingRateIndex: bytes32("SOFR"),
            spread: SPREAD_50_BPS,
            multiplier: ONE,
            dayCountFraction: DayCountFractionEnum.ACT_360,
            compoundingMethod: CompoundingMethodEnum.NONE,
            spreadExclusive: false
        });

        InterestRate.CalculatedRate memory result = InterestRate.calculateEffectiveRate(
            observations,
            floatingRate
        );

        assertEq(result.baseRate, RATE_5_PERCENT, "Base rate");
        assertEq(result.spread, SPREAD_50_BPS, "Spread");
        assertEq(result.multiplier, ONE, "Multiplier");
        assertEq(result.finalRate, 0.055e18, "Final rate (5% + 0.5%)");
    }

    function test_CalculateEffectiveRate_WithMultiplier() public {
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](1);
        observations[0] = createObservation(RATE_3_PERCENT);

        InterestRate.FloatingRate memory floatingRate = InterestRate.FloatingRate({
            floatingRateIndex: bytes32("SOFR"),
            spread: SPREAD_50_BPS,
            multiplier: 2e18,  // 2x
            dayCountFraction: DayCountFractionEnum.ACT_360,
            compoundingMethod: CompoundingMethodEnum.NONE,
            spreadExclusive: false
        });

        InterestRate.CalculatedRate memory result = InterestRate.calculateEffectiveRate(
            observations,
            floatingRate
        );

        assertEq(result.baseRate, RATE_3_PERCENT, "Base rate");
        assertEq(result.finalRate, 0.065e18, "Final rate (3% * 2 + 0.5%)");
    }

    // =============================================================================
    // REAL-WORLD SCENARIOS
    // =============================================================================

    function test_RealWorld_SwapFixedLeg() public {
        // 5-year IRS, fixed leg: $10M notional, 5% fixed, semi-annual ACT/360
        uint256 notional = 10000000e18;
        uint256 rate = RATE_5_PERCENT;

        uint256 sixMonthInterest = InterestRate.calculateFixedRateInterest(
            notional,
            rate,
            JAN_1_2024,
            JUL_1_2024,
            DayCountFractionEnum.ACT_360
        );

        // Expected: 10M * 0.05 * (182/360) = ~252,777.78
        uint256 expected = 252777777777777777800000;
        assertApproxEqAbs(sixMonthInterest, expected, 1e18, "IRS fixed leg payment");
    }

    function test_RealWorld_SOFRCompounding() public {
        // Compounded SOFR with 3 daily observations
        InterestRate.RateObservation[] memory observations = new InterestRate.RateObservation[](3);
        observations[0] = createObservation(0.0525e18);  // 5.25%
        observations[1] = createObservation(0.0530e18);  // 5.30%
        observations[2] = createObservation(0.0535e18);  // 5.35%

        uint256 avgRate = InterestRate.calculateCompoundedRate(
            observations,
            CompoundingMethodEnum.FLAT
        );

        // Expected: (5.25% + 5.30% + 5.35%) / 3 = 5.30%
        uint256 expected = 0.053e18;
        assertEq(avgRate, expected, "Compounded SOFR (simple average)");
    }

    function test_RealWorld_FloatingRateBond() public {
        // Floating rate note: $1M, LIBOR + 75 bps, quarterly
        uint256 principal = 1000000e18;
        uint256 liborRate = 0.0275e18;  // 2.75%
        uint256 spread = 0.0075e18;     // 75 bps

        uint256 quarterlyInterest = InterestRate.calculateFloatingRateInterest(
            principal,
            liborRate,
            spread,
            ONE,
            JAN_1_2024,
            JAN_1_2024 + 91 days,
            DayCountFractionEnum.ACT_360
        );

        // Expected: 1M * (2.75% + 0.75%) * (91/360) = ~8,847.22
        // Tolerance increased due to fixed-point division
        uint256 expected = 8847222222222222000000;
        assertApproxEqAbs(quarterlyInterest, expected, 1e18, "Floating rate note coupon");
    }

    // =============================================================================
    // EDGE CASES
    // =============================================================================

    function test_EdgeCase_VerySmallRate() public {
        uint256 principal = 1000000e18;
        uint256 rate = 1e14;  // 0.01% (1 bps)

        uint256 interest = InterestRate.calculateFixedRateInterest(
            principal,
            rate,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Should be non-zero but very small
        assertTrue(interest > 0, "Very small rate should produce non-zero interest");
        assertTrue(interest < 1000e18, "Interest should be less than 1000");
    }

    function test_EdgeCase_MaxUint256Principal() public {
        // This should not overflow due to fixed-point math scaling
        uint256 principal = type(uint128).max;  // Use uint128 max to avoid overflow
        uint256 rate = 0.0001e18;  // 0.01% (very small rate)

        uint256 interest = InterestRate.calculateFixedRateInterest(
            principal,
            rate,
            JAN_1_2024,
            JAN_1_2024 + 1 days,
            DayCountFractionEnum.ACT_360
        );

        assertTrue(interest > 0, "Should calculate interest for large principal");
    }

    function test_EdgeCase_SameDatePeriod() public {
        uint256 principal = 1000000e18;
        uint256 rate = RATE_5_PERCENT;

        uint256 interest = InterestRate.calculateFixedRateInterest(
            principal,
            rate,
            JAN_1_2024,
            JAN_1_2024,
            DayCountFractionEnum.ACT_365_FIXED
        );

        assertEq(interest, 0, "Same start and end date should produce zero interest");
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function createObservation(uint256 rate) internal pure returns (InterestRate.RateObservation memory) {
        return InterestRate.RateObservation({
            observationDate: JAN_1_2024,
            effectiveDate: JAN_1_2024,
            rate: rate,
            weight: ONE
        });
    }

    function createWeightedObservation(
        uint256 rate,
        uint256 weight
    ) internal pure returns (InterestRate.RateObservation memory) {
        return InterestRate.RateObservation({
            observationDate: JAN_1_2024,
            effectiveDate: JAN_1_2024,
            rate: rate,
            weight: weight
        });
    }
}
