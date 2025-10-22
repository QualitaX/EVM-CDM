// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NettingEngine} from "../../../src/portfolio/NettingEngine.sol";
import {Portfolio} from "../../../src/portfolio/Portfolio.sol";
import {CSA} from "../../../src/agreements/CSA.sol";
import {AgreementRegistry} from "../../../src/agreements/AgreementRegistry.sol";
import {ISDAMasterAgreement} from "../../../src/agreements/ISDAMasterAgreement.sol";

/**
 * @title NettingEngine Unit Tests
 * @notice Comprehensive tests for NettingEngine contract
 */
contract NettingEngineTest is Test {
    NettingEngine public nettingEngine;
    Portfolio public portfolioContract;
    CSA public csa;
    AgreementRegistry public registry;
    ISDAMasterAgreement public isdaMaster;

    // Test constants
    bytes32 constant PORTFOLIO_ID = keccak256("PORTFOLIO_001");
    bytes32 constant CSA_ID = keccak256("CSA_001");
    bytes32 constant NETTING_SET_ID = keccak256("NETTING_SET_001");
    bytes32 constant MASTER_AGREEMENT_ID = keccak256("MASTER_001");
    bytes32 constant NETTING_ID_1 = keccak256("NETTING_001");
    bytes32 constant NETTING_ID_2 = keccak256("NETTING_002");
    bytes32 constant TRADE_ID_1 = keccak256("TRADE_001");
    bytes32 constant TRADE_ID_2 = keccak256("TRADE_002");
    bytes32 constant TRADE_ID_3 = keccak256("TRADE_003");
    bytes32 constant PARTY_A = keccak256("PARTY_A");
    bytes32 constant PARTY_B = keccak256("PARTY_B");
    bytes32 constant CURRENCY_USD = keccak256("USD");
    bytes32 constant CURRENCY_EUR = keccak256("EUR");

    uint256 constant EFFECTIVE_DATE = 1_700_000_000;
    uint256 constant TERMINATION_DATE = 1_800_000_000;
    uint256 constant SETTLEMENT_DATE = 1_750_000_000;

    function setUp() public {
        // Deploy contracts
        registry = new AgreementRegistry();
        csa = new CSA(registry);
        isdaMaster = new ISDAMasterAgreement(registry);
        portfolioContract = new Portfolio(csa, registry);
        nettingEngine = new NettingEngine(portfolioContract, csa, registry, isdaMaster);

        // Setup master agreement and CSA
        _setupAgreements();

        // Create portfolio
        _createPortfolio();
    }

    // =============================================================================
    // PAYMENT NETTING TESTS
    // =============================================================================

    function test_CalculatePaymentNetting_SingleCurrency() public {
        NettingEngine.PaymentNettingInput[] memory payments = new NettingEngine.PaymentNettingInput[](3);

        payments[0] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_1,
            paymentAmount: 1_000_000 * 1e18,
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_A,
            receiver: PARTY_B
        });

        payments[1] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_2,
            paymentAmount: -800_000 * 1e18,
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_B,
            receiver: PARTY_A
        });

        payments[2] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_3,
            paymentAmount: 500_000 * 1e18,
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_A,
            receiver: PARTY_B
        });

        NettingEngine.PaymentNettingResult[] memory results = nettingEngine.calculatePaymentNetting(
            NETTING_ID_1,
            PORTFOLIO_ID,
            payments,
            PARTY_A
        );

        assertEq(results.length, 1);
        assertEq(results[0].currency, CURRENCY_USD);
        assertEq(results[0].netAmount, 700_000 * 1e18);  // 1M + 500K - 800K
        assertEq(results[0].tradeCount, 3);
    }

    function test_CalculatePaymentNetting_RevertIf_NoPayments() public {
        NettingEngine.PaymentNettingInput[] memory payments = new NettingEngine.PaymentNettingInput[](0);

        vm.expectRevert(NettingEngine.NoPayments.selector);
        nettingEngine.calculatePaymentNetting(NETTING_ID_1, PORTFOLIO_ID, payments, PARTY_A);
    }

    function test_CalculatePaymentNetting_RevertIf_PortfolioNotFound() public {
        NettingEngine.PaymentNettingInput[] memory payments = new NettingEngine.PaymentNettingInput[](1);
        payments[0] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_1,
            paymentAmount: 1_000_000 * 1e18,
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_A,
            receiver: PARTY_B
        });

        bytes32 invalidPortfolio = keccak256("INVALID");
        vm.expectRevert(abi.encodeWithSelector(NettingEngine.PortfolioNotFound.selector, invalidPortfolio));
        nettingEngine.calculatePaymentNetting(NETTING_ID_1, invalidPortfolio, payments, PARTY_A);
    }

    // =============================================================================
    // CLOSE-OUT NETTING TESTS
    // =============================================================================

    function test_CalculateCloseOutNetting_Success() public {
        NettingEngine.CloseOutNettingInput[] memory trades = new NettingEngine.CloseOutNettingInput[](3);

        trades[0] = NettingEngine.CloseOutNettingInput({
            tradeId: TRADE_ID_1,
            mtm: 500_000 * 1e18,
            currency: CURRENCY_USD
        });

        trades[1] = NettingEngine.CloseOutNettingInput({
            tradeId: TRADE_ID_2,
            mtm: -800_000 * 1e18,
            currency: CURRENCY_USD
        });

        trades[2] = NettingEngine.CloseOutNettingInput({
            tradeId: TRADE_ID_3,
            mtm: 200_000 * 1e18,
            currency: CURRENCY_USD
        });

        NettingEngine.CloseOutNettingResult memory result = nettingEngine.calculateCloseOutNetting(
            NETTING_ID_1,
            PORTFOLIO_ID,
            trades,
            CURRENCY_USD,
            bytes32(0),  // No event of default for this test
            PARTY_A
        );

        assertEq(result.netCloseOut, -100_000 * 1e18);  // 500K - 800K + 200K
        assertEq(result.baseCurrency, CURRENCY_USD);
        assertEq(result.tradeCount, 3);
    }

    function test_CalculateCloseOutNetting_RevertIf_NoTrades() public {
        NettingEngine.CloseOutNettingInput[] memory trades = new NettingEngine.CloseOutNettingInput[](0);

        vm.expectRevert(NettingEngine.InvalidNettingInputs.selector);
        nettingEngine.calculateCloseOutNetting(
            NETTING_ID_1,
            PORTFOLIO_ID,
            trades,
            CURRENCY_USD,
            bytes32(0),
            PARTY_A
        );
    }

    // =============================================================================
    // MULTI-CURRENCY NETTING TESTS
    // =============================================================================

    function test_CalculateMultiCurrencyNetting_Success() public {
        NettingEngine.MultiCurrencyNettingInput[] memory inputs = new NettingEngine.MultiCurrencyNettingInput[](2);

        // USD: -500,000
        inputs[0] = NettingEngine.MultiCurrencyNettingInput({
            currency: CURRENCY_USD,
            netAmount: -500_000 * 1e18,
            fxRate: 1e18  // USD to USD rate = 1.0
        });

        // EUR: +300,000 at rate 1.10
        inputs[1] = NettingEngine.MultiCurrencyNettingInput({
            currency: CURRENCY_EUR,
            netAmount: 300_000 * 1e18,
            fxRate: 110 * 1e16  // 1.10
        });

        NettingEngine.MultiCurrencyNettingResult memory result = nettingEngine.calculateMultiCurrencyNetting(
            NETTING_ID_1,
            PORTFOLIO_ID,
            inputs,
            CURRENCY_USD,
            PARTY_A
        );

        // Expected: -500,000 + (300,000 * 1.10) = -500,000 + 330,000 = -170,000
        assertEq(result.netAmountBase, -170_000 * 1e18);
        assertEq(result.baseCurrency, CURRENCY_USD);
        assertEq(result.currencyCount, 2);
    }

    function test_CalculateMultiCurrencyNetting_RevertIf_InvalidFXRate() public {
        NettingEngine.MultiCurrencyNettingInput[] memory inputs = new NettingEngine.MultiCurrencyNettingInput[](1);

        inputs[0] = NettingEngine.MultiCurrencyNettingInput({
            currency: CURRENCY_USD,
            netAmount: 500_000 * 1e18,
            fxRate: 0  // Invalid rate
        });

        vm.expectRevert(NettingEngine.InvalidFXRate.selector);
        nettingEngine.calculateMultiCurrencyNetting(
            NETTING_ID_1,
            PORTFOLIO_ID,
            inputs,
            CURRENCY_USD,
            PARTY_A
        );
    }

    // =============================================================================
    // VALIDATION TESTS
    // =============================================================================

    function test_ValidateSettlementThreshold_AboveThreshold() public {
        // First calculate a netting
        NettingEngine.PaymentNettingInput[] memory payments = new NettingEngine.PaymentNettingInput[](1);
        payments[0] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_1,
            paymentAmount: 10_000_000 * 1e18,  // Above threshold
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_A,
            receiver: PARTY_B
        });

        nettingEngine.calculatePaymentNetting(NETTING_ID_1, PORTFOLIO_ID, payments, PARTY_A);

        // Validate threshold (CSA threshold is 1,000 USD)
        bool isValid = nettingEngine.validateSettlementThreshold(NETTING_ID_1, 10_000_000 * 1e18);
        assertTrue(isValid);
    }

    function test_ValidateNetting_Success() public {
        // First calculate a netting
        NettingEngine.PaymentNettingInput[] memory payments = new NettingEngine.PaymentNettingInput[](1);
        payments[0] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_1,
            paymentAmount: 1_000_000 * 1e18,
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_A,
            receiver: PARTY_B
        });

        nettingEngine.calculatePaymentNetting(NETTING_ID_1, PORTFOLIO_ID, payments, PARTY_A);

        // Validate
        nettingEngine.validateNetting(NETTING_ID_1);

        NettingEngine.NettingCalculation memory calc = nettingEngine.getNettingCalculation(NETTING_ID_1);
        assertEq(uint(calc.status), uint(NettingEngine.NettingStatusEnum.VALIDATED));
    }

    // =============================================================================
    // QUERY FUNCTION TESTS
    // =============================================================================

    function test_GetNettingCalculation_Success() public {
        NettingEngine.PaymentNettingInput[] memory payments = new NettingEngine.PaymentNettingInput[](1);
        payments[0] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_1,
            paymentAmount: 1_000_000 * 1e18,
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_A,
            receiver: PARTY_B
        });

        nettingEngine.calculatePaymentNetting(NETTING_ID_1, PORTFOLIO_ID, payments, PARTY_A);

        NettingEngine.NettingCalculation memory calc = nettingEngine.getNettingCalculation(NETTING_ID_1);

        assertEq(calc.nettingId, NETTING_ID_1);
        assertEq(calc.portfolioId, PORTFOLIO_ID);
        assertEq(calc.csaId, CSA_ID);
        assertEq(uint(calc.nettingType), uint(NettingEngine.NettingTypeEnum.PAYMENT));
    }

    function test_GetPaymentNettingResult_Success() public {
        NettingEngine.PaymentNettingInput[] memory payments = new NettingEngine.PaymentNettingInput[](1);
        payments[0] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_1,
            paymentAmount: 1_000_000 * 1e18,
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_A,
            receiver: PARTY_B
        });

        nettingEngine.calculatePaymentNetting(NETTING_ID_1, PORTFOLIO_ID, payments, PARTY_A);

        NettingEngine.PaymentNettingResult memory result = nettingEngine.getPaymentNettingResult(NETTING_ID_1, CURRENCY_USD);

        assertEq(result.currency, CURRENCY_USD);
        assertEq(result.netAmount, 1_000_000 * 1e18);
    }

    function test_GetPortfolioNettings_Success() public {
        NettingEngine.PaymentNettingInput[] memory payments = new NettingEngine.PaymentNettingInput[](1);
        payments[0] = NettingEngine.PaymentNettingInput({
            tradeId: TRADE_ID_1,
            paymentAmount: 1_000_000 * 1e18,
            currency: CURRENCY_USD,
            settlementDate: SETTLEMENT_DATE,
            payer: PARTY_A,
            receiver: PARTY_B
        });

        nettingEngine.calculatePaymentNetting(NETTING_ID_1, PORTFOLIO_ID, payments, PARTY_A);

        bytes32[] memory nettings = nettingEngine.getPortfolioNettings(PORTFOLIO_ID);
        assertEq(nettings.length, 1);
        assertEq(nettings[0], NETTING_ID_1);
    }

    // =============================================================================
    // HELPER FUNCTION TESTS
    // =============================================================================

    function test_Abs_PositiveValue() public {
        uint256 result = nettingEngine.abs(1_000_000 * 1e18);
        assertEq(result, 1_000_000 * 1e18);
    }

    function test_Abs_NegativeValue() public {
        uint256 result = nettingEngine.abs(-1_000_000 * 1e18);
        assertEq(result, 1_000_000 * 1e18);
    }

    function test_Abs_Zero() public {
        uint256 result = nettingEngine.abs(0);
        assertEq(result, 0);
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _setupAgreements() internal {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        // Register master agreement
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

        // Register CSA with netting enabled
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
            PARTY_A,
            1_000_000 * 1e18,
            100_000 * 1e18,
            500_000 * 1e18,
            eligibleCollateral,
            86400,
            false,
            5 * 1e16,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            PARTY_A
        );

        // Create netting set
        csa.createNettingSet(NETTING_SET_ID, CSA_ID, PORTFOLIO_ID, PARTY_A);
    }

    function _createPortfolio() internal {
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
