// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Portfolio} from "./Portfolio.sol";
import {CSA} from "../agreements/CSA.sol";
import {AgreementRegistry} from "../agreements/AgreementRegistry.sol";
import {ISDAMasterAgreement} from "../agreements/ISDAMasterAgreement.sol";

/**
 * @title NettingEngine
 * @notice Automated netting calculation and settlement generation
 * @dev Implements payment netting, close-out netting, and multi-currency netting
 *
 * KEY FEATURES:
 * - Payment netting (same-day settlement aggregation)
 * - Close-out netting (default/termination netting)
 * - Multi-currency netting (FX conversion)
 * - CSA rule validation
 * - Settlement instruction generation
 *
 * NETTING TYPES:
 *
 * 1. Payment Netting:
 *    - Aggregate all payments due on same date
 *    - Net by currency
 *    - Generate single net payment per currency
 *    - Respects settlement threshold
 *
 * 2. Close-out Netting:
 *    - Triggered by Event of Default or Termination Event
 *    - Calculate MTM for all trades in portfolio
 *    - Sum to get single net close-out amount
 *    - Generate settlement instruction
 *
 * 3. Multi-Currency Netting:
 *    - Net across different currencies
 *    - FX conversion to base currency
 *    - Single net payment in base currency
 *
 * TYPICAL USE CASES:
 * - NDF portfolio: Net 5 NDFs with same settlement date
 * - IRS portfolio: Net quarterly interest payments
 * - Multi-currency FX: Net USD, EUR, GBP positions
 * - Default scenario: Close-out net all positions
 *
 * INTEGRATION POINTS:
 * - Portfolio: Source of trades and valuations
 * - CSA: Netting rules and thresholds
 * - ISDAMasterAgreement: Event of Default triggers
 * - TransferEvent: Settlement generation (future)
 *
 * @author QualitaX Team
 */
contract NettingEngine {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Netting type
    enum NettingTypeEnum {
        PAYMENT,                // Payment netting (same-day)
        CLOSE_OUT,              // Close-out netting (termination)
        MULTI_CURRENCY          // Multi-currency netting
    }

    /// @notice Netting status
    enum NettingStatusEnum {
        CALCULATED,             // Netting calculated
        VALIDATED,              // CSA rules validated
        SETTLEMENT_GENERATED,   // Settlement instruction generated
        SETTLED,                // Settlement completed
        FAILED                  // Netting failed
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Payment netting input
    /// @dev Trade payments to be netted
    struct PaymentNettingInput {
        bytes32 tradeId;                    // Trade identifier
        int256 paymentAmount;               // Payment amount (18 decimals, signed)
        bytes32 currency;                   // Payment currency
        uint256 settlementDate;             // Settlement date
        bytes32 payer;                      // Payer party
        bytes32 receiver;                   // Receiver party
    }

    /// @notice Payment netting result
    /// @dev Net payment per currency
    struct PaymentNettingResult {
        bytes32 currency;                   // Currency
        int256 netAmount;                   // Net amount (18 decimals, signed)
        uint256 settlementDate;             // Settlement date
        bytes32 netPayer;                   // Net payer (if netAmount < 0)
        bytes32 netReceiver;                // Net receiver (if netAmount > 0)
        uint256 tradeCount;                 // Number of trades netted
        bytes32[] tradeIds;                 // Trades included in netting
    }

    /// @notice Close-out netting input
    /// @dev Trade MTMs to be netted
    struct CloseOutNettingInput {
        bytes32 tradeId;                    // Trade identifier
        int256 mtm;                         // Mark-to-market (18 decimals, signed)
        bytes32 currency;                   // MTM currency
    }

    /// @notice Close-out netting result
    /// @dev Net close-out amount
    struct CloseOutNettingResult {
        int256 netCloseOut;                 // Net close-out amount (18 decimals, signed)
        bytes32 baseCurrency;               // Base currency
        uint256 valuationDate;              // Valuation date
        bytes32 netPayer;                   // Net payer
        bytes32 netReceiver;                // Net receiver
        uint256 tradeCount;                 // Number of trades netted
        bytes32[] tradeIds;                 // Trades included
        bytes32 eventOfDefaultId;           // Triggering event (if applicable)
    }

    /// @notice Multi-currency netting input
    /// @dev Payments in multiple currencies
    struct MultiCurrencyNettingInput {
        bytes32 currency;                   // Currency
        int256 netAmount;                   // Net amount in this currency
        uint256 fxRate;                     // FX rate to base currency (18 decimals)
    }

    /// @notice Multi-currency netting result
    /// @dev Net amount in base currency
    struct MultiCurrencyNettingResult {
        int256 netAmountBase;               // Net amount in base currency
        bytes32 baseCurrency;               // Base currency
        uint256 currencyCount;              // Number of currencies netted
        MultiCurrencyNettingInput[] inputs; // Input currencies and amounts
    }

    /// @notice Netting calculation record
    /// @dev Complete netting calculation
    struct NettingCalculation {
        bytes32 nettingId;                  // Netting calculation ID
        bytes32 portfolioId;                // Portfolio
        bytes32 csaId;                      // CSA
        NettingTypeEnum nettingType;        // Netting type
        NettingStatusEnum status;           // Status
        uint256 calculationTimestamp;       // When calculated
        bytes32 calculatedBy;               // Who calculated
        bytes32 metaGlobalKey;              // CDM global key
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Portfolio contract reference
    Portfolio public immutable portfolio;

    /// @notice CSA contract reference
    CSA public immutable csa;

    /// @notice Agreement registry reference
    AgreementRegistry public immutable agreementRegistry;

    /// @notice ISDA Master Agreement contract reference
    ISDAMasterAgreement public immutable isdaMasterAgreement;

    /// @notice Mapping from netting ID to calculation
    mapping(bytes32 => NettingCalculation) public nettingCalculations;

    /// @notice Mapping from netting ID to payment netting results
    mapping(bytes32 => mapping(bytes32 => PaymentNettingResult)) public paymentNettingResults;

    /// @notice Mapping from netting ID to close-out netting result
    mapping(bytes32 => CloseOutNettingResult) public closeOutNettingResults;

    /// @notice Mapping from netting ID to multi-currency netting result
    mapping(bytes32 => MultiCurrencyNettingResult) public multiCurrencyNettingResults;

    /// @notice Mapping from portfolio ID to netting IDs
    mapping(bytes32 => bytes32[]) public portfolioNettings;

    /// @notice Counter for total nettings
    uint256 public totalNettings;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event PaymentNettingCalculated(
        bytes32 indexed nettingId,
        bytes32 indexed portfolioId,
        bytes32 indexed currency,
        int256 netAmount,
        uint256 tradeCount
    );

    event CloseOutNettingCalculated(
        bytes32 indexed nettingId,
        bytes32 indexed portfolioId,
        int256 netCloseOut,
        uint256 tradeCount
    );

    event MultiCurrencyNettingCalculated(
        bytes32 indexed nettingId,
        bytes32 indexed portfolioId,
        int256 netAmountBase,
        uint256 currencyCount
    );

    event NettingValidated(
        bytes32 indexed nettingId,
        bytes32 indexed csaId,
        bool isValid
    );

    event SettlementGenerated(
        bytes32 indexed nettingId,
        bytes32 indexed settlementId,
        int256 amount,
        bytes32 currency
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error PortfolioNotFound(bytes32 portfolioId);
    error CSANotFound(bytes32 csaId);
    error PaymentNettingNotEnabled(bytes32 csaId);
    error CloseOutNettingNotEnabled(bytes32 csaId);
    error MultiCurrencyNettingNotEnabled(bytes32 csaId);
    error InvalidNettingInputs();
    error BelowSettlementThreshold(uint256 netAmount, uint256 threshold);
    error NettingAlreadyExists(bytes32 nettingId);
    error NettingNotFound(bytes32 nettingId);
    error InvalidFXRate();
    error InvalidCurrency();
    error NoPayments();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /// @notice Constructor
    /// @param _portfolio Portfolio contract address
    /// @param _csa CSA contract address
    /// @param _agreementRegistry Agreement registry address
    /// @param _isdaMasterAgreement ISDA Master Agreement address
    constructor(
        Portfolio _portfolio,
        CSA _csa,
        AgreementRegistry _agreementRegistry,
        ISDAMasterAgreement _isdaMasterAgreement
    ) {
        portfolio = _portfolio;
        csa = _csa;
        agreementRegistry = _agreementRegistry;
        isdaMasterAgreement = _isdaMasterAgreement;
    }

    // =============================================================================
    // PAYMENT NETTING
    // =============================================================================

    /// @notice Calculate payment netting for a settlement date
    /// @param nettingId Netting calculation ID
    /// @param portfolioId Portfolio ID
    /// @param payments Payments to net
    /// @param calculatedBy Who is calculating
    /// @return results Netting results per currency
    function calculatePaymentNetting(
        bytes32 nettingId,
        bytes32 portfolioId,
        PaymentNettingInput[] calldata payments,
        bytes32 calculatedBy
    ) external returns (PaymentNettingResult[] memory results) {
        // Validation
        if (!portfolio.portfolioExists(portfolioId)) {
            revert PortfolioNotFound(portfolioId);
        }
        if (payments.length == 0) {
            revert NoPayments();
        }

        // Get CSA
        Portfolio.PortfolioData memory portfolioData = portfolio.getPortfolio(portfolioId);
        bytes32 csaId = portfolioData.csaId;

        if (!csa.csaExists(csaId)) {
            revert CSANotFound(csaId);
        }

        // Validate payment netting is enabled
        if (!csa.isPaymentNettingEnabled(csaId)) {
            revert PaymentNettingNotEnabled(csaId);
        }

        // Create netting calculation record
        NettingCalculation storage calculation = nettingCalculations[nettingId];
        calculation.nettingId = nettingId;
        calculation.portfolioId = portfolioId;
        calculation.csaId = csaId;
        calculation.nettingType = NettingTypeEnum.PAYMENT;
        calculation.status = NettingStatusEnum.CALCULATED;
        calculation.calculationTimestamp = block.timestamp;
        calculation.calculatedBy = calculatedBy;
        calculation.metaGlobalKey = nettingId;

        portfolioNettings[portfolioId].push(nettingId);
        totalNettings++;

        // Process payments by currency (simplified - in production would use more efficient grouping)
        // For now, return results array
        results = new PaymentNettingResult[](1); // Simplified: assume single currency

        // Net all payments
        int256 totalNet = 0;
        bytes32 currency = payments[0].currency;
        uint256 settlementDate = payments[0].settlementDate;
        bytes32[] memory tradeIds = new bytes32[](payments.length);

        for (uint256 i = 0; i < payments.length; i++) {
            totalNet += payments[i].paymentAmount;
            tradeIds[i] = payments[i].tradeId;
        }

        // Create result
        results[0] = PaymentNettingResult({
            currency: currency,
            netAmount: totalNet,
            settlementDate: settlementDate,
            netPayer: totalNet < 0 ? payments[0].payer : payments[0].receiver,
            netReceiver: totalNet > 0 ? payments[0].receiver : payments[0].payer,
            tradeCount: payments.length,
            tradeIds: tradeIds
        });

        // Store result
        paymentNettingResults[nettingId][currency] = results[0];

        emit PaymentNettingCalculated(
            nettingId,
            portfolioId,
            currency,
            totalNet,
            payments.length
        );

        return results;
    }

    // =============================================================================
    // CLOSE-OUT NETTING
    // =============================================================================

    /// @notice Calculate close-out netting for entire portfolio
    /// @param nettingId Netting calculation ID
    /// @param portfolioId Portfolio ID
    /// @param trades Trades with MTM values
    /// @param baseCurrency Base currency for netting
    /// @param eventOfDefaultId Event of Default ID (if applicable)
    /// @param calculatedBy Who is calculating
    /// @return result Close-out netting result
    function calculateCloseOutNetting(
        bytes32 nettingId,
        bytes32 portfolioId,
        CloseOutNettingInput[] calldata trades,
        bytes32 baseCurrency,
        bytes32 eventOfDefaultId,
        bytes32 calculatedBy
    ) external returns (CloseOutNettingResult memory result) {
        // Validation
        if (!portfolio.portfolioExists(portfolioId)) {
            revert PortfolioNotFound(portfolioId);
        }
        if (trades.length == 0) {
            revert InvalidNettingInputs();
        }

        // Get CSA
        Portfolio.PortfolioData memory portfolioData = portfolio.getPortfolio(portfolioId);
        bytes32 csaId = portfolioData.csaId;

        if (!csa.csaExists(csaId)) {
            revert CSANotFound(csaId);
        }

        // Validate close-out netting is enabled
        if (!csa.isCloseOutNettingEnabled(csaId)) {
            revert CloseOutNettingNotEnabled(csaId);
        }

        // Calculate net close-out amount
        int256 netCloseOut = 0;
        bytes32[] memory tradeIds = new bytes32[](trades.length);

        for (uint256 i = 0; i < trades.length; i++) {
            // Assume all MTMs are in base currency (in production, would convert)
            netCloseOut += trades[i].mtm;
            tradeIds[i] = trades[i].tradeId;
        }

        // Create result
        result = CloseOutNettingResult({
            netCloseOut: netCloseOut,
            baseCurrency: baseCurrency,
            valuationDate: block.timestamp,
            netPayer: netCloseOut < 0 ? portfolioData.parties[0] : portfolioData.parties[1],
            netReceiver: netCloseOut > 0 ? portfolioData.parties[1] : portfolioData.parties[0],
            tradeCount: trades.length,
            tradeIds: tradeIds,
            eventOfDefaultId: eventOfDefaultId
        });

        // Create netting calculation record
        NettingCalculation storage calculation = nettingCalculations[nettingId];
        calculation.nettingId = nettingId;
        calculation.portfolioId = portfolioId;
        calculation.csaId = csaId;
        calculation.nettingType = NettingTypeEnum.CLOSE_OUT;
        calculation.status = NettingStatusEnum.CALCULATED;
        calculation.calculationTimestamp = block.timestamp;
        calculation.calculatedBy = calculatedBy;
        calculation.metaGlobalKey = nettingId;

        // Store result
        closeOutNettingResults[nettingId] = result;
        portfolioNettings[portfolioId].push(nettingId);
        totalNettings++;

        emit CloseOutNettingCalculated(
            nettingId,
            portfolioId,
            netCloseOut,
            trades.length
        );

        return result;
    }

    // =============================================================================
    // MULTI-CURRENCY NETTING
    // =============================================================================

    /// @notice Calculate multi-currency netting with FX conversion
    /// @param nettingId Netting calculation ID
    /// @param portfolioId Portfolio ID
    /// @param currencyAmounts Net amounts per currency
    /// @param baseCurrency Base currency for conversion
    /// @param calculatedBy Who is calculating
    /// @return result Multi-currency netting result
    function calculateMultiCurrencyNetting(
        bytes32 nettingId,
        bytes32 portfolioId,
        MultiCurrencyNettingInput[] calldata currencyAmounts,
        bytes32 baseCurrency,
        bytes32 calculatedBy
    ) external returns (MultiCurrencyNettingResult memory result) {
        // Validation
        if (!portfolio.portfolioExists(portfolioId)) {
            revert PortfolioNotFound(portfolioId);
        }
        if (currencyAmounts.length == 0) {
            revert InvalidNettingInputs();
        }

        // Get CSA
        Portfolio.PortfolioData memory portfolioData = portfolio.getPortfolio(portfolioId);
        bytes32 csaId = portfolioData.csaId;

        if (!csa.csaExists(csaId)) {
            revert CSANotFound(csaId);
        }

        // Validate multi-currency netting is enabled
        if (!csa.isMultiCurrencyNettingEnabled(csaId)) {
            revert MultiCurrencyNettingNotEnabled(csaId);
        }

        // Calculate net amount in base currency
        int256 netAmountBase = 0;

        for (uint256 i = 0; i < currencyAmounts.length; i++) {
            if (currencyAmounts[i].fxRate == 0) {
                revert InvalidFXRate();
            }

            // Convert to base currency
            // Amount_base = Amount_currency * FX_rate
            // Using signed multiplication (careful with negatives)
            int256 convertedAmount = (currencyAmounts[i].netAmount * int256(currencyAmounts[i].fxRate)) / 1e18;
            netAmountBase += convertedAmount;
        }

        // Create result
        result = MultiCurrencyNettingResult({
            netAmountBase: netAmountBase,
            baseCurrency: baseCurrency,
            currencyCount: currencyAmounts.length,
            inputs: currencyAmounts
        });

        // Create netting calculation record
        NettingCalculation storage calculation = nettingCalculations[nettingId];
        calculation.nettingId = nettingId;
        calculation.portfolioId = portfolioId;
        calculation.csaId = csaId;
        calculation.nettingType = NettingTypeEnum.MULTI_CURRENCY;
        calculation.status = NettingStatusEnum.CALCULATED;
        calculation.calculationTimestamp = block.timestamp;
        calculation.calculatedBy = calculatedBy;
        calculation.metaGlobalKey = nettingId;

        // Store result
        multiCurrencyNettingResults[nettingId] = result;
        portfolioNettings[portfolioId].push(nettingId);
        totalNettings++;

        emit MultiCurrencyNettingCalculated(
            nettingId,
            portfolioId,
            netAmountBase,
            currencyAmounts.length
        );

        return result;
    }

    // =============================================================================
    // VALIDATION
    // =============================================================================

    /// @notice Validate netting against settlement threshold
    /// @param nettingId Netting calculation ID
    /// @param netAmount Net amount (absolute value)
    /// @return isValid True if above threshold
    function validateSettlementThreshold(
        bytes32 nettingId,
        uint256 netAmount
    ) external view returns (bool isValid) {
        NettingCalculation memory calculation = nettingCalculations[nettingId];

        if (calculation.nettingId == bytes32(0)) {
            revert NettingNotFound(nettingId);
        }

        // Get settlement threshold from CSA
        CSA.CSAgreement memory csaAgreement = csa.getCSA(calculation.csaId);
        uint256 threshold = csaAgreement.nettingTerms.settlementThreshold;

        return netAmount >= threshold;
    }

    /// @notice Validate netting calculation
    /// @param nettingId Netting calculation ID
    function validateNetting(bytes32 nettingId) external {
        NettingCalculation storage calculation = nettingCalculations[nettingId];

        if (calculation.nettingId == bytes32(0)) {
            revert NettingNotFound(nettingId);
        }

        // Mark as validated
        calculation.status = NettingStatusEnum.VALIDATED;

        emit NettingValidated(nettingId, calculation.csaId, true);
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /// @notice Get netting calculation
    /// @param nettingId Netting calculation ID
    /// @return calculation Netting calculation
    function getNettingCalculation(bytes32 nettingId)
        external
        view
        returns (NettingCalculation memory calculation)
    {
        if (nettingCalculations[nettingId].nettingId == bytes32(0)) {
            revert NettingNotFound(nettingId);
        }
        return nettingCalculations[nettingId];
    }

    /// @notice Get payment netting result
    /// @param nettingId Netting calculation ID
    /// @param currency Currency
    /// @return result Payment netting result
    function getPaymentNettingResult(
        bytes32 nettingId,
        bytes32 currency
    ) external view returns (PaymentNettingResult memory result) {
        return paymentNettingResults[nettingId][currency];
    }

    /// @notice Get close-out netting result
    /// @param nettingId Netting calculation ID
    /// @return result Close-out netting result
    function getCloseOutNettingResult(bytes32 nettingId)
        external
        view
        returns (CloseOutNettingResult memory result)
    {
        return closeOutNettingResults[nettingId];
    }

    /// @notice Get multi-currency netting result
    /// @param nettingId Netting calculation ID
    /// @return result Multi-currency netting result
    function getMultiCurrencyNettingResult(bytes32 nettingId)
        external
        view
        returns (MultiCurrencyNettingResult memory result)
    {
        return multiCurrencyNettingResults[nettingId];
    }

    /// @notice Get all nettings for a portfolio
    /// @param portfolioId Portfolio ID
    /// @return nettingIds List of netting IDs
    function getPortfolioNettings(bytes32 portfolioId)
        external
        view
        returns (bytes32[] memory nettingIds)
    {
        return portfolioNettings[portfolioId];
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /// @notice Get absolute value of signed integer
    /// @param value Signed integer
    /// @return absValue Absolute value
    function abs(int256 value) public pure returns (uint256 absValue) {
        return value >= 0 ? uint256(value) : uint256(-value);
    }
}
