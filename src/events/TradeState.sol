// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FixedPoint} from "../base/libraries/FixedPoint.sol";

/**
 * @title TradeState
 * @notice Trade lifecycle state management for CDM events
 * @dev Tracks trade state, transitions, and history following CDM event model
 *
 * KEY FEATURES:
 * - Immutable state snapshots
 * - State transition validation
 * - Full audit trail
 * - Multi-product support
 *
 * STATE LIFECYCLE:
 * CREATED → PENDING → CONFIRMED → ACTIVE → MATURED/TERMINATED → SETTLED
 *
 * EXAMPLE FLOW:
 * 1. Trade created (CREATED)
 * 2. Awaiting confirmation (PENDING)
 * 3. Both parties confirm (CONFIRMED)
 * 4. Effective date reached (ACTIVE)
 * 5. Maturity date reached (MATURED)
 * 6. Final settlement (SETTLED)
 *
 * @author QualitaX Team
 */
contract TradeState {
    using FixedPoint for uint256;

    // =============================================================================
    // CONSTANTS
    // =============================================================================

    /// @notice Fixed-point one (1.0)
    uint256 private constant ONE = 1e18;

    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Trade lifecycle state
    enum TradeStateEnum {
        CREATED,        // Trade created, not yet pending
        PENDING,        // Awaiting confirmation
        CONFIRMED,      // Trade confirmed by all parties
        ACTIVE,         // Trade is active (past effective date)
        MATURED,        // Trade reached maturity
        TERMINATED,     // Trade terminated early
        SETTLED         // All obligations settled
    }

    /// @notice Product type classification
    enum ProductTypeEnum {
        INTEREST_RATE_SWAP,
        NON_DELIVERABLE_FORWARD,
        INTEREST_RATE_PAYOUT,
        UNKNOWN
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Trade state snapshot
    /// @dev Immutable snapshot of trade state at a point in time
    struct TradeStateSnapshot {
        bytes32 tradeId;                    // Unique trade identifier
        TradeStateEnum state;               // Current state
        ProductTypeEnum productType;        // Product classification
        uint256 timestamp;                  // State timestamp
        bytes32 eventId;                    // Event that caused this state
        bytes32 previousStateId;            // Previous state snapshot ID
        bytes32 stateId;                    // This state snapshot ID
        bytes32[] partyReferences;          // Parties to the trade
        uint256 effectiveDate;              // Trade effective date
        uint256 maturityDate;               // Trade maturity date
        bytes32 metaGlobalKey;              // CDM global key
    }

    /// @notice State transition record
    /// @dev Records a state change for audit trail
    struct StateTransition {
        bytes32 transitionId;               // Unique transition ID
        bytes32 tradeId;                    // Trade identifier
        TradeStateEnum fromState;           // Previous state
        TradeStateEnum toState;             // New state
        bytes32 eventId;                    // Triggering event
        uint256 timestamp;                  // Transition timestamp
        bytes32 initiatorReference;         // Party that initiated
        bool isValid;                       // Validation result
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Mapping from trade ID to current state snapshot
    mapping(bytes32 => TradeStateSnapshot) public currentStates;

    /// @notice Mapping from state ID to state snapshot (full history)
    mapping(bytes32 => TradeStateSnapshot) public stateHistory;

    /// @notice Mapping from trade ID to array of state transitions
    mapping(bytes32 => StateTransition[]) public tradeTransitions;

    /// @notice Mapping from trade ID to creation timestamp
    mapping(bytes32 => uint256) public tradeCreationTime;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event TradeCreated(
        bytes32 indexed tradeId,
        ProductTypeEnum productType,
        bytes32 stateId,
        uint256 timestamp
    );

    event StateTransitioned(
        bytes32 indexed tradeId,
        TradeStateEnum indexed fromState,
        TradeStateEnum indexed toState,
        bytes32 eventId,
        bytes32 stateId
    );

    event TradeSettled(
        bytes32 indexed tradeId,
        uint256 settlementTimestamp
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error TradeState__TradeAlreadyExists();
    error TradeState__TradeDoesNotExist();
    error TradeState__InvalidStateTransition();
    error TradeState__InvalidDates();
    error TradeState__TradeNotActive();
    error TradeState__TradeAlreadySettled();
    error TradeState__InvalidProductType();

    // =============================================================================
    // TRADE CREATION
    // =============================================================================

    /**
     * @notice Create a new trade
     * @dev Initializes trade in CREATED state
     * @param tradeId Unique trade identifier
     * @param productType Product type classification
     * @param parties Array of party references
     * @param effectiveDate Trade effective date
     * @param maturityDate Trade maturity date
     * @return stateSnapshot Initial state snapshot
     */
    function createTrade(
        bytes32 tradeId,
        ProductTypeEnum productType,
        bytes32[] memory parties,
        uint256 effectiveDate,
        uint256 maturityDate
    ) public returns (TradeStateSnapshot memory stateSnapshot) {
        // Validate
        if (currentStates[tradeId].tradeId != bytes32(0)) {
            revert TradeState__TradeAlreadyExists();
        }
        if (maturityDate <= effectiveDate) {
            revert TradeState__InvalidDates();
        }
        if (productType == ProductTypeEnum.UNKNOWN) {
            revert TradeState__InvalidProductType();
        }

        // Create initial state snapshot
        bytes32 stateId = keccak256(abi.encodePacked(
            tradeId,
            TradeStateEnum.CREATED,
            block.timestamp
        ));

        stateSnapshot = TradeStateSnapshot({
            tradeId: tradeId,
            state: TradeStateEnum.CREATED,
            productType: productType,
            timestamp: block.timestamp,
            eventId: bytes32(0),  // No event for creation
            previousStateId: bytes32(0),
            stateId: stateId,
            partyReferences: parties,
            effectiveDate: effectiveDate,
            maturityDate: maturityDate,
            metaGlobalKey: keccak256(abi.encode(tradeId))
        });

        // Store
        currentStates[tradeId] = stateSnapshot;
        stateHistory[stateId] = stateSnapshot;
        tradeCreationTime[tradeId] = block.timestamp;

        emit TradeCreated(tradeId, productType, stateId, block.timestamp);

        return stateSnapshot;
    }

    // =============================================================================
    // STATE TRANSITIONS
    // =============================================================================

    /**
     * @notice Transition trade to new state
     * @dev Validates transition and creates new state snapshot
     * @param tradeId Trade identifier
     * @param newState Target state
     * @param eventId Event triggering the transition
     * @param initiator Party initiating the transition
     * @return stateSnapshot New state snapshot
     */
    function transitionState(
        bytes32 tradeId,
        TradeStateEnum newState,
        bytes32 eventId,
        bytes32 initiator
    ) public returns (TradeStateSnapshot memory stateSnapshot) {
        // Get current state
        TradeStateSnapshot memory currentState = currentStates[tradeId];
        if (currentState.tradeId == bytes32(0)) {
            revert TradeState__TradeDoesNotExist();
        }

        // Validate transition
        if (!isValidTransition(currentState.state, newState)) {
            revert TradeState__InvalidStateTransition();
        }

        // Create new state snapshot
        bytes32 stateId = keccak256(abi.encodePacked(
            tradeId,
            newState,
            block.timestamp,
            eventId
        ));

        stateSnapshot = TradeStateSnapshot({
            tradeId: tradeId,
            state: newState,
            productType: currentState.productType,
            timestamp: block.timestamp,
            eventId: eventId,
            previousStateId: currentState.stateId,
            stateId: stateId,
            partyReferences: currentState.partyReferences,
            effectiveDate: currentState.effectiveDate,
            maturityDate: currentState.maturityDate,
            metaGlobalKey: currentState.metaGlobalKey
        });

        // Record transition
        StateTransition memory transition = StateTransition({
            transitionId: keccak256(abi.encodePacked(tradeId, currentState.state, newState, block.timestamp)),
            tradeId: tradeId,
            fromState: currentState.state,
            toState: newState,
            eventId: eventId,
            timestamp: block.timestamp,
            initiatorReference: initiator,
            isValid: true
        });

        // Update storage
        currentStates[tradeId] = stateSnapshot;
        stateHistory[stateId] = stateSnapshot;
        tradeTransitions[tradeId].push(transition);

        emit StateTransitioned(tradeId, currentState.state, newState, eventId, stateId);

        // Special handling for settlement
        if (newState == TradeStateEnum.SETTLED) {
            emit TradeSettled(tradeId, block.timestamp);
        }

        return stateSnapshot;
    }

    /**
     * @notice Validate if state transition is allowed
     * @param fromState Current state
     * @param toState Target state
     * @return valid True if transition is valid
     */
    function isValidTransition(
        TradeStateEnum fromState,
        TradeStateEnum toState
    ) public pure returns (bool valid) {
        // CREATED can go to PENDING or CONFIRMED
        if (fromState == TradeStateEnum.CREATED) {
            return toState == TradeStateEnum.PENDING || toState == TradeStateEnum.CONFIRMED;
        }

        // PENDING can go to CONFIRMED or back to CREATED
        if (fromState == TradeStateEnum.PENDING) {
            return toState == TradeStateEnum.CONFIRMED || toState == TradeStateEnum.CREATED;
        }

        // CONFIRMED can go to ACTIVE or TERMINATED
        if (fromState == TradeStateEnum.CONFIRMED) {
            return toState == TradeStateEnum.ACTIVE || toState == TradeStateEnum.TERMINATED;
        }

        // ACTIVE can go to MATURED or TERMINATED
        if (fromState == TradeStateEnum.ACTIVE) {
            return toState == TradeStateEnum.MATURED || toState == TradeStateEnum.TERMINATED;
        }

        // MATURED can only go to SETTLED
        if (fromState == TradeStateEnum.MATURED) {
            return toState == TradeStateEnum.SETTLED;
        }

        // TERMINATED can only go to SETTLED
        if (fromState == TradeStateEnum.TERMINATED) {
            return toState == TradeStateEnum.SETTLED;
        }

        // SETTLED is final
        if (fromState == TradeStateEnum.SETTLED) {
            return false;
        }

        return false;
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get current state of a trade
     * @param tradeId Trade identifier
     * @return stateSnapshot Current state snapshot
     */
    function getCurrentState(
        bytes32 tradeId
    ) public view returns (TradeStateSnapshot memory stateSnapshot) {
        stateSnapshot = currentStates[tradeId];
        if (stateSnapshot.tradeId == bytes32(0)) {
            revert TradeState__TradeDoesNotExist();
        }
        return stateSnapshot;
    }

    /**
     * @notice Get full state history for a trade
     * @param tradeId Trade identifier
     * @return transitions Array of state transitions
     */
    function getStateHistory(
        bytes32 tradeId
    ) public view returns (StateTransition[] memory transitions) {
        if (currentStates[tradeId].tradeId == bytes32(0)) {
            revert TradeState__TradeDoesNotExist();
        }
        return tradeTransitions[tradeId];
    }

    /**
     * @notice Check if trade is in a specific state
     * @param tradeId Trade identifier
     * @param state State to check
     * @return inState True if trade is in the specified state
     */
    function isInState(
        bytes32 tradeId,
        TradeStateEnum state
    ) public view returns (bool inState) {
        TradeStateSnapshot memory currentState = currentStates[tradeId];
        if (currentState.tradeId == bytes32(0)) {
            return false;
        }
        return currentState.state == state;
    }

    /**
     * @notice Check if trade is active
     * @param tradeId Trade identifier
     * @return active True if trade is in ACTIVE state
     */
    function isActive(bytes32 tradeId) public view returns (bool active) {
        return isInState(tradeId, TradeStateEnum.ACTIVE);
    }

    /**
     * @notice Check if trade is settled
     * @param tradeId Trade identifier
     * @return settled True if trade is in SETTLED state
     */
    function isSettled(bytes32 tradeId) public view returns (bool settled) {
        return isInState(tradeId, TradeStateEnum.SETTLED);
    }

    /**
     * @notice Get time since trade creation
     * @param tradeId Trade identifier
     * @return duration Time in seconds since creation
     */
    function getTradeAge(bytes32 tradeId) public view returns (uint256 duration) {
        if (currentStates[tradeId].tradeId == bytes32(0)) {
            revert TradeState__TradeDoesNotExist();
        }
        return block.timestamp - tradeCreationTime[tradeId];
    }

    /**
     * @notice Get number of state transitions
     * @param tradeId Trade identifier
     * @return count Number of state transitions
     */
    function getTransitionCount(bytes32 tradeId) public view returns (uint256 count) {
        return tradeTransitions[tradeId].length;
    }

    /**
     * @notice Check if trade has reached effective date
     * @param tradeId Trade identifier
     * @return effective True if current time >= effective date
     */
    function hasReachedEffectiveDate(bytes32 tradeId) public view returns (bool effective) {
        TradeStateSnapshot memory state = getCurrentState(tradeId);
        return block.timestamp >= state.effectiveDate;
    }

    /**
     * @notice Check if trade has reached maturity
     * @param tradeId Trade identifier
     * @return matured True if current time >= maturity date
     */
    function hasReachedMaturity(bytes32 tradeId) public view returns (bool matured) {
        TradeStateSnapshot memory state = getCurrentState(tradeId);
        return block.timestamp >= state.maturityDate;
    }

    /**
     * @notice Get time until maturity
     * @param tradeId Trade identifier
     * @return timeRemaining Seconds until maturity (0 if already matured)
     */
    function getTimeToMaturity(bytes32 tradeId) public view returns (uint256 timeRemaining) {
        TradeStateSnapshot memory state = getCurrentState(tradeId);
        if (block.timestamp >= state.maturityDate) {
            return 0;
        }
        return state.maturityDate - block.timestamp;
    }
}
