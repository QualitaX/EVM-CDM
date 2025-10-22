// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/agreements/CSA.sol";
import "../../../src/agreements/AgreementRegistry.sol";

/**
 * @title CSATest
 * @notice Comprehensive unit tests for CSA contract
 */
contract CSATest is Test {
    CSA public csa;
    AgreementRegistry public registry;

    // Test constants
    bytes32 constant MASTER_AGREEMENT_ID = keccak256("ISDA_MASTER_001");
    bytes32 constant CSA_ID = keccak256("CSA_001");
    bytes32 constant PARTY_A = keccak256("PARTY_A");
    bytes32 constant PARTY_B = keccak256("PARTY_B");
    bytes32 constant NETTING_SET_ID = keccak256("NETTING_SET_001");
    bytes32 constant PORTFOLIO_ID = keccak256("PORTFOLIO_001");
    bytes32 constant TRADE_ID_1 = keccak256("TRADE_001");
    bytes32 constant TRADE_ID_2 = keccak256("TRADE_002");
    bytes32 constant TRADE_ID_3 = keccak256("TRADE_003");
    bytes32 constant CURRENCY_USD = keccak256("USD");
    bytes32 constant CURRENCY_EUR = keccak256("EUR");
    bytes32 constant REGISTERED_BY = keccak256("REGISTRAR");

    uint256 constant EFFECTIVE_DATE = 1704067200; // Jan 1, 2024
    uint256 constant TERMINATION_DATE = 1735689600; // Jan 1, 2025
    uint256 constant ONE = 1e18;

    function setUp() public {
        registry = new AgreementRegistry();
        csa = new CSA(address(registry));

        _registerMasterAgreement();
    }

    // =============================================================================
    // CSA REGISTRATION TESTS
    // =============================================================================

    function test_RegisterCSA_Success() public {
        CSA.NettingTerms memory nettingTerms = _createStandardNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createStandardCollateralTerms();

        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        CSA.CSAgreement memory csaAgreement = csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            REGISTERED_BY
        );

        assertEq(csaAgreement.csaId, CSA_ID);
        assertEq(csaAgreement.masterAgreementId, MASTER_AGREEMENT_ID);
        assertEq(csaAgreement.parties.length, 2);
        assertTrue(csaAgreement.nettingTerms.paymentNettingEnabled);
        assertEq(csaAgreement.collateralTerms.threshold, 100_000 * ONE);
        assertEq(uint8(csaAgreement.status), uint8(CSA.CSAStatusEnum.ACTIVE));
    }

    function test_RegisterCSA_UpdatesCounters() public {
        assertEq(csa.totalCSAs(), 0);

        _registerStandardCSA();

        assertEq(csa.totalCSAs(), 1);
    }

    function test_RegisterCSA_AttachesToMasterAgreement() public {
        _registerStandardCSA();

        bytes32 masterAgreementId = registry.getMasterAgreementForCSA(CSA_ID);
        assertEq(masterAgreementId, MASTER_AGREEMENT_ID);
    }

    function test_RegisterCSA_RevertWhen_CSAAlreadyExists() public {
        _registerStandardCSA();

        CSA.NettingTerms memory nettingTerms = _createStandardNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createStandardCollateralTerms();

        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectRevert(CSA.CSA__CSAAlreadyExists.selector);
        csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            REGISTERED_BY
        );
    }

    function test_RegisterCSA_RevertWhen_MasterAgreementDoesNotExist() public {
        bytes32 invalidMasterId = keccak256("INVALID");
        CSA.NettingTerms memory nettingTerms = _createStandardNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createStandardCollateralTerms();

        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectRevert(CSA.CSA__MasterAgreementDoesNotExist.selector);
        csa.registerCSA(
            CSA_ID,
            invalidMasterId,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            REGISTERED_BY
        );
    }

    function test_RegisterCSA_RevertWhen_InvalidParties() public {
        CSA.NettingTerms memory nettingTerms = _createStandardNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createStandardCollateralTerms();

        bytes32[] memory parties = new bytes32[](1);
        parties[0] = PARTY_A;

        vm.expectRevert(CSA.CSA__InvalidParties.selector);
        csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            REGISTERED_BY
        );
    }

    function test_RegisterCSA_RevertWhen_InvalidDates() public {
        CSA.NettingTerms memory nettingTerms = _createStandardNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createStandardCollateralTerms();

        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectRevert(CSA.CSA__InvalidDates.selector);
        csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            EFFECTIVE_DATE - 1, // Invalid
            REGISTERED_BY
        );
    }

    function test_RegisterCSA_RevertWhen_NoEligibleProducts() public {
        CSA.NettingTerms memory nettingTerms = _createStandardNettingTerms();
        nettingTerms.eligibleProducts = new CSA.ProductTypeEnum[](0); // Empty

        CSA.CollateralTerms memory collateralTerms = _createStandardCollateralTerms();

        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectRevert(CSA.CSA__InvalidNettingTerms.selector);
        csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            REGISTERED_BY
        );
    }

    function test_RegisterCSA_RevertWhen_InvalidCollateralTerms() public {
        CSA.NettingTerms memory nettingTerms = _createStandardNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createStandardCollateralTerms();
        collateralTerms.minimumTransferAmount = collateralTerms.threshold + 1; // Invalid

        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectRevert(CSA.CSA__InvalidCollateralTerms.selector);
        csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            REGISTERED_BY
        );
    }

    // =============================================================================
    // NETTING SET TESTS
    // =============================================================================

    function test_CreateNettingSet_Success() public {
        _registerStandardCSA();

        CSA.NettingSet memory nettingSet = csa.createNettingSet(
            NETTING_SET_ID,
            CSA_ID,
            PORTFOLIO_ID,
            PARTY_A
        );

        assertEq(nettingSet.nettingSetId, NETTING_SET_ID);
        assertEq(nettingSet.csaId, CSA_ID);
        assertEq(nettingSet.portfolioId, PORTFOLIO_ID);
        assertEq(nettingSet.tradeIds.length, 0);
        assertTrue(nettingSet.isActive);
    }

    function test_CreateNettingSet_UpdatesCounters() public {
        _registerStandardCSA();
        assertEq(csa.totalNettingSets(), 0);

        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);

        assertEq(csa.totalNettingSets(), 1);
    }

    function test_CreateNettingSet_RevertWhen_CSADoesNotExist() public {
        vm.expectRevert(CSA.CSA__CSADoesNotExist.selector);
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
    }

    function test_CreateNettingSet_RevertWhen_CSANotActive() public {
        _registerStandardCSA();
        csa.updateCSAStatus(CSA_ID, CSA.CSAStatusEnum.SUSPENDED, PARTY_A);

        vm.expectRevert(CSA.CSA__CSANotActive.selector);
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
    }

    function test_CreateNettingSet_RevertWhen_AlreadyExists() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);

        vm.expectRevert(CSA.CSA__NettingSetAlreadyExists.selector);
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
    }

    // =============================================================================
    // TRADE MANAGEMENT TESTS
    // =============================================================================

    function test_AddTradeToNettingSet_Success() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);

        csa.addTradeToNettingSet(
            TRADE_ID_1,
            NETTING_SET_ID,
            CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD,
            CURRENCY_USD
        );

        CSA.NettingSet memory nettingSet = csa.getNettingSet(NETTING_SET_ID);
        assertEq(nettingSet.tradeIds.length, 1);
        assertEq(nettingSet.tradeIds[0], TRADE_ID_1);
        assertEq(nettingSet.productTypes.length, 1);
        assertEq(nettingSet.currencies.length, 1);
    }

    function test_AddTradeToNettingSet_MultipleTrades() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);

        csa.addTradeToNettingSet(TRADE_ID_1, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);
        csa.addTradeToNettingSet(TRADE_ID_2, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);
        csa.addTradeToNettingSet(TRADE_ID_3, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_EUR);

        CSA.NettingSet memory nettingSet = csa.getNettingSet(NETTING_SET_ID);
        assertEq(nettingSet.tradeIds.length, 3);
        assertEq(nettingSet.currencies.length, 2); // USD and EUR
    }

    function test_AddTradeToNettingSet_RevertWhen_NettingSetDoesNotExist() public {
        vm.expectRevert(CSA.CSA__NettingSetDoesNotExist.selector);
        csa.addTradeToNettingSet(TRADE_ID_1, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);
    }

    function test_AddTradeToNettingSet_RevertWhen_TradeAlreadyInSet() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
        csa.addTradeToNettingSet(TRADE_ID_1, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);

        vm.expectRevert(CSA.CSA__TradeAlreadyInNettingSet.selector);
        csa.addTradeToNettingSet(TRADE_ID_1, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);
    }

    function test_AddTradeToNettingSet_RevertWhen_ProductNotEligible() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);

        // CSA only allows NDF and IRS, not REPO
        vm.expectRevert(CSA.CSA__ProductTypeNotEligible.selector);
        csa.addTradeToNettingSet(TRADE_ID_1, NETTING_SET_ID, CSA.ProductTypeEnum.REPO, CURRENCY_USD);
    }

    function test_RemoveTradeFromNettingSet_Success() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
        csa.addTradeToNettingSet(TRADE_ID_1, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);

        csa.removeTradeFromNettingSet(TRADE_ID_1);

        CSA.NettingSet memory nettingSet = csa.getNettingSet(NETTING_SET_ID);
        assertEq(nettingSet.tradeIds.length, 0);
    }

    function test_RemoveTradeFromNettingSet_RevertWhen_TradeNotInSet() public {
        vm.expectRevert(CSA.CSA__TradeNotInNettingSet.selector);
        csa.removeTradeFromNettingSet(TRADE_ID_1);
    }

    // =============================================================================
    // CSA LIFECYCLE TESTS
    // =============================================================================

    function test_UpdateCSAStatus_Success() public {
        _registerStandardCSA();

        csa.updateCSAStatus(CSA_ID, CSA.CSAStatusEnum.SUSPENDED, PARTY_A);

        CSA.CSAgreement memory csaAgreement = csa.getCSA(CSA_ID);
        assertEq(uint8(csaAgreement.status), uint8(CSA.CSAStatusEnum.SUSPENDED));
    }

    function test_UpdateCSAStatus_RevertWhen_CSADoesNotExist() public {
        vm.expectRevert(CSA.CSA__CSADoesNotExist.selector);
        csa.updateCSAStatus(CSA_ID, CSA.CSAStatusEnum.SUSPENDED, PARTY_A);
    }

    function test_TerminateCSA_Success() public {
        _registerStandardCSA();

        csa.terminateCSA(CSA_ID, PARTY_A);

        CSA.CSAgreement memory csaAgreement = csa.getCSA(CSA_ID);
        assertEq(uint8(csaAgreement.status), uint8(CSA.CSAStatusEnum.TERMINATED));
    }

    function test_TerminateCSA_RevertWhen_CSADoesNotExist() public {
        vm.expectRevert(CSA.CSA__CSADoesNotExist.selector);
        csa.terminateCSA(CSA_ID, PARTY_A);
    }

    function test_UpdateCollateralTerms_Success() public {
        _registerStandardCSA();

        CSA.CollateralTerms memory newTerms = _createStandardCollateralTerms();
        newTerms.threshold = 200_000 * ONE;
        newTerms.minimumTransferAmount = 20_000 * ONE;

        csa.updateCollateralTerms(CSA_ID, newTerms, PARTY_A);

        CSA.CSAgreement memory csaAgreement = csa.getCSA(CSA_ID);
        assertEq(csaAgreement.collateralTerms.threshold, 200_000 * ONE);
        assertEq(csaAgreement.collateralTerms.minimumTransferAmount, 20_000 * ONE);
    }

    function test_UpdateCollateralTerms_RevertWhen_CSADoesNotExist() public {
        CSA.CollateralTerms memory newTerms = _createStandardCollateralTerms();

        vm.expectRevert(CSA.CSA__CSADoesNotExist.selector);
        csa.updateCollateralTerms(CSA_ID, newTerms, PARTY_A);
    }

    // =============================================================================
    // QUERY FUNCTION TESTS
    // =============================================================================

    function test_GetCSA_Success() public {
        _registerStandardCSA();

        CSA.CSAgreement memory csaAgreement = csa.getCSA(CSA_ID);
        assertEq(csaAgreement.csaId, CSA_ID);
    }

    function test_GetCSA_RevertWhen_DoesNotExist() public {
        vm.expectRevert(CSA.CSA__CSADoesNotExist.selector);
        csa.getCSA(CSA_ID);
    }

    function test_GetNettingSet_Success() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);

        CSA.NettingSet memory nettingSet = csa.getNettingSet(NETTING_SET_ID);
        assertEq(nettingSet.nettingSetId, NETTING_SET_ID);
    }

    function test_GetNettingSet_RevertWhen_DoesNotExist() public {
        vm.expectRevert(CSA.CSA__NettingSetDoesNotExist.selector);
        csa.getNettingSet(NETTING_SET_ID);
    }

    function test_GetNettingSetForTrade() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
        csa.addTradeToNettingSet(TRADE_ID_1, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);

        bytes32 nettingSetId = csa.getNettingSetForTrade(TRADE_ID_1);
        assertEq(nettingSetId, NETTING_SET_ID);
    }

    function test_GetNettingSetForPortfolio() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);

        bytes32 nettingSetId = csa.getNettingSetForPortfolio(PORTFOLIO_ID);
        assertEq(nettingSetId, NETTING_SET_ID);
    }

    function test_CanNetTrades_True() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
        csa.addTradeToNettingSet(TRADE_ID_1, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);
        csa.addTradeToNettingSet(TRADE_ID_2, NETTING_SET_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);

        assertTrue(csa.canNetTrades(TRADE_ID_1, TRADE_ID_2));
    }

    function test_CanNetTrades_False_DifferentNettingSets() public {
        _registerStandardCSA();

        bytes32 nettingSet1 = NETTING_SET_ID;
        bytes32 nettingSet2 = keccak256("NETTING_SET_002");
        bytes32 portfolio2 = keccak256("PORTFOLIO_002");

        csa.createNettingSet(nettingSet1, CSA_ID, PORTFOLIO_ID, PARTY_A);
        csa.createNettingSet(nettingSet2, CSA_ID, portfolio2, PARTY_A);

        csa.addTradeToNettingSet(TRADE_ID_1, nettingSet1, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);
        csa.addTradeToNettingSet(TRADE_ID_2, nettingSet2, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD, CURRENCY_USD);

        assertFalse(csa.canNetTrades(TRADE_ID_1, TRADE_ID_2));
    }

    function test_CanNetProduct_True() public {
        _registerStandardCSA();

        assertTrue(csa.canNetProduct(CSA_ID, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD));
        assertTrue(csa.canNetProduct(CSA_ID, CSA.ProductTypeEnum.INTEREST_RATE_SWAP));
    }

    function test_CanNetProduct_False() public {
        _registerStandardCSA();

        assertFalse(csa.canNetProduct(CSA_ID, CSA.ProductTypeEnum.REPO));
    }

    function test_IsPaymentNettingEnabled_True() public {
        _registerStandardCSA();

        assertTrue(csa.isPaymentNettingEnabled(CSA_ID));
    }

    function test_IsPaymentNettingEnabled_False() public {
        assertFalse(csa.isPaymentNettingEnabled(CSA_ID));
    }

    function test_IsCloseOutNettingEnabled_True() public {
        _registerStandardCSA();

        assertTrue(csa.isCloseOutNettingEnabled(CSA_ID));
    }

    function test_IsMultiCurrencyNettingEnabled_True() public {
        _registerStandardCSA();

        assertTrue(csa.isMultiCurrencyNettingEnabled(CSA_ID));
    }

    function test_GetCollateralThreshold() public {
        _registerStandardCSA();

        uint256 threshold = csa.getCollateralThreshold(CSA_ID);
        assertEq(threshold, 100_000 * ONE);
    }

    function test_GetCollateralThreshold_RevertWhen_CSADoesNotExist() public {
        vm.expectRevert(CSA.CSA__CSADoesNotExist.selector);
        csa.getCollateralThreshold(CSA_ID);
    }

    function test_GetCSAsBetweenParties() public {
        _registerStandardCSA();

        bytes32[] memory csaIds = csa.getCSAsBetweenParties(PARTY_A, PARTY_B);
        assertEq(csaIds.length, 1);
        assertEq(csaIds[0], CSA_ID);
    }

    function test_GetApplicableCSA() public {
        _registerStandardCSA();

        bytes32 csaId = csa.getApplicableCSA(PARTY_A, PARTY_B, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);
        assertEq(csaId, CSA_ID);
    }

    function test_GetApplicableCSA_NotFound_WrongProduct() public {
        _registerStandardCSA();

        bytes32 csaId = csa.getApplicableCSA(PARTY_A, PARTY_B, CSA.ProductTypeEnum.REPO);
        assertEq(csaId, bytes32(0));
    }

    function test_GetNettingSetsForCSA() public {
        _registerStandardCSA();
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);

        bytes32[] memory nettingSetIds = csa.getNettingSetsForCSA(CSA_ID);
        assertEq(nettingSetIds.length, 1);
        assertEq(nettingSetIds[0], NETTING_SET_ID);
    }

    function test_IsCSAActive_True() public {
        _registerStandardCSA();

        assertTrue(csa.isCSAActive(CSA_ID));
    }

    function test_IsCSAActive_False() public {
        _registerStandardCSA();
        csa.terminateCSA(CSA_ID, PARTY_A);

        assertFalse(csa.isCSAActive(CSA_ID));
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _registerMasterAgreement() internal {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        registry.registerMasterAgreement(
            MASTER_AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            keccak256("DOCUMENT_HASH"),
            REGISTERED_BY
        );
    }

    function _registerStandardCSA() internal {
        CSA.NettingTerms memory nettingTerms = _createStandardNettingTerms();
        CSA.CollateralTerms memory collateralTerms = _createStandardCollateralTerms();

        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            nettingTerms,
            collateralTerms,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            REGISTERED_BY
        );
    }

    function _createStandardNettingTerms() internal pure returns (CSA.NettingTerms memory) {
        CSA.ProductTypeEnum[] memory eligibleProducts = new CSA.ProductTypeEnum[](2);
        eligibleProducts[0] = CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD;
        eligibleProducts[1] = CSA.ProductTypeEnum.INTEREST_RATE_SWAP;

        return CSA.NettingTerms({
            closeOutNettingEnabled: true,
            paymentNettingEnabled: true,
            multiCurrencyNettingEnabled: true,
            eligibleProducts: eligibleProducts,
            settlementThreshold: 1_000 * ONE,
            calculationAgent: PARTY_A
        });
    }

    function _createStandardCollateralTerms() internal pure returns (CSA.CollateralTerms memory) {
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
            haircut: 5e16 // 5%
        });
    }
}
