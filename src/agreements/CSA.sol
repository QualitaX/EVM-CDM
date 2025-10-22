// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgreementRegistry} from "./AgreementRegistry.sol";

/**
 * @title CSA (Credit Support Annex)
 * @notice Credit support and netting terms between counterparties
 * @dev Defines netting rules and collateral requirements
 *
 * KEY FEATURES:
 * - Netting terms (payment, close-out, multi-currency)
 * - Collateral requirements (threshold, minimum transfer)
 * - Netting set management (portfolio grouping)
 * - Eligible product types for netting
 * - Trade netting eligibility validation
 *
 * NETTING TYPES:
 * - Payment Netting: Net periodic payments on same date
 * - Close-out Netting: Net all positions on termination
 * - Multi-Currency Netting: Net across currency pairs
 *
 * CSA HIERARCHY:
 * CSAgreement
 *   ├── Linked to Master Agreement (ISDA, GMRA, etc.)
 *   ├── Netting Terms
 *   │   ├── Payment netting enabled
 *   │   ├── Close-out netting enabled
 *   │   ├── Multi-currency netting enabled
 *   │   ├── Eligible product types
 *   │   └── Settlement threshold
 *   ├── Collateral Terms
 *   │   ├── Threshold amount
 *   │   ├── Minimum transfer amount
 *   │   ├── Independent amount (initial margin)
 *   │   ├── Eligible collateral types
 *   │   └── Valuation frequency
 *   └── Netting Sets (Portfolios)
 *
 * TYPICAL USE CASES:
 * - Define netting rules for NDF portfolio
 * - Specify collateral requirements
 * - Group trades into netting sets
 * - Validate trade netting eligibility
 *
 * @author QualitaX Team
 */
contract CSA {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Product type for netting eligibility
    enum ProductTypeEnum {
        INTEREST_RATE_SWAP,         // IRS
        NON_DELIVERABLE_FORWARD,    // NDF
        FX_FORWARD,                 // FX Forward
        FX_SWAP,                    // FX Swap
        CROSS_CURRENCY_SWAP,        // CCS
        REPO,                       // Repurchase agreement
        SECURITIES_LENDING,         // Securities lending
        CREDIT_DEFAULT_SWAP,        // CDS
        EQUITY_OPTION,              // Equity option
        COMMODITY_SWAP,             // Commodity swap
        ALL                         // All product types eligible
    }

    /// @notice CSA status
    enum CSAStatusEnum {
        PENDING,                    // Pending execution
        ACTIVE,                     // Active and enforceable
        SUSPENDED,                  // Temporarily suspended
        TERMINATED,                 // Terminated
        EXPIRED                     // Expired
    }

    /// @notice Collateral type
    enum CollateralTypeEnum {
        CASH_USD,                   // USD cash
        CASH_EUR,                   // EUR cash
        CASH_GBP,                   // GBP cash
        CASH_JPY,                   // JPY cash
        GOVERNMENT_BONDS,           // Government securities
        CORPORATE_BONDS,            // Corporate bonds
        EQUITIES,                   // Equity securities
        CUSTOM                      // Custom collateral
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Netting terms
    /// @dev Defines which types of netting are enabled
    struct NettingTerms {
        bool closeOutNettingEnabled;            // Net on termination/default
        bool paymentNettingEnabled;             // Net periodic payments
        bool multiCurrencyNettingEnabled;       // Net across currencies
        ProductTypeEnum[] eligibleProducts;     // Which products can net
        uint256 settlementThreshold;            // Min amount to settle (e.g., $1,000)
        bytes32 calculationAgent;               // Party performing calculations
    }

    /// @notice Collateral terms
    /// @dev Defines collateral requirements
    struct CollateralTerms {
        uint256 threshold;                      // Collateral threshold
        uint256 minimumTransferAmount;          // Min collateral transfer
        uint256 independentAmount;              // Initial margin requirement
        CollateralTypeEnum[] eligibleCollateral; // Eligible collateral types
        uint256 valuationFrequency;             // Valuation frequency (seconds)
        bool isCashOnly;                        // Cash collateral only
        uint256 haircut;                        // Haircut percentage (18 decimals)
    }

    /// @notice Netting set
    /// @dev Group of trades that can net together
    struct NettingSet {
        bytes32 nettingSetId;                   // Netting set identifier
        bytes32 csaId;                          // Parent CSA
        bytes32 portfolioId;                    // Portfolio/book identifier
        bytes32[] tradeIds;                     // Trades in this netting set
        ProductTypeEnum[] productTypes;         // Product types in set
        bytes32[] currencies;                   // Currencies in set
        uint256 creationTimestamp;
        bool isActive;
    }

    /// @notice CSA agreement
    /// @dev Complete CSA structure
    struct CSAgreement {
        bytes32 csaId;                          // CSA identifier
        bytes32 masterAgreementId;              // Link to master agreement
        bytes32[] parties;                      // Counterparties

        // Terms
        NettingTerms nettingTerms;
        CollateralTerms collateralTerms;

        // Netting sets
        bytes32[] nettingSets;                  // Netting set IDs

        // Dates
        uint256 effectiveDate;
        uint256 terminationDate;                // 0 = no termination

        // Status
        CSAStatusEnum status;
        uint256 registrationTimestamp;
        bytes32 registeredBy;

        bytes32 metaGlobalKey;
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Agreement registry reference
    AgreementRegistry public immutable agreementRegistry;

    /// @notice Mapping from CSA ID to CSA data
    mapping(bytes32 => CSAgreement) public csaAgreements;

    /// @notice Mapping from CSA ID to existence check
    mapping(bytes32 => bool) public csaExists;

    /// @notice Mapping from netting set ID to netting set data
    mapping(bytes32 => NettingSet) public nettingSets;

    /// @notice Mapping from trade ID to netting set ID
    mapping(bytes32 => bytes32) public tradeToNettingSet;

    /// @notice Mapping from portfolio ID to netting set ID
    mapping(bytes32 => bytes32) public portfolioToNettingSet;

    /// @notice Mapping from party pair to their CSAs
    /// @dev Key is keccak256(abi.encodePacked(smaller, larger))
    mapping(bytes32 => bytes32[]) public partyPairCSAs;

    /// @notice Counter for total CSAs
    uint256 public totalCSAs;

    /// @notice Counter for total netting sets
    uint256 public totalNettingSets;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event CSARegistered(
        bytes32 indexed csaId,
        bytes32 indexed masterAgreementId,
        bytes32[] parties,
        uint256 effectiveDate,
        bytes32 registeredBy
    );

    event NettingSetCreated(
        bytes32 indexed nettingSetId,
        bytes32 indexed csaId,
        bytes32 portfolioId,
        bytes32 createdBy
    );

    event TradeAddedToNettingSet(
        bytes32 indexed tradeId,
        bytes32 indexed nettingSetId,
        bytes32 csaId
    );

    event TradeRemovedFromNettingSet(
        bytes32 indexed tradeId,
        bytes32 indexed nettingSetId,
        bytes32 csaId
    );

    event CSAStatusChanged(
        bytes32 indexed csaId,
        CSAStatusEnum oldStatus,
        CSAStatusEnum newStatus,
        bytes32 changedBy
    );

    event CSATerminated(
        bytes32 indexed csaId,
        uint256 terminationDate,
        bytes32 terminatedBy
    );

    event CollateralTermsUpdated(
        bytes32 indexed csaId,
        uint256 threshold,
        uint256 minimumTransferAmount,
        bytes32 updatedBy
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error CSA__CSAAlreadyExists();
    error CSA__CSADoesNotExist();
    error CSA__MasterAgreementDoesNotExist();
    error CSA__MasterAgreementNotActive();
    error CSA__InvalidParties();
    error CSA__InvalidDates();
    error CSA__InvalidNettingTerms();
    error CSA__InvalidCollateralTerms();
    error CSA__CSANotActive();
    error CSA__NettingSetDoesNotExist();
    error CSA__NettingSetAlreadyExists();
    error CSA__TradeAlreadyInNettingSet();
    error CSA__TradeNotInNettingSet();
    error CSA__ProductTypeNotEligible();
    error CSA__NettingNotEnabled();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize CSA contract
     * @param _agreementRegistry Address of AgreementRegistry contract
     */
    constructor(address _agreementRegistry) {
        agreementRegistry = AgreementRegistry(_agreementRegistry);
    }

    // =============================================================================
    // CSA REGISTRATION
    // =============================================================================

    /**
     * @notice Register a new CSA
     * @dev Creates CSA linked to master agreement
     * @param csaId Unique CSA identifier
     * @param masterAgreementId Master agreement this CSA is attached to
     * @param parties Counterparties (must match master agreement)
     * @param nettingTerms Netting terms
     * @param collateralTerms Collateral terms
     * @param effectiveDate CSA effective date
     * @param terminationDate CSA termination date (0 for no termination)
     * @param registeredBy Party registering the CSA
     * @return csa Created CSA
     */
    function registerCSA(
        bytes32 csaId,
        bytes32 masterAgreementId,
        bytes32[] memory parties,
        NettingTerms memory nettingTerms,
        CollateralTerms memory collateralTerms,
        uint256 effectiveDate,
        uint256 terminationDate,
        bytes32 registeredBy
    ) public returns (CSAgreement memory csa) {
        // Validate
        _validateCSARegistration(
            csaId,
            masterAgreementId,
            parties,
            nettingTerms,
            collateralTerms,
            effectiveDate,
            terminationDate
        );

        // Create CSA
        csa = CSAgreement({
            csaId: csaId,
            masterAgreementId: masterAgreementId,
            parties: parties,
            nettingTerms: nettingTerms,
            collateralTerms: collateralTerms,
            nettingSets: new bytes32[](0),
            effectiveDate: effectiveDate,
            terminationDate: terminationDate,
            status: CSAStatusEnum.ACTIVE,
            registrationTimestamp: block.timestamp,
            registeredBy: registeredBy,
            metaGlobalKey: keccak256(abi.encode(csaId, masterAgreementId, parties))
        });

        // Store CSA
        _storeCSA(csa);

        // Attach to master agreement in registry
        agreementRegistry.attachCSA(csaId, masterAgreementId, registeredBy);

        // Emit event
        emit CSARegistered(csaId, masterAgreementId, parties, effectiveDate, registeredBy);

        return csa;
    }

    // =============================================================================
    // NETTING SET MANAGEMENT
    // =============================================================================

    /**
     * @notice Create a new netting set
     * @dev Netting set groups trades for netting
     * @param nettingSetId Netting set identifier
     * @param csaId CSA identifier
     * @param portfolioId Portfolio/book identifier
     * @param createdBy Party creating the netting set
     * @return nettingSet Created netting set
     */
    function createNettingSet(
        bytes32 nettingSetId,
        bytes32 csaId,
        bytes32 portfolioId,
        bytes32 createdBy
    ) public returns (NettingSet memory nettingSet) {
        // Validate CSA exists and is active
        if (!csaExists[csaId]) {
            revert CSA__CSADoesNotExist();
        }
        if (csaAgreements[csaId].status != CSAStatusEnum.ACTIVE) {
            revert CSA__CSANotActive();
        }

        // Check netting set doesn't exist
        if (nettingSets[nettingSetId].nettingSetId != bytes32(0)) {
            revert CSA__NettingSetAlreadyExists();
        }

        // Create netting set
        nettingSet = NettingSet({
            nettingSetId: nettingSetId,
            csaId: csaId,
            portfolioId: portfolioId,
            tradeIds: new bytes32[](0),
            productTypes: new ProductTypeEnum[](0),
            currencies: new bytes32[](0),
            creationTimestamp: block.timestamp,
            isActive: true
        });

        // Store netting set
        nettingSets[nettingSetId] = nettingSet;
        csaAgreements[csaId].nettingSets.push(nettingSetId);
        portfolioToNettingSet[portfolioId] = nettingSetId;

        totalNettingSets++;

        emit NettingSetCreated(nettingSetId, csaId, portfolioId, createdBy);

        return nettingSet;
    }

    /**
     * @notice Add trade to netting set
     * @dev Links trade to netting set for netting
     * @param tradeId Trade identifier
     * @param nettingSetId Netting set identifier
     * @param productType Product type of trade
     * @param currency Trade currency
     */
    function addTradeToNettingSet(
        bytes32 tradeId,
        bytes32 nettingSetId,
        ProductTypeEnum productType,
        bytes32 currency
    ) public {
        // Validate netting set exists
        NettingSet storage nettingSet = nettingSets[nettingSetId];
        if (nettingSet.nettingSetId == bytes32(0)) {
            revert CSA__NettingSetDoesNotExist();
        }

        // Check trade not already in a netting set
        if (tradeToNettingSet[tradeId] != bytes32(0)) {
            revert CSA__TradeAlreadyInNettingSet();
        }

        // Validate product type is eligible
        CSAgreement storage csa = csaAgreements[nettingSet.csaId];
        if (!_isProductEligible(csa.nettingTerms.eligibleProducts, productType)) {
            revert CSA__ProductTypeNotEligible();
        }

        // Add trade to netting set
        nettingSet.tradeIds.push(tradeId);
        tradeToNettingSet[tradeId] = nettingSetId;

        // Add product type if new
        if (!_containsProductType(nettingSet.productTypes, productType)) {
            nettingSet.productTypes.push(productType);
        }

        // Add currency if new
        if (!_containsCurrency(nettingSet.currencies, currency)) {
            nettingSet.currencies.push(currency);
        }

        emit TradeAddedToNettingSet(tradeId, nettingSetId, nettingSet.csaId);
    }

    /**
     * @notice Remove trade from netting set
     * @dev Unlinks trade from netting set
     * @param tradeId Trade identifier
     */
    function removeTradeFromNettingSet(bytes32 tradeId) public {
        bytes32 nettingSetId = tradeToNettingSet[tradeId];

        if (nettingSetId == bytes32(0)) {
            revert CSA__TradeNotInNettingSet();
        }

        NettingSet storage nettingSet = nettingSets[nettingSetId];

        // Remove from trade array
        bytes32[] storage tradeIds = nettingSet.tradeIds;
        for (uint256 i = 0; i < tradeIds.length; i++) {
            if (tradeIds[i] == tradeId) {
                tradeIds[i] = tradeIds[tradeIds.length - 1];
                tradeIds.pop();
                break;
            }
        }

        // Remove mapping
        delete tradeToNettingSet[tradeId];

        emit TradeRemovedFromNettingSet(tradeId, nettingSetId, nettingSet.csaId);
    }

    // =============================================================================
    // CSA LIFECYCLE
    // =============================================================================

    /**
     * @notice Update CSA status
     * @dev Change CSA status
     * @param csaId CSA identifier
     * @param newStatus New status
     * @param changedBy Party making the change
     */
    function updateCSAStatus(
        bytes32 csaId,
        CSAStatusEnum newStatus,
        bytes32 changedBy
    ) public {
        if (!csaExists[csaId]) {
            revert CSA__CSADoesNotExist();
        }

        CSAgreement storage csa = csaAgreements[csaId];
        CSAStatusEnum oldStatus = csa.status;

        csa.status = newStatus;

        emit CSAStatusChanged(csaId, oldStatus, newStatus, changedBy);
    }

    /**
     * @notice Terminate CSA
     * @dev Sets status to TERMINATED
     * @param csaId CSA identifier
     * @param terminatedBy Party terminating the CSA
     */
    function terminateCSA(
        bytes32 csaId,
        bytes32 terminatedBy
    ) public {
        if (!csaExists[csaId]) {
            revert CSA__CSADoesNotExist();
        }

        CSAgreement storage csa = csaAgreements[csaId];
        CSAStatusEnum oldStatus = csa.status;

        csa.status = CSAStatusEnum.TERMINATED;

        emit CSAStatusChanged(csaId, oldStatus, CSAStatusEnum.TERMINATED, terminatedBy);
        emit CSATerminated(csaId, block.timestamp, terminatedBy);
    }

    /**
     * @notice Update collateral terms
     * @dev Allows updating collateral requirements
     * @param csaId CSA identifier
     * @param newCollateralTerms New collateral terms
     * @param updatedBy Party updating terms
     */
    function updateCollateralTerms(
        bytes32 csaId,
        CollateralTerms memory newCollateralTerms,
        bytes32 updatedBy
    ) public {
        if (!csaExists[csaId]) {
            revert CSA__CSADoesNotExist();
        }

        CSAgreement storage csa = csaAgreements[csaId];
        csa.collateralTerms = newCollateralTerms;

        emit CollateralTermsUpdated(
            csaId,
            newCollateralTerms.threshold,
            newCollateralTerms.minimumTransferAmount,
            updatedBy
        );
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @notice Validate CSA registration
     * @dev Internal validation helper
     */
    function _validateCSARegistration(
        bytes32 csaId,
        bytes32 masterAgreementId,
        bytes32[] memory parties,
        NettingTerms memory nettingTerms,
        CollateralTerms memory collateralTerms,
        uint256 effectiveDate,
        uint256 terminationDate
    ) internal view {
        // Check CSA doesn't exist
        if (csaExists[csaId]) {
            revert CSA__CSAAlreadyExists();
        }

        // Validate master agreement exists
        if (!agreementRegistry.agreementExists(masterAgreementId)) {
            revert CSA__MasterAgreementDoesNotExist();
        }

        // Validate master agreement is active
        if (!agreementRegistry.isAgreementActive(masterAgreementId)) {
            revert CSA__MasterAgreementNotActive();
        }

        // Validate parties
        if (parties.length < 2) {
            revert CSA__InvalidParties();
        }
        for (uint256 i = 0; i < parties.length; i++) {
            if (parties[i] == bytes32(0)) {
                revert CSA__InvalidParties();
            }
        }

        // Validate dates
        if (effectiveDate == 0) {
            revert CSA__InvalidDates();
        }
        if (terminationDate != 0 && terminationDate <= effectiveDate) {
            revert CSA__InvalidDates();
        }

        // Validate netting terms
        if (nettingTerms.eligibleProducts.length == 0) {
            revert CSA__InvalidNettingTerms();
        }

        // Validate collateral terms
        if (collateralTerms.minimumTransferAmount > collateralTerms.threshold) {
            revert CSA__InvalidCollateralTerms();
        }
    }

    /**
     * @notice Store CSA and update indexes
     * @dev Internal storage helper
     */
    function _storeCSA(CSAgreement memory csa) internal {
        csaAgreements[csa.csaId] = csa;
        csaExists[csa.csaId] = true;

        // Update party pair index (for bilateral CSAs)
        if (csa.parties.length == 2) {
            bytes32 partyPairKey = _getPartyPairKey(csa.parties[0], csa.parties[1]);
            partyPairCSAs[partyPairKey].push(csa.csaId);
        }

        totalCSAs++;
    }

    /**
     * @notice Get party pair key
     * @dev Ensures consistent ordering
     */
    function _getPartyPairKey(bytes32 party1, bytes32 party2) internal pure returns (bytes32) {
        return party1 < party2
            ? keccak256(abi.encodePacked(party1, party2))
            : keccak256(abi.encodePacked(party2, party1));
    }

    /**
     * @notice Check if product type is eligible
     * @dev Internal helper
     */
    function _isProductEligible(
        ProductTypeEnum[] memory eligibleProducts,
        ProductTypeEnum productType
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < eligibleProducts.length; i++) {
            if (eligibleProducts[i] == ProductTypeEnum.ALL || eligibleProducts[i] == productType) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Check if product type already in array
     * @dev Internal helper
     */
    function _containsProductType(
        ProductTypeEnum[] memory array,
        ProductTypeEnum productType
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == productType) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Check if currency already in array
     * @dev Internal helper
     */
    function _containsCurrency(
        bytes32[] memory array,
        bytes32 currency
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == currency) {
                return true;
            }
        }
        return false;
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get CSA by ID
     * @param csaId CSA identifier
     * @return csa CSA data
     */
    function getCSA(bytes32 csaId) public view returns (CSAgreement memory csa) {
        if (!csaExists[csaId]) {
            revert CSA__CSADoesNotExist();
        }
        return csaAgreements[csaId];
    }

    /**
     * @notice Get netting set by ID
     * @param nettingSetId Netting set identifier
     * @return nettingSet Netting set data
     */
    function getNettingSet(
        bytes32 nettingSetId
    ) public view returns (NettingSet memory nettingSet) {
        nettingSet = nettingSets[nettingSetId];
        if (nettingSet.nettingSetId == bytes32(0)) {
            revert CSA__NettingSetDoesNotExist();
        }
        return nettingSet;
    }

    /**
     * @notice Get netting set for a trade
     * @param tradeId Trade identifier
     * @return nettingSetId Netting set ID
     */
    function getNettingSetForTrade(
        bytes32 tradeId
    ) public view returns (bytes32 nettingSetId) {
        return tradeToNettingSet[tradeId];
    }

    /**
     * @notice Get netting set for a portfolio
     * @param portfolioId Portfolio identifier
     * @return nettingSetId Netting set ID
     */
    function getNettingSetForPortfolio(
        bytes32 portfolioId
    ) public view returns (bytes32 nettingSetId) {
        return portfolioToNettingSet[portfolioId];
    }

    /**
     * @notice Check if two trades can net together
     * @dev Checks if trades are in same netting set
     * @param trade1 First trade ID
     * @param trade2 Second trade ID
     * @return canNet True if trades can net
     */
    function canNetTrades(
        bytes32 trade1,
        bytes32 trade2
    ) public view returns (bool canNet) {
        bytes32 nettingSet1 = tradeToNettingSet[trade1];
        bytes32 nettingSet2 = tradeToNettingSet[trade2];

        // Both trades must be in same netting set
        if (nettingSet1 == bytes32(0) || nettingSet2 == bytes32(0)) {
            return false;
        }

        return nettingSet1 == nettingSet2;
    }

    /**
     * @notice Check if product type can be netted under CSA
     * @param csaId CSA identifier
     * @param productType Product type
     * @return eligible True if product is eligible
     */
    function canNetProduct(
        bytes32 csaId,
        ProductTypeEnum productType
    ) public view returns (bool eligible) {
        if (!csaExists[csaId]) {
            return false;
        }

        CSAgreement storage csa = csaAgreements[csaId];
        return _isProductEligible(csa.nettingTerms.eligibleProducts, productType);
    }

    /**
     * @notice Check if payment netting is enabled
     * @param csaId CSA identifier
     * @return enabled True if payment netting enabled
     */
    function isPaymentNettingEnabled(
        bytes32 csaId
    ) public view returns (bool enabled) {
        if (!csaExists[csaId]) {
            return false;
        }
        return csaAgreements[csaId].nettingTerms.paymentNettingEnabled;
    }

    /**
     * @notice Check if close-out netting is enabled
     * @param csaId CSA identifier
     * @return enabled True if close-out netting enabled
     */
    function isCloseOutNettingEnabled(
        bytes32 csaId
    ) public view returns (bool enabled) {
        if (!csaExists[csaId]) {
            return false;
        }
        return csaAgreements[csaId].nettingTerms.closeOutNettingEnabled;
    }

    /**
     * @notice Check if multi-currency netting is enabled
     * @param csaId CSA identifier
     * @return enabled True if multi-currency netting enabled
     */
    function isMultiCurrencyNettingEnabled(
        bytes32 csaId
    ) public view returns (bool enabled) {
        if (!csaExists[csaId]) {
            return false;
        }
        return csaAgreements[csaId].nettingTerms.multiCurrencyNettingEnabled;
    }

    /**
     * @notice Get collateral threshold
     * @param csaId CSA identifier
     * @return threshold Collateral threshold
     */
    function getCollateralThreshold(
        bytes32 csaId
    ) public view returns (uint256 threshold) {
        if (!csaExists[csaId]) {
            revert CSA__CSADoesNotExist();
        }
        return csaAgreements[csaId].collateralTerms.threshold;
    }

    /**
     * @notice Get CSAs between two parties
     * @param party1 First party
     * @param party2 Second party
     * @return csaIds Array of CSA IDs
     */
    function getCSAsBetweenParties(
        bytes32 party1,
        bytes32 party2
    ) public view returns (bytes32[] memory csaIds) {
        bytes32 partyPairKey = _getPartyPairKey(party1, party2);
        return partyPairCSAs[partyPairKey];
    }

    /**
     * @notice Get applicable CSA for parties and product
     * @param party1 First party
     * @param party2 Second party
     * @param productType Product type
     * @return csaId CSA ID (bytes32(0) if none found)
     */
    function getApplicableCSA(
        bytes32 party1,
        bytes32 party2,
        ProductTypeEnum productType
    ) public view returns (bytes32 csaId) {
        bytes32 partyPairKey = _getPartyPairKey(party1, party2);
        bytes32[] storage csaIds = partyPairCSAs[partyPairKey];

        for (uint256 i = 0; i < csaIds.length; i++) {
            CSAgreement storage csa = csaAgreements[csaIds[i]];

            if (csa.status == CSAStatusEnum.ACTIVE &&
                _isProductEligible(csa.nettingTerms.eligibleProducts, productType)) {
                return csaIds[i];
            }
        }

        return bytes32(0);
    }

    /**
     * @notice Get all netting sets for a CSA
     * @param csaId CSA identifier
     * @return nettingSetIds Array of netting set IDs
     */
    function getNettingSetsForCSA(
        bytes32 csaId
    ) public view returns (bytes32[] memory nettingSetIds) {
        if (!csaExists[csaId]) {
            revert CSA__CSADoesNotExist();
        }
        return csaAgreements[csaId].nettingSets;
    }

    /**
     * @notice Check if CSA is active
     * @param csaId CSA identifier
     * @return active True if CSA is active
     */
    function isCSAActive(bytes32 csaId) public view returns (bool active) {
        if (!csaExists[csaId]) {
            return false;
        }
        return csaAgreements[csaId].status == CSAStatusEnum.ACTIVE;
    }
}
