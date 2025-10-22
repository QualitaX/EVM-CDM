// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Event} from "./Event.sol";
import {TradeState} from "./TradeState.sol";

/**
 * @title ResetEvent
 * @notice Floating rate observation/reset event
 * @dev Represents the observation and fixing of floating rates for calculation periods
 *
 * KEY FEATURES:
 * - Floating rate observation capture
 * - Rate index fixing (SOFR, LIBOR, etc.)
 * - Period-specific reset tracking
 * - Calculation amount determination
 * - Historical rate fixing audit trail
 *
 * RESET FLOW:
 * 1. Trade is ACTIVE with floating leg
 * 2. Reset date arrives for a calculation period
 * 3. ResetEvent captures observed rate
 * 4. Accrual calculation updated
 * 5. Trade remains ACTIVE, awaits next reset/payment
 *
 * TYPICAL USE CASE:
 * Interest Rate Swap with SOFR floating leg
 * - Quarterly reset dates
 * - SOFR observed at reset date
 * - Applied to next calculation period
 * - Used for payment calculation
 *
 * @author QualitaX Team
 */
contract ResetEvent is Event {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Rate index type
    enum RateIndexEnum {
        SOFR,               // Secured Overnight Financing Rate
        LIBOR,              // London Interbank Offered Rate (legacy)
        EURIBOR,            // Euro Interbank Offered Rate
        SONIA,              // Sterling Overnight Index Average
        ESTR,               // Euro Short-Term Rate
        TONAR,              // Tokyo Overnight Average Rate
        CUSTOM              // Custom/proprietary index
    }

    /// @notice Reset source
    enum ResetSourceEnum {
        PUBLISHED,          // Published fixing (e.g., from central bank)
        INTERPOLATED,       // Interpolated from multiple fixings
        FALLBACK,           // Fallback rate (e.g., when primary unavailable)
        MANUAL              // Manually provided (e.g., bilateral agreement)
    }

    /// @notice Reset averaging method
    enum AveragingMethodEnum {
        NONE,               // Single observation
        SIMPLE,             // Simple arithmetic average
        WEIGHTED,           // Weighted average
        COMPOUNDED          // Compounded (e.g., for SOFR)
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Rate observation details
    /// @dev Core rate fixing information
    struct RateObservation {
        uint256 observedRate;           // Observed rate (fixed-point, e.g., 3.5% = 3.5e16)
        RateIndexEnum rateIndex;        // Rate index type
        bytes32 indexTenor;             // Index tenor (e.g., "3M", "ON")
        ResetSourceEnum source;         // Observation source
        uint256 observationDate;        // Date of observation
        bytes32 observationReference;   // External reference (e.g., Bloomberg ticker)
        bool isVerified;                // Whether observation has been verified
    }

    /// @notice Reset calculation details
    /// @dev Information for calculating accrual/payment
    struct ResetCalculation {
        uint256 periodStartDate;        // Calculation period start
        uint256 periodEndDate;          // Calculation period end
        uint256 notionalAmount;         // Notional for this period
        uint256 spread;                 // Spread over index (fixed-point)
        uint256 calculatedRate;         // Final rate after spread (fixed-point)
        uint256 accrualAmount;          // Calculated accrual amount
        bytes32 dayCountFraction;       // Day count convention
    }

    /// @notice Reset averaging data
    /// @dev For averaged/compounded observations
    struct ResetAveraging {
        AveragingMethodEnum method;     // Averaging method
        uint256[] observations;         // Multiple observations (if averaged)
        uint256[] weights;              // Weights (if weighted average)
        uint256 compoundingPeriods;     // Number of compounding periods
        uint256 finalRate;              // Resulting averaged/compounded rate
    }

    /// @notice Reset event data
    /// @dev Complete reset event information
    struct ResetEventData {
        bytes32 eventId;                // Event identifier
        bytes32 tradeId;                // Trade identifier
        bytes32 payoutReference;        // Payout/leg reference (which leg)
        uint256 resetNumber;            // Sequential reset number for this payout
        RateObservation observation;    // Rate observation
        ResetCalculation calculation;   // Calculation details
        ResetAveraging averaging;       // Averaging details (if applicable)
        bytes32 previousResetId;        // Previous reset event (if any)
        bytes32 metaGlobalKey;          // CDM global key
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Mapping from event ID to reset data
    mapping(bytes32 => ResetEventData) public resetData;

    /// @notice Mapping from trade ID to reset event IDs (ordered)
    mapping(bytes32 => bytes32[]) public tradeResets;

    /// @notice Mapping from payout reference to reset event IDs
    mapping(bytes32 => bytes32[]) public payoutResets;

    /// @notice Mapping from (tradeId, resetNumber) to event ID
    mapping(bytes32 => mapping(uint256 => bytes32)) public resetByNumber;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event RateReset(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        bytes32 indexed payoutReference,
        uint256 resetNumber,
        uint256 observedRate,
        RateIndexEnum rateIndex
    );

    event RateVerified(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        uint256 observedRate,
        bytes32 verifier
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error ResetEvent__InvalidResetNumber();
    error ResetEvent__InvalidObservationDate();
    error ResetEvent__InvalidPeriodDates();
    error ResetEvent__InvalidNotional();
    error ResetEvent__TradeNotActive();
    error ResetEvent__ResetAlreadyExists();
    error ResetEvent__InvalidAveragingData();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize ResetEvent contract
     * @param _tradeState Address of TradeState contract
     */
    constructor(address _tradeState) Event(_tradeState) {}

    // =============================================================================
    // RESET FUNCTIONS
    // =============================================================================

    /**
     * @notice Record a rate reset event
     * @dev Creates reset event for a floating rate observation
     * @param eventId Unique event identifier
     * @param tradeId Trade identifier
     * @param payoutReference Payout/leg reference
     * @param resetNumber Sequential reset number
     * @param observation Rate observation details
     * @param calculation Calculation details
     * @param initiator Party initiating reset
     * @return eventRecord Created event record
     */
    function recordReset(
        bytes32 eventId,
        bytes32 tradeId,
        bytes32 payoutReference,
        uint256 resetNumber,
        RateObservation memory observation,
        ResetCalculation memory calculation,
        bytes32 initiator
    ) public returns (EventRecord memory eventRecord) {
        // Validate
        _validateReset(eventId, tradeId, resetNumber, observation, calculation);

        // Create reset data
        ResetEventData memory resetEventData = _createResetData(
            eventId,
            tradeId,
            payoutReference,
            resetNumber,
            observation,
            calculation
        );

        // Store reset
        _storeReset(resetEventData);

        // Create event record
        eventRecord = _createResetEventRecord(eventId, tradeId, observation.observationDate, initiator);

        // Emit events
        emit RateReset(
            eventId,
            tradeId,
            payoutReference,
            resetNumber,
            observation.observedRate,
            observation.rateIndex
        );

        return eventRecord;
    }

    /**
     * @notice Record a rate reset with averaging
     * @dev Creates reset event with averaged/compounded rates
     * @param eventId Unique event identifier
     * @param tradeId Trade identifier
     * @param payoutReference Payout/leg reference
     * @param resetNumber Sequential reset number
     * @param observation Rate observation details (will use averaged rate)
     * @param calculation Calculation details
     * @param averaging Averaging details
     * @param initiator Party initiating reset
     * @return eventRecord Created event record
     */
    function recordResetWithAveraging(
        bytes32 eventId,
        bytes32 tradeId,
        bytes32 payoutReference,
        uint256 resetNumber,
        RateObservation memory observation,
        ResetCalculation memory calculation,
        ResetAveraging memory averaging,
        bytes32 initiator
    ) public returns (EventRecord memory eventRecord) {
        // Validate
        _validateReset(eventId, tradeId, resetNumber, observation, calculation);
        _validateAveraging(averaging);

        // Verify observation rate matches averaging result
        if (observation.observedRate != averaging.finalRate) {
            revert ResetEvent__InvalidAveragingData();
        }

        // Create reset data with averaging
        ResetEventData memory resetEventData = _createResetData(
            eventId,
            tradeId,
            payoutReference,
            resetNumber,
            observation,
            calculation
        );
        resetEventData.averaging = averaging;

        // Store reset
        _storeReset(resetEventData);

        // Create event record
        eventRecord = _createResetEventRecord(eventId, tradeId, observation.observationDate, initiator);

        // Emit events
        emit RateReset(
            eventId,
            tradeId,
            payoutReference,
            resetNumber,
            observation.observedRate,
            observation.rateIndex
        );

        return eventRecord;
    }

    /**
     * @notice Verify a rate observation
     * @dev Marks a reset observation as verified
     * @param eventId Reset event identifier
     * @param verifier Party verifying the rate
     */
    function verifyRate(bytes32 eventId, bytes32 verifier) public {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }

        ResetEventData storage data = resetData[eventId];
        data.observation.isVerified = true;

        emit RateVerified(eventId, data.tradeId, data.observation.observedRate, verifier);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @notice Validate reset event
     * @dev Internal validation helper
     */
    function _validateReset(
        bytes32 eventId,
        bytes32 tradeId,
        uint256 resetNumber,
        RateObservation memory observation,
        ResetCalculation memory calculation
    ) internal view {
        // Check event doesn't exist
        if (eventExists[eventId]) {
            revert Event__EventAlreadyExists();
        }

        // Check reset number doesn't exist for this trade
        if (resetByNumber[tradeId][resetNumber] != bytes32(0)) {
            revert ResetEvent__ResetAlreadyExists();
        }

        // Validate trade is active
        TradeState.TradeStateSnapshot memory currentState = tradeState.getCurrentState(tradeId);
        if (currentState.state != TradeState.TradeStateEnum.ACTIVE) {
            revert ResetEvent__TradeNotActive();
        }

        // Validate observation date
        if (observation.observationDate > block.timestamp) {
            revert ResetEvent__InvalidObservationDate();
        }

        // Validate period dates
        if (calculation.periodEndDate <= calculation.periodStartDate) {
            revert ResetEvent__InvalidPeriodDates();
        }

        // Validate notional
        if (calculation.notionalAmount == 0) {
            revert ResetEvent__InvalidNotional();
        }

        // Validate reset number
        if (resetNumber == 0) {
            revert ResetEvent__InvalidResetNumber();
        }
    }

    /**
     * @notice Validate averaging data
     * @dev Internal validation for averaging
     */
    function _validateAveraging(ResetAveraging memory averaging) internal pure {
        if (averaging.method == AveragingMethodEnum.NONE) {
            return; // No validation needed for single observation
        }

        // Check observations array
        if (averaging.observations.length == 0) {
            revert ResetEvent__InvalidAveragingData();
        }

        // For weighted average, weights must match observations
        if (averaging.method == AveragingMethodEnum.WEIGHTED) {
            if (averaging.weights.length != averaging.observations.length) {
                revert ResetEvent__InvalidAveragingData();
            }
        }
    }

    /**
     * @notice Create reset data
     * @dev Internal helper to build reset data struct
     */
    function _createResetData(
        bytes32 eventId,
        bytes32 tradeId,
        bytes32 payoutReference,
        uint256 resetNumber,
        RateObservation memory observation,
        ResetCalculation memory calculation
    ) internal view returns (ResetEventData memory) {
        // Find previous reset (if any)
        bytes32 previousResetId = bytes32(0);
        if (resetNumber > 1) {
            previousResetId = resetByNumber[tradeId][resetNumber - 1];
        }

        // Create empty averaging
        ResetAveraging memory emptyAveraging = ResetAveraging({
            method: AveragingMethodEnum.NONE,
            observations: new uint256[](0),
            weights: new uint256[](0),
            compoundingPeriods: 0,
            finalRate: 0
        });

        return ResetEventData({
            eventId: eventId,
            tradeId: tradeId,
            payoutReference: payoutReference,
            resetNumber: resetNumber,
            observation: observation,
            calculation: calculation,
            averaging: emptyAveraging,
            previousResetId: previousResetId,
            metaGlobalKey: keccak256(abi.encode(eventId, tradeId, resetNumber))
        });
    }

    /**
     * @notice Store reset data
     * @dev Internal helper to persist reset
     */
    function _storeReset(ResetEventData memory data) internal {
        resetData[data.eventId] = data;
        tradeResets[data.tradeId].push(data.eventId);
        payoutResets[data.payoutReference].push(data.eventId);
        resetByNumber[data.tradeId][data.resetNumber] = data.eventId;
    }

    /**
     * @notice Create reset event record
     * @dev Internal helper to build event record
     */
    function _createResetEventRecord(
        bytes32 eventId,
        bytes32 tradeId,
        uint256 observationDate,
        bytes32 initiator
    ) internal returns (EventRecord memory) {
        TradeState.TradeStateSnapshot memory currentState = tradeState.getCurrentState(tradeId);

        bytes32[] memory parties = new bytes32[](1);
        parties[0] = initiator;

        EventMetadata memory metadata = _createEventMetadata(
            eventId,
            EventTypeEnum.RESET,
            tradeId,
            observationDate,
            parties,
            initiator
        );

        EventRecord memory eventRecord = EventRecord({
            metadata: metadata,
            beforeStateId: currentState.stateId,
            afterStateId: currentState.stateId, // Reset doesn't change state
            previousEventId: getLastTradeEvent(tradeId),
            isValid: true,
            validationMessage: ""
        });

        _storeEvent(eventRecord);
        _markEventProcessed(eventId, currentState.stateId);

        return eventRecord;
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get reset event data
     * @param eventId Event identifier
     * @return data Reset event data
     */
    function getResetData(
        bytes32 eventId
    ) public view returns (ResetEventData memory data) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return resetData[eventId];
    }

    /**
     * @notice Get all resets for a trade
     * @param tradeId Trade identifier
     * @return eventIds Array of reset event IDs
     */
    function getTradeResets(
        bytes32 tradeId
    ) public view returns (bytes32[] memory eventIds) {
        return tradeResets[tradeId];
    }

    /**
     * @notice Get resets for a specific payout/leg
     * @param payoutReference Payout reference
     * @return eventIds Array of reset event IDs
     */
    function getPayoutResets(
        bytes32 payoutReference
    ) public view returns (bytes32[] memory eventIds) {
        return payoutResets[payoutReference];
    }

    /**
     * @notice Get reset by number
     * @param tradeId Trade identifier
     * @param resetNumber Reset number
     * @return eventId Reset event ID
     */
    function getResetByNumber(
        bytes32 tradeId,
        uint256 resetNumber
    ) public view returns (bytes32 eventId) {
        return resetByNumber[tradeId][resetNumber];
    }

    /**
     * @notice Get observed rate for a reset
     * @param eventId Event identifier
     * @return rate Observed rate
     */
    function getObservedRate(
        bytes32 eventId
    ) public view returns (uint256 rate) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return resetData[eventId].observation.observedRate;
    }

    /**
     * @notice Get calculation details for a reset
     * @param eventId Event identifier
     * @return calculation Calculation details
     */
    function getResetCalculation(
        bytes32 eventId
    ) public view returns (ResetCalculation memory calculation) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return resetData[eventId].calculation;
    }

    /**
     * @notice Check if rate is verified
     * @param eventId Event identifier
     * @return verified True if rate is verified
     */
    function isRateVerified(
        bytes32 eventId
    ) public view returns (bool verified) {
        if (!eventExists[eventId]) {
            return false;
        }
        return resetData[eventId].observation.isVerified;
    }

    /**
     * @notice Get reset count for a trade
     * @param tradeId Trade identifier
     * @return count Number of resets
     */
    function getResetCount(
        bytes32 tradeId
    ) public view returns (uint256 count) {
        return tradeResets[tradeId].length;
    }

    /**
     * @notice Get last reset for a trade
     * @param tradeId Trade identifier
     * @return eventId Last reset event ID (or bytes32(0) if none)
     */
    function getLastReset(
        bytes32 tradeId
    ) public view returns (bytes32 eventId) {
        bytes32[] memory resets = tradeResets[tradeId];
        if (resets.length == 0) {
            return bytes32(0);
        }
        return resets[resets.length - 1];
    }

    /**
     * @notice Get rate index for a reset
     * @param eventId Event identifier
     * @return rateIndex Rate index type
     */
    function getRateIndex(
        bytes32 eventId
    ) public view returns (RateIndexEnum rateIndex) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return resetData[eventId].observation.rateIndex;
    }

    /**
     * @notice Get accrual amount for a reset
     * @param eventId Event identifier
     * @return amount Accrual amount
     */
    function getAccrualAmount(
        bytes32 eventId
    ) public view returns (uint256 amount) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return resetData[eventId].calculation.accrualAmount;
    }
}
