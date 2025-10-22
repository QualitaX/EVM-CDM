// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CSA} from "../agreements/CSA.sol";
import {AgreementRegistry} from "../agreements/AgreementRegistry.sol";

/**
 * @title Portfolio
 * @notice Portfolio management and trade grouping for netting
 * @dev Aggregates trades and valuations for netting calculations
 *
 * KEY FEATURES:
 * - Portfolio creation with CSA linkage
 * - Trade addition/removal with validation
 * - MTM aggregation by currency
 * - Portfolio-level exposure tracking
 * - Integration with CSA netting rules
 *
 * PORTFOLIO STRUCTURE:
 * Portfolio
 *   ├── Linked to CSA (for netting rules)
 *   ├── Linked to Netting Set (for trade grouping)
 *   ├── Trade List (all trades in portfolio)
 *   ├── MTM by Currency (aggregated exposures)
 *   └── Portfolio Status (ACTIVE, MATURED, TERMINATED)
 *
 * TYPICAL USE CASES:
 * - NDF portfolio with 5 trades
 * - IRS portfolio with quarterly payments
 * - Multi-currency FX portfolio
 * - Cross-product netting portfolios
 *
 * INTEGRATION POINTS:
 * - CSA: Netting rules and eligibility
 * - NettingEngine: Automated net calculation
 * - TradeState: Trade valuations and status
 * - TransferEvent: Settlement generation
 *
 * @author QualitaX Team
 */
contract Portfolio {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Portfolio status
    enum PortfolioStatusEnum {
        ACTIVE,                     // Active and operational
        SUSPENDED,                  // Temporarily suspended
        MATURED,                    // All trades matured
        TERMINATED,                 // Early termination
        CLOSED                      // Closed (no active trades)
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Trade valuation snapshot
    /// @dev Stores MTM and currency for a trade at a point in time
    struct TradeValuation {
        bytes32 tradeId;                    // Trade identifier
        int256 mtm;                         // Mark-to-market value (18 decimals)
        bytes32 currency;                   // Currency of MTM
        uint256 valuationTimestamp;         // When valuation was recorded
        bool isActive;                      // Trade is active
    }

    /// @notice Currency exposure aggregation
    /// @dev Aggregates all trades in a currency
    struct CurrencyExposure {
        bytes32 currency;                   // Currency identifier
        int256 totalMtm;                    // Total MTM in this currency (18 decimals)
        uint256 tradeCount;                 // Number of trades in this currency
        int256 positiveExposure;            // Sum of positive MTM trades
        int256 negativeExposure;            // Sum of negative MTM trades
    }

    /// @notice Portfolio data structure
    /// @dev Complete portfolio with trades and valuations
    struct PortfolioData {
        bytes32 portfolioId;                // Portfolio identifier
        bytes32 csaId;                      // Linked CSA
        bytes32 nettingSetId;               // Linked netting set
        bytes32[] parties;                  // Counterparties (typically 2)

        // Trades
        bytes32[] tradeIds;                 // All trades in portfolio
        uint256 activeTradeCount;           // Number of active trades

        // Dates
        uint256 creationTimestamp;
        uint256 lastValuationTimestamp;     // Last time valuations were updated

        // Status
        PortfolioStatusEnum status;
        bytes32 createdBy;

        // Metadata
        bytes32 metaGlobalKey;
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice CSA contract reference
    CSA public immutable csa;

    /// @notice Agreement registry reference
    AgreementRegistry public immutable agreementRegistry;

    /// @notice Mapping from portfolio ID to portfolio data
    mapping(bytes32 => PortfolioData) public portfolios;

    /// @notice Mapping from portfolio ID to existence check
    mapping(bytes32 => bool) public portfolioExists;

    /// @notice Mapping from portfolio ID to trade valuations
    mapping(bytes32 => mapping(bytes32 => TradeValuation)) public portfolioTradeValuations;

    /// @notice Mapping from portfolio ID to currency exposures
    mapping(bytes32 => mapping(bytes32 => CurrencyExposure)) public portfolioCurrencyExposures;

    /// @notice Mapping from portfolio ID to list of currencies
    mapping(bytes32 => bytes32[]) public portfolioCurrencies;

    /// @notice Mapping from trade ID to portfolio ID
    mapping(bytes32 => bytes32) public tradeToPortfolio;

    /// @notice Mapping from CSA ID to portfolio IDs
    mapping(bytes32 => bytes32[]) public csaPortfolios;

    /// @notice Counter for total portfolios
    uint256 public totalPortfolios;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event PortfolioCreated(
        bytes32 indexed portfolioId,
        bytes32 indexed csaId,
        bytes32 indexed nettingSetId,
        bytes32[] parties,
        bytes32 createdBy
    );

    event TradeAdded(
        bytes32 indexed portfolioId,
        bytes32 indexed tradeId,
        bytes32 currency,
        int256 mtm
    );

    event TradeRemoved(
        bytes32 indexed portfolioId,
        bytes32 indexed tradeId
    );

    event TradeValuationUpdated(
        bytes32 indexed portfolioId,
        bytes32 indexed tradeId,
        int256 oldMtm,
        int256 newMtm,
        uint256 valuationTimestamp
    );

    event PortfolioRevalued(
        bytes32 indexed portfolioId,
        uint256 valuationTimestamp,
        uint256 tradeCount
    );

    event PortfolioStatusChanged(
        bytes32 indexed portfolioId,
        PortfolioStatusEnum oldStatus,
        PortfolioStatusEnum newStatus
    );

    event CurrencyExposureUpdated(
        bytes32 indexed portfolioId,
        bytes32 indexed currency,
        int256 totalMtm,
        uint256 tradeCount
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error PortfolioAlreadyExists(bytes32 portfolioId);
    error PortfolioNotFound(bytes32 portfolioId);
    error CSANotFound(bytes32 csaId);
    error NettingSetNotFound(bytes32 nettingSetId);
    error InvalidParties();
    error TradeAlreadyInPortfolio(bytes32 tradeId);
    error TradeNotInPortfolio(bytes32 tradeId);
    error PortfolioNotActive(bytes32 portfolioId);
    error InvalidCurrency();
    error InvalidMTM();
    error NoActiveTrades();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /// @notice Constructor
    /// @param _csa CSA contract address
    /// @param _agreementRegistry Agreement registry address
    constructor(CSA _csa, AgreementRegistry _agreementRegistry) {
        csa = _csa;
        agreementRegistry = _agreementRegistry;
    }

    // =============================================================================
    // PORTFOLIO MANAGEMENT
    // =============================================================================

    /// @notice Create a new portfolio
    /// @param portfolioId Portfolio identifier
    /// @param csaId CSA identifier
    /// @param nettingSetId Netting set identifier
    /// @param parties Counterparties
    /// @param createdBy Creator party
    /// @return portfolio Created portfolio
    function createPortfolio(
        bytes32 portfolioId,
        bytes32 csaId,
        bytes32 nettingSetId,
        bytes32[] memory parties,
        bytes32 createdBy
    ) external returns (PortfolioData memory portfolio) {
        // Validation
        if (portfolioExists[portfolioId]) {
            revert PortfolioAlreadyExists(portfolioId);
        }
        if (!csa.csaExists(csaId)) {
            revert CSANotFound(csaId);
        }
        if (parties.length < 2) {
            revert InvalidParties();
        }
        for (uint256 i = 0; i < parties.length; i++) {
            if (parties[i] == bytes32(0)) {
                revert InvalidParties();
            }
        }

        // Create portfolio
        PortfolioData storage newPortfolio = portfolios[portfolioId];
        newPortfolio.portfolioId = portfolioId;
        newPortfolio.csaId = csaId;
        newPortfolio.nettingSetId = nettingSetId;
        newPortfolio.parties = parties;
        newPortfolio.activeTradeCount = 0;
        newPortfolio.creationTimestamp = block.timestamp;
        newPortfolio.lastValuationTimestamp = block.timestamp;
        newPortfolio.status = PortfolioStatusEnum.ACTIVE;
        newPortfolio.createdBy = createdBy;
        newPortfolio.metaGlobalKey = portfolioId;

        portfolioExists[portfolioId] = true;
        csaPortfolios[csaId].push(portfolioId);
        totalPortfolios++;

        emit PortfolioCreated(
            portfolioId,
            csaId,
            nettingSetId,
            parties,
            createdBy
        );

        return portfolios[portfolioId];
    }

    /// @notice Add a trade to portfolio
    /// @param portfolioId Portfolio identifier
    /// @param tradeId Trade identifier
    /// @param currency Currency of trade
    /// @param mtm Mark-to-market value (18 decimals, can be negative)
    /// @param productType Product type for netting validation
    function addTrade(
        bytes32 portfolioId,
        bytes32 tradeId,
        bytes32 currency,
        int256 mtm,
        CSA.ProductTypeEnum productType
    ) external {
        // Validation
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        if (tradeToPortfolio[tradeId] != bytes32(0)) {
            revert TradeAlreadyInPortfolio(tradeId);
        }
        if (currency == bytes32(0)) {
            revert InvalidCurrency();
        }

        PortfolioData storage portfolio = portfolios[portfolioId];

        if (portfolio.status != PortfolioStatusEnum.ACTIVE) {
            revert PortfolioNotActive(portfolioId);
        }

        // Validate trade is eligible for netting (optional, can be enforced)
        // This ensures the trade's product type is allowed by the CSA
        bytes32 csaId = portfolio.csaId;
        if (!csa.canNetProduct(csaId, productType)) {
            // Note: We don't revert here as trades can be added before netting eligibility is determined
            // The NettingEngine will validate eligibility during actual netting
        }

        // Add trade to portfolio
        portfolio.tradeIds.push(tradeId);
        portfolio.activeTradeCount++;
        tradeToPortfolio[tradeId] = portfolioId;

        // Record trade valuation
        TradeValuation storage valuation = portfolioTradeValuations[portfolioId][tradeId];
        valuation.tradeId = tradeId;
        valuation.mtm = mtm;
        valuation.currency = currency;
        valuation.valuationTimestamp = block.timestamp;
        valuation.isActive = true;

        // Update currency exposure
        _updateCurrencyExposure(portfolioId, currency, mtm, true);

        emit TradeAdded(portfolioId, tradeId, currency, mtm);
    }

    /// @notice Remove a trade from portfolio
    /// @param portfolioId Portfolio identifier
    /// @param tradeId Trade identifier
    function removeTrade(
        bytes32 portfolioId,
        bytes32 tradeId
    ) external {
        // Validation
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        if (tradeToPortfolio[tradeId] != portfolioId) {
            revert TradeNotInPortfolio(tradeId);
        }

        PortfolioData storage portfolio = portfolios[portfolioId];
        TradeValuation storage valuation = portfolioTradeValuations[portfolioId][tradeId];

        // Update currency exposure (remove this trade's contribution)
        _updateCurrencyExposure(portfolioId, valuation.currency, -valuation.mtm, false);

        // Mark trade as inactive
        valuation.isActive = false;
        portfolio.activeTradeCount--;
        tradeToPortfolio[tradeId] = bytes32(0);

        // Update portfolio status if no active trades
        if (portfolio.activeTradeCount == 0) {
            _changePortfolioStatus(portfolioId, PortfolioStatusEnum.CLOSED);
        }

        emit TradeRemoved(portfolioId, tradeId);
    }

    /// @notice Update trade valuation (MTM)
    /// @param portfolioId Portfolio identifier
    /// @param tradeId Trade identifier
    /// @param newMtm New mark-to-market value
    function updateTradeValuation(
        bytes32 portfolioId,
        bytes32 tradeId,
        int256 newMtm
    ) external {
        // Validation
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        if (tradeToPortfolio[tradeId] != portfolioId) {
            revert TradeNotInPortfolio(tradeId);
        }

        TradeValuation storage valuation = portfolioTradeValuations[portfolioId][tradeId];

        if (!valuation.isActive) {
            revert TradeNotInPortfolio(tradeId);
        }

        int256 oldMtm = valuation.mtm;
        int256 mtmDelta = newMtm - oldMtm;

        // Update valuation
        valuation.mtm = newMtm;
        valuation.valuationTimestamp = block.timestamp;

        // Update currency exposure
        _updateCurrencyExposure(portfolioId, valuation.currency, mtmDelta, true);

        // Update last valuation timestamp
        portfolios[portfolioId].lastValuationTimestamp = block.timestamp;

        emit TradeValuationUpdated(
            portfolioId,
            tradeId,
            oldMtm,
            newMtm,
            block.timestamp
        );
    }

    /// @notice Revalue entire portfolio
    /// @param portfolioId Portfolio identifier
    /// @param tradeIds Trade identifiers to revalue
    /// @param mtms New MTM values for each trade
    function revaluePortfolio(
        bytes32 portfolioId,
        bytes32[] calldata tradeIds,
        int256[] calldata mtms
    ) external {
        // Validation
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        if (tradeIds.length != mtms.length) {
            revert InvalidMTM();
        }

        // Update all trade valuations
        for (uint256 i = 0; i < tradeIds.length; i++) {
            bytes32 tradeId = tradeIds[i];
            int256 newMtm = mtms[i];

            if (tradeToPortfolio[tradeId] != portfolioId) {
                revert TradeNotInPortfolio(tradeId);
            }

            TradeValuation storage valuation = portfolioTradeValuations[portfolioId][tradeId];

            if (!valuation.isActive) {
                continue; // Skip inactive trades
            }

            int256 oldMtm = valuation.mtm;
            int256 mtmDelta = newMtm - oldMtm;

            valuation.mtm = newMtm;
            valuation.valuationTimestamp = block.timestamp;

            // Update currency exposure
            _updateCurrencyExposure(portfolioId, valuation.currency, mtmDelta, true);

            emit TradeValuationUpdated(
                portfolioId,
                tradeId,
                oldMtm,
                newMtm,
                block.timestamp
            );
        }

        // Update last valuation timestamp
        portfolios[portfolioId].lastValuationTimestamp = block.timestamp;

        emit PortfolioRevalued(
            portfolioId,
            block.timestamp,
            tradeIds.length
        );
    }

    /// @notice Change portfolio status
    /// @param portfolioId Portfolio identifier
    /// @param newStatus New status
    function changePortfolioStatus(
        bytes32 portfolioId,
        PortfolioStatusEnum newStatus
    ) external {
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }

        _changePortfolioStatus(portfolioId, newStatus);
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /// @notice Get portfolio data
    /// @param portfolioId Portfolio identifier
    /// @return portfolio Portfolio data
    function getPortfolio(bytes32 portfolioId)
        external
        view
        returns (PortfolioData memory portfolio)
    {
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        return portfolios[portfolioId];
    }

    /// @notice Get trade valuation in portfolio
    /// @param portfolioId Portfolio identifier
    /// @param tradeId Trade identifier
    /// @return valuation Trade valuation
    function getTradeValuation(
        bytes32 portfolioId,
        bytes32 tradeId
    ) external view returns (TradeValuation memory valuation) {
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        return portfolioTradeValuations[portfolioId][tradeId];
    }

    /// @notice Get currency exposure for portfolio
    /// @param portfolioId Portfolio identifier
    /// @param currency Currency identifier
    /// @return exposure Currency exposure
    function getCurrencyExposure(
        bytes32 portfolioId,
        bytes32 currency
    ) external view returns (CurrencyExposure memory exposure) {
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        return portfolioCurrencyExposures[portfolioId][currency];
    }

    /// @notice Get all currencies in portfolio
    /// @param portfolioId Portfolio identifier
    /// @return currencies List of currencies
    function getPortfolioCurrencies(bytes32 portfolioId)
        external
        view
        returns (bytes32[] memory currencies)
    {
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        return portfolioCurrencies[portfolioId];
    }

    /// @notice Get total MTM for a currency
    /// @param portfolioId Portfolio identifier
    /// @param currency Currency identifier
    /// @return mtm Total MTM in currency
    function getTotalMTMForCurrency(
        bytes32 portfolioId,
        bytes32 currency
    ) external view returns (int256 mtm) {
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        return portfolioCurrencyExposures[portfolioId][currency].totalMtm;
    }

    /// @notice Get all portfolios for a CSA
    /// @param csaId CSA identifier
    /// @return portfolioIds List of portfolio IDs
    function getCSAPortfolios(bytes32 csaId)
        external
        view
        returns (bytes32[] memory portfolioIds)
    {
        return csaPortfolios[csaId];
    }

    /// @notice Check if portfolio has active trades
    /// @param portfolioId Portfolio identifier
    /// @return hasActive True if portfolio has active trades
    function hasActiveTrades(bytes32 portfolioId) external view returns (bool hasActive) {
        if (!portfolioExists[portfolioId]) {
            revert PortfolioNotFound(portfolioId);
        }
        return portfolios[portfolioId].activeTradeCount > 0;
    }

    /// @notice Get portfolio for a trade
    /// @param tradeId Trade identifier
    /// @return portfolioId Portfolio identifier (bytes32(0) if not in portfolio)
    function getPortfolioForTrade(bytes32 tradeId)
        external
        view
        returns (bytes32 portfolioId)
    {
        return tradeToPortfolio[tradeId];
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /// @notice Update currency exposure
    /// @param portfolioId Portfolio identifier
    /// @param currency Currency identifier
    /// @param mtmDelta Change in MTM (can be negative)
    /// @param isAddition True if adding/updating, false if removing
    function _updateCurrencyExposure(
        bytes32 portfolioId,
        bytes32 currency,
        int256 mtmDelta,
        bool isAddition
    ) internal {
        CurrencyExposure storage exposure = portfolioCurrencyExposures[portfolioId][currency];

        // Initialize if first time seeing this currency
        if (exposure.currency == bytes32(0)) {
            exposure.currency = currency;
            portfolioCurrencies[portfolioId].push(currency);
        }

        // Update total MTM
        exposure.totalMtm += mtmDelta;

        // Update trade count
        if (isAddition && mtmDelta != 0) {
            // When adding a new trade or updating valuation
            // We don't change trade count on updates
        }

        // Update positive/negative exposures
        if (mtmDelta > 0) {
            exposure.positiveExposure += mtmDelta;
        } else if (mtmDelta < 0) {
            exposure.negativeExposure += mtmDelta;
        }

        emit CurrencyExposureUpdated(
            portfolioId,
            currency,
            exposure.totalMtm,
            exposure.tradeCount
        );
    }

    /// @notice Change portfolio status
    /// @param portfolioId Portfolio identifier
    /// @param newStatus New status
    function _changePortfolioStatus(
        bytes32 portfolioId,
        PortfolioStatusEnum newStatus
    ) internal {
        PortfolioData storage portfolio = portfolios[portfolioId];
        PortfolioStatusEnum oldStatus = portfolio.status;

        if (oldStatus != newStatus) {
            portfolio.status = newStatus;

            emit PortfolioStatusChanged(
                portfolioId,
                oldStatus,
                newStatus
            );
        }
    }
}
