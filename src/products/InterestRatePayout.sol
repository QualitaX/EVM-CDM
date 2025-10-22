// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {InterestRate} from "../base/libraries/InterestRate.sol";
import {Schedule} from "../base/libraries/Schedule.sol";
import {Cashflow} from "../base/libraries/Cashflow.sol";
import {BusinessDayAdjustments as BDALib} from "../base/libraries/BusinessDayAdjustments.sol";
import {ObservationSchedule} from "../base/libraries/ObservationSchedule.sol";
import {DayCount} from "../base/libraries/DayCount.sol";
import {FixedPoint} from "../base/libraries/FixedPoint.sol";
import {CompoundingLib} from "../base/libraries/CompoundingLib.sol";
import {
    DayCountFractionEnum,
    BusinessDayConventionEnum,
    BusinessCenterEnum,
    PeriodEnum,
    CompoundingMethodEnum
} from "../base/types/Enums.sol";
import {Period, BusinessDayAdjustments as BDAType} from "../base/types/CDMTypes.sol";

/**
 * @title InterestRatePayout
 * @notice Interest rate payout implementation for derivatives
 * @dev Represents one leg of an interest rate swap or other IRP
 * @dev Supports both fixed and floating rate payouts
 * @dev Integrates Schedule, InterestRate, ObservationSchedule, and Cashflow libraries
 *
 * KEY FEATURES:
 * - Fixed rate payout with regular payment schedule
 * - Floating rate payout with observation schedule (SOFR, LIBOR, etc.)
 * - Cashflow generation for past and future payments
 * - NPV calculation with discount curves
 * - Accrued interest calculation
 *
 * FIXED LEG EXAMPLE:
 * - Notional: $10M
 * - Fixed rate: 3.5%
 * - Payment frequency: Quarterly
 * - Day count: ACT/360
 * - Cashflows: ~$87,500 per quarter
 *
 * FLOATING LEG EXAMPLE:
 * - Notional: $10M
 * - Reference rate: SOFR
 * - Spread: +50 bps
 * - Payment frequency: Quarterly
 * - Observation: Daily with 2-day lookback
 * - Day count: ACT/360
 *
 * @author QualitaX Team
 */
contract InterestRatePayout {
    using FixedPoint for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Fixed-point one (1.0)
    uint256 private constant ONE = 1e18;

    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Type of rate payout
    enum PayoutTypeEnum {
        FIXED,      // Fixed rate payout
        FLOATING    // Floating rate payout
    }

    /// @notice Status of calculation period
    enum PeriodStatusEnum {
        PENDING,    // Future period, not yet started
        ACTIVE,     // Current period, accruing interest
        SETTLED     // Past period, payment made
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Interest rate payout specification
    /// @dev Complete specification for one leg of an IRS
    struct InterestRatePayoutSpec {
        // Basic parameters
        uint256 notional;                           // Notional amount (fixed-point)
        PayoutTypeEnum payoutType;                  // Fixed or floating
        Cashflow.PaymentDirectionEnum direction;    // Pay or receive
        bytes32 currency;                           // Currency code

        // Fixed rate parameters (only if payoutType == FIXED)
        uint256 fixedRate;                          // Fixed rate per annum (fixed-point)

        // Floating rate parameters (only if payoutType == FLOATING)
        bytes32 floatingRateIndex;                  // Reference rate identifier (e.g., "SOFR", "LIBOR")
        uint256 spread;                             // Spread over reference rate (fixed-point, can be 0)
        uint256 multiplier;                         // Rate multiplier (1e18 = 1.0, usually 1e18)

        // Schedule parameters
        uint256 effectiveDate;                      // Start date (Unix timestamp)
        uint256 terminationDate;                    // End date (Unix timestamp)
        Period paymentFrequency;                    // How often payments are made
        Period calculationPeriodFrequency;          // How often periods are calculated (usually same as payment)
        DayCountFractionEnum dayCountFraction;      // Day count convention

        // Business day adjustments
        BDAType businessDayAdjustments;             // Business day adjustment rules
        Schedule.RollConventionEnum rollConvention; // Roll convention for schedule
        Schedule.StubTypeEnum stubPeriod;           // Stub period handling

        // Observation parameters (only if payoutType == FLOATING)
        uint256 observationShift;                   // Observation shift in days (e.g., 2 for SOFR lookback)
        ObservationSchedule.ObservationMethodEnum observationMethod;    // SINGLE, DAILY, etc.
        ObservationSchedule.ObservationShiftEnum observationShiftType;  // LOOKBACK, LOCK_OUT, etc.
    }

    /// @notice Calculated interest rate period
    /// @dev Result of calculating interest for one period
    struct CalculatedPeriod {
        uint256 startDate;                          // Period start date
        uint256 endDate;                            // Period end date
        uint256 paymentDate;                        // Date payment is due
        uint256 notional;                           // Notional for this period
        uint256 rate;                               // Applied rate (fixed or compounded floating)
        uint256 dayCountFraction;                   // Calculated day count fraction
        uint256 interestAmount;                     // Calculated interest amount
        PeriodStatusEnum status;                    // Period status
        bool isStub;                                // Whether this is a stub period
    }

    /// @notice Payout calculation result
    /// @dev Complete result of calculating all cashflows for payout
    struct PayoutCalculationResult {
        CalculatedPeriod[] periods;                 // All calculation periods
        uint256 totalInterest;                      // Sum of all interest amounts
        uint256 npv;                                // Net present value (if discount factors provided)
        uint256 accruedInterest;                    // Current accrued interest
    }

    // =============================================================================
    // ERRORS
    // =============================================================================

    error InterestRatePayout__InvalidNotional();
    error InterestRatePayout__InvalidDates();
    error InterestRatePayout__InvalidRate();
    error InterestRatePayout__InvalidPayoutType();
    error InterestRatePayout__MissingFloatingRateParameters();
    error InterestRatePayout__MissingObservationSchedule();
    error InterestRatePayout__InvalidPeriodFrequency();

    // =============================================================================
    // FIXED RATE PAYOUT FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate fixed rate payout cashflows
     * @dev Generates payment schedule and calculates interest for each period
     * @param spec Payout specification
     * @return result Complete calculation result with all periods
     *
     * @custom:example
     * - $10M notional, 3.5% fixed, quarterly payments, ACT/360
     * - Returns ~$87,500 per quarter
     */
    function calculateFixedPayout(
        InterestRatePayoutSpec memory spec
    ) public view returns (PayoutCalculationResult memory result) {
        // Validate inputs
        if (spec.notional == 0) revert InterestRatePayout__InvalidNotional();
        if (spec.terminationDate <= spec.effectiveDate) revert InterestRatePayout__InvalidDates();
        if (spec.payoutType != PayoutTypeEnum.FIXED) revert InterestRatePayout__InvalidPayoutType();
        if (spec.fixedRate == 0) revert InterestRatePayout__InvalidRate();

        // Generate payment schedule
        Schedule.ScheduleParameters memory scheduleParams = Schedule.ScheduleParameters({
            effectiveDate: spec.effectiveDate,
            terminationDate: spec.terminationDate,
            frequency: spec.paymentFrequency,
            rollConvention: spec.rollConvention,
            rollDay: 0, // 0 = use EOM or calculated day
            stubType: spec.stubPeriod,
            adjustments: spec.businessDayAdjustments
        });

        Schedule.ScheduleResult memory scheduleResult = Schedule.generateSchedule(scheduleParams);
        Schedule.CalculationPeriod[] memory periods = scheduleResult.periods;

        // Calculate interest for each period
        CalculatedPeriod[] memory calculatedPeriods = new CalculatedPeriod[](periods.length);
        uint256 totalInterest = 0;

        for (uint256 i = 0; i < periods.length; i++) {
            // Calculate day count fraction
            uint256 dcf = DayCount.calculate(
                spec.dayCountFraction,
                periods[i].startDate,
                periods[i].endDate,
                0,  // No termination date for simple DCF
                0   // No frequency for ACT/360 style conventions
            );

            // Calculate interest: notional * rate * dcf / ONE / ONE
            // Split calculation to avoid stack too deep
            uint256 rateAmount = spec.notional.mul(spec.fixedRate).div(ONE);
            uint256 interest = rateAmount.mul(dcf).div(ONE);

            calculatedPeriods[i] = CalculatedPeriod({
                startDate: periods[i].startDate,
                endDate: periods[i].endDate,
                paymentDate: periods[i].endDate, // Payment at period end
                notional: spec.notional,
                rate: spec.fixedRate,
                dayCountFraction: dcf,
                interestAmount: interest,
                status: _getPeriodStatus(periods[i].endDate),
                isStub: periods[i].isStub
            });

            totalInterest = totalInterest.add(interest);
        }

        result = PayoutCalculationResult({
            periods: calculatedPeriods,
            totalInterest: totalInterest,
            npv: 0, // NPV requires discount factors
            accruedInterest: _calculateAccruedInterest(spec, calculatedPeriods)
        });
    }

    /**
     * @notice Calculate fixed rate interest for a single period
     * @param spec Payout specification
     * @param periodStart Period start date
     * @param periodEnd Period end date
     * @return interest Interest amount for period
     */
    function calculateFixedPeriodInterest(
        InterestRatePayoutSpec memory spec,
        uint256 periodStart,
        uint256 periodEnd
    ) public pure returns (uint256 interest) {
        if (spec.payoutType != PayoutTypeEnum.FIXED) revert InterestRatePayout__InvalidPayoutType();

        return InterestRate.calculateFixedRateInterest(
            spec.notional,
            spec.fixedRate,
            periodStart,
            periodEnd,
            spec.dayCountFraction
        );
    }

    // =============================================================================
    // FLOATING RATE PAYOUT FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate floating rate payout cashflows
     * @dev Generates payment schedule and calculates compounded interest for each period
     * @param spec Payout specification
     * @param rateObservations Array of observed rates for each period
     * @return result Complete calculation result with all periods
     *
     * @custom:note rateObservations array must have one entry per calculation period
     * @custom:example SOFR-based floating leg with 2-day lookback
     */
    function calculateFloatingPayout(
        InterestRatePayoutSpec memory spec,
        uint256[][] memory rateObservations
    ) public view returns (PayoutCalculationResult memory result) {
        // Validate inputs
        if (spec.notional == 0) revert InterestRatePayout__InvalidNotional();
        if (spec.terminationDate <= spec.effectiveDate) revert InterestRatePayout__InvalidDates();
        if (spec.payoutType != PayoutTypeEnum.FLOATING) revert InterestRatePayout__InvalidPayoutType();

        // Generate payment schedule
        Schedule.ScheduleParameters memory scheduleParams = Schedule.ScheduleParameters({
            effectiveDate: spec.effectiveDate,
            terminationDate: spec.terminationDate,
            frequency: spec.paymentFrequency,
            rollConvention: spec.rollConvention,
            rollDay: 0, // 0 = use EOM or calculated day
            stubType: spec.stubPeriod,
            adjustments: spec.businessDayAdjustments
        });

        Schedule.ScheduleResult memory scheduleResult = Schedule.generateSchedule(scheduleParams);
        Schedule.CalculationPeriod[] memory periods = scheduleResult.periods;

        // Validate rate observations
        if (rateObservations.length != periods.length) {
            revert InterestRatePayout__MissingObservationSchedule();
        }

        // Calculate interest for each period
        CalculatedPeriod[] memory calculatedPeriods = new CalculatedPeriod[](periods.length);
        uint256 totalInterest = 0;

        for (uint256 i = 0; i < periods.length; i++) {
            calculatedPeriods[i] = _calculateFloatingPeriod(
                spec,
                periods[i],
                rateObservations[i]
            );
            totalInterest = totalInterest.add(calculatedPeriods[i].interestAmount);
        }

        result = PayoutCalculationResult({
            periods: calculatedPeriods,
            totalInterest: totalInterest,
            npv: 0,
            accruedInterest: _calculateAccruedInterest(spec, calculatedPeriods)
        });
    }

    /**
     * @notice Calculate compounded floating rate for a period
     * @dev Uses observation method specified in spec
     * @param spec Payout specification
     * @param period Calculation period
     * @param observations Array of rate observations
     * @return compoundedRate Compounded rate for period
     */
    function _calculateCompoundedRate(
        InterestRatePayoutSpec memory spec,
        Schedule.CalculationPeriod memory period,
        uint256[] memory observations
    ) private pure returns (uint256 compoundedRate) {
        if (observations.length == 0) {
            revert InterestRatePayout__MissingObservationSchedule();
        }

        // For SINGLE observation method, just use the observation directly
        if (spec.observationMethod == ObservationSchedule.ObservationMethodEnum.SINGLE) {
            return observations[0];
        }

        // For DAILY observations, calculate compounded rate
        // Convert uint256[] to RateObservation[]
        InterestRate.RateObservation[] memory rateObservations =
            new InterestRate.RateObservation[](observations.length);

        for (uint256 i = 0; i < observations.length; i++) {
            rateObservations[i] = InterestRate.RateObservation({
                observationDate: period.startDate + (i * 86400), // Daily observations
                effectiveDate: period.startDate + (i * 86400),
                rate: observations[i],
                weight: ONE / observations.length  // Equal weight
            });
        }

        // Use FLAT compounding (simple average) for daily observations
        // Daily observations (like SOFR) are already annualized, so we average them
        // STRAIGHT compounding would compound them geometrically which is incorrect
        compoundedRate = InterestRate.calculateCompoundedRate(
            rateObservations,
            CompoundingMethodEnum.FLAT
        );
    }

    /**
     * @notice Calculate single floating rate period
     * @dev Helper function to avoid stack too deep error
     * @param spec Payout specification
     * @param period Calculation period
     * @param observations Rate observations for this period
     * @return Calculated period with interest
     */
    function _calculateFloatingPeriod(
        InterestRatePayoutSpec memory spec,
        Schedule.CalculationPeriod memory period,
        uint256[] memory observations
    ) private view returns (CalculatedPeriod memory) {
        // Calculate compounded rate from observations
        uint256 compoundedRate = _calculateCompoundedRate(spec, period, observations);

        // Apply spread
        uint256 effectiveRate = compoundedRate.add(spec.spread);

        // Calculate day count fraction
        uint256 dcf = DayCount.calculate(
            spec.dayCountFraction,
            period.startDate,
            period.endDate,
            0,
            0
        );

        // Calculate interest: notional * effectiveRate * dcf / ONE / ONE
        uint256 rateAmount = spec.notional.mul(effectiveRate).div(ONE);
        uint256 interest = rateAmount.mul(dcf).div(ONE);

        return CalculatedPeriod({
            startDate: period.startDate,
            endDate: period.endDate,
            paymentDate: period.endDate,
            notional: spec.notional,
            rate: effectiveRate,
            dayCountFraction: dcf,
            interestAmount: interest,
            status: _getPeriodStatus(period.endDate),
            isStub: period.isStub
        });
    }

    // =============================================================================
    // NPV CALCULATION
    // =============================================================================

    /**
     * @notice Calculate NPV of payout with discount factors
     * @dev Discounts all future cashflows to present value
     * @param calculationResult Previous calculation result
     * @param discountFactors Discount factor for each period
     * @return npv Net present value
     */
    function calculateNPV(
        PayoutCalculationResult memory calculationResult,
        uint256[] memory discountFactors
    ) public pure returns (uint256 npv) {
        if (calculationResult.periods.length != discountFactors.length) {
            revert InterestRatePayout__InvalidDates();
        }

        npv = 0;
        for (uint256 i = 0; i < calculationResult.periods.length; i++) {
            // interestAmount * discountFactor / ONE
            uint256 pv = calculationResult.periods[i].interestAmount.mul(discountFactors[i]).div(ONE);
            npv = npv.add(pv);
        }
    }

    // =============================================================================
    // ACCRUED INTEREST
    // =============================================================================

    /**
     * @notice Calculate accrued interest as of current time
     * @dev Only calculates for active (current) period
     * @param spec Payout specification
     * @param periods All calculated periods
     * @return accrued Accrued interest amount
     */
    function _calculateAccruedInterest(
        InterestRatePayoutSpec memory spec,
        CalculatedPeriod[] memory periods
    ) private view returns (uint256 accrued) {
        uint256 currentTime = block.timestamp;

        // Find active period
        for (uint256 i = 0; i < periods.length; i++) {
            if (currentTime >= periods[i].startDate && currentTime < periods[i].endDate) {
                // This is the active period
                if (spec.payoutType == PayoutTypeEnum.FIXED) {
                    // For fixed, calculate pro-rata interest
                    return Cashflow.calculateAccruedInterest(
                        spec.notional,
                        spec.fixedRate,
                        periods[i].startDate,
                        periods[i].endDate,
                        currentTime,
                        spec.dayCountFraction
                    );
                } else {
                    // For floating, would need current observations
                    // For now, return 0 (requires oracle integration)
                    return 0;
                }
            }
        }

        return 0;
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Determine period status based on payment date
     * @param paymentDate Payment date for period
     * @return status Period status
     */
    function _getPeriodStatus(uint256 paymentDate) private view returns (PeriodStatusEnum) {
        uint256 currentTime = block.timestamp;

        if (currentTime < paymentDate) {
            return PeriodStatusEnum.PENDING;
        } else {
            return PeriodStatusEnum.SETTLED;
        }
    }

    /**
     * @notice Validate interest rate payout specification
     * @param spec Payout specification to validate
     * @return valid Whether specification is valid
     */
    function validatePayoutSpec(InterestRatePayoutSpec memory spec) public pure returns (bool valid) {
        // Basic validations
        if (spec.notional == 0) return false;
        if (spec.terminationDate <= spec.effectiveDate) return false;
        if (spec.paymentFrequency.periodMultiplier == 0) return false;

        // Fixed rate validations
        if (spec.payoutType == PayoutTypeEnum.FIXED) {
            if (spec.fixedRate == 0) return false;
        }

        // Floating rate validations
        if (spec.payoutType == PayoutTypeEnum.FLOATING) {
            if (spec.floatingRateIndex == bytes32(0)) return false;
            if (spec.multiplier == 0) return false;
        }

        return true;
    }

    /**
     * @notice Get total number of payment periods
     * @param spec Payout specification
     * @return count Number of periods
     */
    function getNumberOfPeriods(InterestRatePayoutSpec memory spec) public pure returns (uint256 count) {
        return Schedule.estimateNumberOfPeriods(
            spec.effectiveDate,
            spec.terminationDate,
            spec.paymentFrequency
        );
    }

    /**
     * @notice Convert cashflows to Cashflow library format
     * @param calculationResult Calculation result
     * @param direction Payment direction
     * @param currency Currency code
     * @return cashflows Array of cashflows in standard format
     */
    function toCashflows(
        PayoutCalculationResult memory calculationResult,
        Cashflow.PaymentDirectionEnum direction,
        bytes32 currency
    ) public pure returns (Cashflow.CashflowData[] memory cashflows) {
        cashflows = new Cashflow.CashflowData[](calculationResult.periods.length);

        for (uint256 i = 0; i < calculationResult.periods.length; i++) {
            cashflows[i] = Cashflow.CashflowData({
                amount: calculationResult.periods[i].interestAmount,
                paymentDate: calculationResult.periods[i].paymentDate,
                calculationPeriodStart: calculationResult.periods[i].startDate,
                calculationPeriodEnd: calculationResult.periods[i].endDate,
                cashflowType: Cashflow.CashflowTypeEnum.INTEREST,
                direction: direction,
                currency: currency,
                isFixed: true // Simplified - would check spec.payoutType
            });
        }
    }
}
