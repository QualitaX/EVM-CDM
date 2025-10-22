// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/events/ExecutionEvent.sol";
import "../../../src/events/TradeState.sol";

/**
 * @title ExecutionEventTest
 * @notice Comprehensive unit tests for ExecutionEvent contract
 */
contract ExecutionEventTest is Test {
    ExecutionEvent public executionEvent;
    TradeState public tradeState;

    // Test constants
    bytes32 constant TRADE_ID = keccak256("TRADE_001");
    bytes32 constant EVENT_ID = keccak256("EVENT_001");
    bytes32 constant BUYER = keccak256("BUYER");
    bytes32 constant SELLER = keccak256("SELLER");
    bytes32 constant BROKER = keccak256("BROKER");
    bytes32 constant PRODUCT_ID = keccak256("IRS");

    uint256 constant ONE = 1e18;
    uint256 constant EFFECTIVE_DATE = 1704067200; // Jan 1, 2024
    uint256 constant MATURITY_DATE = 1735689600;  // Jan 1, 2025
    uint256 constant EXECUTION_TIME = 1703980800; // Dec 31, 2023

    function setUp() public {
        tradeState = new TradeState();
        executionEvent = new ExecutionEvent(address(tradeState));

        // Create a trade in CREATED state
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = BUYER;
        parties[1] = SELLER;

        tradeState.createTrade(
            TRADE_ID,
            TradeState.ProductTypeEnum.INTEREST_RATE_SWAP,
            parties,
            EFFECTIVE_DATE,
            MATURITY_DATE
        );
    }

    // Helper functions
    function _createStandardExecution() internal view returns (
        ExecutionEvent.ExecutionDetails memory,
        ExecutionEvent.EconomicTerms memory
    ) {
        ExecutionEvent.ExecutionDetails memory execution = ExecutionEvent.ExecutionDetails({
            executionTimestamp: EXECUTION_TIME,
            executionPrice: 350e14, // 3.50%
            venue: ExecutionEvent.ExecutionVenueEnum.ELECTRONIC,
            confirmMethod: ExecutionEvent.ConfirmationMethodEnum.ELECTRONIC,
            executionId: keccak256("EXEC_001"),
            venueReference: keccak256("VENUE_001"),
            isAllocated: false,
            allocationReferences: new bytes32[](0)
        });

        ExecutionEvent.EconomicTerms memory terms = ExecutionEvent.EconomicTerms({
            notional: 10_000_000 * ONE,
            currency: keccak256("USD"),
            effectiveDate: EFFECTIVE_DATE,
            maturityDate: MATURITY_DATE,
            productIdentifier: PRODUCT_ID,
            additionalTerms: new bytes32[](0)
        });

        return (execution, terms);
    }

    // =============================================================================
    // EXECUTION TESTS
    // =============================================================================

    function test_ExecuteTrade_Success() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        Event.EventRecord memory record = executionEvent.executeTrade(
            EVENT_ID,
            TRADE_ID,
            execution,
            terms,
            BUYER,
            SELLER,
            bytes32(0), // No broker
            EXECUTION_TIME
        );

        assertEq(record.metadata.eventId, EVENT_ID);
        assertEq(record.metadata.tradeId, TRADE_ID);
        assertEq(uint8(record.metadata.eventType), uint8(Event.EventTypeEnum.EXECUTION));
        assertTrue(record.isValid);

        // Verify trade transitioned to CONFIRMED
        TradeState.TradeStateSnapshot memory state = tradeState.getCurrentState(TRADE_ID);
        assertEq(uint8(state.state), uint8(TradeState.TradeStateEnum.CONFIRMED));
    }

    function test_ExecuteTrade_WithBroker() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(
            EVENT_ID,
            TRADE_ID,
            execution,
            terms,
            BUYER,
            SELLER,
            BROKER,
            EXECUTION_TIME
        );

        ExecutionEvent.ExecutionEventData memory data = executionEvent.getExecutionData(EVENT_ID);
        assertEq(data.brokerReference, BROKER);
    }

    function test_ExecuteTrade_VenueTypes() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        execution.venue = ExecutionEvent.ExecutionVenueEnum.ON_VENUE;
        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        ExecutionEvent.ExecutionVenueEnum venue = executionEvent.getExecutionVenue(EVENT_ID);
        assertEq(uint8(venue), uint8(ExecutionEvent.ExecutionVenueEnum.ON_VENUE));
    }

    function test_ExecuteTrade_RevertWhen_TradeAlreadyExecuted() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        vm.expectRevert(ExecutionEvent.ExecutionEvent__TradeAlreadyExecuted.selector);
        executionEvent.executeTrade(
            keccak256("EVENT_002"),
            TRADE_ID,
            execution,
            terms,
            BUYER,
            SELLER,
            bytes32(0),
            EXECUTION_TIME
        );
    }

    function test_ExecuteTrade_RevertWhen_TradeNotInCreatedState() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        // Execute once (transitions to CONFIRMED)
        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        // Create another trade and transition it to ACTIVE
        bytes32 tradeId2 = keccak256("TRADE_002");
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = BUYER;
        parties[1] = SELLER;
        tradeState.createTrade(tradeId2, TradeState.ProductTypeEnum.INTEREST_RATE_SWAP, parties, EFFECTIVE_DATE, MATURITY_DATE);
        tradeState.transitionState(tradeId2, TradeState.TradeStateEnum.CONFIRMED, EVENT_ID, BUYER);
        tradeState.transitionState(tradeId2, TradeState.TradeStateEnum.ACTIVE, EVENT_ID, BUYER);

        vm.expectRevert(ExecutionEvent.ExecutionEvent__TradeNotInCreatedState.selector);
        executionEvent.executeTrade(
            keccak256("EVENT_002"),
            tradeId2,
            execution,
            terms,
            BUYER,
            SELLER,
            bytes32(0),
            EXECUTION_TIME
        );
    }

    function test_ExecuteTrade_RevertWhen_InvalidParties_SameBuyerSeller() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        vm.expectRevert(ExecutionEvent.ExecutionEvent__InvalidParties.selector);
        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, BUYER, bytes32(0), EXECUTION_TIME);
    }

    function test_ExecuteTrade_RevertWhen_InvalidParties_ZeroBuyer() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        vm.expectRevert(ExecutionEvent.ExecutionEvent__InvalidParties.selector);
        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, bytes32(0), SELLER, bytes32(0), EXECUTION_TIME);
    }

    function test_ExecuteTrade_RevertWhen_InvalidDates_MaturityBeforeEffective() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        terms.maturityDate = EFFECTIVE_DATE - 1;

        vm.expectRevert(ExecutionEvent.ExecutionEvent__InvalidDates.selector);
        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);
    }

    function test_ExecuteTrade_RevertWhen_InvalidDates_ExecutionAfterEffective() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        execution.executionTimestamp = EFFECTIVE_DATE + 1;

        vm.expectRevert(ExecutionEvent.ExecutionEvent__InvalidDates.selector);
        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);
    }

    function test_ExecuteTrade_RevertWhen_ZeroNotional() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        terms.notional = 0;

        vm.expectRevert(ExecutionEvent.ExecutionEvent__InvalidExecutionPrice.selector);
        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);
    }

    // =============================================================================
    // QUERY FUNCTION TESTS
    // =============================================================================

    function test_GetExecutionData() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        ExecutionEvent.ExecutionEventData memory data = executionEvent.getExecutionData(EVENT_ID);
        assertEq(data.eventId, EVENT_ID);
        assertEq(data.tradeId, TRADE_ID);
        assertEq(data.buyerReference, BUYER);
        assertEq(data.sellerReference, SELLER);
        assertEq(data.tradeDate, EXECUTION_TIME);
    }

    function test_GetTradeExecutionEventId() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        bytes32 returnedEventId = executionEvent.getTradeExecutionEventId(TRADE_ID);
        assertEq(returnedEventId, EVENT_ID);
    }

    function test_GetTradeExecutionDetails() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        ExecutionEvent.ExecutionDetails memory details = executionEvent.getTradeExecutionDetails(TRADE_ID);
        assertEq(details.executionTimestamp, EXECUTION_TIME);
        assertEq(details.executionPrice, 350e14);
        assertEq(uint8(details.venue), uint8(ExecutionEvent.ExecutionVenueEnum.ELECTRONIC));
    }

    function test_GetTradeEconomicTerms() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        ExecutionEvent.EconomicTerms memory returnedTerms = executionEvent.getTradeEconomicTerms(TRADE_ID);
        assertEq(returnedTerms.notional, 10_000_000 * ONE);
        assertEq(returnedTerms.effectiveDate, EFFECTIVE_DATE);
        assertEq(returnedTerms.maturityDate, MATURITY_DATE);
    }

    function test_IsTradeExecuted() public {
        assertFalse(executionEvent.isTradeExecuted(TRADE_ID));

        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        assertTrue(executionEvent.isTradeExecuted(TRADE_ID));
    }

    function test_GetExecutionPrice() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        uint256 price = executionEvent.getExecutionPrice(EVENT_ID);
        assertEq(price, 350e14);
    }

    function test_GetTradeCounterparties() public {
        (ExecutionEvent.ExecutionDetails memory execution,
         ExecutionEvent.EconomicTerms memory terms) = _createStandardExecution();

        executionEvent.executeTrade(EVENT_ID, TRADE_ID, execution, terms, BUYER, SELLER, bytes32(0), EXECUTION_TIME);

        (bytes32 buyer, bytes32 seller) = executionEvent.getTradeCounterparties(TRADE_ID);
        assertEq(buyer, BUYER);
        assertEq(seller, SELLER);
    }

    function test_GetExecutionData_RevertWhen_EventDoesNotExist() public {
        vm.expectRevert(Event.Event__EventDoesNotExist.selector);
        executionEvent.getExecutionData(EVENT_ID);
    }
}
