// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FixedPoint} from "../base/libraries/FixedPoint.sol";
import {Cashflow} from "../base/libraries/Cashflow.sol";
import {
    BusinessDayConventionEnum,
    BusinessCenterEnum
} from "../base/types/Enums.sol";
import {BusinessDayAdjustments} from "../base/types/CDMTypes.sol";

/**
 * @title NonDeliverableForward
 * @notice Non-Deliverable Forward (NDF) FX derivative implementation
 * @dev Represents a cash-settled FX forward for emerging market currencies
 * @dev No physical delivery of the non-deliverable currency
 *
 * KEY FEATURES:
 * - Single cashflow settlement at maturity
 * - Cash settlement in reference currency (typically USD)
 * - Settlement based on fixing rate vs forward rate
 * - Mark-to-market valuation
 *
 * TYPICAL NDF STRUCTURE:
 * Currency Pair: USD/CNY (USD is settlement currency)
 * Notional: $10M USD
 * Forward Rate: 7.1500 CNY/USD
 * Tenor: 3 months
 * Fixing Source: PBOC daily fixing
 *
 * SETTLEMENT EXAMPLE:
 * If spot fixing = 7.2000 CNY/USD (CNY weakened)
 * Settlement = $10M × (7.2000 - 7.1500) / 7.2000 = $69,444 USD
 * Buyer of USD (seller of CNY) receives payment
 *
 * @author QualitaX Team
 */
contract NonDeliverableForward {
    using FixedPoint for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Fixed-point one (1.0)
    uint256 private constant ONE = 1e18;

    /// @notice Basis points divisor (10,000)
    uint256 private constant BPS = 10000;

    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice NDF status
    enum NDFStatusEnum {
        CREATED,        // NDF created, not yet active
        ACTIVE,         // NDF is active, before fixing
        FIXED,          // Spot rate has been fixed
        SETTLED,        // Settlement payment made
        CANCELLED       // NDF cancelled before maturity
    }

    /// @notice Settlement direction (from buyer's perspective)
    enum SettlementDirectionEnum {
        RECEIVE,        // Buyer receives settlement
        PAY,            // Buyer pays settlement
        ZERO            // No settlement (spot = forward)
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Non-Deliverable Forward specification
    /// @dev Complete specification for an NDF contract
    struct NDFSpec {
        // Trade identification
        bytes32 ndfId;                              // Unique NDF identifier
        bytes32 tradeId;                            // Trade identifier
        uint256 tradeDate;                          // Date of trade execution

        // Party information
        bytes32 buyerReference;                     // Buyer party reference (long non-deliverable currency)
        bytes32 sellerReference;                    // Seller party reference (short non-deliverable currency)

        // Currency and notional
        bytes32 settlementCurrency;                 // Settlement currency (e.g., "USD")
        bytes32 nonDeliverableCurrency;             // Non-deliverable currency (e.g., "CNY")
        uint256 notionalAmount;                     // Notional in settlement currency (fixed-point)

        // Rates and dates
        uint256 forwardRate;                        // Agreed forward rate (fixed-point, e.g., 7.15 CNY/USD)
        uint256 fixingDate;                         // Date to observe spot rate (Unix timestamp)
        uint256 settlementDate;                     // Date for cash settlement (Unix timestamp)

        // Fixing source
        bytes32 fixingSource;                       // Rate fixing source (e.g., "PBOC", "CENTRAL_BANK")
        BusinessDayAdjustments settlementAdjustments; // Business day adjustments for settlement

        // Metadata
        bytes32 metaGlobalKey;                      // CDM global key
    }

    /// @notice NDF settlement calculation result
    /// @dev Result of settlement calculation at maturity
    struct NDFSettlementResult {
        uint256 spotFixing;                         // Observed spot rate at fixing
        uint256 forwardRate;                        // Agreed forward rate
        uint256 rateDifference;                     // Absolute difference |spot - forward|
        uint256 settlementAmount;                   // Settlement amount in settlement currency
        SettlementDirectionEnum direction;          // Settlement direction
        bytes32 payerReference;                     // Party making settlement payment
        bytes32 receiverReference;                  // Party receiving settlement payment
        uint256 settlementDate;                     // Settlement payment date
    }

    /// @notice NDF valuation result (mark-to-market)
    /// @dev Mark-to-market valuation before maturity
    struct NDFValuationResult {
        uint256 currentForwardRate;                 // Current market forward rate
        uint256 contractForwardRate;                // Original contract forward rate
        int256 mtmValue;                            // Mark-to-market value (signed)
        uint256 daysToMaturity;                     // Days until maturity
        uint256 valuationDate;                      // Valuation date
    }

    // =============================================================================
    // ERRORS
    // =============================================================================

    error NonDeliverableForward__InvalidNotional();
    error NonDeliverableForward__InvalidRate();
    error NonDeliverableForward__InvalidDates();
    error NonDeliverableForward__InvalidCurrencies();
    error NonDeliverableForward__FixingNotAvailable();
    error NonDeliverableForward__AlreadySettled();
    error NonDeliverableForward__NotYetMatured();

    // =============================================================================
    // VALIDATION
    // =============================================================================

    /**
     * @notice Validate NDF specification
     * @dev Checks that NDF is properly configured
     * @param spec NDF specification
     * @return valid True if NDF is valid
     */
    function validateNDFSpec(
        NDFSpec memory spec
    ) public pure returns (bool valid) {
        // Check notional
        if (spec.notionalAmount == 0) return false;

        // Check forward rate
        if (spec.forwardRate == 0) return false;

        // Check dates
        if (spec.settlementDate <= spec.fixingDate) return false;
        if (spec.fixingDate <= spec.tradeDate) return false;

        // Check currencies are different
        if (spec.settlementCurrency == spec.nonDeliverableCurrency) return false;

        // All checks passed
        return true;
    }

    // =============================================================================
    // SETTLEMENT CALCULATION
    // =============================================================================

    /**
     * @notice Calculate NDF settlement at maturity
     * @dev Calculates cash settlement based on spot fixing vs forward rate
     * @param spec NDF specification
     * @param spotFixing Observed spot rate at fixing date (fixed-point)
     * @return result Settlement calculation result
     *
     * @custom:formula Settlement = Notional × (Spot - Forward) / Spot
     * @custom:example
     * Notional: $10M USD
     * Forward: 7.1500 CNY/USD
     * Spot: 7.2000 CNY/USD
     * Settlement = $10M × (7.2000 - 7.1500) / 7.2000 = $69,444 USD
     */
    function calculateSettlement(
        NDFSpec memory spec,
        uint256 spotFixing
    ) public pure returns (NDFSettlementResult memory result) {
        // Validate inputs
        if (!validateNDFSpec(spec)) revert NonDeliverableForward__InvalidDates();
        if (spotFixing == 0) revert NonDeliverableForward__InvalidRate();

        result.spotFixing = spotFixing;
        result.forwardRate = spec.forwardRate;
        result.settlementDate = spec.settlementDate;

        // Calculate rate difference and settlement amount
        // Settlement = Notional × |Spot - Forward| / Spot

        if (spotFixing > spec.forwardRate) {
            // Spot > Forward: Non-deliverable currency weakened
            // Buyer (long non-deliverable currency) receives payment
            result.rateDifference = spotFixing - spec.forwardRate;
            result.direction = SettlementDirectionEnum.RECEIVE;
            result.payerReference = spec.sellerReference;
            result.receiverReference = spec.buyerReference;
        } else if (spotFixing < spec.forwardRate) {
            // Spot < Forward: Non-deliverable currency strengthened
            // Buyer (long non-deliverable currency) pays
            result.rateDifference = spec.forwardRate - spotFixing;
            result.direction = SettlementDirectionEnum.PAY;
            result.payerReference = spec.buyerReference;
            result.receiverReference = spec.sellerReference;
        } else {
            // Spot == Forward: No settlement
            result.rateDifference = 0;
            result.direction = SettlementDirectionEnum.ZERO;
            result.settlementAmount = 0;
            return result;
        }

        // Calculate settlement amount
        // Amount = Notional × RateDifference / SpotFixing
        uint256 rateRatio = result.rateDifference.mul(ONE).div(spotFixing);
        result.settlementAmount = spec.notionalAmount.mul(rateRatio).div(ONE);

        return result;
    }

    /**
     * @notice Calculate NDF mark-to-market value
     * @dev Calculates MTM based on current forward rate vs contract rate
     * @param spec NDF specification
     * @param currentForwardRate Current market forward rate for same maturity
     * @param valuationDate Current valuation date
     * @return result MTM valuation result
     *
     * @custom:formula MTM = Notional × (CurrentFwd - ContractFwd) / CurrentFwd
     */
    function calculateMTM(
        NDFSpec memory spec,
        uint256 currentForwardRate,
        uint256 valuationDate
    ) public pure returns (NDFValuationResult memory result) {
        // Validate inputs
        if (!validateNDFSpec(spec)) revert NonDeliverableForward__InvalidDates();
        if (currentForwardRate == 0) revert NonDeliverableForward__InvalidRate();
        if (valuationDate >= spec.fixingDate) revert NonDeliverableForward__FixingNotAvailable();

        result.currentForwardRate = currentForwardRate;
        result.contractForwardRate = spec.forwardRate;
        result.valuationDate = valuationDate;

        // Calculate days to maturity
        result.daysToMaturity = (spec.fixingDate - valuationDate) / 1 days;

        // Calculate MTM value
        // MTM = Notional × (CurrentFwd - ContractFwd) / CurrentFwd
        if (currentForwardRate > spec.forwardRate) {
            // Current forward higher than contract: positive MTM for buyer
            uint256 rateDiff = currentForwardRate - spec.forwardRate;
            uint256 rateRatio = rateDiff.mul(ONE).div(currentForwardRate);
            uint256 mtm = spec.notionalAmount.mul(rateRatio).div(ONE);
            result.mtmValue = int256(mtm);
        } else if (currentForwardRate < spec.forwardRate) {
            // Current forward lower than contract: negative MTM for buyer
            uint256 rateDiff = spec.forwardRate - currentForwardRate;
            uint256 rateRatio = rateDiff.mul(ONE).div(currentForwardRate);
            uint256 mtm = spec.notionalAmount.mul(rateRatio).div(ONE);
            result.mtmValue = -int256(mtm);
        } else {
            // Equal: zero MTM
            result.mtmValue = 0;
        }

        return result;
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Calculate forward points
     * @dev Forward points = Forward rate - Spot rate (in basis points)
     * @param spotRate Current spot rate
     * @param forwardRate Forward rate
     * @return forwardPoints Forward points in basis points
     */
    function calculateForwardPoints(
        uint256 spotRate,
        uint256 forwardRate
    ) public pure returns (int256 forwardPoints) {
        if (spotRate == 0) revert NonDeliverableForward__InvalidRate();

        // Calculate percentage difference and convert to basis points
        if (forwardRate > spotRate) {
            uint256 diff = forwardRate - spotRate;
            uint256 pctDiff = diff.mul(ONE).div(spotRate);
            // Convert to basis points (multiply by 10000)
            forwardPoints = int256(pctDiff.mul(BPS).div(ONE));
        } else if (forwardRate < spotRate) {
            uint256 diff = spotRate - forwardRate;
            uint256 pctDiff = diff.mul(ONE).div(spotRate);
            forwardPoints = -int256(pctDiff.mul(BPS).div(ONE));
        } else {
            forwardPoints = 0;
        }

        return forwardPoints;
    }

    /**
     * @notice Get settlement amount in notional currency equivalent
     * @dev Converts settlement amount to non-deliverable currency for reference
     * @param settlementAmount Settlement amount in settlement currency
     * @param spotRate Spot exchange rate
     * @return notionalEquivalent Equivalent in non-deliverable currency
     */
    function getNotionalCurrencyEquivalent(
        uint256 settlementAmount,
        uint256 spotRate
    ) public pure returns (uint256 notionalEquivalent) {
        if (spotRate == 0) revert NonDeliverableForward__InvalidRate();

        // Multiply by spot rate to get non-deliverable currency amount
        notionalEquivalent = settlementAmount.mul(spotRate).div(ONE);

        return notionalEquivalent;
    }

    /**
     * @notice Check if NDF is in-the-money for buyer
     * @dev Compares current forward rate to contract rate
     * @param spec NDF specification
     * @param currentForwardRate Current market forward rate
     * @return inTheMoney True if NDF is in-the-money for buyer
     * @return mtmAmount Absolute MTM amount
     */
    function isInTheMoney(
        NDFSpec memory spec,
        uint256 currentForwardRate
    ) public pure returns (bool inTheMoney, uint256 mtmAmount) {
        if (currentForwardRate == 0) revert NonDeliverableForward__InvalidRate();

        if (currentForwardRate > spec.forwardRate) {
            // In-the-money for buyer
            inTheMoney = true;
            uint256 rateDiff = currentForwardRate - spec.forwardRate;
            uint256 rateRatio = rateDiff.mul(ONE).div(currentForwardRate);
            mtmAmount = spec.notionalAmount.mul(rateRatio).div(ONE);
        } else {
            inTheMoney = false;
            if (currentForwardRate < spec.forwardRate) {
                uint256 rateDiff = spec.forwardRate - currentForwardRate;
                uint256 rateRatio = rateDiff.mul(ONE).div(currentForwardRate);
                mtmAmount = spec.notionalAmount.mul(rateRatio).div(ONE);
            } else {
                mtmAmount = 0;
            }
        }

        return (inTheMoney, mtmAmount);
    }

    /**
     * @notice Create a standard NDF specification
     * @dev Helper function to create a typical NDF spec
     * @param ndfId Unique NDF identifier
     * @param buyer Buyer party reference
     * @param seller Seller party reference
     * @param settlementCurrency Settlement currency (e.g., "USD")
     * @param nonDeliverableCurrency Non-deliverable currency (e.g., "CNY")
     * @param notional Notional amount
     * @param forwardRate Forward rate
     * @param tradeDate Trade date
     * @param fixingDate Fixing date
     * @param settlementDate Settlement date
     * @return spec Complete NDF specification
     */
    function createStandardNDF(
        bytes32 ndfId,
        bytes32 buyer,
        bytes32 seller,
        bytes32 settlementCurrency,
        bytes32 nonDeliverableCurrency,
        uint256 notional,
        uint256 forwardRate,
        uint256 tradeDate,
        uint256 fixingDate,
        uint256 settlementDate
    ) public pure returns (NDFSpec memory spec) {
        spec = NDFSpec({
            ndfId: ndfId,
            tradeId: ndfId,
            tradeDate: tradeDate,
            buyerReference: buyer,
            sellerReference: seller,
            settlementCurrency: settlementCurrency,
            nonDeliverableCurrency: nonDeliverableCurrency,
            notionalAmount: notional,
            forwardRate: forwardRate,
            fixingDate: fixingDate,
            settlementDate: settlementDate,
            fixingSource: bytes32("CENTRAL_BANK"),
            settlementAdjustments: BusinessDayAdjustments({
                convention: BusinessDayConventionEnum.FOLLOWING,
                businessCenters: new BusinessCenterEnum[](0)
            }),
            metaGlobalKey: keccak256(abi.encode(ndfId))
        });

        return spec;
    }

    /**
     * @notice Get implied spot rate from MTM
     * @dev Reverse calculates spot rate given MTM value
     * @param spec NDF specification
     * @param mtmValue MTM value (signed)
     * @return impliedSpot Implied current forward rate
     */
    function getImpliedForwardRate(
        NDFSpec memory spec,
        int256 mtmValue
    ) public pure returns (uint256 impliedSpot) {
        if (mtmValue == 0) {
            return spec.forwardRate;
        }

        // This is a simplified reverse calculation
        // In practice, would need iterative solver for exact solution
        uint256 absMtm = mtmValue > 0 ? uint256(mtmValue) : uint256(-mtmValue);

        // Approximate: ImpliedRate ≈ ContractRate × (1 + MTM/Notional)
        uint256 mtmRatio = absMtm.mul(ONE).div(spec.notionalAmount);

        if (mtmValue > 0) {
            // Positive MTM: implied rate is higher
            impliedSpot = spec.forwardRate.mul(ONE + mtmRatio).div(ONE);
        } else {
            // Negative MTM: implied rate is lower
            impliedSpot = spec.forwardRate.mul(ONE - mtmRatio).div(ONE);
        }

        return impliedSpot;
    }
}
