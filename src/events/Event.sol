// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TradeState} from "./TradeState.sol";

/**
 * @title Event
 * @notice Base event structure for CDM lifecycle events
 * @dev Provides common event infrastructure for all CDM event types
 *
 * KEY FEATURES:
 * - Immutable event records
 * - Trade state integration
 * - Multi-party support
 * - Event lineage tracking
 *
 * EVENT TYPES:
 * - EXECUTION: Trade inception/execution
 * - RESET: Floating rate observation/reset
 * - TRANSFER: Payment/settlement transfer
 * - TERMINATION: Early termination
 * - NOVATION: Trade novation (future)
 * - EXERCISE: Option exercise (future)
 *
 * DESIGN PRINCIPLES:
 * 1. Events are immutable once created
 * 2. Events must reference valid trades
 * 3. Events create new trade state snapshots
 * 4. Full audit trail maintained
 *
 * @author QualitaX Team
 */
contract Event {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Event type classification
    enum EventTypeEnum {
        EXECUTION,      // Trade execution
        RESET,          // Rate reset/observation
        TRANSFER,       // Payment transfer
        TERMINATION,    // Trade termination
        NOVATION,       // Trade novation (future)
        EXERCISE        // Option exercise (future)
    }

    /// @notice Event status
    enum EventStatusEnum {
        PENDING,        // Event created, not yet processed
        PROCESSED,      // Event successfully processed
        FAILED,         // Event processing failed
        CANCELLED       // Event cancelled
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Core event metadata
    /// @dev Common fields for all event types
    struct EventMetadata {
        bytes32 eventId;                    // Unique event identifier
        EventTypeEnum eventType;            // Event type classification
        EventStatusEnum status;             // Event processing status
        uint256 timestamp;                  // Event timestamp
        uint256 effectiveDate;              // Event effective date
        bytes32 tradeId;                    // Affected trade
        bytes32[] partyReferences;          // Parties involved
        bytes32 initiatorReference;         // Party that initiated event
        bytes32 metaGlobalKey;              // CDM global key
    }

    /// @notice Event record with state change
    /// @dev Links event to resulting trade state
    struct EventRecord {
        EventMetadata metadata;             // Event metadata
        bytes32 beforeStateId;              // Trade state before event
        bytes32 afterStateId;               // Trade state after event
        bytes32 previousEventId;            // Previous event in chain
        bool isValid;                       // Validation result
        string validationMessage;           // Validation message (if failed)
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Reference to TradeState contract
    TradeState public immutable tradeState;

    /// @notice Mapping from event ID to event record
    mapping(bytes32 => EventRecord) public events;

    /// @notice Mapping from trade ID to event IDs
    mapping(bytes32 => bytes32[]) public tradeEvents;

    /// @notice Mapping from event ID to existence check
    mapping(bytes32 => bool) public eventExists;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event EventCreated(
        bytes32 indexed eventId,
        EventTypeEnum indexed eventType,
        bytes32 indexed tradeId,
        uint256 timestamp
    );

    event EventProcessed(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        bytes32 beforeStateId,
        bytes32 afterStateId
    );

    event EventFailed(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        string reason
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error Event__EventAlreadyExists();
    error Event__EventDoesNotExist();
    error Event__TradeDoesNotExist();
    error Event__InvalidEffectiveDate();
    error Event__InvalidParties();
    error Event__EventAlreadyProcessed();
    error Event__InvalidEventType();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize Event contract
     * @param _tradeState Address of TradeState contract
     */
    constructor(address _tradeState) {
        require(_tradeState != address(0), "Invalid TradeState address");
        tradeState = TradeState(_tradeState);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @notice Create event metadata
     * @dev Internal function for event creation
     * @param eventId Unique event identifier
     * @param eventType Type of event
     * @param tradeId Trade identifier
     * @param effectiveDate Event effective date
     * @param parties Party references
     * @param initiator Initiating party
     * @return metadata Event metadata struct
     */
    function _createEventMetadata(
        bytes32 eventId,
        EventTypeEnum eventType,
        bytes32 tradeId,
        uint256 effectiveDate,
        bytes32[] memory parties,
        bytes32 initiator
    ) internal view returns (EventMetadata memory metadata) {
        metadata = EventMetadata({
            eventId: eventId,
            eventType: eventType,
            status: EventStatusEnum.PENDING,
            timestamp: block.timestamp,
            effectiveDate: effectiveDate,
            tradeId: tradeId,
            partyReferences: parties,
            initiatorReference: initiator,
            metaGlobalKey: keccak256(abi.encode(eventId, tradeId))
        });

        return metadata;
    }

    /**
     * @notice Validate event creation
     * @dev Checks basic event requirements
     * @param eventId Event identifier
     * @param tradeId Trade identifier
     * @param effectiveDate Event effective date
     * @param parties Party references
     */
    function _validateEvent(
        bytes32 eventId,
        bytes32 tradeId,
        uint256 effectiveDate,
        bytes32[] memory parties
    ) internal view {
        // Check event doesn't exist
        if (eventExists[eventId]) {
            revert Event__EventAlreadyExists();
        }

        // Check trade exists
        TradeState.TradeStateSnapshot memory currentState = tradeState.getCurrentState(tradeId);
        if (currentState.tradeId == bytes32(0)) {
            revert Event__TradeDoesNotExist();
        }

        // Check effective date is not in past
        if (effectiveDate < block.timestamp) {
            revert Event__InvalidEffectiveDate();
        }

        // Check parties array
        if (parties.length == 0) {
            revert Event__InvalidParties();
        }
    }

    /**
     * @notice Store event record
     * @dev Internal function to persist event
     * @param record Event record to store
     */
    function _storeEvent(EventRecord memory record) internal {
        bytes32 eventId = record.metadata.eventId;
        bytes32 tradeId = record.metadata.tradeId;

        events[eventId] = record;
        tradeEvents[tradeId].push(eventId);
        eventExists[eventId] = true;

        emit EventCreated(
            eventId,
            record.metadata.eventType,
            tradeId,
            record.metadata.timestamp
        );
    }

    /**
     * @notice Mark event as processed
     * @dev Updates event status and emits event
     * @param eventId Event identifier
     * @param afterStateId New trade state ID
     */
    function _markEventProcessed(
        bytes32 eventId,
        bytes32 afterStateId
    ) internal {
        EventRecord storage record = events[eventId];
        record.metadata.status = EventStatusEnum.PROCESSED;
        record.afterStateId = afterStateId;

        emit EventProcessed(
            eventId,
            record.metadata.tradeId,
            record.beforeStateId,
            afterStateId
        );
    }

    /**
     * @notice Mark event as failed
     * @dev Updates event status with failure reason
     * @param eventId Event identifier
     * @param reason Failure reason
     */
    function _markEventFailed(
        bytes32 eventId,
        string memory reason
    ) internal {
        EventRecord storage record = events[eventId];
        record.metadata.status = EventStatusEnum.FAILED;
        record.isValid = false;
        record.validationMessage = reason;

        emit EventFailed(eventId, record.metadata.tradeId, reason);
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get event record
     * @param eventId Event identifier
     * @return record Event record
     */
    function getEvent(
        bytes32 eventId
    ) public view returns (EventRecord memory record) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return events[eventId];
    }

    /**
     * @notice Get all events for a trade
     * @param tradeId Trade identifier
     * @return eventIds Array of event IDs
     */
    function getTradeEvents(
        bytes32 tradeId
    ) public view returns (bytes32[] memory eventIds) {
        return tradeEvents[tradeId];
    }

    /**
     * @notice Get event count for a trade
     * @param tradeId Trade identifier
     * @return count Number of events
     */
    function getTradeEventCount(
        bytes32 tradeId
    ) public view returns (uint256 count) {
        return tradeEvents[tradeId].length;
    }

    /**
     * @notice Check if event is processed
     * @param eventId Event identifier
     * @return processed True if event is processed
     */
    function isEventProcessed(
        bytes32 eventId
    ) public view returns (bool processed) {
        if (!eventExists[eventId]) {
            return false;
        }
        return events[eventId].metadata.status == EventStatusEnum.PROCESSED;
    }

    /**
     * @notice Get event metadata
     * @param eventId Event identifier
     * @return metadata Event metadata
     */
    function getEventMetadata(
        bytes32 eventId
    ) public view returns (EventMetadata memory metadata) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return events[eventId].metadata;
    }

    /**
     * @notice Get event type
     * @param eventId Event identifier
     * @return eventType Event type
     */
    function getEventType(
        bytes32 eventId
    ) public view returns (EventTypeEnum eventType) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return events[eventId].metadata.eventType;
    }

    /**
     * @notice Get events by type for a trade
     * @param tradeId Trade identifier
     * @param eventType Event type to filter
     * @return eventIds Array of matching event IDs
     */
    function getTradeEventsByType(
        bytes32 tradeId,
        EventTypeEnum eventType
    ) public view returns (bytes32[] memory eventIds) {
        bytes32[] memory allEvents = tradeEvents[tradeId];
        uint256 matchCount = 0;

        // Count matches
        for (uint256 i = 0; i < allEvents.length; i++) {
            if (events[allEvents[i]].metadata.eventType == eventType) {
                matchCount++;
            }
        }

        // Build result array
        eventIds = new bytes32[](matchCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allEvents.length; i++) {
            if (events[allEvents[i]].metadata.eventType == eventType) {
                eventIds[index] = allEvents[i];
                index++;
            }
        }

        return eventIds;
    }

    /**
     * @notice Get last event for a trade
     * @param tradeId Trade identifier
     * @return eventId Last event ID (or bytes32(0) if none)
     */
    function getLastTradeEvent(
        bytes32 tradeId
    ) public view returns (bytes32 eventId) {
        bytes32[] memory eventIds = tradeEvents[tradeId];
        if (eventIds.length == 0) {
            return bytes32(0);
        }
        return eventIds[eventIds.length - 1];
    }
}
