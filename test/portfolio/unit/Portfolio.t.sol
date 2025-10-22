// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Portfolio} from "../../../src/portfolio/Portfolio.sol";
import {CSA} from "../../../src/agreements/CSA.sol";
import {AgreementRegistry} from "../../../src/agreements/AgreementRegistry.sol";

/**
 * @title Portfolio Unit Tests
 * @notice Comprehensive tests for Portfolio contract
 */
contract PortfolioTest is Test {
    Portfolio public portfolioContract;
    CSA public csa;
    AgreementRegistry public registry;

    // Test constants
    bytes32 constant PORTFOLIO_ID = keccak256("PORTFOLIO_001");
    bytes32 constant CSA_ID = keccak256("CSA_001");
    bytes32 constant NETTING_SET_ID = keccak256("NETTING_SET_001");
    bytes32 constant MASTER_AGREEMENT_ID = keccak256("MASTER_001");
    bytes32 constant TRADE_ID_1 = keccak256("TRADE_001");
    bytes32 constant TRADE_ID_2 = keccak256("TRADE_002");
    bytes32 constant TRADE_ID_3 = keccak256("TRADE_003");
    bytes32 constant PARTY_A = keccak256("PARTY_A");
    bytes32 constant PARTY_B = keccak256("PARTY_B");
    bytes32 constant CURRENCY_USD = keccak256("USD");
    bytes32 constant CURRENCY_EUR = keccak256("EUR");

    uint256 constant EFFECTIVE_DATE = 1_700_000_000;
    uint256 constant TERMINATION_DATE = 1_800_000_000;

    function setUp() public {
        // Deploy contracts
        registry = new AgreementRegistry();
        csa = new CSA(registry);
        portfolioContract = new Portfolio(csa, registry);

        // Setup master agreement
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
            keccak256("document"),
            PARTY_A
        );

        // Setup CSA
        CSA.ProductTypeEnum[] memory eligibleProducts = new CSA.ProductTypeEnum[](1);
        eligibleProducts[0] = CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD;

        CSA.CollateralTypeEnum[] memory eligibleCollateral = new CSA.CollateralTypeEnum[](1);
        eligibleCollateral[0] = CSA.CollateralTypeEnum.CASH_USD;

        csa.registerCSA(
            CSA_ID,
            MASTER_AGREEMENT_ID,
            parties,
            true,  // closeOutNettingEnabled
            true,  // paymentNettingEnabled
            true,  // multiCurrencyNettingEnabled
            eligibleProducts,
            1000 * 1e18,  // settlementThreshold
            PARTY_A,      // calculationAgent
            1_000_000 * 1e18,  // threshold
            100_000 * 1e18,    // minimumTransferAmount
            500_000 * 1e18,    // independentAmount
            eligibleCollateral,
            86400,  // valuationFrequency
            false,  // isCashOnly
            5 * 1e16,  // haircut (5%)
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            PARTY_A
        );

        // Create netting set
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
    }

    // =============================================================================
    // PORTFOLIO CREATION TESTS
    // =============================================================================

    function test_CreatePortfolio_Success() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        Portfolio.PortfolioData memory portfolio = portfolioContract.createPortfolio(
            PORTFOLIO_ID,
            CSA_ID,
            NETTING_SET_ID,
            parties,
            PARTY_A
        );

        assertEq(portfolio.portfolioId, PORTFOLIO_ID);
        assertEq(portfolio.csaId, CSA_ID);
        assertEq(portfolio.nettingSetId, NETTING_SET_ID);
        assertEq(portfolio.parties.length, 2);
        assertEq(portfolio.parties[0], PARTY_A);
        assertEq(portfolio.parties[1], PARTY_B);
        assertEq(uint(portfolio.status), uint(Portfolio.PortfolioStatusEnum.ACTIVE));
    }

    function test_CreatePortfolio_RevertIf_AlreadyExists() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        portfolioContract.createPortfolio(PORTFOLIO_ID, CSA_ID, NETTING_SET_ID, parties, PARTY_A);

        vm.expectRevert(abi.encodeWithSelector(Portfolio.PortfolioAlreadyExists.selector, PORTFOLIO_ID));
        portfolioContract.createPortfolio(PORTFOLIO_ID, CSA_ID, NETTING_SET_ID, parties, PARTY_A);
    }

    function test_CreatePortfolio_RevertIf_CSANotFound() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        bytes32 invalidCSA = keccak256("INVALID_CSA");

        vm.expectRevert(abi.encodeWithSelector(Portfolio.CSANotFound.selector, invalidCSA));
        portfolioContract.createPortfolio(PORTFOLIO_ID, invalidCSA, NETTING_SET_ID, parties, PARTY_A);
    }

    function test_CreatePortfolio_RevertIf_InvalidParties() public {
        bytes32[] memory parties = new bytes32[](1);
        parties[0] = PARTY_A;

        vm.expectRevert(Portfolio.InvalidParties.selector);
        portfolioContract.createPortfolio(PORTFOLIO_ID, CSA_ID, NETTING_SET_ID, parties, PARTY_A);
    }

    // =============================================================================
    // TRADE MANAGEMENT TESTS
    // =============================================================================

    function test_AddTrade_Success() public {
        _createStandardPortfolio();

        portfolioContract.addTrade(
            PORTFOLIO_ID,
            TRADE_ID_1,
            CURRENCY_USD,
            1_000_000 * 1e18,  // MTM
            CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD
        );

        Portfolio.TradeValuation memory valuation = portfolioContract.getTradeValuation(
            PORTFOLIO_ID,
            TRADE_ID_1
        );

        assertEq(valuation.tradeId, TRADE_ID_1);
        assertEq(valuation.mtm, 1_000_000 * 1e18);
        assertEq(valuation.currency, CURRENCY_USD);
        assertTrue(valuation.isActive);
    }

    function test_AddTrade_MultipleTrades() public {
        _createStandardPortfolio();

        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_2, CURRENCY_USD, -800_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_3, CURRENCY_EUR, 500_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);

        Portfolio.PortfolioData memory portfolio = portfolioContract.getPortfolio(PORTFOLIO_ID);
        assertEq(portfolio.tradeIds.length, 3);
        assertEq(portfolio.activeTradeCount, 3);
    }

    function test_AddTrade_RevertIf_PortfolioNotFound() public {
        bytes32 invalidPortfolio = keccak256("INVALID");

        vm.expectRevert(abi.encodeWithSelector(Portfolio.PortfolioNotFound.selector, invalidPortfolio));
        portfolioContract.addTrade(
            invalidPortfolio,
            TRADE_ID_1,
            CURRENCY_USD,
            1_000_000 * 1e18,
            CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD
        );
    }

    function test_AddTrade_RevertIf_TradeAlreadyInPortfolio() public {
        _createStandardPortfolio();

        portfolioContract.addTrade(
            PORTFOLIO_ID,
            TRADE_ID_1,
            CURRENCY_USD,
            1_000_000 * 1e18,
            CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD
        );

        vm.expectRevert(abi.encodeWithSelector(Portfolio.TradeAlreadyInPortfolio.selector, TRADE_ID_1));
        portfolioContract.addTrade(
            PORTFOLIO_ID,
            TRADE_ID_1,
            CURRENCY_USD,
            500_000 * 1e18,
            CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD
        );
    }

    function test_RemoveTrade_Success() public {
        _createStandardPortfolio();
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);

        portfolioContract.removeTrade(PORTFOLIO_ID, TRADE_ID_1);

        Portfolio.TradeValuation memory valuation = portfolioContract.getTradeValuation(PORTFOLIO_ID, TRADE_ID_1);
        assertFalse(valuation.isActive);

        Portfolio.PortfolioData memory portfolio = portfolioContract.getPortfolio(PORTFOLIO_ID);
        assertEq(portfolio.activeTradeCount, 0);
    }

    // =============================================================================
    // VALUATION TESTS
    // =============================================================================

    function test_UpdateTradeValuation_Success() public {
        _createStandardPortfolio();
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);

        portfolioContract.updateTradeValuation(PORTFOLIO_ID, TRADE_ID_1, 1_200_000 * 1e18);

        Portfolio.TradeValuation memory valuation = portfolioContract.getTradeValuation(PORTFOLIO_ID, TRADE_ID_1);
        assertEq(valuation.mtm, 1_200_000 * 1e18);
    }

    function test_RevaluePortfolio_Success() public {
        _createStandardPortfolio();
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_2, CURRENCY_USD, -800_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);

        bytes32[] memory tradeIds = new bytes32[](2);
        tradeIds[0] = TRADE_ID_1;
        tradeIds[1] = TRADE_ID_2;

        int256[] memory mtms = new int256[](2);
        mtms[0] = 1_100_000 * 1e18;
        mtms[1] = -900_000 * 1e18;

        portfolioContract.revaluePortfolio(PORTFOLIO_ID, tradeIds, mtms);

        Portfolio.TradeValuation memory val1 = portfolioContract.getTradeValuation(PORTFOLIO_ID, TRADE_ID_1);
        Portfolio.TradeValuation memory val2 = portfolioContract.getTradeValuation(PORTFOLIO_ID, TRADE_ID_2);

        assertEq(val1.mtm, 1_100_000 * 1e18);
        assertEq(val2.mtm, -900_000 * 1e18);
    }

    // =============================================================================
    // CURRENCY EXPOSURE TESTS
    // =============================================================================

    function test_GetCurrencyExposure_SingleCurrency() public {
        _createStandardPortfolio();
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_2, CURRENCY_USD, -800_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);

        Portfolio.CurrencyExposure memory exposure = portfolioContract.getCurrencyExposure(PORTFOLIO_ID, CURRENCY_USD);

        assertEq(exposure.currency, CURRENCY_USD);
        assertEq(exposure.totalMtm, 200_000 * 1e18);
        assertEq(exposure.positiveExposure, 1_000_000 * 1e18);
        assertEq(exposure.negativeExposure, -800_000 * 1e18);
    }

    function test_GetCurrencyExposure_MultiCurrency() public {
        _createStandardPortfolio();
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_2, CURRENCY_EUR, 500_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);

        bytes32[] memory currencies = portfolioContract.getPortfolioCurrencies(PORTFOLIO_ID);
        assertEq(currencies.length, 2);
    }

    // =============================================================================
    // QUERY FUNCTION TESTS
    // =============================================================================

    function test_GetPortfolio_Success() public {
        _createStandardPortfolio();

        Portfolio.PortfolioData memory portfolio = portfolioContract.getPortfolio(PORTFOLIO_ID);

        assertEq(portfolio.portfolioId, PORTFOLIO_ID);
        assertEq(portfolio.csaId, CSA_ID);
        assertEq(portfolio.nettingSetId, NETTING_SET_ID);
    }

    function test_GetPortfolio_RevertIf_NotFound() public {
        bytes32 invalidId = keccak256("INVALID");

        vm.expectRevert(abi.encodeWithSelector(Portfolio.PortfolioNotFound.selector, invalidId));
        portfolioContract.getPortfolio(invalidId);
    }

    function test_HasActiveTrades_True() public {
        _createStandardPortfolio();
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);

        assertTrue(portfolioContract.hasActiveTrades(PORTFOLIO_ID));
    }

    function test_HasActiveTrades_False() public {
        _createStandardPortfolio();

        assertFalse(portfolioContract.hasActiveTrades(PORTFOLIO_ID));
    }

    function test_GetPortfolioForTrade_Success() public {
        _createStandardPortfolio();
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);

        bytes32 foundPortfolio = portfolioContract.getPortfolioForTrade(TRADE_ID_1);
        assertEq(foundPortfolio, PORTFOLIO_ID);
    }

    function test_GetCSAPortfolios_Success() public {
        _createStandardPortfolio();

        bytes32[] memory portfolios = portfolioContract.getCSAPortfolios(CSA_ID);
        assertEq(portfolios.length, 1);
        assertEq(portfolios[0], PORTFOLIO_ID);
    }

    // =============================================================================
    // PORTFOLIO STATUS TESTS
    // =============================================================================

    function test_ChangePortfolioStatus_Success() public {
        _createStandardPortfolio();

        portfolioContract.changePortfolioStatus(PORTFOLIO_ID, Portfolio.PortfolioStatusEnum.SUSPENDED);

        Portfolio.PortfolioData memory portfolio = portfolioContract.getPortfolio(PORTFOLIO_ID);
        assertEq(uint(portfolio.status), uint(Portfolio.PortfolioStatusEnum.SUSPENDED));
    }

    function test_PortfolioStatusChanges_ToClosedWhenNoTrades() public {
        _createStandardPortfolio();
        portfolioContract.addTrade(PORTFOLIO_ID, TRADE_ID_1, CURRENCY_USD, 1_000_000 * 1e18, CSA.ProductTypeEnum.NON_DELIVERABLE_FORWARD);
        portfolioContract.removeTrade(PORTFOLIO_ID, TRADE_ID_1);

        Portfolio.PortfolioData memory portfolio = portfolioContract.getPortfolio(PORTFOLIO_ID);
        assertEq(uint(portfolio.status), uint(Portfolio.PortfolioStatusEnum.CLOSED));
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _createStandardPortfolio() internal {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        portfolioContract.createPortfolio(
            PORTFOLIO_ID,
            CSA_ID,
            NETTING_SET_ID,
            parties,
            PARTY_A
        );
    }
}
