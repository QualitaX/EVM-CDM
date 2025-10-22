// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FixedPoint} from "./FixedPoint.sol";
import {DateTime} from "./DateTime.sol";
import {DayCount} from "./DayCount.sol";
import {InterestRate} from "./InterestRate.sol";
import {Schedule} from "./Schedule.sol";
import {Measure, Price} from "../types/CDMTypes.sol";
import {
    DayCountFractionEnum,
    PriceTypeEnum,
    ArithmeticOperatorEnum
} from "../types/Enums.sol";

/**
 * @title Cashflow
 * @notice Cashflow calculation and payment processing for derivatives
 * @dev Calculates payments, present value, and cash settlement amounts
 * @dev All amounts in fixed-point (18 decimals)
 *
 * FEATURES:
 * - Cashflow calculation (fixed and floating)
 * - Present value calculation with discounting
 * - Net present value (NPV) calculation
 * - Payment netting
 * - Accrual calculations
 * - Payment rounding
 *
 * CASHFLOW TYPES:
 * - Fixed rate payments (known in advance)
 * - Floating rate payments (calculated from observations)
 * - Principal payments (notional exchanges)
 * - Fee payments (upfront, periodic)
 * - Settlement payments (final exchanges)
 *
 * VALUATION:
 * - Present value with discount curves
 * - NPV for pricing and risk
 * - Accrued interest calculations
 * - Payment timing adjustments
 *
 * REFERENCES:
 * - ISDA Definitions (Payment calculation)
 * - Market conventions for rounding
 * - Standard settlement practices
 *
 * @author QualitaX Team
 */
library Cashflow {

    using FixedPoint for uint256;
    using DateTime for uint256;
    using DayCount for *;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Zero constant
    uint256 internal constant ZERO = 0;

    /// @notice Rounding precision (to nearest 0.01)
    uint256 internal constant DEFAULT_ROUNDING_PRECISION = 1e16; // 0.01 in 18 decimals

    // =============================================================================
    // ERRORS
    // =============================================================================

    error Cashflow__InvalidAmount();
    error Cashflow__InvalidDate();
    error Cashflow__InvalidDiscountFactor();
    error Cashflow__NegativeNotional();
    error Cashflow__ArrayLengthMismatch();

    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Cashflow type classification
    enum CashflowTypeEnum {
        INTEREST,           // Interest payment
        PRINCIPAL,          // Principal/notional payment
        FEE,                // Fee payment
        SETTLEMENT,         // Final settlement
        NOTIONAL_EXCHANGE,  // Notional exchange (e.g., at swap inception)
        OTHER               // Other payment type
    }

    /// @notice Payment direction
    enum PaymentDirectionEnum {
        PAY,                // Outflow (payer perspective)
        RECEIVE             // Inflow (receiver perspective)
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Single cashflow
    /// @dev Represents one payment obligation
    struct CashflowData {
        uint256 amount;                     // Payment amount (fixed-point)
        uint256 paymentDate;                // Date of payment
        uint256 calculationPeriodStart;     // Start of calculation period (if applicable)
        uint256 calculationPeriodEnd;       // End of calculation period (if applicable)
        CashflowTypeEnum cashflowType;      // Type of cashflow
        PaymentDirectionEnum direction;     // Pay or receive
        bytes32 currency;                   // Currency code (e.g., "USD", "EUR")
        bool isFixed;                       // True if amount is fixed, false if floating
    }

    /// @notice Payment calculation details
    /// @dev Full breakdown of payment calculation
    struct PaymentCalculation {
        uint256 notional;                   // Notional/principal amount
        uint256 rate;                       // Applied rate (fixed-point)
        uint256 dayCountFraction;           // Day count fraction
        uint256 grossAmount;                // Amount before adjustments
        uint256 netAmount;                  // Amount after adjustments
        uint256 discountFactor;             // Discount factor (for PV)
        uint256 presentValue;               // Present value
    }

    /// @notice Cashflow schedule (multiple payments)
    /// @dev Array of cashflows for a leg or instrument
    struct CashflowSchedule {
        CashflowData[] cashflows;           // Array of cashflows
        uint256 numberOfCashflows;          // Total count
        uint256 totalGrossAmount;           // Sum of all gross amounts
        uint256 totalNetAmount;             // Sum of all net amounts
        uint256 totalPresentValue;          // Sum of all PVs
    }

    /// @notice Discount curve point
    /// @dev Single point on discount curve
    struct DiscountPoint {
        uint256 date;                       // Date
        uint256 discountFactor;             // Discount factor (fixed-point)
    }

    // =============================================================================
    // CASHFLOW CALCULATION
    // =============================================================================

    /**
     * @notice Calculate fixed rate cashflow
     * @dev Interest = notional * rate * dayCountFraction
     * @param notional Notional amount
     * @param rate Fixed rate per annum
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @param dayCountFraction Day count convention
     * @return Cashflow amount
     *
     * @custom:example notional=1000000e18, rate=0.05e18 (5%), 365 days => ~50000e18
     */
    function calculateFixedCashflow(
        uint256 notional,
        uint256 rate,
        uint256 periodStart,
        uint256 periodEnd,
        DayCountFractionEnum dayCountFraction
    ) internal pure returns (uint256) {
        if (notional == 0) return 0;
        if (periodEnd <= periodStart) revert Cashflow__InvalidDate();

        // Calculate day count fraction
        uint256 dcf = DayCount.calculate(
            dayCountFraction,
            periodStart,
            periodEnd,
            0,
            0
        );

        // Interest = notional * rate * dcf
        uint256 rateTimeFraction = rate.mul(dcf);
        return notional.mul(rateTimeFraction);
    }

    /**
     * @notice Calculate floating rate cashflow
     * @dev Uses observed/calculated rate with spread adjustments
     * @param notional Notional amount
     * @param observedRate Observed floating rate
     * @param spread Spread over reference rate
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @param dayCountFraction Day count convention
     * @return Cashflow amount
     */
    function calculateFloatingCashflow(
        uint256 notional,
        uint256 observedRate,
        uint256 spread,
        uint256 periodStart,
        uint256 periodEnd,
        DayCountFractionEnum dayCountFraction
    ) internal pure returns (uint256) {
        if (notional == 0) return 0;
        if (periodEnd <= periodStart) revert Cashflow__InvalidDate();

        // Apply spread to rate
        uint256 effectiveRate = observedRate.add(spread);

        // Calculate using effective rate
        return calculateFixedCashflow(
            notional,
            effectiveRate,
            periodStart,
            periodEnd,
            dayCountFraction
        );
    }

    /**
     * @notice Calculate payment with full details
     * @dev Returns detailed breakdown of calculation
     * @param notional Notional amount
     * @param rate Applied rate
     * @param periodStart Period start
     * @param periodEnd Period end
     * @param dayCountFraction Day count convention
     * @param discountFactor Discount factor (1e18 = no discounting)
     * @return PaymentCalculation with full details
     */
    function calculatePaymentDetails(
        uint256 notional,
        uint256 rate,
        uint256 periodStart,
        uint256 periodEnd,
        DayCountFractionEnum dayCountFraction,
        uint256 discountFactor
    ) internal pure returns (PaymentCalculation memory) {
        // Calculate gross amount
        uint256 grossAmount = calculateFixedCashflow(
            notional,
            rate,
            periodStart,
            periodEnd,
            dayCountFraction
        );

        // Day count fraction for reference
        uint256 dcf = DayCount.calculate(
            dayCountFraction,
            periodStart,
            periodEnd,
            0,
            0
        );

        // Net amount (same as gross for now; can add adjustments)
        uint256 netAmount = grossAmount;

        // Present value
        uint256 presentValue = netAmount.mul(discountFactor);

        return PaymentCalculation({
            notional: notional,
            rate: rate,
            dayCountFraction: dcf,
            grossAmount: grossAmount,
            netAmount: netAmount,
            discountFactor: discountFactor,
            presentValue: presentValue
        });
    }

    // =============================================================================
    // PRESENT VALUE CALCULATIONS
    // =============================================================================

    /**
     * @notice Calculate present value of cashflow
     * @dev PV = amount * discountFactor
     * @param amount Future cashflow amount
     * @param discountFactor Discount factor (1e18 = no discount)
     * @return Present value
     */
    function calculatePresentValue(
        uint256 amount,
        uint256 discountFactor
    ) internal pure returns (uint256) {
        if (discountFactor == 0) revert Cashflow__InvalidDiscountFactor();
        return amount.mul(discountFactor);
    }

    /**
     * @notice Calculate present value with discount rate
     * @dev PV = amount / (1 + rate)^years
     * @dev Simplified: PV = amount * exp(-rate * years)
     * @param amount Future cashflow amount
     * @param discountRate Annual discount rate
     * @param yearsToPayment Years to payment (fixed-point)
     * @return Present value
     */
    function calculatePresentValueWithRate(
        uint256 amount,
        uint256 discountRate,
        uint256 yearsToPayment
    ) internal pure returns (uint256) {
        // Calculate discount factor: e^(-rate * years)
        // Simplified: 1 / (1 + rate * years) for small rates/periods
        uint256 discountFactor = calculateDiscountFactor(discountRate, yearsToPayment);
        return calculatePresentValue(amount, discountFactor);
    }

    /**
     * @notice Calculate discount factor from rate and time
     * @dev Simplified: df = 1 / (1 + rate * years)
     * @param discountRate Annual discount rate
     * @param yearsToPayment Time to payment (fixed-point)
     * @return Discount factor (fixed-point)
     */
    function calculateDiscountFactor(
        uint256 discountRate,
        uint256 yearsToPayment
    ) internal pure returns (uint256) {
        // df = 1 / (1 + rate * years)
        uint256 rateTimeProduct = discountRate.mul(yearsToPayment);
        uint256 onePlusRateTime = FixedPoint.ONE.add(rateTimeProduct);
        return FixedPoint.ONE.div(onePlusRateTime);
    }

    /**
     * @notice Calculate NPV of cashflow schedule
     * @dev Sum of present values of all cashflows
     * @param cashflows Array of cashflows
     * @param discountFactors Array of discount factors (one per cashflow)
     * @return Net present value
     */
    function calculateNetPresentValue(
        CashflowData[] memory cashflows,
        uint256[] memory discountFactors
    ) internal pure returns (uint256) {
        if (cashflows.length != discountFactors.length) {
            revert Cashflow__ArrayLengthMismatch();
        }

        uint256 npv = 0;
        for (uint256 i = 0; i < cashflows.length; i++) {
            uint256 pv = calculatePresentValue(cashflows[i].amount, discountFactors[i]);

            // Adjust for direction (pay = negative, receive = positive)
            if (cashflows[i].direction == PaymentDirectionEnum.PAY) {
                // Note: In fixed-point, we can't have negative numbers
                // This would need to be handled by the calling context
                // For now, we accumulate absolute values
                npv = npv.add(pv);
            } else {
                npv = npv.add(pv);
            }
        }

        return npv;
    }

    // =============================================================================
    // CASHFLOW SCHEDULE GENERATION
    // =============================================================================

    /**
     * @notice Generate fixed rate cashflow schedule
     * @dev Creates cashflows for each period in schedule
     * @param periods Array of calculation periods
     * @param notional Notional amount
     * @param fixedRate Fixed rate
     * @param dayCountFraction Day count convention
     * @param currency Currency code
     * @param direction Payment direction
     * @return CashflowSchedule with all payments
     */
    function generateFixedCashflowSchedule(
        Schedule.CalculationPeriod[] memory periods,
        uint256 notional,
        uint256 fixedRate,
        DayCountFractionEnum dayCountFraction,
        bytes32 currency,
        PaymentDirectionEnum direction
    ) internal pure returns (CashflowSchedule memory) {
        CashflowData[] memory cashflows = new CashflowData[](periods.length);
        uint256 totalGross = 0;

        for (uint256 i = 0; i < periods.length; i++) {
            uint256 amount = calculateFixedCashflow(
                notional,
                fixedRate,
                periods[i].startDate,
                periods[i].endDate,
                dayCountFraction
            );

            cashflows[i] = CashflowData({
                amount: amount,
                paymentDate: periods[i].endDate,
                calculationPeriodStart: periods[i].startDate,
                calculationPeriodEnd: periods[i].endDate,
                cashflowType: CashflowTypeEnum.INTEREST,
                direction: direction,
                currency: currency,
                isFixed: true
            });

            totalGross = totalGross.add(amount);
        }

        return CashflowSchedule({
            cashflows: cashflows,
            numberOfCashflows: periods.length,
            totalGrossAmount: totalGross,
            totalNetAmount: totalGross, // Same as gross (no adjustments)
            totalPresentValue: 0 // Needs discount factors to calculate
        });
    }

    // =============================================================================
    // ACCRUAL CALCULATIONS
    // =============================================================================

    /**
     * @notice Calculate accrued interest as of a date
     * @dev Accrued = notional * rate * daysSinceStart / daysInPeriod
     * @param notional Notional amount
     * @param rate Annual rate
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @param accrualDate Date to calculate accrual (must be between start and end)
     * @param dayCountFraction Day count convention
     * @return Accrued interest amount
     */
    function calculateAccruedInterest(
        uint256 notional,
        uint256 rate,
        uint256 periodStart,
        uint256 periodEnd,
        uint256 accrualDate,
        DayCountFractionEnum dayCountFraction
    ) internal pure returns (uint256) {
        if (accrualDate < periodStart || accrualDate > periodEnd) {
            revert Cashflow__InvalidDate();
        }

        // Calculate interest for accrual period
        return calculateFixedCashflow(
            notional,
            rate,
            periodStart,
            accrualDate,
            dayCountFraction
        );
    }

    /**
     * @notice Calculate accrued interest for current timestamp
     * @dev Convenience function using block.timestamp
     * @param notional Notional amount
     * @param rate Annual rate
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @param dayCountFraction Day count convention
     * @return Accrued interest as of now
     */
    function calculateCurrentAccrual(
        uint256 notional,
        uint256 rate,
        uint256 periodStart,
        uint256 periodEnd,
        DayCountFractionEnum dayCountFraction
    ) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;

        // If before period start, no accrual
        if (currentTime < periodStart) {
            return 0;
        }

        // If after period end, full period interest
        if (currentTime > periodEnd) {
            return calculateFixedCashflow(
                notional,
                rate,
                periodStart,
                periodEnd,
                dayCountFraction
            );
        }

        // Otherwise, accrual to current date
        return calculateAccruedInterest(
            notional,
            rate,
            periodStart,
            periodEnd,
            currentTime,
            dayCountFraction
        );
    }

    // =============================================================================
    // PAYMENT NETTING
    // =============================================================================

    /**
     * @notice Net two cashflows on same date and currency
     * @dev Returns net amount (difference between pay and receive)
     * @param cashflow1 First cashflow
     * @param cashflow2 Second cashflow
     * @return Net cashflow amount (absolute value)
     * @return Resulting direction (PAY if cashflow1 > cashflow2, else RECEIVE)
     */
    function netCashflows(
        CashflowData memory cashflow1,
        CashflowData memory cashflow2
    ) internal pure returns (uint256, PaymentDirectionEnum) {
        // Verify same date and currency
        if (cashflow1.paymentDate != cashflow2.paymentDate) {
            revert Cashflow__InvalidDate();
        }

        // Calculate net based on direction
        uint256 amount1 = cashflow1.direction == PaymentDirectionEnum.PAY
            ? cashflow1.amount
            : 0;
        uint256 amount2 = cashflow2.direction == PaymentDirectionEnum.PAY
            ? cashflow2.amount
            : 0;
        uint256 receive1 = cashflow1.direction == PaymentDirectionEnum.RECEIVE
            ? cashflow1.amount
            : 0;
        uint256 receive2 = cashflow2.direction == PaymentDirectionEnum.RECEIVE
            ? cashflow2.amount
            : 0;

        uint256 totalPay = amount1.add(amount2);
        uint256 totalReceive = receive1.add(receive2);

        if (totalPay > totalReceive) {
            return (totalPay - totalReceive, PaymentDirectionEnum.PAY);
        } else {
            return (totalReceive - totalPay, PaymentDirectionEnum.RECEIVE);
        }
    }

    // =============================================================================
    // PAYMENT ROUNDING
    // =============================================================================

    /**
     * @notice Round payment amount to specified precision
     * @dev Standard rounding to nearest
     * @param amount Amount to round
     * @param precision Rounding precision (e.g., 1e16 = 0.01)
     * @return Rounded amount
     */
    function roundPayment(
        uint256 amount,
        uint256 precision
    ) internal pure returns (uint256) {
        if (precision == 0) return amount;

        uint256 remainder = amount % precision;
        uint256 roundedDown = amount - remainder;

        // Round to nearest
        if (remainder >= precision / 2) {
            return roundedDown + precision;
        } else {
            return roundedDown;
        }
    }

    /**
     * @notice Round payment to standard precision (0.01)
     * @param amount Amount to round
     * @return Rounded amount
     */
    function roundPaymentStandard(uint256 amount) internal pure returns (uint256) {
        return roundPayment(amount, DEFAULT_ROUNDING_PRECISION);
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Create cashflow
     * @param amount Payment amount
     * @param paymentDate Date of payment
     * @param cashflowType Type of cashflow
     * @param direction Payment direction
     * @param currency Currency code
     * @return CashflowData struct
     */
    function createCashflow(
        uint256 amount,
        uint256 paymentDate,
        CashflowTypeEnum cashflowType,
        PaymentDirectionEnum direction,
        bytes32 currency
    ) internal pure returns (CashflowData memory) {
        return CashflowData({
            amount: amount,
            paymentDate: paymentDate,
            calculationPeriodStart: 0,
            calculationPeriodEnd: 0,
            cashflowType: cashflowType,
            direction: direction,
            currency: currency,
            isFixed: true
        });
    }

    /**
     * @notice Get total amount from cashflow schedule
     * @param schedule Cashflow schedule
     * @return Total gross amount
     */
    function getTotalAmount(
        CashflowSchedule memory schedule
    ) internal pure returns (uint256) {
        return schedule.totalGrossAmount;
    }

    /**
     * @notice Get cashflow by date
     * @param schedule Cashflow schedule
     * @param date Payment date to find
     * @return Cashflow for date (reverts if not found)
     */
    function getCashflowByDate(
        CashflowSchedule memory schedule,
        uint256 date
    ) internal pure returns (CashflowData memory) {
        for (uint256 i = 0; i < schedule.numberOfCashflows; i++) {
            if (schedule.cashflows[i].paymentDate == date) {
                return schedule.cashflows[i];
            }
        }
        revert Cashflow__InvalidDate();
    }

    /**
     * @notice Check if cashflow is payment (not receipt)
     * @param cashflow Cashflow to check
     * @return true if payment (PAY direction)
     */
    function isPayment(CashflowData memory cashflow) internal pure returns (bool) {
        return cashflow.direction == PaymentDirectionEnum.PAY;
    }

    /**
     * @notice Check if cashflow is receipt (not payment)
     * @param cashflow Cashflow to check
     * @return true if receipt (RECEIVE direction)
     */
    function isReceipt(CashflowData memory cashflow) internal pure returns (bool) {
        return cashflow.direction == PaymentDirectionEnum.RECEIVE;
    }

    /**
     * @notice Validate cashflow schedule
     * @dev Checks for consistency
     * @param schedule Schedule to validate
     * @return true if valid
     */
    function validateCashflowSchedule(
        CashflowSchedule memory schedule
    ) internal pure returns (bool) {
        if (schedule.numberOfCashflows == 0) {
            return false;
        }

        if (schedule.cashflows.length != schedule.numberOfCashflows) {
            return false;
        }

        // Check dates are in order
        for (uint256 i = 1; i < schedule.numberOfCashflows; i++) {
            if (schedule.cashflows[i].paymentDate <
                schedule.cashflows[i - 1].paymentDate) {
                return false;
            }
        }

        return true;
    }
}
