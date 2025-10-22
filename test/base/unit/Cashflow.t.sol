// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {Cashflow} from "../../../src/base/libraries/Cashflow.sol";
import {Schedule} from "../../../src/base/libraries/Schedule.sol";
import {DayCountFractionEnum} from "../../../src/base/types/Enums.sol";
import {DateTime} from "../../../src/base/libraries/DateTime.sol";
import {FixedPoint} from "../../../src/base/libraries/FixedPoint.sol";

/**
 * @title CashflowTest
 * @notice Comprehensive test suite for Cashflow library
 * @dev Tests cashflow calculations, present value, NPV, and payment processing
 */
contract CashflowTest is Test {
    using FixedPoint for uint256;

    // Constants
    uint256 constant ONE = 1e18; // 1.0 in fixed-point
    uint256 constant NOTIONAL = 1000000e18; // 1,000,000
    uint256 constant RATE_5_PERCENT = 0.05e18;
    uint256 constant RATE_3_PERCENT = 0.03e18;
    uint256 constant DISCOUNT_RATE = 0.04e18;

    // Test dates (midnight UTC)
    uint256 JAN_1_2024;
    uint256 JAN_1_2025;
    uint256 JULY_1_2024;
    uint256 APRIL_1_2024;

    bytes32 constant USD = bytes32("USD");

    function setUp() public {
        JAN_1_2024 = 1704067200;   // Monday, January 1, 2024 00:00:00 UTC
        JAN_1_2025 = 1735689600;   // Wednesday, January 1, 2025 00:00:00 UTC
        JULY_1_2024 = 1719792000;  // Monday, July 1, 2024 00:00:00 UTC
        APRIL_1_2024 = 1711929600; // Monday, April 1, 2024 00:00:00 UTC
    }

    // ============================================
    // Fixed Cashflow Tests
    // ============================================

    function test_CalculateFixedCashflow_OneYear() public {
        uint256 cashflow = Cashflow.calculateFixedCashflow(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~50,000 (1M * 5% * 1 year)
        // 366 days in 2024 (leap year) / 365 = 1.00274
        assertApproxEqAbs(cashflow, 50000e18, 200e18, "Fixed cashflow for one year");
    }

    function test_CalculateFixedCashflow_SixMonths() public {
        uint256 cashflow = Cashflow.calculateFixedCashflow(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2024,
            JULY_1_2024,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~25,068 (1M * 5% * 182/365)
        assertApproxEqAbs(cashflow, 25000e18, 200e18, "Fixed cashflow for six months");
    }

    function test_CalculateFixedCashflow_ZeroNotional() public {
        uint256 cashflow = Cashflow.calculateFixedCashflow(
            0,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        assertEq(cashflow, 0, "Zero notional yields zero cashflow");
    }

    function test_CalculateFixedCashflow_ZeroRate() public {
        uint256 cashflow = Cashflow.calculateFixedCashflow(
            NOTIONAL,
            0,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        assertEq(cashflow, 0, "Zero rate yields zero cashflow");
    }

    // ============================================
    // Floating Cashflow Tests
    // ============================================

    function test_CalculateFloatingCashflow_NoSpread() public {
        uint256 cashflow = Cashflow.calculateFloatingCashflow(
            NOTIONAL,
            RATE_3_PERCENT,
            0, // no spread
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~30,000 (1M * 3% * 1 year)
        assertApproxEqAbs(cashflow, 30000e18, 200e18, "Floating cashflow without spread");
    }

    function test_CalculateFloatingCashflow_WithSpread() public {
        uint256 spread = 0.005e18; // 50 bps
        uint256 cashflow = Cashflow.calculateFloatingCashflow(
            NOTIONAL,
            RATE_3_PERCENT,
            spread,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~35,000 (1M * 3.5% * 1 year)
        assertApproxEqAbs(cashflow, 35000e18, 200e18, "Floating cashflow with 50bps spread");
    }

    // ============================================
    // Payment Details Tests
    // ============================================

    function test_CalculatePaymentDetails_Basic() public {
        Cashflow.PaymentCalculation memory payment = Cashflow.calculatePaymentDetails(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED,
            ONE // no discount
        );

        assertApproxEqAbs(payment.grossAmount, 50000e18, 200e18, "Gross amount");
        assertApproxEqAbs(payment.netAmount, 50000e18, 200e18, "Net amount");
        assertApproxEqAbs(payment.presentValue, 50000e18, 200e18, "Present value (no discount)");
        assertTrue(payment.dayCountFraction > 0, "Has day count fraction");
        assertEq(payment.notional, NOTIONAL, "Notional preserved");
        assertEq(payment.rate, RATE_5_PERCENT, "Rate preserved");
    }

    function test_CalculatePaymentDetails_WithDiscount() public {
        uint256 discountFactor = 0.95e18; // 95%
        Cashflow.PaymentCalculation memory payment = Cashflow.calculatePaymentDetails(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            DayCountFractionEnum.ACT_365_FIXED,
            discountFactor
        );

        assertApproxEqAbs(payment.grossAmount, 50000e18, 200e18, "Gross amount");
        // PV = netAmount * discountFactor = 50000 * 0.95 = 47500
        assertApproxEqAbs(payment.presentValue, 47500e18, 200e18, "Present value with discount");
        assertEq(payment.discountFactor, discountFactor, "Discount factor preserved");
    }

    // ============================================
    // Present Value Tests
    // ============================================

    function test_CalculatePresentValue_Basic() public {
        uint256 futureValue = 100000e18;
        uint256 discountFactor = 0.95e18; // 95%

        uint256 pv = Cashflow.calculatePresentValue(futureValue, discountFactor);

        assertEq(pv, 95000e18, "Present value with 95% discount factor");
    }

    function test_CalculatePresentValue_NoDiscount() public {
        uint256 futureValue = 100000e18;
        uint256 discountFactor = ONE; // 100% - no discount

        uint256 pv = Cashflow.calculatePresentValue(futureValue, discountFactor);

        assertEq(pv, futureValue, "Present value equals future value with no discount");
    }

    function test_CalculatePresentValueWithRate_OneYear() public {
        uint256 futureValue = 100000e18;
        uint256 yearsToPayment = ONE; // 1 year
        uint256 discountRate = DISCOUNT_RATE; // 4%

        uint256 pv = Cashflow.calculatePresentValueWithRate(
            futureValue,
            discountRate,
            yearsToPayment
        );

        // Expected: 100000 / (1.04) ≈ 96,154
        assertApproxEqAbs(pv, 96154e18, 200e18, "PV with 4% discount over 1 year");
    }

    function test_CalculatePresentValueWithRate_TwoYears() public {
        uint256 futureValue = 100000e18;
        uint256 yearsToPayment = 2e18; // 2 years
        uint256 discountRate = DISCOUNT_RATE; // 4%

        uint256 pv = Cashflow.calculatePresentValueWithRate(
            futureValue,
            discountRate,
            yearsToPayment
        );

        // Expected: 100000 / (1 + 0.04*2) = 100000 / 1.08 ≈ 92,593
        // (simplified discounting, not compound)
        assertApproxEqAbs(pv, 92593e18, 500e18, "PV with 4% discount over 2 years");
    }

    // ============================================
    // Discount Factor Tests
    // ============================================

    function test_CalculateDiscountFactor_OneYear() public {
        uint256 df = Cashflow.calculateDiscountFactor(
            DISCOUNT_RATE,
            ONE // 1 year
        );

        // Expected: 1 / (1 + 0.04) ≈ 0.9615
        assertApproxEqAbs(df, 0.9615e18, 0.001e18, "Discount factor for 1 year at 4%");
    }

    function test_CalculateDiscountFactor_ZeroTime() public {
        uint256 df = Cashflow.calculateDiscountFactor(
            DISCOUNT_RATE,
            0 // immediate
        );

        assertEq(df, ONE, "Discount factor is 1.0 for immediate payment");
    }

    function test_CalculateDiscountFactor_HalfYear() public {
        uint256 df = Cashflow.calculateDiscountFactor(
            DISCOUNT_RATE,
            0.5e18 // 0.5 years
        );

        // Expected: 1 / (1 + 0.04*0.5) = 1 / 1.02 ≈ 0.9804
        assertApproxEqAbs(df, 0.9804e18, 0.001e18, "Discount factor for 6 months at 4%");
    }

    // ============================================
    // Net Present Value Tests
    // ============================================

    function test_CalculateNetPresentValue_TwoCashflows() public {
        Cashflow.CashflowData[] memory cashflows = new Cashflow.CashflowData[](2);
        uint256[] memory discountFactors = new uint256[](2);

        // Cashflow 1: 50,000 in 6 months, discount factor ~0.98
        cashflows[0] = Cashflow.createCashflow(
            50000e18,
            JULY_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );
        discountFactors[0] = 0.98e18;

        // Cashflow 2: 50,000 in 1 year, discount factor ~0.96
        cashflows[1] = Cashflow.createCashflow(
            50000e18,
            JAN_1_2025,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );
        discountFactors[1] = 0.96e18;

        uint256 npv = Cashflow.calculateNetPresentValue(
            cashflows,
            discountFactors
        );

        // NPV = 50000*0.98 + 50000*0.96 = 49000 + 48000 = 97000
        assertEq(npv, 97000e18, "NPV of two cashflows");
    }

    function test_CalculateNetPresentValue_EmptyCashflows() public {
        Cashflow.CashflowData[] memory cashflows = new Cashflow.CashflowData[](0);
        uint256[] memory discountFactors = new uint256[](0);

        uint256 npv = Cashflow.calculateNetPresentValue(
            cashflows,
            discountFactors
        );

        assertEq(npv, 0, "NPV of empty cashflows is zero");
    }

    // ============================================
    // Accrued Interest Tests
    // ============================================

    function test_CalculateAccruedInterest_HalfPeriod() public {
        uint256 accrued = Cashflow.calculateAccruedInterest(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            JULY_1_2024, // halfway through
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~25,000 (half of annual interest)
        assertApproxEqAbs(accrued, 25000e18, 300e18, "Accrued interest at midpoint");
    }

    function test_CalculateAccruedInterest_OneDayAfterStart() public {
        uint256 accrued = Cashflow.calculateAccruedInterest(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            JAN_1_2024 + 86400, // 1 day after start
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~137 (1M * 5% * 1/365)
        assertApproxEqAbs(accrued, 137e18, 10e18, "One day of accrued interest");
    }

    function test_CalculateAccruedInterest_EndDate() public {
        uint256 accrued = Cashflow.calculateAccruedInterest(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            JAN_1_2025, // at end
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~50,000 (full annual interest)
        assertApproxEqAbs(accrued, 50000e18, 200e18, "Full interest accrued at end");
    }

    function test_CalculateAccruedInterest_QuarterPeriod() public {
        uint256 accrued = Cashflow.calculateAccruedInterest(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2024,
            JAN_1_2025,
            APRIL_1_2024, // ~3 months
            DayCountFractionEnum.ACT_365_FIXED
        );

        // Expected: ~12,500 (quarter of annual interest)
        assertApproxEqAbs(accrued, 12500e18, 300e18, "Accrued interest at quarter");
    }

    // ============================================
    // Cashflow Netting Tests
    // ============================================

    function test_NetCashflows_BothPay() public {
        Cashflow.CashflowData memory cf1 = Cashflow.createCashflow(
            50000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        Cashflow.CashflowData memory cf2 = Cashflow.createCashflow(
            30000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        (uint256 netAmount, Cashflow.PaymentDirectionEnum direction) = Cashflow.netCashflows(cf1, cf2);

        assertEq(netAmount, 80000e18, "Net of both pay is sum");
        assertTrue(direction == Cashflow.PaymentDirectionEnum.PAY, "Direction is PAY");
    }

    function test_NetCashflows_BothReceive() public {
        Cashflow.CashflowData memory cf1 = Cashflow.createCashflow(
            50000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );

        Cashflow.CashflowData memory cf2 = Cashflow.createCashflow(
            30000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );

        (uint256 netAmount, Cashflow.PaymentDirectionEnum direction) = Cashflow.netCashflows(cf1, cf2);

        assertEq(netAmount, 80000e18, "Net of both receive is sum");
        assertTrue(direction == Cashflow.PaymentDirectionEnum.RECEIVE, "Direction is RECEIVE");
    }

    function test_NetCashflows_OppositeDirection_PayLarger() public {
        Cashflow.CashflowData memory cf1 = Cashflow.createCashflow(
            50000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        Cashflow.CashflowData memory cf2 = Cashflow.createCashflow(
            30000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );

        (uint256 netAmount, Cashflow.PaymentDirectionEnum direction) = Cashflow.netCashflows(cf1, cf2);

        assertEq(netAmount, 20000e18, "Net is difference");
        assertTrue(direction == Cashflow.PaymentDirectionEnum.PAY, "Direction is PAY (larger)");
    }

    function test_NetCashflows_OppositeDirection_ReceiveLarger() public {
        Cashflow.CashflowData memory cf1 = Cashflow.createCashflow(
            30000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        Cashflow.CashflowData memory cf2 = Cashflow.createCashflow(
            50000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );

        (uint256 netAmount, Cashflow.PaymentDirectionEnum direction) = Cashflow.netCashflows(cf1, cf2);

        assertEq(netAmount, 20000e18, "Net is difference");
        assertTrue(direction == Cashflow.PaymentDirectionEnum.RECEIVE, "Direction is RECEIVE (larger)");
    }

    // ============================================
    // Payment Rounding Tests
    // ============================================

    function test_RoundPayment_RoundDown() public {
        uint256 amount = 12345.674e18; // 12345.674
        uint256 precision = 0.01e18; // round to 0.01

        uint256 rounded = Cashflow.roundPayment(amount, precision);

        assertEq(rounded, 12345.67e18, "Rounds down to nearest 0.01");
    }

    function test_RoundPayment_RoundUp() public {
        uint256 amount = 12345.675e18; // 12345.675
        uint256 precision = 0.01e18; // round to 0.01

        uint256 rounded = Cashflow.roundPayment(amount, precision);

        assertEq(rounded, 12345.68e18, "Rounds up to nearest 0.01");
    }

    function test_RoundPayment_NoPrecision() public {
        uint256 amount = 12345.678e18;

        uint256 rounded = Cashflow.roundPayment(amount, 0);

        assertEq(rounded, amount, "No rounding when precision is 0");
    }

    function test_RoundPaymentStandard() public {
        uint256 amount = 12345.674e18;

        uint256 rounded = Cashflow.roundPaymentStandard(amount);

        // Default precision is 0.01
        assertEq(rounded, 12345.67e18, "Standard rounding to 0.01");
    }

    // ============================================
    // Helper Function Tests
    // ============================================

    function test_CreateCashflow() public {
        Cashflow.CashflowData memory cf = Cashflow.createCashflow(
            50000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        assertEq(cf.amount, 50000e18, "Amount set");
        assertEq(cf.paymentDate, JAN_1_2024, "Payment date set");
        assertTrue(cf.cashflowType == Cashflow.CashflowTypeEnum.INTEREST, "Type set");
        assertTrue(cf.direction == Cashflow.PaymentDirectionEnum.PAY, "Direction set");
        assertEq(cf.currency, USD, "Currency set");
        assertTrue(cf.isFixed, "Marked as fixed");
    }

    function test_IsPayment() public {
        Cashflow.CashflowData memory cf = Cashflow.createCashflow(
            50000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        assertTrue(Cashflow.isPayment(cf), "Cashflow is payment");
        assertFalse(Cashflow.isReceipt(cf), "Cashflow is not receipt");
    }

    function test_IsReceipt() public {
        Cashflow.CashflowData memory cf = Cashflow.createCashflow(
            50000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );

        assertTrue(Cashflow.isReceipt(cf), "Cashflow is receipt");
        assertFalse(Cashflow.isPayment(cf), "Cashflow is not payment");
    }

    function test_GetTotalAmount() public {
        Cashflow.CashflowData[] memory cashflows = new Cashflow.CashflowData[](2);
        cashflows[0] = Cashflow.createCashflow(
            30000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );
        cashflows[1] = Cashflow.createCashflow(
            20000e18,
            JULY_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        Cashflow.CashflowSchedule memory schedule = Cashflow.CashflowSchedule({
            cashflows: cashflows,
            numberOfCashflows: 2,
            totalGrossAmount: 50000e18,
            totalNetAmount: 50000e18,
            totalPresentValue: 0
        });

        uint256 total = Cashflow.getTotalAmount(schedule);
        assertEq(total, 50000e18, "Total amount");
    }

    function test_GetCashflowByDate() public {
        Cashflow.CashflowData[] memory cashflows = new Cashflow.CashflowData[](2);
        cashflows[0] = Cashflow.createCashflow(
            30000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );
        cashflows[1] = Cashflow.createCashflow(
            20000e18,
            JULY_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        Cashflow.CashflowSchedule memory schedule = Cashflow.CashflowSchedule({
            cashflows: cashflows,
            numberOfCashflows: 2,
            totalGrossAmount: 50000e18,
            totalNetAmount: 50000e18,
            totalPresentValue: 0
        });

        Cashflow.CashflowData memory cf = Cashflow.getCashflowByDate(schedule, JULY_1_2024);
        assertEq(cf.amount, 20000e18, "Found correct cashflow");
        assertEq(cf.paymentDate, JULY_1_2024, "Correct date");
    }

    function test_ValidateCashflowSchedule_Valid() public {
        Cashflow.CashflowData[] memory cashflows = new Cashflow.CashflowData[](2);
        cashflows[0] = Cashflow.createCashflow(
            30000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );
        cashflows[1] = Cashflow.createCashflow(
            20000e18,
            JULY_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.PAY,
            USD
        );

        Cashflow.CashflowSchedule memory schedule = Cashflow.CashflowSchedule({
            cashflows: cashflows,
            numberOfCashflows: 2,
            totalGrossAmount: 50000e18,
            totalNetAmount: 50000e18,
            totalPresentValue: 0
        });

        assertTrue(Cashflow.validateCashflowSchedule(schedule), "Valid schedule");
    }

    function test_ValidateCashflowSchedule_Empty() public {
        Cashflow.CashflowData[] memory cashflows = new Cashflow.CashflowData[](0);

        Cashflow.CashflowSchedule memory schedule = Cashflow.CashflowSchedule({
            cashflows: cashflows,
            numberOfCashflows: 0,
            totalGrossAmount: 0,
            totalNetAmount: 0,
            totalPresentValue: 0
        });

        assertFalse(Cashflow.validateCashflowSchedule(schedule), "Empty schedule is invalid");
    }

    // ============================================
    // Error Case Tests (using external wrappers)
    // ============================================

    // External wrapper for testing revert conditions
    function externalCalculateFixedCashflow(
        uint256 notional,
        uint256 rate,
        uint256 periodStart,
        uint256 periodEnd,
        DayCountFractionEnum dayCountFraction
    ) external pure returns (uint256) {
        return Cashflow.calculateFixedCashflow(notional, rate, periodStart, periodEnd, dayCountFraction);
    }

    function test_Error_InvalidDate_EndBeforeStart() public {
        try this.externalCalculateFixedCashflow(
            NOTIONAL,
            RATE_5_PERCENT,
            JAN_1_2025,  // end date
            JAN_1_2024,  // start date (reversed!)
            DayCountFractionEnum.ACT_365_FIXED
        ) {
            fail("Expected revert for end before start");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, Cashflow.Cashflow__InvalidDate.selector, "Should revert with InvalidDate");
        }
    }

    function externalCalculatePresentValue(
        uint256 amount,
        uint256 discountFactor
    ) external pure returns (uint256) {
        return Cashflow.calculatePresentValue(amount, discountFactor);
    }

    function test_Error_InvalidDiscountFactor_Zero() public {
        try this.externalCalculatePresentValue(100000e18, 0) {
            fail("Expected revert for zero discount factor");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, Cashflow.Cashflow__InvalidDiscountFactor.selector, "Should revert with InvalidDiscountFactor");
        }
    }

    function externalCalculateAccruedInterest(
        uint256 notional,
        uint256 rate,
        uint256 periodStart,
        uint256 periodEnd,
        uint256 accrualDate,
        DayCountFractionEnum dayCountFraction
    ) external pure returns (uint256) {
        return Cashflow.calculateAccruedInterest(notional, rate, periodStart, periodEnd, accrualDate, dayCountFraction);
    }

    function test_Error_AccrualDate_OutOfRange() public {
        // Accrual date before period start
        try this.externalCalculateAccruedInterest(
            NOTIONAL,
            RATE_5_PERCENT,
            JULY_1_2024,
            JAN_1_2025,
            JAN_1_2024, // before start
            DayCountFractionEnum.ACT_365_FIXED
        ) {
            fail("Expected revert for accrual date before period");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, Cashflow.Cashflow__InvalidDate.selector, "Should revert with InvalidDate");
        }
    }

    function externalCalculateNetPresentValue(
        Cashflow.CashflowData[] memory cashflows,
        uint256[] memory discountFactors
    ) external pure returns (uint256) {
        return Cashflow.calculateNetPresentValue(cashflows, discountFactors);
    }

    function test_Error_ArrayLengthMismatch() public {
        Cashflow.CashflowData[] memory cashflows = new Cashflow.CashflowData[](2);
        uint256[] memory discountFactors = new uint256[](1); // wrong length

        cashflows[0] = Cashflow.createCashflow(
            50000e18,
            JAN_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );
        cashflows[1] = Cashflow.createCashflow(
            50000e18,
            JULY_1_2024,
            Cashflow.CashflowTypeEnum.INTEREST,
            Cashflow.PaymentDirectionEnum.RECEIVE,
            USD
        );
        discountFactors[0] = ONE;

        try this.externalCalculateNetPresentValue(cashflows, discountFactors) {
            fail("Expected revert for array length mismatch");
        } catch (bytes memory reason) {
            bytes4 selector = bytes4(reason);
            assertEq(selector, Cashflow.Cashflow__ArrayLengthMismatch.selector, "Should revert with ArrayLengthMismatch");
        }
    }
}
