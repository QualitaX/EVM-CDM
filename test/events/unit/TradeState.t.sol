// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/events/TradeState.sol";

/**
 * @title TradeStateTest
 * @notice Comprehensive unit tests for TradeState contract
 * @dev Tests all state transitions, validations, and query functions
 */
contract TradeStateTest is Test {
    TradeState public tradeState;

    // Test constants
    bytes32 constant TRADE_ID_1 = keccak256("TRADE_001");
    bytes32 constant TRADE_ID_2 = keccak256("TRADE_002");
    bytes32 constant EVENT_ID_1 = keccak256("EVENT_001");
    bytes32 constant EVENT_ID_2 = keccak256("EVENT_002");
    bytes32 constant PARTY_A = keccak256("PARTY_A");
    bytes32 constant PARTY_B = keccak256("PARTY_B");
    bytes32 constant INITIATOR = keccak256("INITIATOR");

    uint256 constant ONE = 1e18;
    uint256 constant EFFECTIVE_DATE = 1704067200; // Jan 1, 2024
    uint256 constant MATURITY_DATE = 1735689600;  // Jan 1, 2025

    // Events
    event TradeCreated(
        bytes32 indexed tradeId,
        TradeState.ProductTypeEnum productType,
        bytes32 stateId,
        uint256 timestamp
    );

    event StateTransitioned(
        bytes32 indexed tradeId,
        TradeState.TradeStateEnum indexed fromState,
        TradeState.TradeStateEnum indexed toState,
        bytes32 eventId,
        bytes32 stateId
    );

    event TradeSettled(
        bytes32 indexed tradeId,
        uint256 settlementTimestamp
    );

    function setUp() public {
        tradeState = new TradeState();
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _createStandardTrade(
        bytes32 tradeId
    ) internal returns (TradeState.TradeStateSnapshot memory) {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        return tradeState.createTrade(
            tradeId,
            TradeState.ProductTypeEnum.INTEREST_RATE_SWAP,
            parties,
            EFFECTIVE_DATE,
            MATURITY_DATE
        );
    }

    function _createNDFTrade(
        bytes32 tradeId
    ) internal returns (TradeState.TradeStateSnapshot memory) {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        return tradeState.createTrade(
            tradeId,
            TradeState.ProductTypeEnum.NON_DELIVERABLE_FORWARD,
            parties,
            EFFECTIVE_DATE,
            MATURITY_DATE
        );
    }

    // =============================================================================
    // TRADE CREATION TESTS
    // =============================================================================

    function test_CreateTrade_Success() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectEmit(true, false, false, false);
        emit TradeCreated(
            TRADE_ID_1,
            TradeState.ProductTypeEnum.INTEREST_RATE_SWAP,
            bytes32(0), // stateId will be computed
            block.timestamp
        );

        TradeState.TradeStateSnapshot memory snapshot = tradeState.createTrade(
            TRADE_ID_1,
            TradeState.ProductTypeEnum.INTEREST_RATE_SWAP,
            parties,
            EFFECTIVE_DATE,
            MATURITY_DATE
        );

        assertEq(snapshot.tradeId, TRADE_ID_1);
        assertEq(uint8(snapshot.state), uint8(TradeState.TradeStateEnum.CREATED));
        assertEq(uint8(snapshot.productType), uint8(TradeState.ProductTypeEnum.INTEREST_RATE_SWAP));
        assertEq(snapshot.timestamp, block.timestamp);
        assertEq(snapshot.effectiveDate, EFFECTIVE_DATE);
        assertEq(snapshot.maturityDate, MATURITY_DATE);
        assertEq(snapshot.partyReferences.length, 2);
        assertEq(snapshot.partyReferences[0], PARTY_A);
        assertEq(snapshot.partyReferences[1], PARTY_B);
    }

    function test_CreateTrade_NDF() public {
        TradeState.TradeStateSnapshot memory snapshot = _createNDFTrade(TRADE_ID_1);

        assertEq(uint8(snapshot.productType), uint8(TradeState.ProductTypeEnum.NON_DELIVERABLE_FORWARD));
        assertEq(uint8(snapshot.state), uint8(TradeState.TradeStateEnum.CREATED));
    }

    function test_CreateTrade_RevertWhen_AlreadyExists() public {
        _createStandardTrade(TRADE_ID_1);

        vm.expectRevert(TradeState.TradeState__TradeAlreadyExists.selector);
        _createStandardTrade(TRADE_ID_1);
    }

    function test_CreateTrade_RevertWhen_InvalidDates() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        // Maturity before effective
        vm.expectRevert(TradeState.TradeState__InvalidDates.selector);
        tradeState.createTrade(
            TRADE_ID_1,
            TradeState.ProductTypeEnum.INTEREST_RATE_SWAP,
            parties,
            MATURITY_DATE,
            EFFECTIVE_DATE
        );
    }

    function test_CreateTrade_RevertWhen_InvalidDates_Equal() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        // Maturity equals effective
        vm.expectRevert(TradeState.TradeState__InvalidDates.selector);
        tradeState.createTrade(
            TRADE_ID_1,
            TradeState.ProductTypeEnum.INTEREST_RATE_SWAP,
            parties,
            EFFECTIVE_DATE,
            EFFECTIVE_DATE
        );
    }

    function test_CreateTrade_RevertWhen_UnknownProductType() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectRevert(TradeState.TradeState__InvalidProductType.selector);
        tradeState.createTrade(
            TRADE_ID_1,
            TradeState.ProductTypeEnum.UNKNOWN,
            parties,
            EFFECTIVE_DATE,
            MATURITY_DATE
        );
    }

    // =============================================================================
    // STATE TRANSITION VALIDATION TESTS
    // =============================================================================

    function test_IsValidTransition_CREATED_To_PENDING() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.CREATED,
            TradeState.TradeStateEnum.PENDING
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_CREATED_To_CONFIRMED() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.CREATED,
            TradeState.TradeStateEnum.CONFIRMED
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_CREATED_To_ACTIVE_Invalid() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.CREATED,
            TradeState.TradeStateEnum.ACTIVE
        );
        assertFalse(valid);
    }

    function test_IsValidTransition_PENDING_To_CONFIRMED() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.PENDING,
            TradeState.TradeStateEnum.CONFIRMED
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_PENDING_To_CREATED() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.PENDING,
            TradeState.TradeStateEnum.CREATED
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_CONFIRMED_To_ACTIVE() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.CONFIRMED,
            TradeState.TradeStateEnum.ACTIVE
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_CONFIRMED_To_TERMINATED() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.CONFIRMED,
            TradeState.TradeStateEnum.TERMINATED
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_ACTIVE_To_MATURED() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.ACTIVE,
            TradeState.TradeStateEnum.MATURED
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_ACTIVE_To_TERMINATED() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.ACTIVE,
            TradeState.TradeStateEnum.TERMINATED
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_MATURED_To_SETTLED() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.MATURED,
            TradeState.TradeStateEnum.SETTLED
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_TERMINATED_To_SETTLED() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.TERMINATED,
            TradeState.TradeStateEnum.SETTLED
        );
        assertTrue(valid);
    }

    function test_IsValidTransition_SETTLED_To_Any_Invalid() public {
        bool valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.SETTLED,
            TradeState.TradeStateEnum.CREATED
        );
        assertFalse(valid);

        valid = tradeState.isValidTransition(
            TradeState.TradeStateEnum.SETTLED,
            TradeState.TradeStateEnum.ACTIVE
        );
        assertFalse(valid);
    }

    // =============================================================================
    // STATE TRANSITION EXECUTION TESTS
    // =============================================================================

    function test_TransitionState_CREATED_To_PENDING() public {
        _createStandardTrade(TRADE_ID_1);

        vm.expectEmit(true, true, true, false);
        emit StateTransitioned(
            TRADE_ID_1,
            TradeState.TradeStateEnum.CREATED,
            TradeState.TradeStateEnum.PENDING,
            EVENT_ID_1,
            bytes32(0) // stateId will be computed
        );

        TradeState.TradeStateSnapshot memory snapshot = tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.PENDING,
            EVENT_ID_1,
            INITIATOR
        );

        assertEq(uint8(snapshot.state), uint8(TradeState.TradeStateEnum.PENDING));
        assertEq(snapshot.eventId, EVENT_ID_1);
        assertNotEq(snapshot.previousStateId, bytes32(0));
    }

    function test_TransitionState_FullLifecycle_ToMatured() public {
        // Create trade
        _createStandardTrade(TRADE_ID_1);

        // CREATED -> CONFIRMED
        tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.CONFIRMED,
            EVENT_ID_1,
            INITIATOR
        );

        // CONFIRMED -> ACTIVE
        tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.ACTIVE,
            EVENT_ID_1,
            INITIATOR
        );

        // ACTIVE -> MATURED
        TradeState.TradeStateSnapshot memory snapshot = tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.MATURED,
            EVENT_ID_2,
            INITIATOR
        );

        assertEq(uint8(snapshot.state), uint8(TradeState.TradeStateEnum.MATURED));

        // MATURED -> SETTLED
        vm.expectEmit(true, false, false, true);
        emit TradeSettled(TRADE_ID_1, block.timestamp);

        snapshot = tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.SETTLED,
            EVENT_ID_2,
            INITIATOR
        );

        assertEq(uint8(snapshot.state), uint8(TradeState.TradeStateEnum.SETTLED));
    }

    function test_TransitionState_FullLifecycle_ToTerminated() public {
        // Create trade
        _createStandardTrade(TRADE_ID_1);

        // CREATED -> CONFIRMED
        tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.CONFIRMED,
            EVENT_ID_1,
            INITIATOR
        );

        // CONFIRMED -> ACTIVE
        tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.ACTIVE,
            EVENT_ID_1,
            INITIATOR
        );

        // ACTIVE -> TERMINATED
        TradeState.TradeStateSnapshot memory snapshot = tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.TERMINATED,
            EVENT_ID_2,
            INITIATOR
        );

        assertEq(uint8(snapshot.state), uint8(TradeState.TradeStateEnum.TERMINATED));

        // TERMINATED -> SETTLED
        snapshot = tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.SETTLED,
            EVENT_ID_2,
            INITIATOR
        );

        assertEq(uint8(snapshot.state), uint8(TradeState.TradeStateEnum.SETTLED));
    }

    function test_TransitionState_RevertWhen_TradeDoesNotExist() public {
        vm.expectRevert(TradeState.TradeState__TradeDoesNotExist.selector);
        tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.PENDING,
            EVENT_ID_1,
            INITIATOR
        );
    }

    function test_TransitionState_RevertWhen_InvalidTransition() public {
        _createStandardTrade(TRADE_ID_1);

        // Try to go directly from CREATED to ACTIVE (invalid)
        vm.expectRevert(TradeState.TradeState__InvalidStateTransition.selector);
        tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.ACTIVE,
            EVENT_ID_1,
            INITIATOR
        );
    }

    function test_TransitionState_RevertWhen_SETTLED_To_ACTIVE() public {
        _createStandardTrade(TRADE_ID_1);

        // Go through full lifecycle
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.CONFIRMED, EVENT_ID_1, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.ACTIVE, EVENT_ID_1, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.MATURED, EVENT_ID_2, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.SETTLED, EVENT_ID_2, INITIATOR);

        // Try to transition from SETTLED (should fail)
        vm.expectRevert(TradeState.TradeState__InvalidStateTransition.selector);
        tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.ACTIVE,
            EVENT_ID_2,
            INITIATOR
        );
    }

    // =============================================================================
    // QUERY FUNCTION TESTS
    // =============================================================================

    function test_GetCurrentState() public {
        TradeState.TradeStateSnapshot memory created = _createStandardTrade(TRADE_ID_1);

        TradeState.TradeStateSnapshot memory current = tradeState.getCurrentState(TRADE_ID_1);

        assertEq(current.tradeId, created.tradeId);
        assertEq(uint8(current.state), uint8(created.state));
        assertEq(current.stateId, created.stateId);
    }

    function test_GetCurrentState_RevertWhen_TradeDoesNotExist() public {
        vm.expectRevert(TradeState.TradeState__TradeDoesNotExist.selector);
        tradeState.getCurrentState(TRADE_ID_1);
    }

    function test_GetStateHistory() public {
        _createStandardTrade(TRADE_ID_1);

        // Make several transitions
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.CONFIRMED, EVENT_ID_1, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.ACTIVE, EVENT_ID_2, INITIATOR);

        TradeState.StateTransition[] memory history = tradeState.getStateHistory(TRADE_ID_1);

        assertEq(history.length, 3);
        assertEq(uint8(history[0].fromState), uint8(TradeState.TradeStateEnum.CREATED));
        assertEq(uint8(history[0].toState), uint8(TradeState.TradeStateEnum.PENDING));
        assertEq(uint8(history[1].fromState), uint8(TradeState.TradeStateEnum.PENDING));
        assertEq(uint8(history[1].toState), uint8(TradeState.TradeStateEnum.CONFIRMED));
        assertEq(uint8(history[2].fromState), uint8(TradeState.TradeStateEnum.CONFIRMED));
        assertEq(uint8(history[2].toState), uint8(TradeState.TradeStateEnum.ACTIVE));
    }

    function test_GetStateHistory_RevertWhen_TradeDoesNotExist() public {
        vm.expectRevert(TradeState.TradeState__TradeDoesNotExist.selector);
        tradeState.getStateHistory(TRADE_ID_1);
    }

    function test_IsInState() public {
        _createStandardTrade(TRADE_ID_1);

        assertTrue(tradeState.isInState(TRADE_ID_1, TradeState.TradeStateEnum.CREATED));
        assertFalse(tradeState.isInState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING));

        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);

        assertFalse(tradeState.isInState(TRADE_ID_1, TradeState.TradeStateEnum.CREATED));
        assertTrue(tradeState.isInState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING));
    }

    function test_IsInState_NonExistentTrade() public {
        bool inState = tradeState.isInState(TRADE_ID_1, TradeState.TradeStateEnum.CREATED);
        assertFalse(inState);
    }

    function test_IsActive() public {
        _createStandardTrade(TRADE_ID_1);

        assertFalse(tradeState.isActive(TRADE_ID_1));

        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.CONFIRMED, EVENT_ID_1, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.ACTIVE, EVENT_ID_1, INITIATOR);

        assertTrue(tradeState.isActive(TRADE_ID_1));
    }

    function test_IsSettled() public {
        _createStandardTrade(TRADE_ID_1);

        assertFalse(tradeState.isSettled(TRADE_ID_1));

        // Full lifecycle
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.CONFIRMED, EVENT_ID_1, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.ACTIVE, EVENT_ID_1, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.MATURED, EVENT_ID_2, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.SETTLED, EVENT_ID_2, INITIATOR);

        assertTrue(tradeState.isSettled(TRADE_ID_1));
    }

    function test_GetTradeAge() public {
        uint256 createTime = block.timestamp;
        _createStandardTrade(TRADE_ID_1);

        uint256 age = tradeState.getTradeAge(TRADE_ID_1);
        assertEq(age, 0);

        // Move time forward
        vm.warp(createTime + 1 days);
        age = tradeState.getTradeAge(TRADE_ID_1);
        assertEq(age, 1 days);

        vm.warp(createTime + 30 days);
        age = tradeState.getTradeAge(TRADE_ID_1);
        assertEq(age, 30 days);
    }

    function test_GetTradeAge_RevertWhen_TradeDoesNotExist() public {
        vm.expectRevert(TradeState.TradeState__TradeDoesNotExist.selector);
        tradeState.getTradeAge(TRADE_ID_1);
    }

    function test_GetTransitionCount() public {
        _createStandardTrade(TRADE_ID_1);

        uint256 count = tradeState.getTransitionCount(TRADE_ID_1);
        assertEq(count, 0);

        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);
        count = tradeState.getTransitionCount(TRADE_ID_1);
        assertEq(count, 1);

        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.CONFIRMED, EVENT_ID_1, INITIATOR);
        count = tradeState.getTransitionCount(TRADE_ID_1);
        assertEq(count, 2);
    }

    function test_HasReachedEffectiveDate() public {
        _createStandardTrade(TRADE_ID_1);

        // Before effective date
        vm.warp(EFFECTIVE_DATE - 1 days);
        assertFalse(tradeState.hasReachedEffectiveDate(TRADE_ID_1));

        // On effective date
        vm.warp(EFFECTIVE_DATE);
        assertTrue(tradeState.hasReachedEffectiveDate(TRADE_ID_1));

        // After effective date
        vm.warp(EFFECTIVE_DATE + 1 days);
        assertTrue(tradeState.hasReachedEffectiveDate(TRADE_ID_1));
    }

    function test_HasReachedMaturity() public {
        _createStandardTrade(TRADE_ID_1);

        // Before maturity
        vm.warp(MATURITY_DATE - 1 days);
        assertFalse(tradeState.hasReachedMaturity(TRADE_ID_1));

        // On maturity
        vm.warp(MATURITY_DATE);
        assertTrue(tradeState.hasReachedMaturity(TRADE_ID_1));

        // After maturity
        vm.warp(MATURITY_DATE + 1 days);
        assertTrue(tradeState.hasReachedMaturity(TRADE_ID_1));
    }

    function test_GetTimeToMaturity() public {
        _createStandardTrade(TRADE_ID_1);

        // 30 days before maturity
        vm.warp(MATURITY_DATE - 30 days);
        uint256 timeRemaining = tradeState.getTimeToMaturity(TRADE_ID_1);
        assertEq(timeRemaining, 30 days);

        // 1 day before maturity
        vm.warp(MATURITY_DATE - 1 days);
        timeRemaining = tradeState.getTimeToMaturity(TRADE_ID_1);
        assertEq(timeRemaining, 1 days);

        // At maturity
        vm.warp(MATURITY_DATE);
        timeRemaining = tradeState.getTimeToMaturity(TRADE_ID_1);
        assertEq(timeRemaining, 0);

        // After maturity
        vm.warp(MATURITY_DATE + 10 days);
        timeRemaining = tradeState.getTimeToMaturity(TRADE_ID_1);
        assertEq(timeRemaining, 0);
    }

    // =============================================================================
    // MULTI-TRADE TESTS
    // =============================================================================

    function test_MultipleTrades_IndependentState() public {
        _createStandardTrade(TRADE_ID_1);
        _createNDFTrade(TRADE_ID_2);

        // Transition trade 1
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);

        // Trade 1 should be PENDING, trade 2 should still be CREATED
        assertTrue(tradeState.isInState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING));
        assertTrue(tradeState.isInState(TRADE_ID_2, TradeState.TradeStateEnum.CREATED));
    }

    function test_MultipleTrades_DifferentProducts() public {
        TradeState.TradeStateSnapshot memory irsSnapshot = _createStandardTrade(TRADE_ID_1);
        TradeState.TradeStateSnapshot memory ndfSnapshot = _createNDFTrade(TRADE_ID_2);

        assertEq(
            uint8(irsSnapshot.productType),
            uint8(TradeState.ProductTypeEnum.INTEREST_RATE_SWAP)
        );
        assertEq(
            uint8(ndfSnapshot.productType),
            uint8(TradeState.ProductTypeEnum.NON_DELIVERABLE_FORWARD)
        );
    }

    // =============================================================================
    // STATE SNAPSHOT IMMUTABILITY TESTS
    // =============================================================================

    function test_StateSnapshot_Immutable() public {
        TradeState.TradeStateSnapshot memory initial = _createStandardTrade(TRADE_ID_1);
        bytes32 initialStateId = initial.stateId;

        // Transition to new state
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);

        // Verify initial snapshot is still accessible via state history
        TradeState.StateTransition[] memory history = tradeState.getStateHistory(TRADE_ID_1);
        assertEq(history.length, 1);
        assertEq(uint8(history[0].fromState), uint8(TradeState.TradeStateEnum.CREATED));

        // Verify current state is different
        TradeState.TradeStateSnapshot memory current = tradeState.getCurrentState(TRADE_ID_1);
        assertNotEq(current.stateId, initialStateId);
        assertEq(uint8(current.state), uint8(TradeState.TradeStateEnum.PENDING));
    }

    function test_StateSnapshot_PreviousStateId_ChainOfCustody() public {
        TradeState.TradeStateSnapshot memory state1 = _createStandardTrade(TRADE_ID_1);

        TradeState.TradeStateSnapshot memory state2 = tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.PENDING,
            EVENT_ID_1,
            INITIATOR
        );

        TradeState.TradeStateSnapshot memory state3 = tradeState.transitionState(
            TRADE_ID_1,
            TradeState.TradeStateEnum.CONFIRMED,
            EVENT_ID_1,
            INITIATOR
        );

        // Verify chain of custody
        assertEq(state1.previousStateId, bytes32(0)); // First state has no previous
        assertEq(state2.previousStateId, state1.stateId);
        assertEq(state3.previousStateId, state2.stateId);
    }

    // =============================================================================
    // EDGE CASES
    // =============================================================================

    function test_TransitionHistory_RecordsAllData() public {
        _createStandardTrade(TRADE_ID_1);

        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);

        TradeState.StateTransition[] memory history = tradeState.getStateHistory(TRADE_ID_1);

        assertEq(history[0].tradeId, TRADE_ID_1);
        assertEq(history[0].eventId, EVENT_ID_1);
        assertEq(history[0].initiatorReference, INITIATOR);
        assertTrue(history[0].isValid);
        assertNotEq(history[0].transitionId, bytes32(0));
    }

    function test_MetaGlobalKey_Consistent() public {
        TradeState.TradeStateSnapshot memory state1 = _createStandardTrade(TRADE_ID_1);
        bytes32 initialKey = state1.metaGlobalKey;

        // Transition and verify key persists
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);

        TradeState.TradeStateSnapshot memory state2 = tradeState.getCurrentState(TRADE_ID_1);
        assertEq(state2.metaGlobalKey, initialKey);
    }

    function test_PartyReferences_PreservedAcrossTransitions() public {
        TradeState.TradeStateSnapshot memory initial = _createStandardTrade(TRADE_ID_1);

        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);
        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.CONFIRMED, EVENT_ID_1, INITIATOR);

        TradeState.TradeStateSnapshot memory current = tradeState.getCurrentState(TRADE_ID_1);

        assertEq(current.partyReferences.length, initial.partyReferences.length);
        assertEq(current.partyReferences[0], initial.partyReferences[0]);
        assertEq(current.partyReferences[1], initial.partyReferences[1]);
    }

    function test_Dates_PreservedAcrossTransitions() public {
        TradeState.TradeStateSnapshot memory initial = _createStandardTrade(TRADE_ID_1);

        tradeState.transitionState(TRADE_ID_1, TradeState.TradeStateEnum.PENDING, EVENT_ID_1, INITIATOR);

        TradeState.TradeStateSnapshot memory current = tradeState.getCurrentState(TRADE_ID_1);

        assertEq(current.effectiveDate, initial.effectiveDate);
        assertEq(current.maturityDate, initial.maturityDate);
    }
}
