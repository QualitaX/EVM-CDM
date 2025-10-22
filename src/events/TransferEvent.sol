// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Event} from "./Event.sol";
import {TradeState} from "./TradeState.sol";

/**
 * @title TransferEvent
 * @notice Payment/settlement transfer event
 * @dev Represents actual payment transfers between parties
 *
 * KEY FEATURES:
 * - Payment transfer recording
 * - Settlement tracking
 * - Multi-currency support
 * - Gross and net payment handling
 * - Transfer status management
 *
 * TRANSFER FLOW:
 * 1. Payment becomes due (from calculation period)
 * 2. TransferEvent created with payment details
 * 3. Transfer initiated
 * 4. Transfer settled
 * 5. Trade remains ACTIVE (or transitions if final payment)
 *
 * TYPICAL USE CASES:
 * - Interest Rate Swap periodic payments
 * - NDF settlement at maturity
 * - Bond coupon payments
 * - Principal repayments
 *
 * @author QualitaX Team
 */
contract TransferEvent is Event {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Transfer type
    enum TransferTypeEnum {
        INTEREST_PAYMENT,       // Interest payment
        PRINCIPAL_PAYMENT,      // Principal payment
        SETTLEMENT,             // Settlement payment (e.g., NDF)
        FEE,                    // Fee payment
        PREMIUM,                // Premium payment
        MARGIN,                 // Margin/collateral transfer
        NETTED_PAYMENT          // Netted payment (multiple cashflows)
    }

    /// @notice Transfer status
    enum TransferStatusEnum {
        PENDING,                // Transfer pending
        INITIATED,              // Transfer initiated
        SETTLED,                // Transfer completed/settled
        FAILED,                 // Transfer failed
        CANCELLED               // Transfer cancelled
    }

    /// @notice Transfer direction (from payer perspective)
    enum TransferDirectionEnum {
        PAY,                    // Payer pays receiver
        RECEIVE                 // Payer receives from receiver
    }

    /// @notice Settlement method
    enum SettlementMethodEnum {
        CASH,                   // Cash settlement
        PHYSICAL,               // Physical delivery
        NETTED,                 // Netted settlement
        DVP,                    // Delivery vs Payment
        PVP                     // Payment vs Payment
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Payment details
    /// @dev Core payment information
    struct PaymentDetails {
        uint256 grossAmount;            // Gross payment amount (fixed-point)
        uint256 netAmount;              // Net payment amount (fixed-point)
        bytes32 currency;               // Payment currency
        TransferDirectionEnum direction; // Transfer direction
        uint256 valueDate;              // Payment value date
        uint256 paymentDate;            // Actual payment date
        bytes32 paymentReference;       // External payment reference
    }

    /// @notice Transfer parties
    /// @dev Parties involved in transfer
    struct TransferParties {
        bytes32 payerReference;         // Payer party
        bytes32 receiverReference;      // Receiver party
        bytes32 payerAccount;           // Payer account identifier
        bytes32 receiverAccount;        // Receiver account identifier
        bytes32 intermediaryReference;  // Intermediary (if applicable)
    }

    /// @notice Settlement details
    /// @dev Settlement-specific information
    struct SettlementDetails {
        SettlementMethodEnum method;    // Settlement method
        TransferStatusEnum status;      // Transfer status
        uint256 settlementDate;         // Settlement date
        bytes32 settlementReference;    // Settlement reference
        bytes32[] cashflowReferences;   // Related cashflow references
        bool isVerified;                // Whether settlement is verified
        bytes32 verifierReference;      // Verifying party
    }

    /// @notice Transfer event data
    /// @dev Complete transfer event information
    struct TransferEventData {
        bytes32 eventId;                // Event identifier
        bytes32 tradeId;                // Trade identifier
        TransferTypeEnum transferType;  // Transfer type
        PaymentDetails payment;         // Payment details
        TransferParties parties;        // Transfer parties
        SettlementDetails settlement;   // Settlement details
        bytes32[] relatedResetIds;      // Related reset events (if any)
        bytes32 previousTransferId;     // Previous transfer event
        bytes32 metaGlobalKey;          // CDM global key
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Mapping from event ID to transfer data
    mapping(bytes32 => TransferEventData) public transferData;

    /// @notice Mapping from trade ID to transfer event IDs (ordered)
    mapping(bytes32 => bytes32[]) public tradeTransfers;

    /// @notice Mapping from transfer number to event ID
    mapping(bytes32 => mapping(uint256 => bytes32)) public transferByNumber;

    /// @notice Mapping from transfer reference to event ID
    mapping(bytes32 => bytes32) public transferByReference;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event TransferInitiated(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        bytes32 indexed payerReference,
        bytes32 receiverReference,
        uint256 amount,
        bytes32 currency
    );

    event TransferSettled(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        uint256 settlementDate,
        bytes32 settlementReference
    );

    event TransferFailed(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        string reason
    );

    event TransferVerified(
        bytes32 indexed eventId,
        bytes32 indexed tradeId,
        bytes32 verifier
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error TransferEvent__InvalidAmount();
    error TransferEvent__InvalidParties();
    error TransferEvent__InvalidDates();
    error TransferEvent__TransferAlreadyExists();
    error TransferEvent__TransferNotPending();
    error TransferEvent__InvalidStatus();
    error TransferEvent__AlreadySettled();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize TransferEvent contract
     * @param _tradeState Address of TradeState contract
     */
    constructor(address _tradeState) Event(_tradeState) {}

    // =============================================================================
    // TRANSFER FUNCTIONS
    // =============================================================================

    /**
     * @notice Record a transfer event
     * @dev Creates transfer event for a payment
     * @param eventId Unique event identifier
     * @param tradeId Trade identifier
     * @param transferType Type of transfer
     * @param payment Payment details
     * @param parties Transfer parties
     * @param initiator Party initiating transfer
     * @return eventRecord Created event record
     */
    function recordTransfer(
        bytes32 eventId,
        bytes32 tradeId,
        TransferTypeEnum transferType,
        PaymentDetails memory payment,
        TransferParties memory parties,
        bytes32 initiator
    ) public returns (EventRecord memory eventRecord) {
        // Validate
        _validateTransfer(eventId, tradeId, payment, parties);

        // Create transfer data
        TransferEventData memory transferEventData = _createTransferData(
            eventId,
            tradeId,
            transferType,
            payment,
            parties
        );

        // Store transfer
        _storeTransfer(transferEventData);

        // Create event record
        eventRecord = _createTransferEventRecord(eventId, tradeId, payment.valueDate, initiator, parties);

        // Emit event
        emit TransferInitiated(
            eventId,
            tradeId,
            parties.payerReference,
            parties.receiverReference,
            payment.netAmount,
            payment.currency
        );

        return eventRecord;
    }

    /**
     * @notice Settle a transfer
     * @dev Marks transfer as settled
     * @param eventId Transfer event identifier
     * @param settlementDate Settlement date
     * @param settlementReference Settlement reference
     */
    function settleTransfer(
        bytes32 eventId,
        uint256 settlementDate,
        bytes32 settlementReference
    ) public {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }

        TransferEventData storage data = transferData[eventId];

        // Check current status
        if (data.settlement.status == TransferStatusEnum.SETTLED) {
            revert TransferEvent__AlreadySettled();
        }

        // Update settlement details
        data.settlement.status = TransferStatusEnum.SETTLED;
        data.settlement.settlementDate = settlementDate;
        data.settlement.settlementReference = settlementReference;

        emit TransferSettled(eventId, data.tradeId, settlementDate, settlementReference);
    }

    /**
     * @notice Mark transfer as failed
     * @dev Records transfer failure
     * @param eventId Transfer event identifier
     * @param reason Failure reason
     */
    function failTransfer(
        bytes32 eventId,
        string memory reason
    ) public {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }

        TransferEventData storage data = transferData[eventId];

        // Check current status
        if (data.settlement.status == TransferStatusEnum.SETTLED) {
            revert TransferEvent__AlreadySettled();
        }

        data.settlement.status = TransferStatusEnum.FAILED;

        emit TransferFailed(eventId, data.tradeId, reason);
    }

    /**
     * @notice Verify a transfer
     * @dev Marks transfer as verified
     * @param eventId Transfer event identifier
     * @param verifier Party verifying the transfer
     */
    function verifyTransfer(
        bytes32 eventId,
        bytes32 verifier
    ) public {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }

        TransferEventData storage data = transferData[eventId];
        data.settlement.isVerified = true;
        data.settlement.verifierReference = verifier;

        emit TransferVerified(eventId, data.tradeId, verifier);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @notice Validate transfer event
     * @dev Internal validation helper
     */
    function _validateTransfer(
        bytes32 eventId,
        bytes32 tradeId,
        PaymentDetails memory payment,
        TransferParties memory parties
    ) internal view {
        // Check event doesn't exist
        if (eventExists[eventId]) {
            revert Event__EventAlreadyExists();
        }

        // Validate payment reference uniqueness
        if (payment.paymentReference != bytes32(0)) {
            if (transferByReference[payment.paymentReference] != bytes32(0)) {
                revert TransferEvent__TransferAlreadyExists();
            }
        }

        // Validate trade exists
        TradeState.TradeStateSnapshot memory currentState = tradeState.getCurrentState(tradeId);
        if (currentState.tradeId == bytes32(0)) {
            revert Event__TradeDoesNotExist();
        }

        // Validate amount
        if (payment.netAmount == 0) {
            revert TransferEvent__InvalidAmount();
        }

        // Validate parties
        if (parties.payerReference == bytes32(0) || parties.receiverReference == bytes32(0)) {
            revert TransferEvent__InvalidParties();
        }
        if (parties.payerReference == parties.receiverReference) {
            revert TransferEvent__InvalidParties();
        }

        // Validate dates
        if (payment.valueDate == 0) {
            revert TransferEvent__InvalidDates();
        }
    }

    /**
     * @notice Create transfer data
     * @dev Internal helper to build transfer data struct
     */
    function _createTransferData(
        bytes32 eventId,
        bytes32 tradeId,
        TransferTypeEnum transferType,
        PaymentDetails memory payment,
        TransferParties memory parties
    ) internal view returns (TransferEventData memory) {
        // Find previous transfer (if any)
        bytes32 previousTransferId = bytes32(0);
        bytes32[] memory transfers = tradeTransfers[tradeId];
        if (transfers.length > 0) {
            previousTransferId = transfers[transfers.length - 1];
        }

        // Create settlement details
        SettlementDetails memory settlement = SettlementDetails({
            method: SettlementMethodEnum.CASH,
            status: TransferStatusEnum.PENDING,
            settlementDate: 0,
            settlementReference: bytes32(0),
            cashflowReferences: new bytes32[](0),
            isVerified: false,
            verifierReference: bytes32(0)
        });

        return TransferEventData({
            eventId: eventId,
            tradeId: tradeId,
            transferType: transferType,
            payment: payment,
            parties: parties,
            settlement: settlement,
            relatedResetIds: new bytes32[](0),
            previousTransferId: previousTransferId,
            metaGlobalKey: keccak256(abi.encode(eventId, tradeId))
        });
    }

    /**
     * @notice Store transfer data
     * @dev Internal helper to persist transfer
     */
    function _storeTransfer(TransferEventData memory data) internal {
        transferData[data.eventId] = data;
        tradeTransfers[data.tradeId].push(data.eventId);

        uint256 transferNumber = tradeTransfers[data.tradeId].length;
        transferByNumber[data.tradeId][transferNumber] = data.eventId;

        if (data.payment.paymentReference != bytes32(0)) {
            transferByReference[data.payment.paymentReference] = data.eventId;
        }
    }

    /**
     * @notice Create transfer event record
     * @dev Internal helper to build event record
     */
    function _createTransferEventRecord(
        bytes32 eventId,
        bytes32 tradeId,
        uint256 valueDate,
        bytes32 initiator,
        TransferParties memory parties
    ) internal returns (EventRecord memory) {
        TradeState.TradeStateSnapshot memory currentState = tradeState.getCurrentState(tradeId);

        bytes32[] memory eventParties = new bytes32[](2);
        eventParties[0] = parties.payerReference;
        eventParties[1] = parties.receiverReference;

        EventMetadata memory metadata = _createEventMetadata(
            eventId,
            EventTypeEnum.TRANSFER,
            tradeId,
            valueDate,
            eventParties,
            initiator
        );

        EventRecord memory eventRecord = EventRecord({
            metadata: metadata,
            beforeStateId: currentState.stateId,
            afterStateId: currentState.stateId, // Transfer doesn't change trade state
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
     * @notice Get transfer event data
     * @param eventId Event identifier
     * @return data Transfer event data
     */
    function getTransferData(
        bytes32 eventId
    ) public view returns (TransferEventData memory data) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return transferData[eventId];
    }

    /**
     * @notice Get all transfers for a trade
     * @param tradeId Trade identifier
     * @return eventIds Array of transfer event IDs
     */
    function getTradeTransfers(
        bytes32 tradeId
    ) public view returns (bytes32[] memory eventIds) {
        return tradeTransfers[tradeId];
    }

    /**
     * @notice Get transfer by number
     * @param tradeId Trade identifier
     * @param transferNumber Transfer number (1-indexed)
     * @return eventId Transfer event ID
     */
    function getTransferByNumber(
        bytes32 tradeId,
        uint256 transferNumber
    ) public view returns (bytes32 eventId) {
        return transferByNumber[tradeId][transferNumber];
    }

    /**
     * @notice Get transfer by payment reference
     * @param paymentReference Payment reference
     * @return eventId Transfer event ID
     */
    function getTransferByReference(
        bytes32 paymentReference
    ) public view returns (bytes32 eventId) {
        return transferByReference[paymentReference];
    }

    /**
     * @notice Get payment details for a transfer
     * @param eventId Event identifier
     * @return payment Payment details
     */
    function getPaymentDetails(
        bytes32 eventId
    ) public view returns (PaymentDetails memory payment) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return transferData[eventId].payment;
    }

    /**
     * @notice Get settlement status
     * @param eventId Event identifier
     * @return status Settlement status
     */
    function getSettlementStatus(
        bytes32 eventId
    ) public view returns (TransferStatusEnum status) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return transferData[eventId].settlement.status;
    }

    /**
     * @notice Check if transfer is settled
     * @param eventId Event identifier
     * @return settled True if transfer is settled
     */
    function isTransferSettled(
        bytes32 eventId
    ) public view returns (bool settled) {
        if (!eventExists[eventId]) {
            return false;
        }
        return transferData[eventId].settlement.status == TransferStatusEnum.SETTLED;
    }

    /**
     * @notice Check if transfer is verified
     * @param eventId Event identifier
     * @return verified True if transfer is verified
     */
    function isTransferVerified(
        bytes32 eventId
    ) public view returns (bool verified) {
        if (!eventExists[eventId]) {
            return false;
        }
        return transferData[eventId].settlement.isVerified;
    }

    /**
     * @notice Get transfer count for a trade
     * @param tradeId Trade identifier
     * @return count Number of transfers
     */
    function getTransferCount(
        bytes32 tradeId
    ) public view returns (uint256 count) {
        return tradeTransfers[tradeId].length;
    }

    /**
     * @notice Get last transfer for a trade
     * @param tradeId Trade identifier
     * @return eventId Last transfer event ID (or bytes32(0) if none)
     */
    function getLastTransfer(
        bytes32 tradeId
    ) public view returns (bytes32 eventId) {
        bytes32[] memory transfers = tradeTransfers[tradeId];
        if (transfers.length == 0) {
            return bytes32(0);
        }
        return transfers[transfers.length - 1];
    }

    /**
     * @notice Get payment amount
     * @param eventId Event identifier
     * @return amount Net payment amount
     */
    function getPaymentAmount(
        bytes32 eventId
    ) public view returns (uint256 amount) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        return transferData[eventId].payment.netAmount;
    }

    /**
     * @notice Get transfer parties
     * @param eventId Event identifier
     * @return payer Payer reference
     * @return receiver Receiver reference
     */
    function getTransferParties(
        bytes32 eventId
    ) public view returns (bytes32 payer, bytes32 receiver) {
        if (!eventExists[eventId]) {
            revert Event__EventDoesNotExist();
        }
        TransferEventData memory data = transferData[eventId];
        return (data.parties.payerReference, data.parties.receiverReference);
    }
}
