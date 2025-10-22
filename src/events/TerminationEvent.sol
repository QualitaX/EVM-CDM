// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Event} from "./Event.sol";
import {TradeState} from "./TradeState.sol";

/**
 * @title TerminationEvent
 * @notice Trade early termination event
 * @dev Represents early termination of a trade before maturity
 *
 * KEY FEATURES:
 * - Early termination handling
 * - Termination payment calculation
 * - State transition to TERMINATED
 * - Termination reason tracking
 * - Final settlement coordination
 *
 * TERMINATION FLOW:
 * 1. Trade is ACTIVE or CONFIRMED
 * 2. Termination event triggered
 * 3. Termination payment calculated
 * 4. Trade transitions to TERMINATED
 * 5. Final settlement via TransferEvent
 * 6. Trade transitions to SETTLED
 *
 * TYPICAL USE CASES:
 * - Early termination by mutual agreement
 * - Default termination
 * - Novation termination
 * - Regulatory termination
 *
 * @author QualitaX Team
 */
contract TerminationEvent is Event {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Termination type
    enum TerminationTypeEnum {
        MUTUAL_AGREEMENT,       // Bilateral termination agreement
        UNILATERAL,             // One party terminates
        DEFAULT,                // Default/breach termination
        NOVATION,               // Termination due to novation
        REGULATORY,             // Regulatory requirement
        FORCE_MAJEURE,          // Force majeure event
        MATURITY                // Natural maturity (not early termination)
    }

    /// @notice Termination calculation method
    enum TerminationCalculationEnum {
        MARKET_VALUE,           // Market value of position
        REPLACEMENT_VALUE,      // Replacement cost
        AGREED_VALUE,           // Bilaterally agreed value
        CLOSE_OUT_VALUE,        // Close-out valuation (ISDA)
        ZERO                    // No termination payment
    }

    /// @notice Termination status
    enum TerminationStatusEnum {
        PENDING,                // Termination pending
        CONFIRMED,              // Termination confirmed
        SETTLED,                // Termination payment settled
        DISPUTED,               // Termination disputed
        CANCELLED               // Termination cancelled
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Termination details
    /// @dev Core termination information
    struct TerminationDetails {
        TerminationTypeEnum terminationType;        // Type of termination
        uint256 terminationDate;                    // Termination effective date
        uint256 notificationDate;                   // Notification date
        bytes32 terminatingParty;                   // Party initiating termination
        bytes32 terminationReason;                  // Reason for termination
        bool isMutual;                              // Whether termination is mutual
        bytes32 externalReference;                  // External reference (e.g., legal notice)
    }

    /// @notice Termination payment calculation
    /// @dev Valuation details for termination payment
    struct TerminationPayment {
        TerminationCalculationEnum calculationMethod; // Calculation method
        uint256 terminationValue;                   // Calculated termination value
        bytes32 currency;                           // Payment currency
        bytes32 payerReference;                     // Party making payment
        bytes32 receiverReference;                  // Party receiving payment
        uint256 paymentDate;                        // Payment date
        bytes32 valuationReference;                 // Valuation reference/source
        bool isDisputed;                            // Whether value is disputed
    }

    /// @notice Termination event data
    /// @dev Complete termination event information
    struct TerminationEventData {
        bytes32 eventId;                            // Event identifier
        bytes32 tradeId;                            // Trade identifier
        TerminationDetails details;                 // Termination details
        TerminationPayment payment;                 // Payment details
        TerminationStatusEnum status;               // Termination status
        bytes32 settlementTransferId;               // Related settlement transfer
        bytes32[] relatedEventIds;                  // Related events (resets, transfers)
        bytes32 metaGlobalKey;                      // CDM global key
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Mapping from event ID to termination data
    mapping(bytes32 => TerminationEventData) public terminationData;

    /// @notice Mapping from trade ID to termination event ID
    mapping(bytes32 => bytes32) public tradeTermination;

    /// @notice Mapping from termination reference to event ID
    mapping(bytes32 => bytes32) public terminationByReference;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event TradeTerminated(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        TerminationTypeEnum terminationType,
        uint256 terminationDate,
        bytes32 terminatingParty
    );

    event TerminationConfirmed(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        uint256 terminationValue,
        bytes32 currency
    );

    event TerminationDisputed(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        bytes32 disputingParty,
        string reason
    );

    event TerminationSettled(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        bytes32 settlementTransferId
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error TerminationEvent__TradeNotActive();
    error TerminationEvent__TradeAlreadyTerminated();
    error TerminationEvent__InvalidTerminationDate();
    error TerminationEvent__InvalidPaymentDetails();
    error TerminationEvent__InvalidParties();
    error TerminationEvent__AlreadySettled();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize TerminationEvent contract
     * @param _tradeState Address of TradeState contract
     */
    constructor(address _tradeState) Event(_tradeState) {}

    // =============================================================================
    // TERMINATION FUNCTIONS
    // =============================================================================

    /**
     * @notice Record a trade termination
     * @dev Creates termination event and transitions trade to TERMINATED
     * @param eventId Unique event identifier
     * @param tradeId Trade identifier
     * @param details Termination details
     * @param payment Payment calculation details
     * @param initiator Party initiating termination
     * @return eventRecord Created event record
     */
    function terminateTrade(
        bytes32 eventId,
        bytes32 tradeId,
        TerminationDetails memory details,
        TerminationPayment memory payment,
        bytes32 initiator
    ) public returns (EventRecord memory eventRecord) {
        // Validate
        _validateTermination(eventId, tradeId, details, payment);

        // Create termination data
        TerminationEventData memory terminationEventData = _createTerminationData(
            eventId,
            tradeId,
            details,
            payment
        );

        // Store termination
        _storeTermination(terminationEventData);

        // Create event record and transition state
        eventRecord = _createTerminationEventRecord(eventId, tradeId, details, initiator);

        // Emit events
        emit TradeTerminated(
            eventId,
            tradeId,
            details.terminationType,
            details.terminationDate,
            details.terminatingParty
        );

        return eventRecord;
    }

    /**
     * @notice Confirm a termination
     * @dev Marks termination as confirmed by all parties
     * @param eventId Termination event identifier
     */
    function confirmTermination(bytes32 eventId) public {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }

        TerminationEventData storage data = terminationData[eventId];

        // Update status
        data.status = TerminationStatusEnum.CONFIRMED;

        emit TerminationConfirmed(
            eventId,
            data.tradeId,
            data.payment.terminationValue,
            data.payment.currency
        );
    }

    /**
     * @notice Dispute a termination
     * @dev Records dispute over termination terms
     * @param eventId Termination event identifier
     * @param disputingParty Party disputing the termination
     * @param reason Dispute reason
     */
    function disputeTermination(
        bytes32 eventId,
        bytes32 disputingParty,
        string memory reason
    ) public {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }

        TerminationEventData storage data = terminationData[eventId];

        // Update status
        data.status = TerminationStatusEnum.DISPUTED;
        data.payment.isDisputed = true;

        emit TerminationDisputed(eventId, data.tradeId, disputingParty, reason);
    }

    /**
     * @notice Link settlement transfer to termination
     * @dev Records the transfer event that settles the termination payment
     * @param eventId Termination event identifier
     * @param settlementTransferId Transfer event ID
     */
    function linkSettlementTransfer(
        bytes32 eventId,
        bytes32 settlementTransferId
    ) public {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }

        TerminationEventData storage data = terminationData[eventId];

        if (data.status == TerminationStatusEnum.SETTLED) {
            revert TerminationEvent__AlreadySettled();
        }

        data.settlementTransferId = settlementTransferId;
        data.status = TerminationStatusEnum.SETTLED;

        emit TerminationSettled(eventId, data.tradeId, settlementTransferId);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @notice Validate termination event
     * @dev Internal validation helper
     */
    function _validateTermination(
        bytes32 eventId,
        bytes32 tradeId,
        TerminationDetails memory details,
        TerminationPayment memory payment
    ) internal view {
        // Check event doesn't exist
        if (eventExists[eventId]) {
            revert Event__EventAlreadyExists();
        }

        // Check trade not already terminated
        if (tradeTermination[tradeId] != bytes32(0)) {
            revert TerminationEvent__TradeAlreadyTerminated();
        }

        // Validate trade state
        TradeState.TradeStateSnapshot memory currentState = tradeState.getCurrentState(tradeId);
        if (currentState.state != TradeState.TradeStateEnum.ACTIVE &&
            currentState.state != TradeState.TradeStateEnum.CONFIRMED) {
            revert TerminationEvent__TradeNotActive();
        }

        // Validate dates
        if (details.terminationDate < block.timestamp) {
            revert TerminationEvent__InvalidTerminationDate();
        }
        if (details.notificationDate > details.terminationDate) {
            revert TerminationEvent__InvalidTerminationDate();
        }

        // Validate payment parties
        if (payment.calculationMethod != TerminationCalculationEnum.ZERO) {
            if (payment.payerReference == bytes32(0) || payment.receiverReference == bytes32(0)) {
                revert TerminationEvent__InvalidPaymentDetails();
            }
            if (payment.payerReference == payment.receiverReference) {
                revert TerminationEvent__InvalidParties();
            }
        }
    }

    /**
     * @notice Create termination data
     * @dev Internal helper to build termination data struct
     */
    function _createTerminationData(
        bytes32 eventId,
        bytes32 tradeId,
        TerminationDetails memory details,
        TerminationPayment memory payment
    ) internal pure returns (TerminationEventData memory) {
        return TerminationEventData({
            eventId: eventId,
            tradeId: tradeId,
            details: details,
            payment: payment,
            status: TerminationStatusEnum.PENDING,
            settlementTransferId: bytes32(0),
            relatedEventIds: new bytes32[](0),
            metaGlobalKey: keccak256(abi.encode(eventId, tradeId))
        });
    }

    /**
     * @notice Store termination data
     * @dev Internal helper to persist termination
     */
    function _storeTermination(TerminationEventData memory data) internal {
        terminationData[data.eventId] = data;
        tradeTermination[data.tradeId] = data.eventId;

        if (data.details.externalReference != bytes32(0)) {
            terminationByReference[data.details.externalReference] = data.eventId;
        }
    }

    /**
     * @notice Create termination event record
     * @dev Internal helper to build event record and transition state
     */
    function _createTerminationEventRecord(
        bytes32 eventId,
        bytes32 tradeId,
        TerminationDetails memory details,
        bytes32 initiator
    ) internal returns (EventRecord memory) {
        TradeState.TradeStateSnapshot memory currentState = tradeState.getCurrentState(tradeId);

        bytes32[] memory parties = new bytes32[](1);
        parties[0] = details.terminatingParty;

        EventMetadata memory metadata = _createEventMetadata(
            eventId,
            EventTypeEnum.TERMINATION,
            tradeId,
            details.terminationDate,
            parties,
            initiator
        );

        EventRecord memory eventRecord = EventRecord({
            metadata: metadata,
            beforeStateId: currentState.stateId,
            afterStateId: bytes32(0), // Will be set after state transition
            previousEventId: getLastTradeEvent(tradeId),
            isValid: true,
            validationMessage: ""
        });

        _storeEvent(eventRecord);

        // Transition trade state to TERMINATED
        TradeState.TradeStateSnapshot memory newState = tradeState.transitionState(
            tradeId,
            TradeState.TradeStateEnum.TERMINATED,
            eventId,
            initiator
        );

        _markEventProcessed(eventId, newState.stateId);

        return eventRecord;
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get termination event data
     * @param eventId Event identifier
     * @return data Termination event data
     */
    function getTerminationData(
        bytes32 eventId
    ) public view returns (TerminationEventData memory data) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return terminationData[eventId];
    }

    /**
     * @notice Get termination event for a trade
     * @param tradeId Trade identifier
     * @return eventId Termination event ID
     */
    function getTradeTerminationEventId(
        bytes32 tradeId
    ) public view returns (bytes32 eventId) {
        return tradeTermination[tradeId];
    }

    /**
     * @notice Check if trade is terminated
     * @param tradeId Trade identifier
     * @return terminated True if trade has termination event
     */
    function isTradeTerminated(
        bytes32 tradeId
    ) public view returns (bool terminated) {
        return tradeTermination[tradeId] != bytes32(0);
    }

    /**
     * @notice Get termination details
     * @param eventId Event identifier
     * @return details Termination details
     */
    function getTerminationDetails(
        bytes32 eventId
    ) public view returns (TerminationDetails memory details) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return terminationData[eventId].details;
    }

    /**
     * @notice Get termination payment
     * @param eventId Event identifier
     * @return payment Payment details
     */
    function getTerminationPayment(
        bytes32 eventId
    ) public view returns (TerminationPayment memory payment) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return terminationData[eventId].payment;
    }

    /**
     * @notice Get termination status
     * @param eventId Event identifier
     * @return status Termination status
     */
    function getTerminationStatus(
        bytes32 eventId
    ) public view returns (TerminationStatusEnum status) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return terminationData[eventId].status;
    }

    /**
     * @notice Check if termination is settled
     * @param eventId Event identifier
     * @return settled True if termination is settled
     */
    function isTerminationSettled(
        bytes32 eventId
    ) public view returns (bool settled) {
        if (!eventExists[eventId]) {
            return false;
        }
        return terminationData[eventId].status == TerminationStatusEnum.SETTLED;
    }

    /**
     * @notice Check if termination is disputed
     * @param eventId Event identifier
     * @return disputed True if termination is disputed
     */
    function isTerminationDisputed(
        bytes32 eventId
    ) public view returns (bool disputed) {
        if (!eventExists[eventId]) {
            return false;
        }
        return terminationData[eventId].payment.isDisputed;
    }

    /**
     * @notice Get termination value
     * @param eventId Event identifier
     * @return value Termination value
     */
    function getTerminationValue(
        bytes32 eventId
    ) public view returns (uint256 value) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return terminationData[eventId].payment.terminationValue;
    }

    /**
     * @notice Get termination type
     * @param eventId Event identifier
     * @return terminationType Termination type
     */
    function getTerminationType(
        bytes32 eventId
    ) public view returns (TerminationTypeEnum terminationType) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return terminationData[eventId].details.terminationType;
    }
}
