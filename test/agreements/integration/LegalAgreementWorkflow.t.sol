// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/agreements/AgreementRegistry.sol";
import "../../../src/agreements/CSA.sol";
import "../../../src/agreements/ISDAMasterAgreement.sol";

/**
 * @title LegalAgreementWorkflowTest
 * @notice Integration tests for complete legal agreement workflows
 */
contract LegalAgreementWorkflowTest is Test {
    AgreementRegistry public registry;
    CSA public csa;
    ISDAMasterAgreement public isdaMaster;

    // Test constants
    bytes32 constant MASTER_AGREEMENT_ID = keccak256("ISDA_MASTER_001");
    bytes32 constant CSA_ID = keccak256("CSA_001");
    bytes32 constant PARTY_A = keccak256("BANK_A");
    bytes32 constant PARTY_B = keccak256("CORP_B");
    bytes32 constant NETTING_SET_NDF = keccak256("NETTING_SET_NDF");
    bytes32 constant NETTING_SET_IRS = keccak256("NETTING_SET_IRS");
    bytes32 constant PORTFOLIO_NDF = keccak256("PORTFOLIO_NDF");
    bytes32 constant PORTFOLIO_IRS = keccak256("PORTFOLIO_IRS");
    bytes32 constant REGISTERED_BY = keccak256("OPERATIONS");

    uint256 constant ONE = 1e18;
    uint256 constant EFFECTIVE_DATE = 1704067200; // Jan 1, 2024
    uint256 constant TERMINATION_DATE = 1735689600; // Jan 1, 2025

    function setUp() public {
        registry = new AgreementRegistry();
        csa = new CSA(address(registry));
        isdaMaster = new ISDAMasterAgreement(address(registry));
    }

    // =============================================================================
    // COMPLETE SETUP WORKFLOW
    // =============================================================================

    function test_CompleteSetup_MasterAgreement_ISDA_CSA() public {
        // Step 1: Register ISDA Master Agreement
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        AgreementRegistry.MasterAgreement memory agreement = registry.registerMasterAgreement(
            MASTER_AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            0, // Evergreen
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            keccak256("ipfs://Qm...MasterAgreement"),
            REGISTERED_BY
        );

        assertEq(agreement.agreementId, MASTER_AGREEMENT_ID);
        assertTrue(registry.isAgreementActive(MASTER_AGREEMENT_ID));

        // Step 2: Register ISDA Terms
        ISDAMasterAgreement.EventOfDefaultEnum[] memory eventsOfDefault = new ISDAMasterAgreement.EventOfDefaultEnum[](3);
        eventsOfDefault[0] = ISDAMasterAgreement.EventOfDefaultEnum.FAILURE_TO_PAY_OR_DELIVER;
        eventsOfDefault[1] = ISDAMasterAgreement.EventOfDefaultEnum.BANKRUPTCY;
        eventsOfDefault[2] = ISDAMasterAgreement.EventOfDefaultEnum.CROSS_DEFAULT;

        ISDAMasterAgreement.TerminationEventEnum[] memory terminationEvents = new ISDAMasterAgreement.TerminationEventEnum[](2);
        terminationEvents[0] = ISDAMasterAgreement.TerminationEventEnum.ILLEGALITY;
        terminationEvents[1] = ISDAMasterAgreement.TerminationEventEnum.TAX_EVENT;

        ISDAMasterAgreement.ISDATerms memory isdaTerms = isdaMaster.registerISDATerms(
            MASTER_AGREEMENT_ID,
            ISDAMasterAgreement.ISDAVersionEnum.ISDA_2002,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            true, // AET enabled
            3, // 3-day grace period
            eventsOfDefault,
            terminationEvents,
            PARTY_A, // Calculation agent
            REGISTERED_BY
        );

        assertEq(isdaTerms.agreementId, MASTER_AGREEMENT_ID);
        assertTrue(isdaTerms.automaticEarlyTermination);
        assertTrue(isdaMaster.isCrossDefaultEnabled(MASTER_AGREEMENT_ID));

        // Step 3: Register CSA with netting terms
        CSA.NettingTerms memory nettingTerms = _createNDFNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createCollateralTerms();

        CSA.CSAgreement memory csaAgreement = csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            0, // Evergreen
            REGISTERED_BY
        );

        assertEq(csaAgreement.csaId, CSA_ID);
        assertTrue(csa.isPaymentNettingEnabled(CSA_ID));
        assertTrue(csa.isCloseOutNettingEnabled(CSA_ID));
        assertTrue(csa.isMultiCurrencyNettingEnabled(CSA_ID));

        // Step 4: Verify complete setup
        assertTrue(registry.hasActiveRelationship(PARTY_A, PARTY_B));
        assertEq(registry.getMasterAgreementForCSA(CSA_ID), MASTER_AGREEMENT_ID);
        assertTrue(csa.canNetProduct(CSA_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD));
    }

    // =============================================================================
    // NDF PORTFOLIO NETTING SCENARIO
    // =============================================================================

    function test_NDFPortfolio_FiveTradesWithNetting() public {
        // Setup: Master Agreement + CSA
        _setupMasterAgreementAndCSA();

        // Create netting set for NDF portfolio
        CSA.NettingSet memory nettingSet = csa.createNettingSet(
            NETTING_SET_NDF,
            CSA_ID,
            PORTFOLIO_NDF,
            PARTY_A
        );

        assertEq(nettingSet.nettingSetId, NETTING_SET_NDF);

        // Add 5 NDF trades to netting set
        bytes32 trade1 = keccak256("NDF_USD_JPY_001"); // $1M USD/JPY
        bytes32 trade2 = keccak256("NDF_USD_JPY_002"); // $500K USD/JPY
        bytes32 trade3 = keccak256("NDF_USD_JPY_003"); // -$800K USD/JPY (opposite direction)
        bytes32 trade4 = keccak256("NDF_EUR_USD_001"); // €2M EUR/USD
        bytes32 trade5 = keccak256("NDF_EUR_USD_002"); // -€1M EUR/USD (opposite direction)

        csa.addTradeToNettingSet(trade1, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("USD"));
        csa.addTradeToNettingSet(trade2, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("USD"));
        csa.addTradeToNettingSet(trade3, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("USD"));
        csa.addTradeToNettingSet(trade4, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("EUR"));
        csa.addTradeToNettingSet(trade5, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("EUR"));

        // Verify netting set contains all 5 trades
        CSA.NettingSet memory updatedSet = csa.getNettingSet(NETTING_SET_NDF);
        assertEq(updatedSet.tradeIds.length, 5);

        // Verify all trades can net together
        assertTrue(csa.canNetTrades(trade1, trade2));
        assertTrue(csa.canNetTrades(trade1, trade3));
        assertTrue(csa.canNetTrades(trade4, trade5));

        // In real scenario:
        // USD/JPY net position = $1M + $500K - $800K = $700K net
        // EUR/USD net position = €2M - €1M = €1M net
        // These would be netted via TransferEvent (Phase 3)
    }

    // =============================================================================
    // IRS PORTFOLIO WITH PAYMENT NETTING
    // =============================================================================

    function test_IRSPortfolio_QuarterlyPaymentNetting() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Create netting set for IRS portfolio
        csa.createNettingSet(NETTING_SET_IRS, CSA_ID, PORTFOLIO_IRS, PARTY_A);

        // Add 3 IRS trades (all with quarterly payments on same date)
        bytes32 irs1 = keccak256("IRS_USD_001"); // Receive fixed, pay floating
        bytes32 irs2 = keccak256("IRS_USD_002"); // Receive fixed, pay floating
        bytes32 irs3 = keccak256("IRS_USD_003"); // Pay fixed, receive floating

        csa.addTradeToNettingSet(irs1, NETTING_SET_IRS, CSA.ProductTypeEnum.INTEREST_RATE_SWAP, keccak256("USD"));
        csa.addTradeToNettingSet(irs2, NETTING_SET_IRS, CSA.ProductTypeEnum.INTEREST_RATE_SWAP, keccak256("USD"));
        csa.addTradeToNettingSet(irs3, NETTING_SET_IRS, CSA.ProductTypeEnum.INTEREST_RATE_SWAP, keccak256("USD"));

        // Verify payment netting is enabled
        assertTrue(csa.isPaymentNettingEnabled(CSA_ID));

        // Verify all trades can net
        assertTrue(csa.canNetTrades(irs1, irs2));
        assertTrue(csa.canNetTrades(irs2, irs3));

        // In real scenario: Quarterly payments would be netted via TransferEvent
        // If IRS1 pays $10K, IRS2 pays $8K, IRS3 receives $5K
        // Net payment = $10K + $8K - $5K = $13K net payment
    }

    // =============================================================================
    // MULTI-CURRENCY NETTING
    // =============================================================================

    function test_MultiCurrencyNetting_USDAndEUR() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Verify multi-currency netting is enabled
        assertTrue(csa.isMultiCurrencyNettingEnabled(CSA_ID));

        // Create netting set
        csa.createNettingSet(NETTING_SET_NDF, CSA_ID, PORTFOLIO_NDF, PARTY_A);

        // Add trades in different currencies
        bytes32 trade1 = keccak256("TRADE_USD_001");
        bytes32 trade2 = keccak256("TRADE_EUR_001");
        bytes32 trade3 = keccak256("TRADE_GBP_001");

        csa.addTradeToNettingSet(trade1, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("USD"));
        csa.addTradeToNettingSet(trade2, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("EUR"));
        csa.addTradeToNettingSet(trade3, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("GBP"));

        // Verify netting set has multiple currencies
        CSA.NettingSet memory nettingSet = csa.getNettingSet(NETTING_SET_NDF);
        assertEq(nettingSet.currencies.length, 3);

        // All trades in same netting set can net (with FX conversion)
        assertTrue(csa.canNetTrades(trade1, trade2));
        assertTrue(csa.canNetTrades(trade2, trade3));
    }

    // =============================================================================
    // EVENT OF DEFAULT SCENARIO
    // =============================================================================

    function test_EventOfDefault_FailureToPay_TriggersCloseOutNetting() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Verify AET is enabled
        assertTrue(isdaMaster.isAutomaticEarlyTerminationEnabled(MASTER_AGREEMENT_ID));

        // Create netting set with trades
        csa.createNettingSet(NETTING_SET_NDF, CSA_ID, PORTFOLIO_NDF, PARTY_A);

        bytes32 trade1 = keccak256("TRADE_001");
        bytes32 trade2 = keccak256("TRADE_002");

        csa.addTradeToNettingSet(trade1, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("USD"));
        csa.addTradeToNettingSet(trade2, NETTING_SET_NDF, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, keccak256("USD"));

        // Record Event of Default
        bytes32 eventId = keccak256("EVENT_OF_DEFAULT_001");

        ISDAMasterAgreement.EventOfDefaultRecord memory eventRecord = isdaMaster.recordEventOfDefault(
            eventId,
            MASTER_AGREEMENT_ID,
            ISDAMasterAgreement.EventOfDefaultEnum.FAILURE_TO_PAY_OR_DELIVER,
            PARTY_B, // Defaulting party
            PARTY_A, // Non-defaulting party
            block.timestamp,
            block.timestamp,
            keccak256("Failed to pay $1M on settlement date")
        );

        assertEq(eventRecord.eventId, eventId);
        assertEq(eventRecord.defaultingParty, PARTY_B);
        assertFalse(eventRecord.isResolved);

        // Verify close-out netting is enabled (would trigger automatic close-out)
        assertTrue(csa.isCloseOutNettingEnabled(CSA_ID));

        // In real scenario:
        // 1. Event of Default triggers Automatic Early Termination (AET)
        // 2. All trades in netting sets are closed out
        // 3. Net position is calculated (close-out netting)
        // 4. Single net payment is made (via TerminationEvent from Phase 3)
    }

    // =============================================================================
    // TERMINATION EVENT SCENARIO
    // =============================================================================

    function test_TerminationEvent_Illegality() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Record Termination Event (Illegality)
        bytes32 eventId = keccak256("TERMINATION_EVENT_001");

        ISDAMasterAgreement.TerminationEventRecord memory eventRecord = isdaMaster.recordTerminationEvent(
            eventId,
            MASTER_AGREEMENT_ID,
            ISDAMasterAgreement.TerminationEventEnum.ILLEGALITY,
            PARTY_A, // Affected party
            block.timestamp,
            block.timestamp,
            keccak256("New regulations make these transactions illegal")
        );

        assertEq(eventRecord.eventId, eventId);
        assertEq(eventRecord.affectedParty, PARTY_A);
        assertFalse(eventRecord.isResolved);

        // Verify illegality provision is applicable
        assertTrue(isdaMaster.isTerminationEventApplicable(
            MASTER_AGREEMENT_ID,
            ISDAMasterAgreement.TerminationEventEnum.ILLEGALITY
        ));

        // In real scenario:
        // 1. Affected party can terminate affected transactions
        // 2. Close-out netting applies if CSA enables it
        // 3. Settlement payments calculated and made
    }

    // =============================================================================
    // COLLATERAL CALL SCENARIO
    // =============================================================================

    function test_CollateralCall_ThresholdExceeded() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Get collateral terms
        uint256 threshold = csa.getCollateralThreshold(CSA_ID);
        assertEq(threshold, 100_000 * ONE); // $100,000 threshold

        // Verify minimum transfer amount
        CSA.CSAgreement memory csaAgreement = csa.getCSA(CSA_ID);
        assertEq(csaAgreement.collateralTerms.minimumTransferAmount, 10_000 * ONE); // $10,000 min

        // In real scenario:
        // 1. Mark-to-market exposure is calculated
        // 2. If exposure > threshold + minimumTransferAmount
        // 3. Collateral call is made
        // 4. Eligible collateral is transferred (CASH_USD, GOVERNMENT_BONDS, etc.)
    }

    // =============================================================================
    // CALCULATION AGENT ROLE
    // =============================================================================

    function test_CalculationAgent_Designation() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Verify calculation agent is designated
        bytes32 calcAgent = isdaMaster.getCalculationAgent(MASTER_AGREEMENT_ID);
        assertEq(calcAgent, PARTY_A);

        // Update calculation agent
        isdaMaster.updateCalculationAgent(MASTER_AGREEMENT_ID, PARTY_B, PARTY_A);

        bytes32 newCalcAgent = isdaMaster.getCalculationAgent(MASTER_AGREEMENT_ID);
        assertEq(newCalcAgent, PARTY_B);

        // In real scenario:
        // Calculation agent is responsible for:
        // - Determining close-out amounts
        // - Calculating termination payments
        // - Resolving disputes over valuations
    }

    // =============================================================================
    // CSA AMENDMENT SCENARIO
    // =============================================================================

    function test_CSAAmendment_UpdateCollateralTerms() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Original terms
        uint256 originalThreshold = csa.getCollateralThreshold(CSA_ID);
        assertEq(originalThreshold, 100_000 * ONE);

        // Amend collateral terms (both parties agree to increase threshold)
        CSA.CollateralTerms memory newTerms = _createCollateralTerms();
        newTerms.threshold = 250_000 * ONE; // Increase to $250,000
        newTerms.minimumTransferAmount = 25_000 * ONE; // Increase to $25,000

        csa.updateCollateralTerms(CSA_ID, newTerms, PARTY_A);

        // Verify updated terms
        uint256 newThreshold = csa.getCollateralThreshold(CSA_ID);
        assertEq(newThreshold, 250_000 * ONE);

        CSA.CSAgreement memory csaAgreement = csa.getCSA(CSA_ID);
        assertEq(csaAgreement.collateralTerms.minimumTransferAmount, 25_000 * ONE);
    }

    // =============================================================================
    // CROSS-DEFAULT SCENARIO
    // =============================================================================

    function test_CrossDefault_ThresholdConfiguration() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Verify cross-default is enabled
        assertTrue(isdaMaster.isCrossDefaultEnabled(MASTER_AGREEMENT_ID));

        // Set cross-default threshold
        isdaMaster.updateCrossDefaultThreshold(MASTER_AGREEMENT_ID, 1_000_000 * ONE); // $1M threshold

        ISDAMasterAgreement.ISDATerms memory terms = isdaMaster.getISDATerms(MASTER_AGREEMENT_ID);
        assertEq(terms.crossDefaultThreshold, 1_000_000 * ONE);

        // In real scenario:
        // If Party B defaults on another agreement with amount > threshold
        // → Event of Default under this ISDA Master Agreement
        // → Triggers AET and close-out netting
    }

    // =============================================================================
    // GRACE PERIOD SCENARIO
    // =============================================================================

    function test_GracePeriod_PaymentDefault() public {
        // Setup
        _setupMasterAgreementAndCSA();

        // Verify grace period
        uint256 gracePeriod = isdaMaster.getGracePeriod(MASTER_AGREEMENT_ID);
        assertEq(gracePeriod, 3); // 3 days

        // In real scenario:
        // 1. Payment is due on Day 0
        // 2. Payment not received on Day 0
        // 3. Grace period: Days 1-3
        // 4. If payment received during grace period: No Event of Default
        // 5. If Day 3 ends without payment: Event of Default triggered
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _setupMasterAgreementAndCSA() internal {
        // Register Master Agreement
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        registry.registerMasterAgreement(
            MASTER_AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            0,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            keccak256("ipfs://Qm..."),
            REGISTERED_BY
        );

        // Register ISDA Terms
        ISDAMasterAgreement.EventOfDefaultEnum[] memory eventsOfDefault = new ISDAMasterAgreement.EventOfDefaultEnum[](3);
        eventsOfDefault[0] = ISDAMasterAgreement.EventOfDefaultEnum.FAILURE_TO_PAY_OR_DELIVER;
        eventsOfDefault[1] = ISDAMasterAgreement.EventOfDefaultEnum.BANKRUPTCY;
        eventsOfDefault[2] = ISDAMasterAgreement.EventOfDefaultEnum.CROSS_DEFAULT;

        ISDAMasterAgreement.TerminationEventEnum[] memory terminationEvents = new ISDAMasterAgreement.TerminationEventEnum[](2);
        terminationEvents[0] = ISDAMasterAgreement.TerminationEventEnum.ILLEGALITY;
        terminationEvents[1] = ISDAMasterAgreement.TerminationEventEnum.TAX_EVENT;

        isdaMaster.registerISDATerms(
            MASTER_AGREEMENT_ID,
            ISDAMasterAgreement.ISDAVersionEnum.ISDA_2002,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            true,
            3,
            eventsOfDefault,
            terminationEvents,
            PARTY_A,
            REGISTERED_BY
        );

        // Register CSA
        CSA.NettingTerms memory nettingTerms = _createNDFNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createCollateralTerms();

        csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            0,
            REGISTERED_BY
        );
    }

    function _createNDFNettingTerms() internal pure returns (CSA.NettingTerms memory) {
        CSA.ProductTypeEnum[] memory eligibleProducts = new CSA.ProductTypeEnum[](3);
        eligibleProducts[0] = CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD;
        eligibleProducts[1] = CSA.ProductTypeEnum.INTEREST_RATE_SWAP;
        eligibleProducts[2] = CSA.ProductTypeEnum.FX_FORWARD;

        return CSA.NettingTerms({
            closeOutNettingEnabled: true,
            paymentNettingEnabled: true,
            multiCurrencyNettingEnabled: true,
            eligibleProducts: eligibleProducts,
            settlementThreshold: 1_000 * ONE,
            calculationAgent: PARTY_A
        });
    }

    function _createCollateralTerms() internal pure returns (CSA.CollateralTerms memory) {
        CSA.CollateralTypeEnum[] memory eligibleCollateral = new CSA.CollateralTypeEnum[](2);
        eligibleCollateral[0] = CSA.CollateralTypeEnum.CASH_USD;
        eligibleCollateral[1] = CSA.CollateralTypeEnum.GOVERNMENT_BONDS;

        return CSA.CollateralTerms({
            threshold: 100_000 * ONE,
            minimumTransferAmount: 10_000 * ONE,
            independentAmount: 0,
            eligibleCollateral: eligibleCollateral,
            valuationFrequency: 1 days,
            isCashOnly: false,
            haircut: 5e16
        });
    }
}
