// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {CompoundingLib} from "../../../src/base/libraries/CompoundingLib.sol";
import {FixedPoint} from "../../../src/base/libraries/FixedPoint.sol";
import {CompoundingMethodEnum} from "../../../src/base/types/Enums.sol";

/**
 * @title CompoundingLibTest
 * @notice Unit tests for CompoundingLib library
 * @dev Tests interest rate compounding and averaging methods
 */
contract CompoundingLibTest is Test {

    using FixedPoint for uint256;

    // =============================================================================
    // EXTERNAL WRAPPERS (for testing reverts)
    // =============================================================================

    function externalCompound(
        uint256[] memory rates,
        CompoundingMethodEnum method
    ) external pure returns (uint256) {
        return CompoundingLib.compound(rates, method);
    }

    function externalWeightedAverage(
        uint256[] memory rates,
        uint256[] memory weights
    ) external pure returns (uint256) {
        return CompoundingLib.weightedAverage(rates, weights);
    }

    function externalTimeWeightedAverage(
        uint256[] memory rates,
        uint256[] memory daysCounts
    ) external pure returns (uint256) {
        return CompoundingLib.timeWeightedAverage(rates, daysCounts);
    }

    // =============================================================================
    // TEST CONSTANTS
    // =============================================================================

    uint256 constant ONE = 1e18; // 1.0 in fixed-point

    // Test rates (in fixed-point)
    uint256 constant RATE_5_PERCENT = 5e16;   // 0.05 = 5%
    uint256 constant RATE_6_PERCENT = 6e16;   // 0.06 = 6%
    uint256 constant RATE_7_PERCENT = 7e16;   // 0.07 = 7%
    uint256 constant RATE_10_PERCENT = 10e16; // 0.10 = 10%

    // =============================================================================
    // SIMPLE AVERAGE TESTS
    // =============================================================================

    function test_SimpleAverage_TwoRates() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256 result = CompoundingLib.simpleAverage(rates);

        // (5% + 6%) / 2 = 5.5%
        uint256 expected = 55e15;
        assertEq(result, expected, "Average of 5% and 6% should be 5.5%");
    }

    function test_SimpleAverage_ThreeRates() public pure {
        uint256[] memory rates = new uint256[](3);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;
        rates[2] = RATE_7_PERCENT;

        uint256 result = CompoundingLib.simpleAverage(rates);

        // (5% + 6% + 7%) / 3 = 6%
        uint256 expected = RATE_6_PERCENT;
        assertEq(result, expected, "Average should be 6%");
    }

    function test_SimpleAverage_SingleRate() public pure {
        uint256[] memory rates = new uint256[](1);
        rates[0] = RATE_5_PERCENT;

        uint256 result = CompoundingLib.simpleAverage(rates);

        assertEq(result, RATE_5_PERCENT, "Single rate should return itself");
    }

    function test_SimpleAverage_EmptyArray() public {
        uint256[] memory rates = new uint256[](0);

        try this.externalCompound(rates, CompoundingMethodEnum.FLAT) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CompoundingLib.CompoundingLib__EmptyRatesArray.selector, "Wrong error");
        }
    }

    // =============================================================================
    // GEOMETRIC COMPOUNDING TESTS
    // =============================================================================

    function test_GeometricCompounding_TwoRates() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;  // 0.05
        rates[1] = RATE_6_PERCENT;  // 0.06

        uint256 result = CompoundingLib.geometricCompounding(rates);

        // (1.05) * (1.06) - 1 = 1.113 - 1 = 0.113 = 11.3%
        uint256 expected = 113e15;
        assertApproxEqAbs(result, expected, 1e14, "Geometric compounding of 5% and 6%");
    }

    function test_GeometricCompounding_ThreeRates() public pure {
        uint256[] memory rates = new uint256[](3);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;
        rates[2] = RATE_7_PERCENT;

        uint256 result = CompoundingLib.geometricCompounding(rates);

        // (1.05) * (1.06) * (1.07) - 1 = 1.19091 - 1 = 0.19091 = 19.091%
        uint256 expected = 19091e13;
        assertApproxEqAbs(result, expected, 1e15, "Geometric compounding");
    }

    function test_GeometricCompounding_SingleRate() public pure {
        uint256[] memory rates = new uint256[](1);
        rates[0] = RATE_5_PERCENT;

        uint256 result = CompoundingLib.geometricCompounding(rates);

        assertEq(result, RATE_5_PERCENT, "Single rate should return itself");
    }

    function test_GeometricCompounding_ZeroRate() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = 0;

        uint256 result = CompoundingLib.geometricCompounding(rates);

        // (1.05) * (1.0) - 1 = 1.05 - 1 = 0.05
        assertEq(result, RATE_5_PERCENT, "Compounding with zero");
    }

    // =============================================================================
    // SPREAD EXCLUSIVE COMPOUNDING TESTS
    // =============================================================================

    function test_SpreadExclusiveCompounding_TwoRates() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256 result = CompoundingLib.spreadExclusiveCompounding(rates);

        // This is simplified implementation: geometric compounding / n
        // Should be less than simple average
        assertTrue(result > 0, "Should be positive");
        assertTrue(result < 10e16, "Should be reasonable");
    }

    // =============================================================================
    // COMPOUND FUNCTION ROUTING TESTS
    // =============================================================================

    function test_Compound_RouteToFlat() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256 result = CompoundingLib.compound(rates, CompoundingMethodEnum.FLAT);
        uint256 expected = CompoundingLib.simpleAverage(rates);

        assertEq(result, expected, "FLAT should route to simple average");
    }

    function test_Compound_RouteToNone() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256 result = CompoundingLib.compound(rates, CompoundingMethodEnum.NONE);
        uint256 expected = CompoundingLib.simpleAverage(rates);

        assertEq(result, expected, "NONE should route to simple average");
    }

    function test_Compound_RouteToStraight() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256 result = CompoundingLib.compound(rates, CompoundingMethodEnum.STRAIGHT);
        uint256 expected = CompoundingLib.geometricCompounding(rates);

        assertEq(result, expected, "STRAIGHT should route to geometric compounding");
    }

    function test_Compound_RouteToSpreadExclusive() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256 result = CompoundingLib.compound(rates, CompoundingMethodEnum.SPREAD_EXCLUSIVE);
        uint256 expected = CompoundingLib.spreadExclusiveCompounding(rates);

        assertEq(result, expected, "SPREAD_EXCLUSIVE should route correctly");
    }

    function test_Compound_SingleRate() public pure {
        uint256[] memory rates = new uint256[](1);
        rates[0] = RATE_5_PERCENT;

        // All methods should return the single rate
        assertEq(
            CompoundingLib.compound(rates, CompoundingMethodEnum.FLAT),
            RATE_5_PERCENT,
            "FLAT with single rate"
        );
        assertEq(
            CompoundingLib.compound(rates, CompoundingMethodEnum.STRAIGHT),
            RATE_5_PERCENT,
            "STRAIGHT with single rate"
        );
    }

    // =============================================================================
    // WEIGHTED AVERAGE TESTS
    // =============================================================================

    function test_WeightedAverage_EqualWeights() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5e17; // 0.5
        weights[1] = 5e17; // 0.5

        uint256 result = CompoundingLib.weightedAverage(rates, weights);

        // 5% * 0.5 + 6% * 0.5 = 5.5%
        uint256 expected = 55e15;
        assertEq(result, expected, "Equal weights should give 5.5%");
    }

    function test_WeightedAverage_UnequalWeights() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6e17; // 0.6
        weights[1] = 4e17; // 0.4

        uint256 result = CompoundingLib.weightedAverage(rates, weights);

        // 5% * 0.6 + 6% * 0.4 = 3% + 2.4% = 5.4%
        uint256 expected = 54e15;
        assertEq(result, expected, "Weighted average should be 5.4%");
    }

    function test_WeightedAverage_ThreeRates() public pure {
        uint256[] memory rates = new uint256[](3);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;
        rates[2] = RATE_7_PERCENT;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 2e17; // 0.2
        weights[1] = 3e17; // 0.3
        weights[2] = 5e17; // 0.5

        uint256 result = CompoundingLib.weightedAverage(rates, weights);

        // 5% * 0.2 + 6% * 0.3 + 7% * 0.5 = 1% + 1.8% + 3.5% = 6.3%
        uint256 expected = 63e15;
        assertEq(result, expected, "Weighted average should be 6.3%");
    }

    function test_WeightedAverage_ArrayLengthMismatch() public {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256[] memory weights = new uint256[](3);
        weights[0] = 5e17;
        weights[1] = 5e17;
        weights[2] = 0;

        try this.externalWeightedAverage(rates, weights) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CompoundingLib.CompoundingLib__ArrayLengthMismatch.selector, "Wrong error");
        }
    }

    function test_WeightedAverage_InvalidWeights() public {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256[] memory weights = new uint256[](2);
        weights[0] = 4e17; // 0.4
        weights[1] = 4e17; // 0.4 (sum = 0.8, not 1.0)

        try this.externalWeightedAverage(rates, weights) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CompoundingLib.CompoundingLib__InvalidWeights.selector, "Wrong error");
        }
    }

    // =============================================================================
    // TIME-WEIGHTED AVERAGE TESTS
    // =============================================================================

    function test_TimeWeightedAverage_EqualDays() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256[] memory daysCounts = new uint256[](2);
        daysCounts[0] = 10;
        daysCounts[1] = 10;

        uint256 result = CompoundingLib.timeWeightedAverage(rates, daysCounts);

        // (5% * 10 + 6% * 10) / 20 = 5.5%
        uint256 expected = 55e15;
        assertApproxEqAbs(result, expected, 1e14, "Equal days should give 5.5%");
    }

    function test_TimeWeightedAverage_UnequalDays() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256[] memory daysCounts = new uint256[](2);
        daysCounts[0] = 20;
        daysCounts[1] = 10;

        uint256 result = CompoundingLib.timeWeightedAverage(rates, daysCounts);

        // (5% * 20 + 6% * 10) / 30 = (1.0 + 0.6) / 30 = 1.6 / 30 = 0.0533... = 5.33%
        uint256 expected = 533e14;
        assertApproxEqAbs(result, expected, 1e15, "Time-weighted should be ~5.33%");
    }

    function test_TimeWeightedAverage_ThreeRates() public pure {
        uint256[] memory rates = new uint256[](3);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;
        rates[2] = RATE_7_PERCENT;

        uint256[] memory daysCounts = new uint256[](3);
        daysCounts[0] = 30;
        daysCounts[1] = 30;
        daysCounts[2] = 30;

        uint256 result = CompoundingLib.timeWeightedAverage(rates, daysCounts);

        // Equal periods should give simple average = 6%
        uint256 expected = RATE_6_PERCENT;
        assertApproxEqAbs(result, expected, 1e14, "Equal periods should give 6%");
    }

    function test_TimeWeightedAverage_ArrayLengthMismatch() public {
        uint256[] memory rates = new uint256[](2);
        rates[0] = RATE_5_PERCENT;
        rates[1] = RATE_6_PERCENT;

        uint256[] memory daysCounts = new uint256[](3);
        daysCounts[0] = 10;
        daysCounts[1] = 10;
        daysCounts[2] = 10;

        try this.externalTimeWeightedAverage(rates, daysCounts) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, CompoundingLib.CompoundingLib__ArrayLengthMismatch.selector, "Wrong error");
        }
    }

    // =============================================================================
    // UTILITY FUNCTION TESTS - ACCRUAL FACTOR
    // =============================================================================

    function test_AccrualFactor_FullYear() public pure {
        uint256 result = CompoundingLib.accrualFactor(RATE_5_PERCENT, ONE);

        // 1 + 0.05 * 1 = 1.05
        uint256 expected = 105e16;
        assertEq(result, expected, "Accrual factor should be 1.05");
    }

    function test_AccrualFactor_HalfYear() public pure {
        uint256 result = CompoundingLib.accrualFactor(RATE_5_PERCENT, 5e17);

        // 1 + 0.05 * 0.5 = 1.025
        uint256 expected = 1025e15;
        assertEq(result, expected, "Accrual factor should be 1.025");
    }

    function test_AccrualFactor_Quarter() public pure {
        uint256 result = CompoundingLib.accrualFactor(RATE_10_PERCENT, 25e16);

        // 1 + 0.10 * 0.25 = 1.025
        uint256 expected = 1025e15;
        assertEq(result, expected, "Accrual factor should be 1.025");
    }

    function test_AccrualFactor_ZeroTime() public pure {
        uint256 result = CompoundingLib.accrualFactor(RATE_5_PERCENT, 0);

        // 1 + 0.05 * 0 = 1.0
        assertEq(result, ONE, "Accrual factor should be 1.0");
    }

    // =============================================================================
    // UTILITY FUNCTION TESTS - DISCOUNT FACTOR
    // =============================================================================

    function test_DiscountFactor_FullYear() public pure {
        uint256 result = CompoundingLib.discountFactor(RATE_5_PERCENT, ONE);

        // 1 / (1 + 0.05 * 1) = 1 / 1.05 = 0.952380...
        uint256 expected = 952380952380952380;
        assertApproxEqAbs(result, expected, 1e14, "Discount factor");
    }

    function test_DiscountFactor_HalfYear() public pure {
        uint256 result = CompoundingLib.discountFactor(RATE_5_PERCENT, 5e17);

        // 1 / (1 + 0.05 * 0.5) = 1 / 1.025 = 0.975609...
        uint256 expected = 975609756097560975;
        assertApproxEqAbs(result, expected, 1e14, "Discount factor half year");
    }

    function test_DiscountFactor_ZeroTime() public pure {
        uint256 result = CompoundingLib.discountFactor(RATE_5_PERCENT, 0);

        // 1 / (1 + 0.05 * 0) = 1 / 1 = 1.0
        assertEq(result, ONE, "Discount factor should be 1.0");
    }

    // =============================================================================
    // UTILITY FUNCTION TESTS - CONTINUOUS COMPOUNDING
    // =============================================================================

    function test_ContinuousCompounding_SmallRate() public pure {
        uint256 result = CompoundingLib.continuousCompounding(RATE_5_PERCENT, ONE);

        // For small rates: e^0.05 - 1 ≈ 0.05 + 0.05^2/2 = 0.05 + 0.00125 = 0.05125
        uint256 expected = 51250000000000000;
        assertApproxEqAbs(result, expected, 1e15, "Continuous compounding approximation");
    }

    function test_ContinuousCompounding_HalfYear() public pure {
        uint256 result = CompoundingLib.continuousCompounding(RATE_5_PERCENT, 5e17);

        // e^(0.05 * 0.5) - 1 ≈ 0.025 + 0.025^2/2
        assertTrue(result > 0, "Should be positive");
        assertTrue(result < RATE_5_PERCENT, "Should be less than annual rate");
    }

    // =============================================================================
    // UTILITY FUNCTION TESTS - RATE CONVERSION
    // =============================================================================

    function test_AnnualToPeriodRate_Quarterly() public pure {
        uint256 result = CompoundingLib.annualToPeriodRate(RATE_6_PERCENT, 4);

        // 6% / 4 = 1.5%
        uint256 expected = 15e15;
        assertEq(result, expected, "Quarterly rate should be 1.5%");
    }

    function test_AnnualToPeriodRate_SemiAnnual() public pure {
        uint256 result = CompoundingLib.annualToPeriodRate(RATE_6_PERCENT, 2);

        // 6% / 2 = 3%
        uint256 expected = 3e16;
        assertEq(result, expected, "Semi-annual rate should be 3%");
    }

    function test_AnnualToPeriodRate_Monthly() public pure {
        uint256 result = CompoundingLib.annualToPeriodRate(RATE_6_PERCENT, 12);

        // 6% / 12 = 0.5%
        uint256 expected = 5e15;
        assertEq(result, expected, "Monthly rate should be 0.5%");
    }

    function test_PeriodToAnnualRate_Quarterly() public pure {
        uint256 quarterlyRate = 15e15; // 1.5%
        uint256 result = CompoundingLib.periodToAnnualRate(quarterlyRate, 4);

        // 1.5% * 4 = 6%
        assertEq(result, RATE_6_PERCENT, "Annual rate should be 6%");
    }

    function test_PeriodToAnnualRate_SemiAnnual() public pure {
        uint256 semiAnnualRate = 3e16; // 3%
        uint256 result = CompoundingLib.periodToAnnualRate(semiAnnualRate, 2);

        // 3% * 2 = 6%
        assertEq(result, RATE_6_PERCENT, "Annual rate should be 6%");
    }

    function test_PeriodToAnnualRate_Monthly() public pure {
        uint256 monthlyRate = 5e15; // 0.5%
        uint256 result = CompoundingLib.periodToAnnualRate(monthlyRate, 12);

        // 0.5% * 12 = 6%
        assertEq(result, RATE_6_PERCENT, "Annual rate should be 6%");
    }

    // =============================================================================
    // REAL-WORLD SCENARIO TESTS
    // =============================================================================

    function test_RealWorld_FloatingRateAverage() public pure {
        // Daily SOFR rates for a week
        uint256[] memory rates = new uint256[](5);
        rates[0] = 53e15; // 5.3%
        rates[1] = 52e15; // 5.2%
        rates[2] = 54e15; // 5.4%
        rates[3] = 53e15; // 5.3%
        rates[4] = 52e15; // 5.2%

        uint256 result = CompoundingLib.simpleAverage(rates);

        // Average = 5.28%
        uint256 expected = 528e14;
        assertEq(result, expected, "Week average SOFR");
    }

    function test_RealWorld_CompoundedSOFR() public pure {
        // Three-month SOFR observation period
        uint256[] memory rates = new uint256[](3);
        rates[0] = 50e15; // 5.0%
        rates[1] = 52e15; // 5.2%
        rates[2] = 54e15; // 5.4%

        uint256 result = CompoundingLib.compound(rates, CompoundingMethodEnum.STRAIGHT);

        // Geometric compounding for accurate rate
        assertTrue(result > 52e15, "Should be greater than middle rate");
        assertTrue(result < 165e15, "Should be less than sum");
    }

    function test_RealWorld_WeightedCoupon() public pure {
        // Bond with different rate periods
        uint256[] memory rates = new uint256[](2);
        rates[0] = 50e15; // 5.0% for first period
        rates[1] = 60e15; // 6.0% for second period

        uint256[] memory daysCounts = new uint256[](2);
        daysCounts[0] = 90;  // 90 days at 5%
        daysCounts[1] = 90;  // 90 days at 6%

        uint256 result = CompoundingLib.timeWeightedAverage(rates, daysCounts);

        // Should be 5.5%
        uint256 expected = 55e15;
        assertApproxEqAbs(result, expected, 1e14, "Weighted coupon");
    }

    // =============================================================================
    // EDGE CASE TESTS
    // =============================================================================

    function test_EdgeCase_AllZeroRates() public pure {
        uint256[] memory rates = new uint256[](3);
        rates[0] = 0;
        rates[1] = 0;
        rates[2] = 0;

        uint256 result = CompoundingLib.simpleAverage(rates);
        assertEq(result, 0, "Average of zeros should be zero");

        result = CompoundingLib.geometricCompounding(rates);
        assertEq(result, 0, "Geometric compounding of zeros should be zero");
    }

    function test_EdgeCase_VerySmallRates() public pure {
        uint256[] memory rates = new uint256[](2);
        rates[0] = 1e12; // 0.0001%
        rates[1] = 2e12; // 0.0002%

        uint256 result = CompoundingLib.simpleAverage(rates);
        uint256 expected = 15e11; // 0.00015%
        assertEq(result, expected, "Very small rates");
    }

    function test_EdgeCase_AccrualFactorIdentity() public pure {
        // Accrual * Discount should be close to 1.0
        uint256 accrual = CompoundingLib.accrualFactor(RATE_5_PERCENT, ONE);
        uint256 discount = CompoundingLib.discountFactor(RATE_5_PERCENT, ONE);

        uint256 product = accrual.mul(discount);
        assertApproxEqAbs(product, ONE, 1e15, "Accrual * Discount should equal 1");
    }

    function test_EdgeCase_RateConversionRoundTrip() public pure {
        // Convert annual to period and back
        uint256 periodRate = CompoundingLib.annualToPeriodRate(RATE_6_PERCENT, 4);
        uint256 backToAnnual = CompoundingLib.periodToAnnualRate(periodRate, 4);

        assertEq(backToAnnual, RATE_6_PERCENT, "Round-trip conversion");
    }
}
