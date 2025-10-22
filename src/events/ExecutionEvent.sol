// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Event} from "./Event.sol";
import {TradeState} from "./TradeState.sol";

/**
 * @title ExecutionEvent
 * @notice Trade execution/inception event
 * @dev Represents the initial execution of a trade
 *
 * KEY FEATURES:
 * - Trade inception recording
 * - Economic terms capture
 * - State transition to CONFIRMED
 * - Multi-product support
 *
 * EXECUTION FLOW:
 * 1. Trade created (CREATED state)
 * 2. Execution event occurs
 * 3. Trade transitions to CONFIRMED
 * 4. Awaits effective date to become ACTIVE
 *
 * CAPTURED DATA:
 * - Execution price/rate
 * - Economic terms
 * - Counterparty confirmation
 * - Execution venue/method
 *
 * @author QualitaX Team
 */
contract ExecutionEvent is Event {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Execution venue type
    enum ExecutionVenueEnum {
        ON_VENUE,           // Exchange/SEF/MTF
        OFF_VENUE,          // Bilateral OTC
        ELECTRONIC,         // Electronic platform
        VOICE               // Voice brokered
    }

    /// @notice Confirmation method
    enum ConfirmationMethodEnum {
        ELECTRONIC,         // Electronic confirmation
        WRITTEN,            // Written confirmation
        ORAL,               // Oral confirmation
        AUTOMATED           // Automated confirmation
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Execution details
    /// @dev Core execution information
    struct ExecutionDetails {
        uint256 executionTimestamp;         // Time of execution
        uint256 executionPrice;             // Execution price (product-specific)
        ExecutionVenueEnum venue;           // Execution venue
        ConfirmationMethodEnum confirmMethod; // Confirmation method
        bytes32 executionId;                // Unique execution identifier
        bytes32 venueReference;             // Venue/platform reference
        bool isAllocated;                   // Has trade been allocated
        bytes32[] allocationReferences;     // Allocation references (if applicable)
    }

    /// @notice Economic terms snapshot
    /// @dev Captures agreed economic terms at execution
    struct EconomicTerms {
        uint256 notional;                   // Trade notional
        bytes32 currency;                   // Primary currency
        uint256 effectiveDate;              // Trade effective date
        uint256 maturityDate;               // Trade maturity/termination date
        bytes32 productIdentifier;          // Product classification
        bytes32[] additionalTerms;          // Additional product-specific terms
    }

    /// @notice Execution event data
    /// @dev Complete execution event information
    struct ExecutionEventData {
        bytes32 eventId;                    // Event identifier
        bytes32 tradeId;                    // Trade identifier
        ExecutionDetails execution;         // Execution details
        EconomicTerms terms;                // Economic terms
        bytes32 buyerReference;             // Buyer/receiver party
        bytes32 sellerReference;            // Seller/payer party
        bytes32 brokerReference;            // Broker (if applicable)
        uint256 tradeDate;                  // Trade date (may differ from execution)
        bytes32 metaGlobalKey;              // CDM global key
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Mapping from event ID to execution data
    mapping(bytes32 => ExecutionEventData) public executionData;

    /// @notice Mapping from trade ID to execution event ID
    mapping(bytes32 => bytes32) public tradeExecutionEvent;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event TradeExecuted(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        uint256 executionPrice,
        ExecutionVenueEnum venue,
        uint256 timestamp
    );

    event TradeConfirmed(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        bytes32 buyerReference,
        bytes32 sellerReference
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error ExecutionEvent__TradeAlreadyExecuted();
    error ExecutionEvent__InvalidExecutionPrice();
    error ExecutionEvent__InvalidDates();
    error ExecutionEvent__InvalidParties();
    error ExecutionEvent__TradeNotInCreatedState();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize ExecutionEvent contract
     * @param _tradeState Address of TradeState contract
     */
    constructor(address _tradeState) Event(_tradeState) {}

    // =============================================================================
    // EXECUTION FUNCTIONS
    // =============================================================================

    /**
     * @notice Execute a trade
     * @dev Creates execution event and transitions trade to CONFIRMED
     * @param eventId Unique event identifier
     * @param tradeId Trade identifier
     * @param execution Execution details
     * @param terms Economic terms
     * @param buyer Buyer party reference
     * @param seller Seller party reference
     * @param broker Broker reference (optional, use bytes32(0) if none)
     * @param tradeDate Trade date
     * @return eventRecord Created event record
     */
    function executeTrade(
        bytes32 eventId,
        bytes32 tradeId,
        ExecutionDetails memory execution,
        EconomicTerms memory terms,
        bytes32 buyer,
        bytes32 seller,
        bytes32 broker,
        uint256 tradeDate
    ) public returns (EventRecord memory eventRecord) {
        // Validate
        _validateExecution(eventId, tradeId, execution, terms, buyer, seller);

        // Get current state and validate
        bytes32 beforeStateId = _validateTradeState(tradeId);

        // Create and store execution data
        _createExecutionData(eventId, tradeId, execution, terms, buyer, seller, broker, tradeDate);

        // Build party array
        bytes32[] memory parties = _buildPartyArray(buyer, seller, broker);

        // Create and store event
        eventRecord = _createAndStoreEvent(eventId, tradeId, terms.effectiveDate, parties, buyer, beforeStateId);

        // Transition state and emit events
        _processExecution(eventId, tradeId, buyer, execution);

        return eventRecord;
    }

    /**
     * @notice Validate trade state
     * @dev Internal helper to reduce stack depth
     */
    function _validateTradeState(bytes32 tradeId) internal view returns (bytes32 beforeStateId) {
        TradeState.TradeStateSnapshot memory currentState = tradeState.getCurrentState(tradeId);

        if (currentState.state != TradeState.TradeStateEnum.CREATED) {
            revert ExecutionEvent__TradeNotInCreatedState();
        }

        return currentState.stateId;
    }

    /**
     * @notice Create execution data
     * @dev Internal helper to reduce stack depth
     */
    function _createExecutionData(
        bytes32 eventId,
        bytes32 tradeId,
        ExecutionDetails memory execution,
        EconomicTerms memory terms,
        bytes32 buyer,
        bytes32 seller,
        bytes32 broker,
        uint256 tradeDate
    ) internal {
        executionData[eventId] = ExecutionEventData({
            eventId: eventId,
            tradeId: tradeId,
            execution: execution,
            terms: terms,
            buyerReference: buyer,
            sellerReference: seller,
            brokerReference: broker,
            tradeDate: tradeDate,
            metaGlobalKey: keccak256(abi.encode(eventId, tradeId))
        });

        tradeExecutionEvent[tradeId] = eventId;
    }

    /**
     * @notice Build party array
     * @dev Internal helper to reduce stack depth
     */
    function _buildPartyArray(
        bytes32 buyer,
        bytes32 seller,
        bytes32 broker
    ) internal pure returns (bytes32[] memory parties) {
        parties = new bytes32[](broker == bytes32(0) ? 2 : 3);
        parties[0] = buyer;
        parties[1] = seller;
        if (broker != bytes32(0)) {
            parties[2] = broker;
        }
        return parties;
    }

    /**
     * @notice Create and store event
     * @dev Internal helper to reduce stack depth
     */
    function _createAndStoreEvent(
        bytes32 eventId,
        bytes32 tradeId,
        uint256 effectiveDate,
        bytes32[] memory parties,
        bytes32 buyer,
        bytes32 beforeStateId
    ) internal returns (EventRecord memory eventRecord) {
        EventMetadata memory metadata = _createEventMetadata(
            eventId,
            EventTypeEnum.EXECUTION,
            tradeId,
            effectiveDate,
            parties,
            buyer
        );

        eventRecord = EventRecord({
            metadata: metadata,
            beforeStateId: beforeStateId,
            afterStateId: bytes32(0),
            previousEventId: bytes32(0),
            isValid: true,
            validationMessage: ""
        });

        _storeEvent(eventRecord);

        return eventRecord;
    }

    /**
     * @notice Process execution and emit events
     * @dev Internal helper to reduce stack depth
     */
    function _processExecution(
        bytes32 eventId,
        bytes32 tradeId,
        bytes32 buyer,
        ExecutionDetails memory execution
    ) internal {
        // Transition trade state
        TradeState.TradeStateSnapshot memory newState = tradeState.transitionState(
            tradeId,
            TradeState.TradeStateEnum.CONFIRMED,
            eventId,
            buyer
        );

        // Update event with new state
        _markEventProcessed(eventId, newState.stateId);

        // Emit events
        emit TradeExecuted(
            eventId,
            tradeId,
            execution.executionPrice,
            execution.venue,
            execution.executionTimestamp
        );

        ExecutionEventData memory data = executionData[eventId];
        emit TradeConfirmed(eventId, tradeId, data.buyerReference, data.sellerReference);
    }

    // =============================================================================
    // VALIDATION
    // =============================================================================

    /**
     * @notice Validate execution event
     * @dev Checks all execution requirements
     */
    function _validateExecution(
        bytes32 eventId,
        bytes32 tradeId,
        ExecutionDetails memory execution,
        EconomicTerms memory terms,
        bytes32 buyer,
        bytes32 seller
    ) internal view {
        // Check if trade already has execution event
        if (tradeExecutionEvent[tradeId] != bytes32(0)) {
            revert ExecutionEvent__TradeAlreadyExecuted();
        }

        // Validate event doesn't exist
        if (eventExists[eventId]) {
            revert Event__EventAlreadyExists();
        }

        // Validate parties
        if (buyer == bytes32(0) || seller == bytes32(0)) {
            revert ExecutionEvent__InvalidParties();
        }
        if (buyer == seller) {
            revert ExecutionEvent__InvalidParties();
        }

        // Validate dates
        if (terms.maturityDate <= terms.effectiveDate) {
            revert ExecutionEvent__InvalidDates();
        }
        if (execution.executionTimestamp > terms.effectiveDate) {
            revert ExecutionEvent__InvalidDates();
        }

        // Validate notional
        if (terms.notional == 0) {
            revert ExecutionEvent__InvalidExecutionPrice();
        }
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get execution event data
     * @param eventId Event identifier
     * @return data Execution event data
     */
    function getExecutionData(
        bytes32 eventId
    ) public view returns (ExecutionEventData memory data) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return executionData[eventId];
    }

    /**
     * @notice Get execution event for a trade
     * @param tradeId Trade identifier
     * @return eventId Execution event ID
     */
    function getTradeExecutionEventId(
        bytes32 tradeId
    ) public view returns (bytes32 eventId) {
        return tradeExecutionEvent[tradeId];
    }

    /**
     * @notice Get execution details for a trade
     * @param tradeId Trade identifier
     * @return details Execution details
     */
    function getTradeExecutionDetails(
        bytes32 tradeId
    ) public view returns (ExecutionDetails memory details) {
        bytes32 eventId = tradeExecutionEvent[tradeId];
        if (eventId == bytes32(0)) {
            revert Event__EventDoesNotExist();
        }
        return executionData[eventId].execution;
    }

    /**
     * @notice Get economic terms from execution
     * @param tradeId Trade identifier
     * @return terms Economic terms
     */
    function getTradeEconomicTerms(
        bytes32 tradeId
    ) public view returns (EconomicTerms memory terms) {
        bytes32 eventId = tradeExecutionEvent[tradeId];
        if (eventId == bytes32(0)) {
            revert Event__EventDoesNotExist();
        }
        return executionData[eventId].terms;
    }

    /**
     * @notice Check if trade has been executed
     * @param tradeId Trade identifier
     * @return executed True if trade has execution event
     */
    function isTradeExecuted(
        bytes32 tradeId
    ) public view returns (bool executed) {
        return tradeExecutionEvent[tradeId] != bytes32(0);
    }

    /**
     * @notice Get execution venue
     * @param eventId Event identifier
     * @return venue Execution venue
     */
    function getExecutionVenue(
        bytes32 eventId
    ) public view returns (ExecutionVenueEnum venue) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return executionData[eventId].execution.venue;
    }

    /**
     * @notice Get execution price
     * @param eventId Event identifier
     * @return price Execution price
     */
    function getExecutionPrice(
        bytes32 eventId
    ) public view returns (uint256 price) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return executionData[eventId].execution.executionPrice;
    }

    /**
     * @notice Get trade counterparties
     * @param tradeId Trade identifier
     * @return buyer Buyer party reference
     * @return seller Seller party reference
     */
    function getTradeCounterparties(
        bytes32 tradeId
    ) public view returns (bytes32 buyer, bytes32 seller) {
        bytes32 eventId = tradeExecutionEvent[tradeId];
        if (eventId == bytes32(0)) {
            revert Event__EventDoesNotExist();
        }
        ExecutionEventData memory data = executionData[eventId];
        return (data.buyerReference, data.sellerReference);
    }
}
