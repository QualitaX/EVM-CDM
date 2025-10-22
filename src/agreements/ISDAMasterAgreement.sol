// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgreementRegistry} from "./AgreementRegistry.sol";

/**
 * @title ISDAMasterAgreement
 * @notice ISDA Master Agreement specific terms and provisions
 * @dev Manages ISDA-specific terms, events of default, and termination events
 *
 * KEY FEATURES:
 * - ISDA version tracking (1992, 2002, 2016)
 * - Jurisdiction specification (NY Law vs. English Law)
 * - Events of Default definitions
 * - Termination Events definitions
 * - Automatic Early Termination (AET) settings
 * - Grace period configuration
 * - Cross-default provisions
 * - Calculation agent designation
 *
 * ISDA VERSIONS:
 * - 1992: Original ISDA Master Agreement
 * - 2002: Updated with enhanced close-out netting
 * - 2016: Latest version with additional protections
 *
 * JURISDICTIONS:
 * - New York Law: Most common for US counterparties
 * - English Law: Common for European counterparties
 * - Others: Japanese, German, French, etc.
 *
 * EVENTS OF DEFAULT (Section 5(a)):
 * - Failure to Pay or Deliver
 * - Breach of Agreement
 * - Credit Support Default
 * - Misrepresentation
 * - Default under Specified Transaction
 * - Cross Default
 * - Bankruptcy
 * - Merger without Assumption
 *
 * TERMINATION EVENTS (Section 5(b)):
 * - Illegality
 * - Tax Event
 * - Tax Event Upon Merger
 * - Credit Event Upon Merger
 * - Additional Termination Event
 *
 * @author QualitaX Team
 */
contract ISDAMasterAgreement {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice ISDA Master Agreement version
    enum ISDAVersionEnum {
        ISDA_1992,                      // 1992 ISDA Master Agreement
        ISDA_1992_MULTICURRENCY,        // 1992 Multicurrency - Cross Border
        ISDA_2002,                      // 2002 ISDA Master Agreement
        ISDA_2016,                      // 2016 ISDA Master Agreement (Bail-in)
        CUSTOM                          // Custom or other version
    }

    /// @notice Event of Default type (Section 5(a))
    enum EventOfDefaultEnum {
        FAILURE_TO_PAY_OR_DELIVER,      // Section 5(a)(i)
        BREACH_OF_AGREEMENT,            // Section 5(a)(ii)
        CREDIT_SUPPORT_DEFAULT,         // Section 5(a)(iii)
        MISREPRESENTATION,              // Section 5(a)(iv)
        DEFAULT_UNDER_SPECIFIED_TRANSACTION, // Section 5(a)(v)
        CROSS_DEFAULT,                  // Section 5(a)(vi)
        BANKRUPTCY,                     // Section 5(a)(vii)
        MERGER_WITHOUT_ASSUMPTION,      // Section 5(a)(viii)
        CUSTOM                          // Custom event of default
    }

    /// @notice Termination Event type (Section 5(b))
    enum TerminationEventEnum {
        ILLEGALITY,                     // Section 5(b)(i)
        FORCE_MAJEURE,                  // Section 5(b)(i) (2002 version)
        TAX_EVENT,                      // Section 5(b)(ii)
        TAX_EVENT_UPON_MERGER,          // Section 5(b)(iii)
        CREDIT_EVENT_UPON_MERGER,       // Section 5(b)(iv)
        ADDITIONAL_TERMINATION_EVENT,   // Section 5(b)(v)
        CUSTOM                          // Custom termination event
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice ISDA-specific terms and provisions
    /// @dev Complete ISDA Master Agreement configuration
    struct ISDATerms {
        bytes32 agreementId;                        // Link to master agreement
        ISDAVersionEnum version;                    // ISDA version
        AgreementRegistry.JurisdictionEnum jurisdiction; // Governing law jurisdiction

        // Default and termination provisions
        bool automaticEarlyTermination;             // AET on default (Section 6(a))
        uint256 gracePeriodDays;                    // Grace period for payments
        bool waitingPeriod;                         // Waiting period (Section 5(a)(vi))
        uint256 waitingPeriodDays;                  // Waiting period duration

        // Events of Default
        EventOfDefaultEnum[] eventsOfDefault;       // Applicable events of default
        bool crossDefaultEnabled;                   // Cross-default provision
        uint256 crossDefaultThreshold;              // Cross-default threshold amount

        // Termination Events
        TerminationEventEnum[] terminationEvents;   // Applicable termination events
        bool taxEventApplicable;                    // Tax event provision
        bool illegalityApplicable;                  // Illegality provision

        // Calculation and valuation
        bytes32 calculationAgent;                   // Calculation agent party
        bytes32 valuationMethod;                    // Valuation method (Market Quotation, Loss, etc.)
        uint256 valuationTime;                      // Time for valuation

        // Additional provisions
        bool setOffEnabled;                         // Set-off provision (Section 6(f))
        bytes32 baseCurrency;                       // Base currency for calculations
        bool multibranchParty;                      // Multi-branch party indicator

        uint256 registrationTimestamp;
        bytes32 registeredBy;
        bytes32 metaGlobalKey;
    }

    /// @notice Event of Default record
    /// @dev Tracks specific event of default occurrence
    struct EventOfDefaultRecord {
        bytes32 eventId;
        bytes32 agreementId;
        EventOfDefaultEnum eventType;
        bytes32 defaultingParty;
        bytes32 nonDefaultingParty;
        uint256 eventDate;
        uint256 notificationDate;
        bytes32 description;
        bool isResolved;
        uint256 resolutionDate;
    }

    /// @notice Termination Event record
    /// @dev Tracks specific termination event occurrence
    struct TerminationEventRecord {
        bytes32 eventId;
        bytes32 agreementId;
        TerminationEventEnum eventType;
        bytes32 affectedParty;
        uint256 eventDate;
        uint256 notificationDate;
        bytes32 description;
        bool isResolved;
        uint256 resolutionDate;
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Agreement registry reference
    AgreementRegistry public immutable agreementRegistry;

    /// @notice Mapping from agreement ID to ISDA terms
    mapping(bytes32 => ISDATerms) public isdaTerms;

    /// @notice Mapping from agreement ID to existence check
    mapping(bytes32 => bool) public isdaTermsExist;

    /// @notice Mapping from event ID to Event of Default record
    mapping(bytes32 => EventOfDefaultRecord) public eventsOfDefault;

    /// @notice Mapping from event ID to Termination Event record
    mapping(bytes32 => TerminationEventRecord) public terminationEvents;

    /// @notice Mapping from agreement ID to Event of Default IDs
    mapping(bytes32 => bytes32[]) public agreementEventsOfDefault;

    /// @notice Mapping from agreement ID to Termination Event IDs
    mapping(bytes32 => bytes32[]) public agreementTerminationEvents;

    /// @notice Counter for total ISDA terms registered
    uint256 public totalISDATerms;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event ISDATermsRegistered(
        bytes32 indexed agreementId,
        ISDAVersionEnum version,
        AgreementRegistry.JurisdictionEnum jurisdiction,
        bytes32 registeredBy
    );

    event EventOfDefaultRecorded(
        bytes32 indexed eventId,
        bytes32 indexed agreementId,
        EventOfDefaultEnum eventType,
        bytes32 defaultingParty,
        uint256 eventDate
    );

    event TerminationEventRecorded(
        bytes32 indexed eventId,
        bytes32 indexed agreementId,
        TerminationEventEnum eventType,
        bytes32 affectedParty,
        uint256 eventDate
    );

    event EventOfDefaultResolved(
        bytes32 indexed eventId,
        bytes32 indexed agreementId,
        uint256 resolutionDate
    );

    event TerminationEventResolved(
        bytes32 indexed eventId,
        bytes32 indexed agreementId,
        uint256 resolutionDate
    );

    event CalculationAgentUpdated(
        bytes32 indexed agreementId,
        bytes32 oldAgent,
        bytes32 newAgent,
        bytes32 updatedBy
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error ISDAMasterAgreement__ISDATermsAlreadyExist();
    error ISDAMasterAgreement__ISDATermsDoNotExist();
    error ISDAMasterAgreement__MasterAgreementDoesNotExist();
    error ISDAMasterAgreement__MasterAgreementNotActive();
    error ISDAMasterAgreement__InvalidGracePeriod();
    error ISDAMasterAgreement__InvalidThreshold();
    error ISDAMasterAgreement__EventAlreadyExists();
    error ISDAMasterAgreement__EventDoesNotExist();
    error ISDAMasterAgreement__EventAlreadyResolved();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize ISDAMasterAgreement contract
     * @param _agreementRegistry Address of AgreementRegistry contract
     */
    constructor(address _agreementRegistry) {
        agreementRegistry = AgreementRegistry(_agreementRegistry);
    }

    // =============================================================================
    // ISDA TERMS REGISTRATION
    // =============================================================================

    /**
     * @notice Register ISDA terms for a master agreement
     * @dev Links ISDA-specific terms to registered master agreement
     * @param agreementId Master agreement identifier
     * @param version ISDA version
     * @param jurisdiction Governing law jurisdiction
     * @param automaticEarlyTermination AET enabled
     * @param gracePeriodDays Grace period in days
     * @param eventsOfDefault Applicable events of default
     * @param terminationEvents Applicable termination events
     * @param calculationAgent Calculation agent party
     * @param registeredBy Party registering the terms
     * @return terms Created ISDA terms
     */
    function registerISDATerms(
        bytes32 agreementId,
        ISDAVersionEnum version,
        AgreementRegistry.JurisdictionEnum jurisdiction,
        bool automaticEarlyTermination,
        uint256 gracePeriodDays,
        EventOfDefaultEnum[] memory eventsOfDefault,
        TerminationEventEnum[] memory terminationEvents,
        bytes32 calculationAgent,
        bytes32 registeredBy
    ) public returns (ISDATerms memory terms) {
        // Validate
        _validateISDATermsRegistration(agreementId, gracePeriodDays);

        // Create ISDA terms
        terms = ISDATerms({
            agreementId: agreementId,
            version: version,
            jurisdiction: jurisdiction,
            automaticEarlyTermination: automaticEarlyTermination,
            gracePeriodDays: gracePeriodDays,
            waitingPeriod: false,
            waitingPeriodDays: 0,
            eventsOfDefault: eventsOfDefault,
            crossDefaultEnabled: _containsEventOfDefault(eventsOfDefault, EventOfDefaultEnum.CROSS_DEFAULT),
            crossDefaultThreshold: 0,
            terminationEvents: terminationEvents,
            taxEventApplicable: _containsTerminationEvent(terminationEvents, TerminationEventEnum.TAX_EVENT),
            illegalityApplicable: _containsTerminationEvent(terminationEvents, TerminationEventEnum.ILLEGALITY),
            calculationAgent: calculationAgent,
            valuationMethod: bytes32(0),
            valuationTime: 0,
            setOffEnabled: false,
            baseCurrency: keccak256("USD"),
            multibranchParty: false,
            registrationTimestamp: block.timestamp,
            registeredBy: registeredBy,
            metaGlobalKey: keccak256(abi.encode(agreementId, version))
        });

        // Store ISDA terms
        isdaTerms[agreementId] = terms;
        isdaTermsExist[agreementId] = true;

        totalISDATerms++;

        emit ISDATermsRegistered(agreementId, version, jurisdiction, registeredBy);

        return terms;
    }

    /**
     * @notice Update calculation agent
     * @dev Changes the calculation agent for an agreement
     * @param agreementId Agreement identifier
     * @param newCalculationAgent New calculation agent party
     * @param updatedBy Party making the update
     */
    function updateCalculationAgent(
        bytes32 agreementId,
        bytes32 newCalculationAgent,
        bytes32 updatedBy
    ) public {
        if (!isdaTermsExist[agreementId]) {
            revert ISDAMasterAgreement__ISDATermsDoNotExist();
        }

        ISDATerms storage terms = isdaTerms[agreementId];
        bytes32 oldAgent = terms.calculationAgent;
        terms.calculationAgent = newCalculationAgent;

        emit CalculationAgentUpdated(agreementId, oldAgent, newCalculationAgent, updatedBy);
    }

    /**
     * @notice Update cross-default threshold
     * @dev Sets the threshold amount for cross-default provisions
     * @param agreementId Agreement identifier
     * @param threshold Cross-default threshold amount
     */
    function updateCrossDefaultThreshold(
        bytes32 agreementId,
        uint256 threshold
    ) public {
        if (!isdaTermsExist[agreementId]) {
            revert ISDAMasterAgreement__ISDATermsDoNotExist();
        }

        isdaTerms[agreementId].crossDefaultThreshold = threshold;
    }

    // =============================================================================
    // EVENT RECORDING
    // =============================================================================

    /**
     * @notice Record an Event of Default
     * @dev Creates record of event of default occurrence
     * @param eventId Unique event identifier
     * @param agreementId Agreement identifier
     * @param eventType Type of event of default
     * @param defaultingParty Party in default
     * @param nonDefaultingParty Non-defaulting party
     * @param eventDate Date of event
     * @param notificationDate Date of notification
     * @param description Event description
     * @return record Created event record
     */
    function recordEventOfDefault(
        bytes32 eventId,
        bytes32 agreementId,
        EventOfDefaultEnum eventType,
        bytes32 defaultingParty,
        bytes32 nonDefaultingParty,
        uint256 eventDate,
        uint256 notificationDate,
        bytes32 description
    ) public returns (EventOfDefaultRecord memory record) {
        // Validate
        if (!isdaTermsExist[agreementId]) {
            revert ISDAMasterAgreement__ISDATermsDoNotExist();
        }
        if (eventsOfDefault[eventId].eventId != bytes32(0)) {
            revert ISDAMasterAgreement__EventAlreadyExists();
        }

        // Create record
        record = EventOfDefaultRecord({
            eventId: eventId,
            agreementId: agreementId,
            eventType: eventType,
            defaultingParty: defaultingParty,
            nonDefaultingParty: nonDefaultingParty,
            eventDate: eventDate,
            notificationDate: notificationDate,
            description: description,
            isResolved: false,
            resolutionDate: 0
        });

        // Store record
        eventsOfDefault[eventId] = record;
        agreementEventsOfDefault[agreementId].push(eventId);

        emit EventOfDefaultRecorded(eventId, agreementId, eventType, defaultingParty, eventDate);

        return record;
    }

    /**
     * @notice Record a Termination Event
     * @dev Creates record of termination event occurrence
     * @param eventId Unique event identifier
     * @param agreementId Agreement identifier
     * @param eventType Type of termination event
     * @param affectedParty Affected party
     * @param eventDate Date of event
     * @param notificationDate Date of notification
     * @param description Event description
     * @return record Created event record
     */
    function recordTerminationEvent(
        bytes32 eventId,
        bytes32 agreementId,
        TerminationEventEnum eventType,
        bytes32 affectedParty,
        uint256 eventDate,
        uint256 notificationDate,
        bytes32 description
    ) public returns (TerminationEventRecord memory record) {
        // Validate
        if (!isdaTermsExist[agreementId]) {
            revert ISDAMasterAgreement__ISDATermsDoNotExist();
        }
        if (terminationEvents[eventId].eventId != bytes32(0)) {
            revert ISDAMasterAgreement__EventAlreadyExists();
        }

        // Create record
        record = TerminationEventRecord({
            eventId: eventId,
            agreementId: agreementId,
            eventType: eventType,
            affectedParty: affectedParty,
            eventDate: eventDate,
            notificationDate: notificationDate,
            description: description,
            isResolved: false,
            resolutionDate: 0
        });

        // Store record
        terminationEvents[eventId] = record;
        agreementTerminationEvents[agreementId].push(eventId);

        emit TerminationEventRecorded(eventId, agreementId, eventType, affectedParty, eventDate);

        return record;
    }

    /**
     * @notice Resolve an Event of Default
     * @dev Marks event of default as resolved
     * @param eventId Event identifier
     */
    function resolveEventOfDefault(bytes32 eventId) public {
        if (eventsOfDefault[eventId].eventId == bytes32(0)) {
            revert ISDAMasterAgreement__EventDoesNotExist();
        }
        if (eventsOfDefault[eventId].isResolved) {
            revert ISDAMasterAgreement__EventAlreadyResolved();
        }

        eventsOfDefault[eventId].isResolved = true;
        eventsOfDefault[eventId].resolutionDate = block.timestamp;

        emit EventOfDefaultResolved(eventId, eventsOfDefault[eventId].agreementId, block.timestamp);
    }

    /**
     * @notice Resolve a Termination Event
     * @dev Marks termination event as resolved
     * @param eventId Event identifier
     */
    function resolveTerminationEvent(bytes32 eventId) public {
        if (terminationEvents[eventId].eventId == bytes32(0)) {
            revert ISDAMasterAgreement__EventDoesNotExist();
        }
        if (terminationEvents[eventId].isResolved) {
            revert ISDAMasterAgreement__EventAlreadyResolved();
        }

        terminationEvents[eventId].isResolved = true;
        terminationEvents[eventId].resolutionDate = block.timestamp;

        emit TerminationEventResolved(eventId, terminationEvents[eventId].agreementId, block.timestamp);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @notice Validate ISDA terms registration
     * @dev Internal validation helper
     */
    function _validateISDATermsRegistration(
        bytes32 agreementId,
        uint256 gracePeriodDays
    ) internal view {
        // Check ISDA terms don't already exist
        if (isdaTermsExist[agreementId]) {
            revert ISDAMasterAgreement__ISDATermsAlreadyExist();
        }

        // Validate master agreement exists
        if (!agreementRegistry.agreementExists(agreementId)) {
            revert ISDAMasterAgreement__MasterAgreementDoesNotExist();
        }

        // Validate master agreement is active
        if (!agreementRegistry.isAgreementActive(agreementId)) {
            revert ISDAMasterAgreement__MasterAgreementNotActive();
        }

        // Validate grace period (typically 0-30 days)
        if (gracePeriodDays > 365) {
            revert ISDAMasterAgreement__InvalidGracePeriod();
        }
    }

    /**
     * @notice Check if event of default type is in array
     * @dev Internal helper
     */
    function _containsEventOfDefault(
        EventOfDefaultEnum[] memory events,
        EventOfDefaultEnum eventType
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < events.length; i++) {
            if (events[i] == eventType) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Check if termination event type is in array
     * @dev Internal helper
     */
    function _containsTerminationEvent(
        TerminationEventEnum[] memory events,
        TerminationEventEnum eventType
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < events.length; i++) {
            if (events[i] == eventType) {
                return true;
            }
        }
        return false;
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get ISDA terms for an agreement
     * @param agreementId Agreement identifier
     * @return terms ISDA terms
     */
    function getISDATerms(
        bytes32 agreementId
    ) public view returns (ISDATerms memory terms) {
        if (!isdaTermsExist[agreementId]) {
            revert ISDAMasterAgreement__ISDATermsDoNotExist();
        }
        return isdaTerms[agreementId];
    }

    /**
     * @notice Get Event of Default record
     * @param eventId Event identifier
     * @return record Event of default record
     */
    function getEventOfDefault(
        bytes32 eventId
    ) public view returns (EventOfDefaultRecord memory record) {
        record = eventsOfDefault[eventId];
        if (record.eventId == bytes32(0)) {
            revert ISDAMasterAgreement__EventDoesNotExist();
        }
        return record;
    }

    /**
     * @notice Get Termination Event record
     * @param eventId Event identifier
     * @return record Termination event record
     */
    function getTerminationEvent(
        bytes32 eventId
    ) public view returns (TerminationEventRecord memory record) {
        record = terminationEvents[eventId];
        if (record.eventId == bytes32(0)) {
            revert ISDAMasterAgreement__EventDoesNotExist();
        }
        return record;
    }

    /**
     * @notice Get all Events of Default for an agreement
     * @param agreementId Agreement identifier
     * @return eventIds Array of event IDs
     */
    function getAgreementEventsOfDefault(
        bytes32 agreementId
    ) public view returns (bytes32[] memory eventIds) {
        return agreementEventsOfDefault[agreementId];
    }

    /**
     * @notice Get all Termination Events for an agreement
     * @param agreementId Agreement identifier
     * @return eventIds Array of event IDs
     */
    function getAgreementTerminationEvents(
        bytes32 agreementId
    ) public view returns (bytes32[] memory eventIds) {
        return agreementTerminationEvents[agreementId];
    }

    /**
     * @notice Check if AET is enabled
     * @param agreementId Agreement identifier
     * @return enabled True if AET enabled
     */
    function isAutomaticEarlyTerminationEnabled(
        bytes32 agreementId
    ) public view returns (bool enabled) {
        if (!isdaTermsExist[agreementId]) {
            return false;
        }
        return isdaTerms[agreementId].automaticEarlyTermination;
    }

    /**
     * @notice Check if cross-default is enabled
     * @param agreementId Agreement identifier
     * @return enabled True if cross-default enabled
     */
    function isCrossDefaultEnabled(
        bytes32 agreementId
    ) public view returns (bool enabled) {
        if (!isdaTermsExist[agreementId]) {
            return false;
        }
        return isdaTerms[agreementId].crossDefaultEnabled;
    }

    /**
     * @notice Get grace period
     * @param agreementId Agreement identifier
     * @return gracePeriodDays Grace period in days
     */
    function getGracePeriod(
        bytes32 agreementId
    ) public view returns (uint256 gracePeriodDays) {
        if (!isdaTermsExist[agreementId]) {
            revert ISDAMasterAgreement__ISDATermsDoNotExist();
        }
        return isdaTerms[agreementId].gracePeriodDays;
    }

    /**
     * @notice Get calculation agent
     * @param agreementId Agreement identifier
     * @return calculationAgent Calculation agent party
     */
    function getCalculationAgent(
        bytes32 agreementId
    ) public view returns (bytes32 calculationAgent) {
        if (!isdaTermsExist[agreementId]) {
            revert ISDAMasterAgreement__ISDATermsDoNotExist();
        }
        return isdaTerms[agreementId].calculationAgent;
    }

    /**
     * @notice Check if event type is an Event of Default for agreement
     * @param agreementId Agreement identifier
     * @param eventType Event of default type
     * @return applicable True if event type is applicable
     */
    function isEventOfDefaultApplicable(
        bytes32 agreementId,
        EventOfDefaultEnum eventType
    ) public view returns (bool applicable) {
        if (!isdaTermsExist[agreementId]) {
            return false;
        }
        return _containsEventOfDefault(isdaTerms[agreementId].eventsOfDefault, eventType);
    }

    /**
     * @notice Check if event type is a Termination Event for agreement
     * @param agreementId Agreement identifier
     * @param eventType Termination event type
     * @return applicable True if event type is applicable
     */
    function isTerminationEventApplicable(
        bytes32 agreementId,
        TerminationEventEnum eventType
    ) public view returns (bool applicable) {
        if (!isdaTermsExist[agreementId]) {
            return false;
        }
        return _containsTerminationEvent(isdaTerms[agreementId].terminationEvents, eventType);
    }
}
