// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {NonDeliverableForward} from "../../../src/products/NonDeliverableForward.sol";
import {FixedPoint} from "../../../src/base/libraries/FixedPoint.sol";
import {
    BusinessDayConventionEnum,
    BusinessCenterEnum
} from "../../../src/base/types/Enums.sol";
import {BusinessDayAdjustments} from "../../../src/base/types/CDMTypes.sol";

/**
 * @title NonDeliverableForwardTest
 * @notice Comprehensive test suite for NonDeliverableForward contract
 * @dev Tests FX NDF derivatives with cash settlement
 *
 * TEST COVERAGE:
 * 1. Validation Tests (5 tests)
 * 2. Settlement Calculation Tests (8 tests)
 * 3. MTM Calculation Tests (5 tests)
 * 4. Helper Function Tests (5 tests)
 * 5. Real-World Scenarios (5 tests)
 * 6. Edge Cases (3 tests)
 *
 * TOTAL: 31 tests
 */
contract NonDeliverableForwardTest is Test {
    using FixedPoint for uint256;

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    NonDeliverableForward public ndf;

    uint256 constant ONE = 1e18;

    // Test parameters
    bytes32 constant BUYER = bytes32("BUYER");
    bytes32 constant SELLER = bytes32("SELLER");
    bytes32 constant USD = bytes32("USD");
    bytes32 constant CNY = bytes32("CNY");
    bytes32 constant BRL = bytes32("BRL");
    bytes32 constant INR = bytes32("INR");
    bytes32 constant KRW = bytes32("KRW");

    // Standard dates
    uint256 constant TRADE_DATE = 1735689600; // 2025-01-01
    uint256 constant FIXING_DATE = 1743465600; // 2025-04-01 (3 months later)
    uint256 constant SETTLEMENT_DATE = 1743724800; // 2025-04-04 (T+2)

    // =============================================================================
    // SETUP
    // =============================================================================

    function setUp() public {
        ndf = new NonDeliverableForward();
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    /**
     * @notice Create a standard 3-month NDF
     */
    function _createStandardNDF(
        uint256 notional,
        uint256 forwardRate
    ) internal pure returns (NonDeliverableForward.NDFSpec memory spec) {
        spec = NonDeliverableForward.NDFSpec({
            ndfId: bytes32("NDF001"),
            tradeId: bytes32("NDF001"),
            tradeDate: TRADE_DATE,
            buyerReference: BUYER,
            sellerReference: SELLER,
            settlementCurrency: USD,
            nonDeliverableCurrency: CNY,
            notionalAmount: notional,
            forwardRate: forwardRate,
            fixingDate: FIXING_DATE,
            settlementDate: SETTLEMENT_DATE,
            fixingSource: bytes32("PBOC"),
            settlementAdjustments: BusinessDayAdjustments({
                convention: BusinessDayConventionEnum.FOLLOWING,
                businessCenters: new BusinessCenterEnum[](0)
            }),
            metaGlobalKey: keccak256(abi.encode(bytes32("NDF001")))
        });

        return spec;
    }

    // =============================================================================
    // VALIDATION TESTS
    // =============================================================================

    function test_ValidateNDFSpec_Valid() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,  // $10M
            715e16             // 7.15 CNY/USD
        );

        bool valid = ndf.validateNDFSpec(spec);
        assertTrue(valid, "NDF should be valid");
    }

    function test_ValidateNDFSpec_ZeroNotional() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        spec.notionalAmount = 0;

        bool valid = ndf.validateNDFSpec(spec);
        assertFalse(valid, "Should be invalid with zero notional");
    }

    function test_ValidateNDFSpec_ZeroForwardRate() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        spec.forwardRate = 0;

        bool valid = ndf.validateNDFSpec(spec);
        assertFalse(valid, "Should be invalid with zero forward rate");
    }

    function test_ValidateNDFSpec_InvalidDates() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        // Settlement before fixing
        spec.settlementDate = spec.fixingDate - 1 days;

        bool valid = ndf.validateNDFSpec(spec);
        assertFalse(valid, "Should be invalid with settlement before fixing");
    }

    function test_ValidateNDFSpec_SameCurrency() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        // Same currency for both
        spec.nonDeliverableCurrency = USD;

        bool valid = ndf.validateNDFSpec(spec);
        assertFalse(valid, "Should be invalid with same currencies");
    }

    // =============================================================================
    // SETTLEMENT CALCULATION TESTS
    // =============================================================================

    function test_CalculateSettlement_SpotAboveForward() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,  // $10M
            715e16             // 7.15 CNY/USD
        );

        uint256 spotFixing = 720e16; // 7.20 CNY/USD (CNY weakened)

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Settlement = $10M × (7.20 - 7.15) / 7.20
        // = $10M × 0.05 / 7.20 = $69,444.44
        uint256 expectedSettlement = 69_444_444444444444444444; // ~$69,444

        assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.RECEIVE));
        assertEq(result.payerReference, SELLER, "Seller should pay");
        assertEq(result.receiverReference, BUYER, "Buyer should receive");
        assertApproxEqRel(result.settlementAmount, expectedSettlement, 1e15, "Settlement amount");
    }

    function test_CalculateSettlement_SpotBelowForward() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16  // 7.15 CNY/USD
        );

        uint256 spotFixing = 710e16; // 7.10 CNY/USD (CNY strengthened)

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Settlement = $10M × (7.15 - 7.10) / 7.10
        // = $10M × 0.05 / 7.10 = $70,422.54
        uint256 expectedSettlement = 70_422_535211267605633802; // ~$70,423

        assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.PAY));
        assertEq(result.payerReference, BUYER, "Buyer should pay");
        assertEq(result.receiverReference, SELLER, "Seller should receive");
        assertApproxEqRel(result.settlementAmount, expectedSettlement, 1e15, "Settlement amount");
    }

    function test_CalculateSettlement_SpotEqualsForward() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        uint256 spotFixing = 715e16; // Exactly at forward

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.ZERO));
        assertEq(result.settlementAmount, 0, "No settlement needed");
    }

    function test_CalculateSettlement_LargeMove() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        // Large depreciation: 10% move
        uint256 spotFixing = 7865e15; // 7.865 CNY/USD (+10%)

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Settlement = $10M × (7.865 - 7.15) / 7.865
        uint256 expectedSettlement = 909_090_909090909090909090; // ~$909,091

        assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.RECEIVE));
        assertApproxEqRel(result.settlementAmount, expectedSettlement, 1e15, "Large settlement");
    }

    function test_CalculateSettlement_SmallMove() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        // Small move: 0.1%
        uint256 spotFixing = 7157e15; // 7.157 CNY/USD

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Very small settlement
        assertGt(result.settlementAmount, 0, "Should have some settlement");
        assertLt(result.settlementAmount, 10_000 * ONE, "Should be small");
    }

    function test_CalculateSettlement_LargeNotional() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            100_000_000 * ONE,  // $100M
            715e16
        );

        uint256 spotFixing = 720e16;

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Should handle large notionals without overflow
        assertGt(result.settlementAmount, 0, "Should calculate large settlement");
    }

    function test_CalculateSettlement_MultipleScenarios() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        // Test multiple spot levels
        uint256[] memory spots = new uint256[](5);
        spots[0] = 700e16; // -2.1%
        spots[1] = 710e16; // -0.7%
        spots[2] = 715e16; // 0%
        spots[3] = 720e16; // +0.7%
        spots[4] = 730e16; // +2.1%

        for (uint256 i = 0; i < spots.length; i++) {
            NonDeliverableForward.NDFSettlementResult memory result =
                ndf.calculateSettlement(spec, spots[i]);

            if (i < 2) {
                assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.PAY));
            } else if (i == 2) {
                assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.ZERO));
            } else {
                assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.RECEIVE));
            }
        }
    }

    function test_CalculateSettlement_InvalidSpot() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        vm.expectRevert(NonDeliverableForward.NonDeliverableForward__InvalidRate.selector);
        ndf.calculateSettlement(spec, 0);
    }

    // =============================================================================
    // MTM CALCULATION TESTS
    // =============================================================================

    function test_CalculateMTM_PositiveMTM() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16  // Contract forward: 7.15
        );

        uint256 currentForward = 720e16; // Current market: 7.20
        uint256 valuationDate = TRADE_DATE + 30 days;

        NonDeliverableForward.NDFValuationResult memory result =
            ndf.calculateMTM(spec, currentForward, valuationDate);

        // Positive MTM for buyer (current forward > contract forward)
        assertGt(result.mtmValue, 0, "Should have positive MTM");

        // Check days to maturity
        uint256 expectedDays = (FIXING_DATE - valuationDate) / 1 days;
        assertEq(result.daysToMaturity, expectedDays, "Days to maturity");
    }

    function test_CalculateMTM_NegativeMTM() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        uint256 currentForward = 710e16; // Current market below contract
        uint256 valuationDate = TRADE_DATE + 30 days;

        NonDeliverableForward.NDFValuationResult memory result =
            ndf.calculateMTM(spec, currentForward, valuationDate);

        // Negative MTM for buyer
        assertLt(result.mtmValue, 0, "Should have negative MTM");
    }

    function test_CalculateMTM_ZeroMTM() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        uint256 currentForward = 715e16; // Same as contract
        uint256 valuationDate = TRADE_DATE + 30 days;

        NonDeliverableForward.NDFValuationResult memory result =
            ndf.calculateMTM(spec, currentForward, valuationDate);

        assertEq(result.mtmValue, 0, "MTM should be zero");
    }

    function test_CalculateMTM_TimeDecay() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        uint256 currentForward = 720e16;

        // MTM at different times
        uint256 valuationDate1 = TRADE_DATE + 30 days;
        uint256 valuationDate2 = TRADE_DATE + 60 days;

        NonDeliverableForward.NDFValuationResult memory result1 =
            ndf.calculateMTM(spec, currentForward, valuationDate1);

        NonDeliverableForward.NDFValuationResult memory result2 =
            ndf.calculateMTM(spec, currentForward, valuationDate2);

        // Days to maturity should decrease
        assertGt(result1.daysToMaturity, result2.daysToMaturity, "Time to maturity decreases");
    }

    function test_CalculateMTM_AfterFixing() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        uint256 currentForward = 720e16;
        uint256 valuationDate = FIXING_DATE + 1 days; // After fixing

        vm.expectRevert(NonDeliverableForward.NonDeliverableForward__FixingNotAvailable.selector);
        ndf.calculateMTM(spec, currentForward, valuationDate);
    }

    // =============================================================================
    // HELPER FUNCTION TESTS
    // =============================================================================

    function test_CalculateForwardPoints_Premium() public {
        uint256 spot = 700e16; // 7.00
        uint256 forward = 715e16; // 7.15

        int256 points = ndf.calculateForwardPoints(spot, forward);

        // Forward premium: (7.15 - 7.00) / 7.00 × 10000 = 214.29 bps
        assertGt(points, 0, "Should be positive (premium)");
        assertApproxEqRel(uint256(points), 214, 5e16, "Forward points");
    }

    function test_CalculateForwardPoints_Discount() public {
        uint256 spot = 715e16; // 7.15
        uint256 forward = 700e16; // 7.00

        int256 points = ndf.calculateForwardPoints(spot, forward);

        // Forward discount
        assertLt(points, 0, "Should be negative (discount)");
    }

    function test_GetNotionalCurrencyEquivalent() public {
        uint256 settlementAmount = 69_444_444444444444444444; // ~$69,444
        uint256 spotRate = 720e16; // 7.20 CNY/USD

        uint256 equivalent = ndf.getNotionalCurrencyEquivalent(settlementAmount, spotRate);

        // $69,444 × 7.20 = 500,000 CNY
        uint256 expected = 500_000 * ONE;
        assertApproxEqRel(equivalent, expected, 1e15, "Currency equivalent");
    }

    function test_IsInTheMoney_ITM() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        uint256 currentForward = 720e16; // Above contract rate

        (bool itm, uint256 mtmAmount) = ndf.isInTheMoney(spec, currentForward);

        assertTrue(itm, "Should be in-the-money");
        assertGt(mtmAmount, 0, "Should have positive MTM amount");
    }

    function test_IsInTheMoney_OTM() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        uint256 currentForward = 710e16; // Below contract rate

        (bool itm, uint256 mtmAmount) = ndf.isInTheMoney(spec, currentForward);

        assertFalse(itm, "Should be out-of-the-money");
        assertGt(mtmAmount, 0, "Should have MTM amount (absolute value)");
    }

    // =============================================================================
    // REAL-WORLD SCENARIO TESTS
    // =============================================================================

    function test_RealWorld_USDCNY_3Month() public {
        // $10M USD/CNY NDF, 3-month tenor
        NonDeliverableForward.NDFSpec memory spec = ndf.createStandardNDF(
            bytes32("USDCNY_3M"),
            BUYER,
            SELLER,
            USD,
            CNY,
            10_000_000 * ONE,
            715e16,  // 7.15 CNY/USD
            TRADE_DATE,
            FIXING_DATE,
            SETTLEMENT_DATE
        );

        // Spot fixes at 7.25 (CNY depreciation)
        uint256 spotFixing = 725e16;

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Settlement ≈ $10M × (7.25 - 7.15) / 7.25 ≈ $137,931
        assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.RECEIVE));
        assertGt(result.settlementAmount, 130_000 * ONE, "Significant settlement");
    }

    function test_RealWorld_USDBRL_1Month() public {
        // $5M USD/BRL NDF, 1-month tenor
        uint256 fixingDate1M = TRADE_DATE + 30 days;
        uint256 settlementDate1M = fixingDate1M + 2 days;

        NonDeliverableForward.NDFSpec memory spec = ndf.createStandardNDF(
            bytes32("USDBRL_1M"),
            BUYER,
            SELLER,
            USD,
            BRL,
            5_000_000 * ONE,
            5e18,     // 5.00 BRL/USD
            TRADE_DATE,
            fixingDate1M,
            settlementDate1M
        );

        // Spot fixes at 5.10 (BRL depreciation)
        uint256 spotFixing = 51e17;

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Buyer receives (BRL weakened vs USD)
        assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.RECEIVE));
    }

    function test_RealWorld_USDINR_6Month() public {
        // $20M USD/INR NDF, 6-month tenor
        uint256 fixingDate6M = TRADE_DATE + 180 days;
        uint256 settlementDate6M = fixingDate6M + 2 days;

        NonDeliverableForward.NDFSpec memory spec = ndf.createStandardNDF(
            bytes32("USDINR_6M"),
            BUYER,
            SELLER,
            USD,
            INR,
            20_000_000 * ONE,
            83e18,    // 83.00 INR/USD
            TRADE_DATE,
            fixingDate6M,
            settlementDate6M
        );

        // Spot fixes at 82.00 (INR appreciation)
        uint256 spotFixing = 82e18;

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Buyer pays (INR strengthened vs USD)
        assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.PAY));

        // Settlement ≈ $20M × (83 - 82) / 82 ≈ $243,902
        uint256 expectedSettlement = 243_902_439024390243902439;
        assertApproxEqRel(result.settlementAmount, expectedSettlement, 1e15, "Settlement");
    }

    function test_RealWorld_USDKRW_Volatile() public {
        // $15M USD/KRW NDF with volatile move
        NonDeliverableForward.NDFSpec memory spec = ndf.createStandardNDF(
            bytes32("USDKRW_3M"),
            BUYER,
            SELLER,
            USD,
            KRW,
            15_000_000 * ONE,
            1300e18,  // 1300 KRW/USD
            TRADE_DATE,
            FIXING_DATE,
            SETTLEMENT_DATE
        );

        // Large move: 1350 KRW/USD (+3.85%)
        uint256 spotFixing = 1350e18;

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Large settlement due to high notional and volatility
        assertGt(result.settlementAmount, 500_000 * ONE, "Large settlement from volatility");
    }

    function test_RealWorld_MTM_Pipeline() public {
        // Track MTM over life of NDF
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        // Check MTM at different points
        uint256[] memory valuationDates = new uint256[](3);
        valuationDates[0] = TRADE_DATE + 30 days;
        valuationDates[1] = TRADE_DATE + 60 days;
        valuationDates[2] = TRADE_DATE + 80 days;

        uint256 currentForward = 720e16;

        for (uint256 i = 0; i < valuationDates.length; i++) {
            NonDeliverableForward.NDFValuationResult memory result =
                ndf.calculateMTM(spec, currentForward, valuationDates[i]);

            // MTM should be positive (favorable to buyer)
            assertGt(result.mtmValue, 0, "Positive MTM throughout");

            // Days to maturity should decrease
            if (i > 0) {
                assertLt(result.daysToMaturity, 90 - (i * 30), "Time decay");
            }
        }
    }

    // =============================================================================
    // EDGE CASE TESTS
    // =============================================================================

    function test_EdgeCase_ExtremeDepreciation() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        // Extreme move: 50% depreciation
        uint256 spotFixing = 10725e15; // 10.725 CNY/USD

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Should handle extreme moves
        assertEq(uint8(result.direction), uint8(NonDeliverableForward.SettlementDirectionEnum.RECEIVE));
        assertGt(result.settlementAmount, 3_000_000 * ONE, "Large settlement");
    }

    function test_EdgeCase_VerySmallNotional() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            1000 * ONE,  // $1,000 only
            715e16
        );

        uint256 spotFixing = 720e16;

        NonDeliverableForward.NDFSettlementResult memory result =
            ndf.calculateSettlement(spec, spotFixing);

        // Should handle small notionals
        assertGt(result.settlementAmount, 0, "Should have settlement");
        assertLt(result.settlementAmount, 10 * ONE, "Small settlement");
    }

    function test_EdgeCase_NearMaturity() public {
        NonDeliverableForward.NDFSpec memory spec = _createStandardNDF(
            10_000_000 * ONE,
            715e16
        );

        uint256 currentForward = 720e16;
        uint256 valuationDate = FIXING_DATE - 1 days; // 1 day before fixing

        NonDeliverableForward.NDFValuationResult memory result =
            ndf.calculateMTM(spec, currentForward, valuationDate);

        // Should work even very close to maturity
        assertEq(result.daysToMaturity, 1, "1 day to maturity");
        assertGt(result.mtmValue, 0, "Should still have MTM");
    }
}
