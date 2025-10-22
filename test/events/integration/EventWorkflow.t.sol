// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/events/TradeState.sol";
import "../../../src/events/Event.sol";
import "../../../src/events/ExecutionEvent.sol";
import "../../../src/events/ResetEvent.sol";
import "../../../src/events/TransferEvent.sol";
import "../../../src/events/TerminationEvent.sol";

/**
 * @title EventWorkflowTest
 * @notice End-to-end integration tests for complete trade lifecycle
 * @dev Tests realistic scenarios with multiple events across trade lifecycle
 */
contract EventWorkflowTest is Test {
    TradeState public tradeState;
    ExecutionEvent public executionEvent;
    ResetEvent public resetEvent;
    TransferEvent public transferEvent;
    TerminationEvent public terminationEvent;

    // Test constants
    bytes32 constant TRADE_ID = keccak256("IRS_TRADE_001");
    bytes32 constant PARTY_A = keccak256("PARTY_A");
    bytes32 constant PARTY_B = keccak256("PARTY_B");
    bytes32 constant PAYOUT_FLOATING = keccak256("FLOATING_LEG");

    uint256 constant ONE = 1e18;
    uint256 constant NOTIONAL = 10_000_000 * ONE; // $10M
    uint256 constant EXECUTION_TIME = 1703980800; // Dec 31, 2023
    uint256 constant EFFECTIVE_DATE = 1704067200; // Jan 1, 2024
    uint256 constant MATURITY_DATE = 1735689600;  // Jan 1, 2025

    function setUp() public {
        // Deploy contracts
        tradeState = new TradeState();
        executionEvent = new ExecutionEvent(address(tradeState));
        resetEvent = new ResetEvent(address(tradeState));
        transferEvent = new TransferEvent(address(tradeState));
        terminationEvent = new TerminationEvent(address(tradeState));

        // Create trade
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        tradeState.createTrade(
            TRADE_ID,
            TradeState.ProductTypeEnum.INTEREST_RATE_SWAP,
            parties,
            EFFECTIVE_DATE,
            MATURITY_DATE
        );
    }

    // =============================================================================
    // FULL LIFECYCLE TEST - EXECUTION TO MATURITY
    // =============================================================================

    function test_FullLifecycle_ExecutionToMaturity() public {
        // Set time to execution time
        vm.warp(EXECUTION_TIME);

        // ========== STEP 1: EXECUTION ==========
        ExecutionEvent.ExecutionDetails memory execution = ExecutionEvent.ExecutionDetails({
            executionTimestamp: EXECUTION_TIME,
            executionPrice: 350e14, // 3.50% fixed rate
            venue: ExecutionEvent.ExecutionVenueEnum.ELECTRONIC,
            confirmMethod: ExecutionEvent.ConfirmationMethodEnum.ELECTRONIC,
            executionId: keccak256("EXEC_001"),
            venueReference: keccak256("VENUE_001"),
            isAllocated: false,
            allocationReferences: new bytes32[](0)
        });

        ExecutionEvent.EconomicTerms memory terms = ExecutionEvent.EconomicTerms({
            notional: NOTIONAL,
            currency: keccak256("USD"),
            effectiveDate: EFFECTIVE_DATE,
            maturityDate: MATURITY_DATE,
            productIdentifier: keccak256("IRS"),
            additionalTerms: new bytes32[](0)
        });

        bytes32 execEventId = keccak256("EXEC_EVENT_001");
        executionEvent.executeTrade(
            execEventId,
            TRADE_ID,
            execution,
            terms,
            PARTY_A,
            PARTY_B,
            bytes32(0),
            EXECUTION_TIME
        );

        // Verify state: CREATED -> CONFIRMED
        TradeState.TradeStateSnapshot memory state = tradeState.getCurrentState(TRADE_ID);
        assertEq(uint8(state.state), uint8(TradeState.TradeStateEnum.CONFIRMED));
        assertTrue(executionEvent.isTradeExecuted(TRADE_ID));

        // ========== STEP 2: TRANSITION TO ACTIVE ==========
        tradeState.transitionState(
            TRADE_ID,
            TradeState.TradeStateEnum.ACTIVE,
            execEventId,
            PARTY_A
        );

        state = tradeState.getCurrentState(TRADE_ID);
        assertEq(uint8(state.state), uint8(TradeState.TradeStateEnum.ACTIVE));

        // ========== STEP 3: RESET #1 - QUARTERLY SOFR OBSERVATION ==========
        // Move time to effective date for reset observation
        vm.warp(EFFECTIVE_DATE);

        ResetEvent.RateObservation memory reset1Obs = ResetEvent.RateObservation({
            observedRate: 525e14, // 5.25% SOFR
            rateIndex: ResetEvent.RateIndexEnum.SOFR,
            indexTenor: keccak256("3M"),
            source: ResetEvent.ResetSourceEnum.PUBLISHED,
            observationDate: EFFECTIVE_DATE,
            observationReference: keccak256("SOFR_FED"),
            isVerified: false
        });

        ResetEvent.ResetCalculation memory reset1Calc = ResetEvent.ResetCalculation({
            periodStartDate: EFFECTIVE_DATE,
            periodEndDate: EFFECTIVE_DATE + 90 days,
            notionalAmount: NOTIONAL,
            spread: 0, // No spread
            calculatedRate: 525e14,
            accrualAmount: 131_250 * ONE, // ~$131,250 for 90 days
            dayCountFraction: keccak256("ACT/360")
        });

        bytes32 reset1EventId = keccak256("RESET_001");
        resetEvent.recordReset(
            reset1EventId,
            TRADE_ID,
            PAYOUT_FLOATING,
            1, // Reset number 1
            reset1Obs,
            reset1Calc,
            PARTY_A
        );

        // Verify reset
        assertTrue(resetEvent.eventExists(reset1EventId));
        assertEq(resetEvent.getObservedRate(reset1EventId), 525e14);
        assertEq(resetEvent.getResetCount(TRADE_ID), 1);

        // Verify rate
        resetEvent.verifyRate(reset1EventId, PARTY_B);
        assertTrue(resetEvent.isRateVerified(reset1EventId));

        // ========== STEP 4: TRANSFER #1 - QUARTERLY PAYMENT ==========
        TransferEvent.PaymentDetails memory payment1 = TransferEvent.PaymentDetails({
            grossAmount: 131_250 * ONE,
            netAmount: 131_250 * ONE,
            currency: keccak256("USD"),
            direction: TransferEvent.TransferDirectionEnum.PAY,
            valueDate: EFFECTIVE_DATE + 90 days,
            paymentDate: EFFECTIVE_DATE + 90 days,
            paymentReference: keccak256("PAY_001")
        });

        TransferEvent.TransferParties memory parties1 = TransferEvent.TransferParties({
            payerReference: PARTY_A,
            receiverReference: PARTY_B,
            payerAccount: keccak256("ACCT_A"),
            receiverAccount: keccak256("ACCT_B"),
            intermediaryReference: bytes32(0)
        });

        bytes32 transfer1EventId = keccak256("TRANSFER_001");
        transferEvent.recordTransfer(
            transfer1EventId,
            TRADE_ID,
            TransferEvent.TransferTypeEnum.INTEREST_PAYMENT,
            payment1,
            parties1,
            PARTY_A
        );

        // Verify transfer
        assertTrue(transferEvent.eventExists(transfer1EventId));
        assertEq(transferEvent.getPaymentAmount(transfer1EventId), 131_250 * ONE);
        assertEq(transferEvent.getTransferCount(TRADE_ID), 1);

        // Settle transfer
        transferEvent.settleTransfer(transfer1EventId, EFFECTIVE_DATE + 90 days, keccak256("SETTLEMENT_001"));
        assertTrue(transferEvent.isTransferSettled(transfer1EventId));

        // ========== STEP 5: RESET #2 - SECOND QUARTER ==========
        // Move time to second reset observation
        vm.warp(EFFECTIVE_DATE + 90 days);

        ResetEvent.RateObservation memory reset2Obs = ResetEvent.RateObservation({
            observedRate: 550e14, // 5.50% SOFR (rate increased)
            rateIndex: ResetEvent.RateIndexEnum.SOFR,
            indexTenor: keccak256("3M"),
            source: ResetEvent.ResetSourceEnum.PUBLISHED,
            observationDate: EFFECTIVE_DATE + 90 days,
            observationReference: keccak256("SOFR_FED"),
            isVerified: true
        });

        ResetEvent.ResetCalculation memory reset2Calc = ResetEvent.ResetCalculation({
            periodStartDate: EFFECTIVE_DATE + 90 days,
            periodEndDate: EFFECTIVE_DATE + 180 days,
            notionalAmount: NOTIONAL,
            spread: 0,
            calculatedRate: 550e14,
            accrualAmount: 137_500 * ONE, // ~$137,500 for 90 days
            dayCountFraction: keccak256("ACT/360")
        });

        bytes32 reset2EventId = keccak256("RESET_002");
        resetEvent.recordReset(
            reset2EventId,
            TRADE_ID,
            PAYOUT_FLOATING,
            2, // Reset number 2
            reset2Obs,
            reset2Calc,
            PARTY_A
        );

        assertEq(resetEvent.getResetCount(TRADE_ID), 2);
        assertEq(resetEvent.getObservedRate(reset2EventId), 550e14);

        // Verify trade still ACTIVE
        state = tradeState.getCurrentState(TRADE_ID);
        assertEq(uint8(state.state), uint8(TradeState.TradeStateEnum.ACTIVE));
    }

    // =============================================================================
    // FULL LIFECYCLE TEST - EARLY TERMINATION
    // =============================================================================

    function test_FullLifecycle_EarlyTermination() public {
        // Setup: Execute trade and transition to ACTIVE
        _executeAndActivateTrade();

        // Record one reset and transfer
        _recordReset1();
        _recordTransfer1();

        // ========== EARLY TERMINATION ==========
        uint256 terminationDate = EFFECTIVE_DATE + 180 days;

        TerminationEvent.TerminationDetails memory termDetails = TerminationEvent.TerminationDetails({
            terminationType: TerminationEvent.TerminationTypeEnum.MUTUAL_AGREEMENT,
            terminationDate: terminationDate,
            notificationDate: terminationDate - 30 days,
            terminatingParty: PARTY_A,
            terminationReason: keccak256("MUTUAL_AGREEMENT"),
            isMutual: true,
            externalReference: keccak256("TERM_NOTICE_001")
        });

        TerminationEvent.TerminationPayment memory termPayment = TerminationEvent.TerminationPayment({
            calculationMethod: TerminationEvent.TerminationCalculationEnum.MARKET_VALUE,
            terminationValue: 50_000 * ONE, // $50,000 termination payment
            currency: keccak256("USD"),
            payerReference: PARTY_A,
            receiverReference: PARTY_B,
            paymentDate: terminationDate + 2 days,
            valuationReference: keccak256("BLOOMBERG_VALUATION"),
            isDisputed: false
        });

        bytes32 termEventId = keccak256("TERMINATION_001");
        terminationEvent.terminateTrade(
            termEventId,
            TRADE_ID,
            termDetails,
            termPayment,
            PARTY_A
        );

        // Verify termination
        assertTrue(terminationEvent.isTradeTerminated(TRADE_ID));
        assertEq(terminationEvent.getTerminationValue(termEventId), 50_000 * ONE);

        // Verify state: ACTIVE -> TERMINATED
        TradeState.TradeStateSnapshot memory state = tradeState.getCurrentState(TRADE_ID);
        assertEq(uint8(state.state), uint8(TradeState.TradeStateEnum.TERMINATED));

        // Confirm termination
        terminationEvent.confirmTermination(termEventId);
        TerminationEvent.TerminationStatusEnum status = terminationEvent.getTerminationStatus(termEventId);
        assertEq(uint8(status), uint8(TerminationEvent.TerminationStatusEnum.CONFIRMED));

        // Create termination settlement transfer
        TransferEvent.PaymentDetails memory termSettlement = TransferEvent.PaymentDetails({
            grossAmount: 50_000 * ONE,
            netAmount: 50_000 * ONE,
            currency: keccak256("USD"),
            direction: TransferEvent.TransferDirectionEnum.PAY,
            valueDate: terminationDate + 2 days,
            paymentDate: terminationDate + 2 days,
            paymentReference: keccak256("TERM_PAY_001")
        });

        TransferEvent.TransferParties memory termParties = TransferEvent.TransferParties({
            payerReference: PARTY_A,
            receiverReference: PARTY_B,
            payerAccount: keccak256("ACCT_A"),
            receiverAccount: keccak256("ACCT_B"),
            intermediaryReference: bytes32(0)
        });

        bytes32 termTransferId = keccak256("TERM_TRANSFER_001");
        transferEvent.recordTransfer(
            termTransferId,
            TRADE_ID,
            TransferEvent.TransferTypeEnum.SETTLEMENT,
            termSettlement,
            termParties,
            PARTY_A
        );

        // Settle termination payment
        transferEvent.settleTransfer(termTransferId, terminationDate + 2 days, keccak256("TERM_SETTLEMENT_001"));
        assertTrue(transferEvent.isTransferSettled(termTransferId));

        // Link settlement to termination
        terminationEvent.linkSettlementTransfer(termEventId, termTransferId);
        assertTrue(terminationEvent.isTerminationSettled(termEventId));

        // Transition to SETTLED
        tradeState.transitionState(
            TRADE_ID,
            TradeState.TradeStateEnum.SETTLED,
            termEventId,
            PARTY_A
        );

        state = tradeState.getCurrentState(TRADE_ID);
        assertEq(uint8(state.state), uint8(TradeState.TradeStateEnum.SETTLED));
    }

    // =============================================================================
    // EVENT HISTORY & AUDIT TRAIL
    // =============================================================================

    function test_EventHistory_CompleteAuditTrail() public {
        _executeAndActivateTrade();
        _recordReset1();
        _recordTransfer1();

        // Verify all events are recorded
        bytes32[] memory tradeEvents = transferEvent.getTradeEvents(TRADE_ID);
        assertTrue(tradeEvents.length > 0);

        // Verify state history
        TradeState.StateTransition[] memory history = tradeState.getStateHistory(TRADE_ID);
        assertEq(history.length, 2); // CREATED->CONFIRMED, CONFIRMED->ACTIVE

        // Verify reset history
        bytes32[] memory resets = resetEvent.getTradeResets(TRADE_ID);
        assertEq(resets.length, 1);

        // Verify transfer history
        bytes32[] memory transfers = transferEvent.getTradeTransfers(TRADE_ID);
        assertEq(transfers.length, 1);
    }

    function test_ResetWithAveraging_CompoundedSOFR() public {
        _executeAndActivateTrade();

        // Move time to effective date
        vm.warp(EFFECTIVE_DATE);

        // Create averaged observation (e.g., compounded SOFR)
        uint256[] memory observations = new uint256[](3);
        observations[0] = 520e14; // 5.20%
        observations[1] = 525e14; // 5.25%
        observations[2] = 530e14; // 5.30%

        uint256[] memory weights = new uint256[](3);
        weights[0] = ONE / 3;
        weights[1] = ONE / 3;
        weights[2] = ONE / 3;

        uint256 avgRate = 525e14; // Average: 5.25%

        ResetEvent.ResetAveraging memory averaging = ResetEvent.ResetAveraging({
            method: ResetEvent.AveragingMethodEnum.COMPOUNDED,
            observations: observations,
            weights: weights,
            compoundingPeriods: 3,
            finalRate: avgRate
        });

        ResetEvent.RateObservation memory obs = ResetEvent.RateObservation({
            observedRate: avgRate,
            rateIndex: ResetEvent.RateIndexEnum.SOFR,
            indexTenor: keccak256("ON"),
            source: ResetEvent.ResetSourceEnum.PUBLISHED,
            observationDate: EFFECTIVE_DATE,
            observationReference: keccak256("SOFR_COMPOUNDED"),
            isVerified: true
        });

        ResetEvent.ResetCalculation memory calc = ResetEvent.ResetCalculation({
            periodStartDate: EFFECTIVE_DATE,
            periodEndDate: EFFECTIVE_DATE + 90 days,
            notionalAmount: NOTIONAL,
            spread: 0,
            calculatedRate: avgRate,
            accrualAmount: 131_250 * ONE,
            dayCountFraction: keccak256("ACT/360")
        });

        bytes32 resetEventId = keccak256("RESET_AVG_001");
        resetEvent.recordResetWithAveraging(
            resetEventId,
            TRADE_ID,
            PAYOUT_FLOATING,
            1,
            obs,
            calc,
            averaging,
            PARTY_A
        );

        ResetEvent.ResetEventData memory data = resetEvent.getResetData(resetEventId);
        assertEq(uint8(data.averaging.method), uint8(ResetEvent.AveragingMethodEnum.COMPOUNDED));
        assertEq(data.averaging.observations.length, 3);
        assertEq(data.averaging.finalRate, avgRate);
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _executeAndActivateTrade() internal {
        vm.warp(EXECUTION_TIME);

        ExecutionEvent.ExecutionDetails memory execution = ExecutionEvent.ExecutionDetails({
            executionTimestamp: EXECUTION_TIME,
            executionPrice: 350e14,
            venue: ExecutionEvent.ExecutionVenueEnum.ELECTRONIC,
            confirmMethod: ExecutionEvent.ConfirmationMethodEnum.ELECTRONIC,
            executionId: keccak256("EXEC_001"),
            venueReference: keccak256("VENUE_001"),
            isAllocated: false,
            allocationReferences: new bytes32[](0)
        });

        ExecutionEvent.EconomicTerms memory terms = ExecutionEvent.EconomicTerms({
            notional: NOTIONAL,
            currency: keccak256("USD"),
            effectiveDate: EFFECTIVE_DATE,
            maturityDate: MATURITY_DATE,
            productIdentifier: keccak256("IRS"),
            additionalTerms: new bytes32[](0)
        });

        bytes32 execEventId = keccak256("EXEC_EVENT_001");
        executionEvent.executeTrade(execEventId, TRADE_ID, execution, terms, PARTY_A, PARTY_B, bytes32(0), EXECUTION_TIME);

        tradeState.transitionState(TRADE_ID, TradeState.TradeStateEnum.ACTIVE, execEventId, PARTY_A);
    }

    function _recordReset1() internal {
        vm.warp(EFFECTIVE_DATE);

        ResetEvent.RateObservation memory obs = ResetEvent.RateObservation({
            observedRate: 525e14,
            rateIndex: ResetEvent.RateIndexEnum.SOFR,
            indexTenor: keccak256("3M"),
            source: ResetEvent.ResetSourceEnum.PUBLISHED,
            observationDate: EFFECTIVE_DATE,
            observationReference: keccak256("SOFR_FED"),
            isVerified: true
        });

        ResetEvent.ResetCalculation memory calc = ResetEvent.ResetCalculation({
            periodStartDate: EFFECTIVE_DATE,
            periodEndDate: EFFECTIVE_DATE + 90 days,
            notionalAmount: NOTIONAL,
            spread: 0,
            calculatedRate: 525e14,
            accrualAmount: 131_250 * ONE,
            dayCountFraction: keccak256("ACT/360")
        });

        bytes32 resetEventId = keccak256("RESET_001");
        resetEvent.recordReset(resetEventId, TRADE_ID, PAYOUT_FLOATING, 1, obs, calc, PARTY_A);
    }

    function _recordTransfer1() internal {
        TransferEvent.PaymentDetails memory payment = TransferEvent.PaymentDetails({
            grossAmount: 131_250 * ONE,
            netAmount: 131_250 * ONE,
            currency: keccak256("USD"),
            direction: TransferEvent.TransferDirectionEnum.PAY,
            valueDate: EFFECTIVE_DATE + 90 days,
            paymentDate: EFFECTIVE_DATE + 90 days,
            paymentReference: keccak256("PAY_001")
        });

        TransferEvent.TransferParties memory parties = TransferEvent.TransferParties({
            payerReference: PARTY_A,
            receiverReference: PARTY_B,
            payerAccount: keccak256("ACCT_A"),
            receiverAccount: keccak256("ACCT_B"),
            intermediaryReference: bytes32(0)
        });

        bytes32 transferEventId = keccak256("TRANSFER_001");
        transferEvent.recordTransfer(transferEventId, TRADE_ID, TransferEvent.TransferTypeEnum.INTEREST_PAYMENT, payment, parties, PARTY_A);
        transferEvent.settleTransfer(transferEventId, EFFECTIVE_DATE + 90 days, keccak256("SETTLEMENT_001"));
    }
}
