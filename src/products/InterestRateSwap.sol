// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {InterestRatePayout} from "./InterestRatePayout.sol";
import {Cashflow} from "../base/libraries/Cashflow.sol";
import {FixedPoint} from "../base/libraries/FixedPoint.sol";
import {Schedule} from "../base/libraries/Schedule.sol";
import {ObservationSchedule} from "../base/libraries/ObservationSchedule.sol";
import {
    DayCountFractionEnum,
    BusinessDayConventionEnum,
    BusinessCenterEnum,
    PeriodEnum
} from "../base/types/Enums.sol";
import {Period, BusinessDayAdjustments, PartyRole} from "../base/types/CDMTypes.sol";

/**
 * @title InterestRateSwap
 * @notice Interest rate swap implementation
 * @dev Represents a vanilla fixed-for-floating interest rate swap
 * @dev Combines two InterestRatePayout legs (fixed and floating)
 *
 * KEY FEATURES:
 * - Two-leg structure (fixed payer leg + floating receiver leg, or vice versa)
 * - Net cashflow calculation (offset payments between legs)
 * - Mark-to-market (MTM) valuation
 * - Fair value calculation
 * - Settlement net amounts
 *
 * TYPICAL IRS STRUCTURE:
 * Party A: Pays fixed 3.5%, receives SOFR
 * Party B: Receives fixed 3.5%, pays SOFR
 * Notional: $10M
 * Tenor: 5 years
 * Frequency: Quarterly
 *
 * EXAMPLE CASHFLOW:
 * Period 1: Party A pays $87,500 (fixed), receives $75,000 (SOFR @ 3.0%)
 * Net: Party A pays $12,500 to Party B
 *
 * @author QualitaX Team
 */
contract InterestRateSwap {
    using FixedPoint for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Fixed-point one (1.0)
    uint256 private constant ONE = 1e18;

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    /// @notice InterestRatePayout contract reference
    InterestRatePayout public immutable payoutContract;

    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Swap status
    enum SwapStatusEnum {
        CREATED,        // Swap created, not yet active
        ACTIVE,         // Swap is active and accruing
        TERMINATED,     // Swap terminated early
        MATURED         // Swap reached maturity
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Interest rate swap specification
    /// @dev Complete specification for a fixed-for-floating IRS
    struct InterestRateSwapSpec {
        // Swap identification
        bytes32 swapId;                                 // Unique swap identifier
        bytes32 tradeId;                                // Trade identifier
        uint256 tradeDate;                              // Date of trade execution

        // Party information
        bytes32 partyAReference;                        // Party A reference
        bytes32 partyBReference;                        // Party B reference

        // Leg specifications
        InterestRatePayout.InterestRatePayoutSpec fixedLeg;    // Fixed rate leg
        InterestRatePayout.InterestRatePayoutSpec floatingLeg; // Floating rate leg

        // Common parameters (should match in both legs)
        uint256 notional;                               // Notional amount (fixed-point)
        bytes32 currency;                               // Currency code
        uint256 effectiveDate;                          // Swap effective date
        uint256 terminationDate;                        // Swap termination date

        // Metadata
        bytes32 metaGlobalKey;                          // CDM global key
    }

    /// @notice Swap leg result
    /// @dev Result of calculating one leg of the swap
    struct SwapLegResult {
        InterestRatePayout.PayoutCalculationResult payoutResult;  // Full payout calculation
        bytes32 legReference;                                     // Leg identifier
        bool isPayer;                                             // True if this party pays this leg
    }

    /// @notice Net cashflow for a period
    /// @dev Represents the net payment between parties for one period
    struct NetCashflow {
        uint256 periodStart;                            // Period start date
        uint256 periodEnd;                              // Period end date
        uint256 paymentDate;                            // Net payment date
        uint256 fixedAmount;                            // Fixed leg amount
        uint256 floatingAmount;                         // Floating leg amount
        int256 netAmount;                               // Net amount (positive = Party A pays Party B)
        bytes32 payerReference;                         // Party making net payment
        bytes32 receiverReference;                      // Party receiving net payment
    }

    /// @notice Complete swap valuation result
    /// @dev All calculation results for the swap
    struct SwapValuationResult {
        SwapLegResult fixedLegResult;                   // Fixed leg calculation
        SwapLegResult floatingLegResult;                // Floating leg calculation
        NetCashflow[] netCashflows;                     // Net cashflows per period
        uint256 fixedLegNPV;                            // Fixed leg NPV
        uint256 floatingLegNPV;                         // Floating leg NPV
        int256 swapNPV;                                 // Swap NPV (positive = asset, negative = liability)
        uint256 totalFixedInterest;                     // Total fixed interest
        uint256 totalFloatingInterest;                  // Total floating interest
    }

    // =============================================================================
    // ERRORS
    // =============================================================================

    error InterestRateSwap__InvalidNotional();
    error InterestRateSwap__InvalidDates();
    error InterestRateSwap__CurrencyMismatch();
    error InterestRateSwap__DateMismatch();
    error InterestRateSwap__InvalidLegConfiguration();
    error InterestRateSwap__MissingFloatingRateObservations();
    error InterestRateSwap__DiscountFactorMismatch();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize InterestRateSwap contract
     * @param _payoutContract Address of InterestRatePayout contract
     */
    constructor(address _payoutContract) {
        require(_payoutContract != address(0), "Invalid payout contract");
        payoutContract = InterestRatePayout(_payoutContract);
    }

    // =============================================================================
    // SWAP VALIDATION
    // =============================================================================

    /**
     * @notice Validate interest rate swap specification
     * @dev Checks that both legs are properly configured and compatible
     * @param spec Swap specification
     * @return valid True if swap is valid
     */
    function validateSwapSpec(
        InterestRateSwapSpec memory spec
    ) public pure returns (bool valid) {
        // Check notional
        if (spec.notional == 0) return false;
        if (spec.fixedLeg.notional != spec.notional) return false;
        if (spec.floatingLeg.notional != spec.notional) return false;

        // Check dates
        if (spec.terminationDate <= spec.effectiveDate) return false;
        if (spec.fixedLeg.effectiveDate != spec.effectiveDate) return false;
        if (spec.fixedLeg.terminationDate != spec.terminationDate) return false;
        if (spec.floatingLeg.effectiveDate != spec.effectiveDate) return false;
        if (spec.floatingLeg.terminationDate != spec.terminationDate) return false;

        // Check currency
        if (spec.fixedLeg.currency != spec.currency) return false;
        if (spec.floatingLeg.currency != spec.currency) return false;

        // Check leg types
        if (spec.fixedLeg.payoutType != InterestRatePayout.PayoutTypeEnum.FIXED) return false;
        if (spec.floatingLeg.payoutType != InterestRatePayout.PayoutTypeEnum.FLOATING) return false;

        // Check directions are opposite
        if (spec.fixedLeg.direction == spec.floatingLeg.direction) return false;

        // All checks passed
        return true;
    }

    // =============================================================================
    // SWAP CALCULATION
    // =============================================================================

    /**
     * @notice Calculate complete swap valuation (both legs)
     * @dev Calculates fixed leg, floating leg, and net cashflows
     * @param spec Swap specification
     * @param floatingRateObservations Array of rate observations for floating leg
     * @return result Complete swap valuation result
     *
     * @custom:example
     * Fixed leg: $10M @ 3.5% quarterly
     * Floating leg: $10M @ SOFR + 0bps quarterly
     * If SOFR averages 3.0%, Party A (fixed payer) pays net $12,500 per quarter
     */
    function calculateSwap(
        InterestRateSwapSpec memory spec,
        uint256[][] memory floatingRateObservations
    ) public view returns (SwapValuationResult memory result) {
        // Validate swap
        if (!validateSwapSpec(spec)) revert InterestRateSwap__InvalidLegConfiguration();

        // Calculate fixed leg
        InterestRatePayout.PayoutCalculationResult memory fixedResult =
            payoutContract.calculateFixedPayout(spec.fixedLeg);

        // Calculate floating leg
        InterestRatePayout.PayoutCalculationResult memory floatingResult =
            payoutContract.calculateFloatingPayout(spec.floatingLeg, floatingRateObservations);

        // Package leg results
        result.fixedLegResult = SwapLegResult({
            payoutResult: fixedResult,
            legReference: keccak256(abi.encodePacked(spec.swapId, "FIXED")),
            isPayer: spec.fixedLeg.direction == Cashflow.PaymentDirectionEnum.PAY
        });

        result.floatingLegResult = SwapLegResult({
            payoutResult: floatingResult,
            legReference: keccak256(abi.encodePacked(spec.swapId, "FLOATING")),
            isPayer: spec.floatingLeg.direction == Cashflow.PaymentDirectionEnum.PAY
        });

        // Calculate net cashflows
        result.netCashflows = _calculateNetCashflows(
            spec,
            fixedResult,
            floatingResult
        );

        // Store totals
        result.totalFixedInterest = fixedResult.totalInterest;
        result.totalFloatingInterest = floatingResult.totalInterest;

        return result;
    }

    /**
     * @notice Calculate swap valuation with NPV (discount factors provided)
     * @dev Extends calculateSwap with present value calculations
     * @param spec Swap specification
     * @param floatingRateObservations Array of rate observations for floating leg
     * @param discountFactors Discount factors for each period
     * @return result Complete swap valuation with NPV
     */
    function calculateSwapWithNPV(
        InterestRateSwapSpec memory spec,
        uint256[][] memory floatingRateObservations,
        uint256[] memory discountFactors
    ) public view returns (SwapValuationResult memory result) {
        // Calculate base swap
        result = calculateSwap(spec, floatingRateObservations);

        // Validate discount factors length
        if (discountFactors.length != result.fixedLegResult.payoutResult.periods.length) {
            revert InterestRateSwap__DiscountFactorMismatch();
        }

        // Calculate NPV for each leg
        result.fixedLegNPV = payoutContract.calculateNPV(
            result.fixedLegResult.payoutResult,
            discountFactors
        );

        result.floatingLegNPV = payoutContract.calculateNPV(
            result.floatingLegResult.payoutResult,
            discountFactors
        );

        // Calculate net swap NPV
        // If Party A pays fixed and receives floating:
        // Swap NPV (from Party A perspective) = Floating NPV - Fixed NPV
        // Positive NPV = asset (in-the-money), Negative NPV = liability (out-of-the-money)
        if (spec.fixedLeg.direction == Cashflow.PaymentDirectionEnum.PAY) {
            // Fixed payer perspective: receive floating - pay fixed
            result.swapNPV = int256(result.floatingLegNPV) - int256(result.fixedLegNPV);
        } else {
            // Fixed receiver perspective: receive fixed - pay floating
            result.swapNPV = int256(result.fixedLegNPV) - int256(result.floatingLegNPV);
        }

        return result;
    }

    /**
     * @notice Get net settlement amount for a specific period
     * @dev Calculates the net payment between parties for a single period
     * @param spec Swap specification
     * @param fixedAmount Fixed leg interest amount for the period
     * @param floatingAmount Floating leg interest amount for the period
     * @return netAmount Net amount (positive = Party A pays Party B)
     * @return payer Party making the net payment
     * @return receiver Party receiving the net payment
     */
    function getNetSettlement(
        InterestRateSwapSpec memory spec,
        uint256 fixedAmount,
        uint256 floatingAmount
    ) public pure returns (
        int256 netAmount,
        bytes32 payer,
        bytes32 receiver
    ) {
        // Calculate net based on fixed leg direction
        if (spec.fixedLeg.direction == Cashflow.PaymentDirectionEnum.PAY) {
            // Party A pays fixed, receives floating
            // Net from Party A perspective: floating received - fixed paid
            netAmount = int256(floatingAmount) - int256(fixedAmount);

            if (netAmount < 0) {
                // Party A pays net amount
                payer = spec.partyAReference;
                receiver = spec.partyBReference;
                netAmount = -netAmount; // Make positive for payment amount
            } else {
                // Party B pays net amount (Party A receives)
                payer = spec.partyBReference;
                receiver = spec.partyAReference;
            }
        } else {
            // Party A receives fixed, pays floating
            // Net from Party A perspective: fixed received - floating paid
            netAmount = int256(fixedAmount) - int256(floatingAmount);

            if (netAmount < 0) {
                // Party A pays net amount
                payer = spec.partyAReference;
                receiver = spec.partyBReference;
                netAmount = -netAmount; // Make positive for payment amount
            } else {
                // Party B pays net amount (Party A receives)
                payer = spec.partyBReference;
                receiver = spec.partyAReference;
            }
        }

        return (netAmount, payer, receiver);
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate net cashflows for all periods
     * @dev Internal function to compute net payments between parties
     * @param spec Swap specification
     * @param fixedResult Fixed leg calculation result
     * @param floatingResult Floating leg calculation result
     * @return netCashflows Array of net cashflows per period
     */
    function _calculateNetCashflows(
        InterestRateSwapSpec memory spec,
        InterestRatePayout.PayoutCalculationResult memory fixedResult,
        InterestRatePayout.PayoutCalculationResult memory floatingResult
    ) internal pure returns (NetCashflow[] memory netCashflows) {
        uint256 numPeriods = fixedResult.periods.length;

        // Ensure both legs have same number of periods
        require(
            numPeriods == floatingResult.periods.length,
            "Period count mismatch"
        );

        netCashflows = new NetCashflow[](numPeriods);

        for (uint256 i = 0; i < numPeriods; i++) {
            InterestRatePayout.CalculatedPeriod memory fixedPeriod = fixedResult.periods[i];
            InterestRatePayout.CalculatedPeriod memory floatingPeriod = floatingResult.periods[i];

            // Calculate net settlement
            (int256 netAmount, bytes32 payer, bytes32 receiver) = getNetSettlement(
                spec,
                fixedPeriod.interestAmount,
                floatingPeriod.interestAmount
            );

            // Create net cashflow
            netCashflows[i] = NetCashflow({
                periodStart: fixedPeriod.startDate,
                periodEnd: fixedPeriod.endDate,
                paymentDate: fixedPeriod.paymentDate,  // Assume same payment date
                fixedAmount: fixedPeriod.interestAmount,
                floatingAmount: floatingPeriod.interestAmount,
                netAmount: netAmount,
                payerReference: payer,
                receiverReference: receiver
            });
        }

        return netCashflows;
    }

    /**
     * @notice Get total accrued interest across both legs
     * @dev Calculates current accrued interest for the swap
     * @param spec Swap specification
     * @return fixedAccrued Accrued interest on fixed leg
     * @return floatingAccrued Accrued interest on floating leg (if observable)
     * @return netAccrued Net accrued amount
     */
    function getAccruedInterest(
        InterestRateSwapSpec memory spec
    ) public view returns (
        uint256 fixedAccrued,
        uint256 floatingAccrued,
        int256 netAccrued
    ) {
        // Calculate fixed leg
        InterestRatePayout.PayoutCalculationResult memory fixedResult =
            payoutContract.calculateFixedPayout(spec.fixedLeg);

        fixedAccrued = fixedResult.accruedInterest;

        // For floating leg, accrued is not computable without observations
        // In practice, this would use last fixing or estimated rate
        floatingAccrued = 0;

        // Calculate net accrued
        if (spec.fixedLeg.direction == Cashflow.PaymentDirectionEnum.PAY) {
            netAccrued = int256(floatingAccrued) - int256(fixedAccrued);
        } else {
            netAccrued = int256(fixedAccrued) - int256(floatingAccrued);
        }

        return (fixedAccrued, floatingAccrued, netAccrued);
    }

    /**
     * @notice Get number of remaining periods in swap
     * @dev Estimates number of remaining payment periods
     * @param spec Swap specification
     * @return remainingPeriods Number of periods remaining
     */
    function getRemainingPeriods(
        InterestRateSwapSpec memory spec
    ) public view returns (uint256 remainingPeriods) {
        // This is a simplified implementation
        // Real implementation would check against current block timestamp
        uint256 estimatedPeriods = payoutContract.getNumberOfPeriods(spec.fixedLeg);
        return estimatedPeriods;
    }

    /**
     * @notice Create a standard fixed-for-floating IRS specification
     * @dev Helper function to create a typical IRS spec
     * @param swapId Unique swap identifier
     * @param partyA Party A reference
     * @param partyB Party B reference
     * @param notional Notional amount
     * @param fixedRate Fixed rate (fixed-point)
     * @param floatingRateIndex Floating rate index identifier
     * @param spread Floating rate spread
     * @param effectiveDate Swap effective date
     * @param terminationDate Swap termination date
     * @param paymentFrequency Payment frequency period
     * @return spec Complete swap specification
     */
    function createStandardIRS(
        bytes32 swapId,
        bytes32 partyA,
        bytes32 partyB,
        uint256 notional,
        uint256 fixedRate,
        bytes32 floatingRateIndex,
        uint256 spread,
        uint256 effectiveDate,
        uint256 terminationDate,
        Period memory paymentFrequency
    ) public pure returns (InterestRateSwapSpec memory spec) {
        // Create fixed leg (Party A pays fixed)
        InterestRatePayout.InterestRatePayoutSpec memory fixedLeg = InterestRatePayout.InterestRatePayoutSpec({
            notional: notional,
            payoutType: InterestRatePayout.PayoutTypeEnum.FIXED,
            direction: Cashflow.PaymentDirectionEnum.PAY,
            currency: bytes32("USD"),
            fixedRate: fixedRate,
            floatingRateIndex: bytes32(0),
            spread: 0,
            multiplier: ONE,
            effectiveDate: effectiveDate,
            terminationDate: terminationDate,
            paymentFrequency: paymentFrequency,
            calculationPeriodFrequency: paymentFrequency,
            dayCountFraction: DayCountFractionEnum.ACT_360,
            businessDayAdjustments: BusinessDayAdjustments({
                convention: BusinessDayConventionEnum.MODIFIED_FOLLOWING,
                businessCenters: new BusinessCenterEnum[](0)
            }),
            rollConvention: Schedule.RollConventionEnum.END_OF_MONTH,
            stubPeriod: Schedule.StubTypeEnum.NONE,
            observationShift: 0,
            observationMethod: ObservationSchedule.ObservationMethodEnum.SINGLE,
            observationShiftType: ObservationSchedule.ObservationShiftEnum.NONE
        });

        // Create floating leg (Party A receives floating)
        InterestRatePayout.InterestRatePayoutSpec memory floatingLeg = InterestRatePayout.InterestRatePayoutSpec({
            notional: notional,
            payoutType: InterestRatePayout.PayoutTypeEnum.FLOATING,
            direction: Cashflow.PaymentDirectionEnum.RECEIVE,
            currency: bytes32("USD"),
            fixedRate: 0,
            floatingRateIndex: floatingRateIndex,
            spread: spread,
            multiplier: ONE,
            effectiveDate: effectiveDate,
            terminationDate: terminationDate,
            paymentFrequency: paymentFrequency,
            calculationPeriodFrequency: paymentFrequency,
            dayCountFraction: DayCountFractionEnum.ACT_360,
            businessDayAdjustments: BusinessDayAdjustments({
                convention: BusinessDayConventionEnum.MODIFIED_FOLLOWING,
                businessCenters: new BusinessCenterEnum[](0)
            }),
            rollConvention: Schedule.RollConventionEnum.END_OF_MONTH,
            stubPeriod: Schedule.StubTypeEnum.NONE,
            observationShift: 2,
            observationMethod: ObservationSchedule.ObservationMethodEnum.DAILY,
            observationShiftType: ObservationSchedule.ObservationShiftEnum.LOOKBACK
        });

        // Create swap spec
        spec = InterestRateSwapSpec({
            swapId: swapId,
            tradeId: swapId,
            tradeDate: effectiveDate,
            partyAReference: partyA,
            partyBReference: partyB,
            fixedLeg: fixedLeg,
            floatingLeg: floatingLeg,
            notional: notional,
            currency: bytes32("USD"),
            effectiveDate: effectiveDate,
            terminationDate: terminationDate,
            metaGlobalKey: keccak256(abi.encode(swapId))
        });

        return spec;
    }
}
