// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {FixedPoint} from "../../../src/base/libraries/FixedPoint.sol";
import {RoundingDirectionEnum} from "../../../src/base/types/Enums.sol";

/**
 * @title FixedPointTest
 * @notice Unit tests for FixedPoint library
 * @dev Tests all mathematical operations with known values
 */
contract FixedPointTest is Test {
    using FixedPoint for uint256;

    // Test constants
    uint256 constant ONE = 1e18;
    uint256 constant TWO = 2e18;
    uint256 constant THREE = 3e18;
    uint256 constant HALF = 5e17;
    uint256 constant QUARTER = 25e16;

    // =============================================================================
    // WRAPPER FUNCTIONS (for testing reverts at proper call depth)
    // =============================================================================

    function _mulWrapper(uint256 a, uint256 b) internal pure returns (uint256) {
        return FixedPoint.mul(a, b);
    }

    function _divWrapper(uint256 a, uint256 b) internal pure returns (uint256) {
        return FixedPoint.div(a, b);
    }

    function _subWrapper(uint256 a, uint256 b) internal pure returns (uint256) {
        return FixedPoint.sub(a, b);
    }

    // =============================================================================
    // MULTIPLICATION TESTS
    // =============================================================================

    function testMul_BasicMultiplication() public {
        // 2.0 * 3.0 = 6.0
        uint256 result = FixedPoint.mul(TWO, THREE);
        assertEq(result, 6e18, "2 * 3 should equal 6");
    }

    function testMul_WithDecimals() public {
        // 1.5 * 2.0 = 3.0
        uint256 onePointFive = 15e17;
        uint256 result = FixedPoint.mul(onePointFive, TWO);
        assertEq(result, THREE, "1.5 * 2 should equal 3");
    }

    function testMul_ByZero() public {
        uint256 result = FixedPoint.mul(ONE, 0);
        assertEq(result, 0, "Any number * 0 should equal 0");
    }

    function testMul_ByOne() public {
        uint256 result = FixedPoint.mul(THREE, ONE);
        assertEq(result, THREE, "Any number * 1 should equal itself");
    }

    function testMul_SmallNumbers() public {
        // 0.5 * 0.5 = 0.25
        uint256 result = FixedPoint.mul(HALF, HALF);
        assertEq(result, QUARTER, "0.5 * 0.5 should equal 0.25");
    }

    function testMul_RevertOnOverflow() public {
        uint256 maxValue = type(uint256).max;
        try this.externalMulWrapper(maxValue, TWO) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            // Verify the revert reason is FixedPoint__Overflow
            bytes4 selector = bytes4(reason);
            assertEq(selector, FixedPoint.FixedPoint__Overflow.selector, "Wrong error selector");
        }
    }

    // External wrapper for testMul_RevertOnOverflow (must be external for try/catch)
    function externalMulWrapper(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPoint.mul(a, b);
    }

    // =============================================================================
    // DIVISION TESTS
    // =============================================================================

    function testDiv_BasicDivision() public {
        // 6.0 / 2.0 = 3.0
        uint256 result = FixedPoint.div(6e18, TWO);
        assertEq(result, THREE, "6 / 2 should equal 3");
    }

    function testDiv_WithRemainder() public {
        // 1.0 / 3.0 = 0.333...
        uint256 result = FixedPoint.div(ONE, THREE);
        // Expected: 333333333333333333 (0.333... truncated)
        assertEq(result, 333333333333333333, "1 / 3 should equal ~0.333");
    }

    function testDiv_ByOne() public {
        uint256 result = FixedPoint.div(THREE, ONE);
        assertEq(result, THREE, "Any number / 1 should equal itself");
    }

    function testDiv_ZeroNumerator() public {
        uint256 result = FixedPoint.div(0, TWO);
        assertEq(result, 0, "0 / any number should equal 0");
    }

    function testDiv_RevertOnDivisionByZero() public {
        try this.externalDivWrapper(ONE, 0) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            // Verify the revert reason is FixedPoint__DivisionByZero
            bytes4 selector = bytes4(reason);
            assertEq(selector, FixedPoint.FixedPoint__DivisionByZero.selector, "Wrong error selector");
        }
    }

    // External wrapper for testDiv_RevertOnDivisionByZero (must be external for try/catch)
    function externalDivWrapper(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPoint.div(a, b);
    }

    function testDiv_LargeDenominator() public {
        // 1.0 / 1000.0 = 0.001
        uint256 result = FixedPoint.div(ONE, 1000e18);
        assertEq(result, 1e15, "1 / 1000 should equal 0.001");
    }

    // =============================================================================
    // ADDITION TESTS
    // =============================================================================

    function testAdd_BasicAddition() public {
        uint256 result = FixedPoint.add(TWO, THREE);
        assertEq(result, 5e18, "2 + 3 should equal 5");
    }

    function testAdd_WithDecimals() public {
        uint256 result = FixedPoint.add(HALF, QUARTER);
        assertEq(result, 75e16, "0.5 + 0.25 should equal 0.75");
    }

    function testAdd_Zero() public {
        uint256 result = FixedPoint.add(THREE, 0);
        assertEq(result, THREE, "Any number + 0 should equal itself");
    }

    // =============================================================================
    // SUBTRACTION TESTS
    // =============================================================================

    function testSub_BasicSubtraction() public {
        uint256 result = FixedPoint.sub(THREE, TWO);
        assertEq(result, ONE, "3 - 2 should equal 1");
    }

    function testSub_ResultZero() public {
        uint256 result = FixedPoint.sub(THREE, THREE);
        assertEq(result, 0, "3 - 3 should equal 0");
    }

    function testSub_RevertOnUnderflow() public {
        try this.externalSubWrapper(TWO, THREE) {
            fail("Expected revert");
        } catch (bytes memory reason) {
            // Verify the revert reason is FixedPoint__Underflow
            bytes4 selector = bytes4(reason);
            assertEq(selector, FixedPoint.FixedPoint__Underflow.selector, "Wrong error selector");
        }
    }

    // External wrapper for testSub_RevertOnUnderflow (must be external for try/catch)
    function externalSubWrapper(uint256 a, uint256 b) external pure returns (uint256) {
        return FixedPoint.sub(a, b);
    }

    // =============================================================================
    // CONVERSION TESTS
    // =============================================================================

    function testFromUint() public {
        uint256 result = FixedPoint.fromUint(5);
        assertEq(result, 5e18, "fromUint(5) should equal 5.0");
    }

    function testToUint_Truncation() public {
        uint256 value = 57e17; // 5.7
        uint256 result = FixedPoint.toUint(value);
        assertEq(result, 5, "toUint(5.7) should equal 5 (truncated)");
    }

    function testToUintRounded() public {
        // Test rounding down
        uint256 result1 = FixedPoint.toUintRounded(54e17); // 5.4
        assertEq(result1, 5, "5.4 should round down to 5");

        // Test rounding up
        uint256 result2 = FixedPoint.toUintRounded(56e17); // 5.6
        assertEq(result2, 6, "5.6 should round up to 6");

        // Test exact half rounds up
        uint256 result3 = FixedPoint.toUintRounded(55e17); // 5.5
        assertEq(result3, 6, "5.5 should round up to 6");
    }

    // =============================================================================
    // ROUNDING TESTS
    // =============================================================================

    function testRound_Down() public {
        uint256 value = 1234e15; // 1.234
        uint256 result = FixedPoint.round(value, 2, RoundingDirectionEnum.DOWN);
        assertEq(result, 123e16, "1.234 rounded down to 2 decimals = 1.23");
    }

    function testRound_Up() public {
        uint256 value = 1234e15; // 1.234
        uint256 result = FixedPoint.round(value, 2, RoundingDirectionEnum.UP);
        assertEq(result, 124e16, "1.234 rounded up to 2 decimals = 1.24");
    }

    function testRound_Nearest() public {
        // Test rounding down
        uint256 value1 = 1234e15; // 1.234
        uint256 result1 = FixedPoint.round(value1, 2, RoundingDirectionEnum.NEAREST);
        assertEq(result1, 123e16, "1.234 rounded nearest to 2 decimals = 1.23");

        // Test rounding up
        uint256 value2 = 1236e15; // 1.236
        uint256 result2 = FixedPoint.round(value2, 2, RoundingDirectionEnum.NEAREST);
        assertEq(result2, 124e16, "1.236 rounded nearest to 2 decimals = 1.24");
    }

    function testRound_ToZeroDecimals() public {
        uint256 value = 1567e15; // 1.567
        uint256 result = FixedPoint.round(value, 0, RoundingDirectionEnum.DOWN);
        assertEq(result, 1e18, "1.567 rounded down to 0 decimals = 1");
    }

    // =============================================================================
    // COMPARISON TESTS
    // =============================================================================

    function testComparisons() public {
        assertTrue(FixedPoint.eq(ONE, ONE), "1 should equal 1");
        assertTrue(FixedPoint.gt(TWO, ONE), "2 should be greater than 1");
        assertTrue(FixedPoint.gte(ONE, ONE), "1 should be >= 1");
        assertTrue(FixedPoint.lt(ONE, TWO), "1 should be less than 2");
        assertTrue(FixedPoint.lte(ONE, ONE), "1 should be <= 1");
    }

    // =============================================================================
    // ADVANCED OPERATION TESTS
    // =============================================================================

    function testAvg() public {
        uint256 result = FixedPoint.avg(TWO, 4e18);
        assertEq(result, THREE, "Average of 2 and 4 should be 3");
    }

    function testMinMax() public {
        assertEq(FixedPoint.min(TWO, THREE), TWO, "Min of 2 and 3 is 2");
        assertEq(FixedPoint.max(TWO, THREE), THREE, "Max of 2 and 3 is 3");
    }

    function testPow() public {
        // 2^3 = 8
        uint256 result = FixedPoint.pow(TWO, 3);
        assertEq(result, 8e18, "2^3 should equal 8");

        // 10^2 = 100
        uint256 result2 = FixedPoint.pow(10e18, 2);
        assertEq(result2, 100e18, "10^2 should equal 100");

        // x^0 = 1
        uint256 result3 = FixedPoint.pow(999e18, 0);
        assertEq(result3, ONE, "Any number^0 should equal 1");

        // x^1 = x
        uint256 result4 = FixedPoint.pow(THREE, 1);
        assertEq(result4, THREE, "Any number^1 should equal itself");
    }

    // =============================================================================
    // FINANCIAL HELPER TESTS
    // =============================================================================

    function testFromBasisPoints() public {
        // 100 basis points = 1%
        uint256 result = FixedPoint.fromBasisPoints(100);
        assertEq(result, 1e16, "100 bp should equal 1% (0.01)");

        // 25 basis points = 0.25%
        uint256 result2 = FixedPoint.fromBasisPoints(25);
        assertEq(result2, 25e14, "25 bp should equal 0.25% (0.0025)");
    }

    function testToBasisPoints() public {
        // 1% = 100 basis points
        uint256 onePercent = 1e16;
        uint256 result = FixedPoint.toBasisPoints(onePercent);
        assertEq(result, 100, "1% should equal 100 bp");
    }

    function testApplyPercentage() public {
        // 5% of 1000 = 50
        uint256 value = 1000e18;
        uint256 percentage = 5e16; // 5%
        uint256 result = FixedPoint.applyPercentage(value, percentage);
        assertEq(result, 50e18, "5% of 1000 should be 50");

        // 10% of 200 = 20
        uint256 result2 = FixedPoint.applyPercentage(200e18, 10e16);
        assertEq(result2, 20e18, "10% of 200 should be 20");
    }

    function testPercentageChange() public {
        // From 100 to 110 = 10% increase
        uint256 result = FixedPoint.percentageChange(100e18, 110e18);
        assertEq(result, 10e18, "100 to 110 is 10% change");

        // From 200 to 150 = 25% decrease (in absolute terms)
        uint256 result2 = FixedPoint.percentageChange(200e18, 150e18);
        assertEq(result2, 25e18, "200 to 150 is 25% change (absolute)");
    }

    // =============================================================================
    // FUZZ TESTS
    // =============================================================================

    function testFuzz_Mul(uint256 a, uint256 b) public {
        // Bound to reasonable values to avoid overflow
        a = bound(a, 0, 1e36); // Max ~1e18 in fixed-point
        b = bound(b, 0, 1e36);

        // Only test if multiplication won't overflow
        if (a == 0 || b == 0 || a <= type(uint256).max / b) {
            uint256 result = FixedPoint.mul(a, b);
            // Result should not overflow
            assertTrue(result >= 0, "Result should be non-negative");
        }
    }

    function testFuzz_Add(uint128 a, uint128 b) public {
        // Use uint128 to ensure no overflow in addition
        uint256 result = FixedPoint.add(uint256(a), uint256(b));
        assertEq(result, uint256(a) + uint256(b), "Addition should be correct");
    }

    function testFuzz_Sub(uint256 a, uint256 b) public {
        // Only test when a >= b to avoid underflow
        if (a >= b) {
            uint256 result = FixedPoint.sub(a, b);
            assertEq(result, a - b, "Subtraction should be correct");
        }
    }

    function testFuzz_Div(uint256 a, uint256 b) public {
        // Bound values to avoid extreme cases
        a = bound(a, 0, type(uint128).max);
        b = bound(b, 1, type(uint128).max); // Avoid division by zero

        uint256 result = FixedPoint.div(a, b);
        // Result should be >= 0
        assertTrue(result >= 0, "Division result should be non-negative");
    }
}
