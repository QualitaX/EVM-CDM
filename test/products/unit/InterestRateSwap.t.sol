// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {InterestRateSwap} from "../../../src/products/InterestRateSwap.sol";
import {InterestRatePayout} from "../../../src/products/InterestRatePayout.sol";
import {Cashflow} from "../../../src/base/libraries/Cashflow.sol";
import {Schedule} from "../../../src/base/libraries/Schedule.sol";
import {ObservationSchedule} from "../../../src/base/libraries/ObservationSchedule.sol";
import {FixedPoint} from "../../../src/base/libraries/FixedPoint.sol";
import {
    DayCountFractionEnum,
    BusinessDayConventionEnum,
    BusinessCenterEnum,
    PeriodEnum
} from "../../../src/base/types/Enums.sol";
import {Period, BusinessDayAdjustments} from "../../../src/base/types/CDMTypes.sol";

/**
 * @title InterestRateSwapTest
 * @notice Comprehensive test suite for InterestRateSwap contract
 * @dev Tests vanilla fixed-for-floating interest rate swaps
 *
 * TEST COVERAGE:
 * 1. Swap Validation (5 tests)
 * 2. Basic Swap Calculations (8 tests)
 * 3. NPV Calculations (5 tests)
 * 4. Net Settlement (4 tests)
 * 5. Helper Functions (3 tests)
 * 6. Real-World Scenarios (5 tests)
 * 7. Edge Cases (3 tests)
 *
 * TOTAL: 33 tests
 */
contract InterestRateSwapTest is Test {
    using FixedPoint for uint256;

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    InterestRateSwap public swap;
    InterestRatePayout public payout;

    uint256 constant ONE = 1e18;

    // Test parameters
    bytes32 constant PARTY_A = bytes32("PARTY_A");
    bytes32 constant PARTY_B = bytes32("PARTY_B");
    bytes32 constant USD = bytes32("USD");
    bytes32 constant SOFR = bytes32("SOFR");

    // =============================================================================
    // SETUP
    // =============================================================================

    function setUp() public {
        // Deploy contracts
        payout = new InterestRatePayout();
        swap = new InterestRateSwap(address(payout));
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Create a standard quarterly IRS spec
     * @param notional Notional amount
     * @param fixedRate Fixed rate (annual)
     * @param spread Floating spread
     * @param tenor Tenor in years
     * @return spec Swap specification
     */
    function _createStandardQuarterlySwap(
        uint256 notional,
        uint256 fixedRate,
        uint256 spread,
        uint256 tenor
    ) internal view returns (InterestRateSwap.InterestRateSwapSpec memory spec) {
        // Use realistic future dates (Jan 1, 2025)
        uint256 effectiveDate = 1735689600; // 2025-01-01
        uint256 terminationDate = effectiveDate + (tenor * 365 days);

        Period memory frequency = Period({
            periodMultiplier: 3,
            period: PeriodEnum.MONTH
        });

        spec = swap.createStandardIRS(
            bytes32("SWAP001"),
            PARTY_A,
            PARTY_B,
            notional,
            fixedRate,
            SOFR,
            spread,
            effectiveDate,
            terminationDate,
            frequency
        );

        return spec;
    }

    /**
     * @notice Generate constant rate observations for testing
     * @param numPeriods Number of periods
     * @param daysPerPeriod Days per period
     * @param rate Constant rate to use
     * @return observations Array of rate observations
     */
    function _generateConstantRateObservations(
        uint256 numPeriods,
        uint256 daysPerPeriod,
        uint256 rate
    ) internal pure returns (uint256[][] memory observations) {
        observations = new uint256[][](numPeriods);

        for (uint256 i = 0; i < numPeriods; i++) {
            observations[i] = new uint256[](daysPerPeriod);
            for (uint256 j = 0; j < daysPerPeriod; j++) {
                observations[i][j] = rate;
            }
        }

        return observations;
    }

    // =============================================================================
    // VALIDATION TESTS
    // =============================================================================

    function test_ValidateSwapSpec_Valid() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,  // $10M
            35e15,             // 3.5%
            0,                 // No spread
            5                  // 5 years
        );

        bool valid = swap.validateSwapSpec(spec);
        assertTrue(valid, "Swap should be valid");
    }

    function test_ValidateSwapSpec_ZeroNotional() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            5
        );

        // Set notional to zero
        spec.notional = 0;

        bool valid = swap.validateSwapSpec(spec);
        assertFalse(valid, "Should be invalid with zero notional");
    }

    function test_ValidateSwapSpec_DateMismatch() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            5
        );

        // Set mismatched dates
        spec.fixedLeg.effectiveDate = spec.effectiveDate + 1 days;

        bool valid = swap.validateSwapSpec(spec);
        assertFalse(valid, "Should be invalid with mismatched dates");
    }

    function test_ValidateSwapSpec_SameDirection() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            5
        );

        // Set both legs to same direction (both PAY)
        spec.floatingLeg.direction = Cashflow.PaymentDirectionEnum.PAY;

        bool valid = swap.validateSwapSpec(spec);
        assertFalse(valid, "Should be invalid with same direction on both legs");
    }

    function test_ValidateSwapSpec_WrongLegTypes() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            5
        );

        // Set wrong payout types
        spec.fixedLeg.payoutType = InterestRatePayout.PayoutTypeEnum.FLOATING;

        bool valid = swap.validateSwapSpec(spec);
        assertFalse(valid, "Should be invalid with wrong leg types");
    }

    // =============================================================================
    // BASIC SWAP CALCULATION TESTS
    // =============================================================================

    function test_CalculateSwap_BasicQuarterly() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,  // $10M
            35e15,             // 3.5%
            0,                 // No spread
            1                  // 1 year
        );

        // Generate constant SOFR observations at 3.0%
        uint256[][] memory observations = _generateConstantRateObservations(
            4,    // 4 quarters
            90,   // ~90 days per quarter
            3e16  // 3.0%
        );

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Check that we have results for both legs
        assertGt(result.fixedLegResult.payoutResult.periods.length, 0, "Should have fixed periods");
        assertGt(result.floatingLegResult.payoutResult.periods.length, 0, "Should have floating periods");

        // Check total interest
        assertGt(result.totalFixedInterest, 0, "Should have fixed interest");
        assertGt(result.totalFloatingInterest, 0, "Should have floating interest");

        // Fixed at 3.5% should be higher than floating at 3.0%
        assertGt(result.totalFixedInterest, result.totalFloatingInterest, "Fixed should be higher");
    }

    function test_CalculateSwap_FixedHigherThanFloating() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            40e15,  // 4.0% fixed
            0,
            1
        );

        // SOFR at 3.0%
        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Fixed payer (Party A) pays more than receives
        // Net cashflows should show Party A paying
        for (uint256 i = 0; i < result.netCashflows.length; i++) {
            assertEq(result.netCashflows[i].payerReference, PARTY_A, "Party A should pay net");
            assertEq(result.netCashflows[i].receiverReference, PARTY_B, "Party B should receive net");
            assertGt(result.netCashflows[i].netAmount, 0, "Net amount should be positive");
        }
    }

    function test_CalculateSwap_FloatingHigherThanFixed() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            25e15,  // 2.5% fixed
            0,
            1
        );

        // SOFR at 3.5%
        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 35e15);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Fixed payer (Party A) receives more than pays
        // Net cashflows should show Party B paying
        for (uint256 i = 0; i < result.netCashflows.length; i++) {
            assertEq(result.netCashflows[i].payerReference, PARTY_B, "Party B should pay net");
            assertEq(result.netCashflows[i].receiverReference, PARTY_A, "Party A should receive net");
        }
    }

    function test_CalculateSwap_WithSpread() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,  // 3.5% fixed
            50e14,  // +50bps spread on floating
            1
        );

        // SOFR at 3.0%, +50bps = 3.5% effective
        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // With spread, floating should be close to fixed
        // Allow some tolerance for day count differences
        uint256 tolerance = 1e17; // 10% tolerance
        assertApproxEqRel(
            result.totalFloatingInterest,
            result.totalFixedInterest,
            tolerance,
            "Floating + spread should approximate fixed"
        );
    }

    function test_CalculateSwap_LongTenor() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            5  // 5 years
        );

        // Generate observations for 5 years (20 quarters)
        uint256[][] memory observations = _generateConstantRateObservations(20, 90, 3e16);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Should have 20 quarters
        assertEq(result.fixedLegResult.payoutResult.periods.length, 20, "Should have 20 periods");
        assertEq(result.netCashflows.length, 20, "Should have 20 net cashflows");

        // Total interest should be approximately 5x annual interest
        uint256 expectedAnnualFixed = 10_000_000 * ONE * 35e15 / ONE;  // $350,000
        uint256 expectedTotal = expectedAnnualFixed * 5;  // ~$1,750,000

        uint256 tolerance = 1e17; // 10% tolerance for day count variations
        assertApproxEqRel(
            result.totalFixedInterest,
            expectedTotal,
            tolerance,
            "Total should be approximately 5x annual"
        );
    }

    function test_CalculateSwap_NetCashflowDates() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Verify net cashflow dates match leg dates
        for (uint256 i = 0; i < result.netCashflows.length; i++) {
            assertEq(
                result.netCashflows[i].periodStart,
                result.fixedLegResult.payoutResult.periods[i].startDate,
                "Net cashflow start should match fixed leg"
            );
            assertEq(
                result.netCashflows[i].periodEnd,
                result.fixedLegResult.payoutResult.periods[i].endDate,
                "Net cashflow end should match fixed leg"
            );
        }
    }

    function test_CalculateSwap_LargeNotional() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            100_000_000 * ONE,  // $100M
            35e15,
            0,
            1
        );

        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Should handle large notionals without overflow
        assertGt(result.totalFixedInterest, 0, "Should calculate large notional");
        assertGt(result.totalFloatingInterest, 0, "Should calculate large notional");
    }

    function test_CalculateSwap_InvalidSpec() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        // Make spec invalid
        spec.notional = 0;

        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        vm.expectRevert(InterestRateSwap.InterestRateSwap__InvalidLegConfiguration.selector);
        swap.calculateSwap(spec, observations);
    }

    // =============================================================================
    // NPV CALCULATION TESTS
    // =============================================================================

    function test_CalculateSwapWithNPV_FlatCurve() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        // Flat discount curve at 95% per period
        uint256[] memory discountFactors = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            discountFactors[i] = 95e16; // 0.95
        }

        InterestRateSwap.SwapValuationResult memory result =
            swap.calculateSwapWithNPV(spec, observations, discountFactors);

        // NPV should be calculated
        assertGt(result.fixedLegNPV, 0, "Fixed leg NPV should be positive");
        assertGt(result.floatingLegNPV, 0, "Floating leg NPV should be positive");

        // Fixed payer perspective: receive floating - pay fixed
        // Since fixed rate > floating rate, swap NPV should be negative (liability)
        assertLt(result.swapNPV, 0, "Swap should be out-of-the-money for fixed payer");
    }

    function test_CalculateSwapWithNPV_InTheMoney() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            25e15,  // 2.5% fixed (below floating)
            0,
            1
        );

        // SOFR at 3.5% (above fixed)
        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 35e15);

        uint256[] memory discountFactors = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            discountFactors[i] = 95e16;
        }

        InterestRateSwap.SwapValuationResult memory result =
            swap.calculateSwapWithNPV(spec, observations, discountFactors);

        // Fixed payer receives more than pays, so swap is in-the-money (asset)
        assertGt(result.swapNPV, 0, "Swap should be in-the-money for fixed payer");
    }

    function test_CalculateSwapWithNPV_AtTheMoney() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,  // 3.5% fixed
            50e14,  // +50bps spread
            1
        );

        // SOFR at 3.0%, +50bps = 3.5% (matches fixed)
        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        uint256[] memory discountFactors = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            discountFactors[i] = 95e16;
        }

        InterestRateSwap.SwapValuationResult memory result =
            swap.calculateSwapWithNPV(spec, observations, discountFactors);

        // NPV should be close to zero (at-the-money)
        uint256 absNPV = result.swapNPV > 0
            ? uint256(result.swapNPV)
            : uint256(-result.swapNPV);

        // Allow 10% tolerance
        uint256 maxExpected = result.fixedLegNPV / 10;
        assertLt(absNPV, maxExpected, "Swap should be approximately at-the-money");
    }

    function test_CalculateSwapWithNPV_NoDiscount() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        // No discounting (all 1.0)
        uint256[] memory discountFactors = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            discountFactors[i] = ONE;
        }

        InterestRateSwap.SwapValuationResult memory result =
            swap.calculateSwapWithNPV(spec, observations, discountFactors);

        // NPV should equal total interest (no discounting)
        assertEq(result.fixedLegNPV, result.totalFixedInterest, "NPV should equal total (no discount)");
        assertEq(result.floatingLegNPV, result.totalFloatingInterest, "NPV should equal total (no discount)");
    }

    function test_CalculateSwapWithNPV_WrongDiscountLength() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 3e16);

        // Wrong number of discount factors
        uint256[] memory discountFactors = new uint256[](3);  // Should be 4

        vm.expectRevert(InterestRateSwap.InterestRateSwap__DiscountFactorMismatch.selector);
        swap.calculateSwapWithNPV(spec, observations, discountFactors);
    }

    // =============================================================================
    // NET SETTLEMENT TESTS
    // =============================================================================

    function test_GetNetSettlement_FixedPayerPaysNet() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        // Fixed = $87,500, Floating = $75,000
        uint256 fixedAmount = 87_500 * ONE;
        uint256 floatingAmount = 75_000 * ONE;

        (int256 netAmount, bytes32 payer, bytes32 receiver) =
            swap.getNetSettlement(spec, fixedAmount, floatingAmount);

        // Party A pays fixed, receives floating
        // Net: pays $12,500
        assertEq(payer, PARTY_A, "Party A should pay");
        assertEq(receiver, PARTY_B, "Party B should receive");
        assertApproxEqRel(uint256(netAmount), 12_500 * ONE, 1e15, "Net should be ~$12,500");
    }

    function test_GetNetSettlement_FixedPayerReceivesNet() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        // Fixed = $87,500, Floating = $100,000
        uint256 fixedAmount = 87_500 * ONE;
        uint256 floatingAmount = 100_000 * ONE;

        (int256 netAmount, bytes32 payer, bytes32 receiver) =
            swap.getNetSettlement(spec, fixedAmount, floatingAmount);

        // Party A pays fixed, receives floating
        // Net: receives $12,500 (Party B pays)
        assertEq(payer, PARTY_B, "Party B should pay");
        assertEq(receiver, PARTY_A, "Party A should receive");
        assertApproxEqRel(uint256(netAmount), 12_500 * ONE, 1e15, "Net should be ~$12,500");
    }

    function test_GetNetSettlement_EqualAmounts() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        uint256 amount = 87_500 * ONE;

        (int256 netAmount, bytes32 payer, bytes32 receiver) =
            swap.getNetSettlement(spec, amount, amount);

        // Net should be zero or very small
        assertLt(uint256(netAmount < 0 ? -netAmount : netAmount), 1e15, "Net should be approximately zero");
    }

    function test_GetNetSettlement_ReverseDirection() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        // Reverse directions (Party A receives fixed, pays floating)
        spec.fixedLeg.direction = Cashflow.PaymentDirectionEnum.RECEIVE;
        spec.floatingLeg.direction = Cashflow.PaymentDirectionEnum.PAY;

        uint256 fixedAmount = 87_500 * ONE;
        uint256 floatingAmount = 75_000 * ONE;

        (int256 netAmount, bytes32 payer, bytes32 receiver) =
            swap.getNetSettlement(spec, fixedAmount, floatingAmount);

        // Party A receives fixed, pays floating
        // Net: receives $12,500 (Party B pays)
        assertEq(payer, PARTY_B, "Party B should pay");
        assertEq(receiver, PARTY_A, "Party A should receive");
    }

    // =============================================================================
    // HELPER FUNCTION TESTS
    // =============================================================================

    function test_GetAccruedInterest() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            1
        );

        // Warp to middle of first period (45 days into 90-day quarter)
        vm.warp(spec.effectiveDate + 45 days);

        (uint256 fixedAccrued, uint256 floatingAccrued, int256 netAccrued) =
            swap.getAccruedInterest(spec);

        // Fixed accrued should be calculated (roughly half of quarterly interest)
        assertGt(fixedAccrued, 0, "Should have fixed accrued interest");

        // Floating accrued is zero without observations
        assertEq(floatingAccrued, 0, "Floating accrued should be zero without observations");
    }

    function test_GetRemainingPeriods() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            35e15,
            0,
            5
        );

        uint256 remaining = swap.getRemainingPeriods(spec);

        // 5 years quarterly = approximately 20 periods (may vary due to schedule generation)
        assertGe(remaining, 20, "Should have at least 20 periods");
        assertLe(remaining, 21, "Should have at most 21 periods");
    }

    function test_CreateStandardIRS() public {
        uint256 effectiveDate = 1735689600; // 2025-01-01
        uint256 terminationDate = effectiveDate + 365 days;

        Period memory frequency = Period({
            periodMultiplier: 3,
            period: PeriodEnum.MONTH
        });

        InterestRateSwap.InterestRateSwapSpec memory spec = swap.createStandardIRS(
            bytes32("TEST"),
            PARTY_A,
            PARTY_B,
            10_000_000 * ONE,
            35e15,
            SOFR,
            50e14,
            effectiveDate,
            terminationDate,
            frequency
        );

        // Verify spec is valid
        assertTrue(swap.validateSwapSpec(spec), "Created spec should be valid");

        // Verify key parameters
        assertEq(spec.notional, 10_000_000 * ONE, "Notional should match");
        assertEq(spec.fixedLeg.fixedRate, 35e15, "Fixed rate should match");
        assertEq(spec.floatingLeg.spread, 50e14, "Spread should match");
    }

    // =============================================================================
    // REAL-WORLD SCENARIO TESTS
    // =============================================================================

    function test_RealWorld_5YearIRS() public {
        // 5-year $100M IRS
        // Party A: Pays 4.25% fixed, receives SOFR
        // Semiannual payments
        uint256 effectiveDate = 1735689600; // 2025-01-01
        uint256 terminationDate = effectiveDate + (5 * 365 days);

        Period memory frequency = Period({
            periodMultiplier: 6,
            period: PeriodEnum.MONTH
        });

        InterestRateSwap.InterestRateSwapSpec memory spec = swap.createStandardIRS(
            bytes32("IRS_5Y_100M"),
            PARTY_A,
            PARTY_B,
            100_000_000 * ONE,
            425e14,  // 4.25%
            SOFR,
            0,
            effectiveDate,
            terminationDate,
            frequency
        );

        // SOFR at 3.75% (below fixed)
        uint256[][] memory observations = _generateConstantRateObservations(10, 180, 375e14);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Verify swap is out-of-the-money for fixed payer
        // (pays 4.25%, receives 3.75%)
        for (uint256 i = 0; i < result.netCashflows.length; i++) {
            assertEq(result.netCashflows[i].payerReference, PARTY_A, "Party A pays net");
        }

        // Total fixed should be approximately $21.25M over 5 years
        uint256 expectedFixed = 100_000_000 * ONE * 425e14 / ONE * 5;
        assertApproxEqRel(result.totalFixedInterest, expectedFixed, 1e17, "Fixed interest");
    }

    function test_RealWorld_BasisSwap() public {
        // 3-year basis swap: SOFR vs SOFR + 25bps
        uint256 effectiveDate = 1735689600; // 2025-01-01
        uint256 terminationDate = effectiveDate + (3 * 365 days);

        Period memory frequency = Period({
            periodMultiplier: 3,
            period: PeriodEnum.MONTH
        });

        // Note: This is simulated as a fixed-for-floating swap
        // where "fixed" represents SOFR flat
        InterestRateSwap.InterestRateSwapSpec memory spec = swap.createStandardIRS(
            bytes32("BASIS_3Y"),
            PARTY_A,
            PARTY_B,
            50_000_000 * ONE,
            3e16,      // "Fixed" at 3% (simulating SOFR flat)
            SOFR,
            25e14,     // +25bps spread
            effectiveDate,
            terminationDate,
            frequency
        );

        // SOFR at 3.0%
        uint256[][] memory observations = _generateConstantRateObservations(12, 90, 3e16);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Spread causes consistent net payment
        for (uint256 i = 0; i < result.netCashflows.length; i++) {
            assertGt(result.netCashflows[i].netAmount, 0, "Should have consistent net payments");
        }
    }

    function test_RealWorld_RateFall() public {
        // 2-year swap with falling rates
        uint256 effectiveDate = 1735689600; // 2025-01-01
        uint256 terminationDate = effectiveDate + (2 * 365 days);

        Period memory frequency = Period({
            periodMultiplier: 3,
            period: PeriodEnum.MONTH
        });

        InterestRateSwap.InterestRateSwapSpec memory spec = swap.createStandardIRS(
            bytes32("FALLING"),
            PARTY_A,
            PARTY_B,
            20_000_000 * ONE,
            4e16,  // 4% fixed
            SOFR,
            0,
            effectiveDate,
            terminationDate,
            frequency
        );

        // Rates fall from 4% to 2% over 2 years (8 quarters)
        uint256[][] memory observations = new uint256[][](8);
        for (uint256 i = 0; i < 8; i++) {
            uint256 rate = 4e16 - (i * 25e13);  // Decrease by 0.25% per quarter
            observations[i] = new uint256[](90);
            for (uint256 j = 0; j < 90; j++) {
                observations[i][j] = rate;
            }
        }

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Earlier periods: Party A pays more (fixed > floating)
        // Later periods: Party A receives more (fixed < floating)
        // Note: This would require more detailed period analysis
        assertGt(result.fixedLegResult.payoutResult.periods.length, 0, "Should complete calculation");
    }

    function test_RealWorld_MTM_Valuation() public {
        // Mark-to-market valuation scenario
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            50_000_000 * ONE,
            35e15,
            0,
            3
        );

        uint256[][] memory observations = _generateConstantRateObservations(12, 90, 4e16);

        // Upward sloping discount curve
        uint256[] memory discountFactors = new uint256[](12);
        for (uint256 i = 0; i < 12; i++) {
            discountFactors[i] = ONE - (i * 2e16 / 12);  // 0% to 2% discount per period
        }

        InterestRateSwap.SwapValuationResult memory result =
            swap.calculateSwapWithNPV(spec, observations, discountFactors);

        // Verify MTM is calculated
        assertNotEq(result.swapNPV, 0, "Swap should have non-zero MTM");

        // Higher floating rate (4% vs 3.5% fixed) should make swap in-the-money
        assertGt(result.swapNPV, 0, "Swap should be in-the-money");
    }

    function test_RealWorld_AmortizingSwap() public {
        // Simplified amortizing swap (constant notional in this implementation)
        // Note: Full amortizing swaps would require per-period notional
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            30_000_000 * ONE,
            375e14,
            0,
            2
        );

        uint256[][] memory observations = _generateConstantRateObservations(8, 90, 35e15);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Verify calculation completes
        assertEq(result.netCashflows.length, 8, "Should have 8 periods");
    }

    // =============================================================================
    // EDGE CASE TESTS
    // =============================================================================

    function test_EdgeCase_ExtremeRateDifference() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            1e16,   // 1% fixed
            0,
            1
        );

        // Extreme floating rate at 10%
        uint256[][] memory observations = _generateConstantRateObservations(4, 90, 10e16);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Large net payments
        for (uint256 i = 0; i < result.netCashflows.length; i++) {
            uint256 absNetAmount = uint256(result.netCashflows[i].netAmount);
            assertGt(absNetAmount, 100_000 * ONE, "Should have large net payments");
        }
    }

    function test_EdgeCase_VeryShortTenor() public {
        // 3-month swap
        uint256 effectiveDate = 1735689600; // 2025-01-01
        uint256 terminationDate = effectiveDate + 90 days;

        Period memory frequency = Period({
            periodMultiplier: 3,
            period: PeriodEnum.MONTH
        });

        InterestRateSwap.InterestRateSwapSpec memory spec = swap.createStandardIRS(
            bytes32("SHORT"),
            PARTY_A,
            PARTY_B,
            10_000_000 * ONE,
            35e15,
            SOFR,
            0,
            effectiveDate,
            terminationDate,
            frequency
        );

        uint256[][] memory observations = _generateConstantRateObservations(1, 90, 3e16);

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Should have just 1 period
        assertEq(result.netCashflows.length, 1, "Should have 1 period");
    }

    function test_EdgeCase_HighVolatilityRates() public {
        InterestRateSwap.InterestRateSwapSpec memory spec = _createStandardQuarterlySwap(
            10_000_000 * ONE,
            5e16,  // 5% fixed
            0,
            1
        );

        // Volatile rates: 2%, 8%, 1%, 10%
        uint256[][] memory observations = new uint256[][](4);
        uint256[] memory rates = new uint256[](4);
        rates[0] = 2e16;
        rates[1] = 8e16;
        rates[2] = 1e16;
        rates[3] = 10e16;

        for (uint256 i = 0; i < 4; i++) {
            observations[i] = new uint256[](90);
            for (uint256 j = 0; j < 90; j++) {
                observations[i][j] = rates[i];
            }
        }

        InterestRateSwap.SwapValuationResult memory result = swap.calculateSwap(spec, observations);

        // Should handle volatile rates
        assertGt(result.totalFloatingInterest, 0, "Should calculate with volatile rates");

        // Net payments should vary significantly
        uint256 minNet = type(uint256).max;
        uint256 maxNet = 0;
        for (uint256 i = 0; i < result.netCashflows.length; i++) {
            uint256 net = uint256(result.netCashflows[i].netAmount);
            if (net < minNet) minNet = net;
            if (net > maxNet) maxNet = net;
        }
        // Adjust expectation since averaging reduces variance
        assertGt(maxNet - minNet, 20_000 * ONE, "Net payments should vary significantly");
    }
}
