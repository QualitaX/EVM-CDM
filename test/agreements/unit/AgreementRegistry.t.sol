// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/agreements/AgreementRegistry.sol";

/**
 * @title AgreementRegistryTest
 * @notice Comprehensive unit tests for AgreementRegistry contract
 */
contract AgreementRegistryTest is Test {
    AgreementRegistry public registry;

    // Test constants
    bytes32 constant AGREEMENT_ID = keccak256("ISDA_MASTER_001");
    bytes32 constant PARTY_A = keccak256("PARTY_A");
    bytes32 constant PARTY_B = keccak256("PARTY_B");
    bytes32 constant PARTY_C = keccak256("PARTY_C");
    bytes32 constant CSA_ID_1 = keccak256("CSA_001");
    bytes32 constant CSA_ID_2 = keccak256("CSA_002");
    bytes32 constant DOCUMENT_HASH = keccak256("ipfs://Qm...");
    bytes32 constant REGISTERED_BY = keccak256("REGISTRAR");

    uint256 constant EFFECTIVE_DATE = 1704067200; // Jan 1, 2024
    uint256 constant TERMINATION_DATE = 1735689600; // Jan 1, 2025

    function setUp() public {
        registry = new AgreementRegistry();
    }

    // =============================================================================
    // REGISTRATION TESTS
    // =============================================================================

    function test_RegisterMasterAgreement_Success() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        AgreementRegistry.MasterAgreement memory agreement = registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );

        assertEq(agreement.agreementId, AGREEMENT_ID);
        assertEq(uint8(agreement.agreementType), uint8(AgreementRegistry.AgreementTypeEnum.ISDA_MASTER));
        assertEq(agreement.parties.length, 2);
        assertEq(agreement.parties[0], PARTY_A);
        assertEq(agreement.parties[1], PARTY_B);
        assertEq(agreement.effectiveDate, EFFECTIVE_DATE);
        assertEq(agreement.terminationDate, TERMINATION_DATE);
        assertEq(uint8(agreement.governingLaw), uint8(AgreementRegistry.JurisdictionEnum.NEW_YORK));
        assertEq(agreement.documentHash, DOCUMENT_HASH);
        assertEq(uint8(agreement.status), uint8(AgreementRegistry.AgreementStatusEnum.ACTIVE));
        assertEq(agreement.registeredBy, REGISTERED_BY);
    }

    function test_RegisterMasterAgreement_Evergreen() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        AgreementRegistry.MasterAgreement memory agreement = registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            0, // No termination date (evergreen)
            AgreementRegistry.JurisdictionEnum.ENGLISH_LAW,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );

        assertEq(agreement.terminationDate, 0);
    }

    function test_RegisterMasterAgreement_GMRA() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        AgreementRegistry.MasterAgreement memory agreement = registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.GMRA,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.ENGLISH_LAW,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );

        assertEq(uint8(agreement.agreementType), uint8(AgreementRegistry.AgreementTypeEnum.GMRA));
    }

    function test_RegisterMasterAgreement_ThreeParties() public {
        bytes32[] memory parties = new bytes32[](3);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;
        parties[2] = PARTY_C;

        AgreementRegistry.MasterAgreement memory agreement = registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );

        assertEq(agreement.parties.length, 3);
    }

    function test_RegisterMasterAgreement_UpdatesCounters() public {
        assertEq(registry.totalAgreements(), 0);

        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );

        assertEq(registry.totalAgreements(), 1);
    }

    function test_RegisterMasterAgreement_RevertWhen_AlreadyExists() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );

        vm.expectRevert(AgreementRegistry.AgreementRegistry__AgreementAlreadyExists.selector);
        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );
    }

    function test_RegisterMasterAgreement_RevertWhen_InsufficientParties() public {
        bytes32[] memory parties = new bytes32[](1);
        parties[0] = PARTY_A;

        vm.expectRevert(AgreementRegistry.AgreementRegistry__InvalidParties.selector);
        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );
    }

    function test_RegisterMasterAgreement_RevertWhen_ZeroParty() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = bytes32(0);

        vm.expectRevert(AgreementRegistry.AgreementRegistry__InvalidParties.selector);
        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );
    }

    function test_RegisterMasterAgreement_RevertWhen_DuplicateParties() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_A; // Duplicate

        vm.expectRevert(AgreementRegistry.AgreementRegistry__InvalidParties.selector);
        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );
    }

    function test_RegisterMasterAgreement_RevertWhen_ZeroEffectiveDate() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectRevert(AgreementRegistry.AgreementRegistry__InvalidDates.selector);
        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            0, // Invalid
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );
    }

    function test_RegisterMasterAgreement_RevertWhen_TerminationBeforeEffective() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        vm.expectRevert(AgreementRegistry.AgreementRegistry__InvalidDates.selector);
        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            EFFECTIVE_DATE - 1, // Before effective
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );
    }

    function test_RegisterMasterAgreement_RevertWhen_DocumentHashAlreadyUsed() public {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );

        bytes32 agreementId2 = keccak256("ISDA_MASTER_002");

        vm.expectRevert(AgreementRegistry.AgreementRegistry__DocumentHashAlreadyUsed.selector);
        registry.registerMasterAgreement(
            agreementId2,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH, // Same document hash
            REGISTERED_BY
        );
    }

    // =============================================================================
    // CSA ATTACHMENT TESTS
    // =============================================================================

    function test_AttachCSA_Success() public {
        _registerStandardAgreement();

        registry.attachCSA(CSA_ID_1, AGREEMENT_ID, PARTY_A);

        bytes32[] memory csas = registry.getAttachedCSAs(AGREEMENT_ID);
        assertEq(csas.length, 1);
        assertEq(csas[0], CSA_ID_1);

        assertEq(registry.getMasterAgreementForCSA(CSA_ID_1), AGREEMENT_ID);
    }

    function test_AttachCSA_Multiple() public {
        _registerStandardAgreement();

        registry.attachCSA(CSA_ID_1, AGREEMENT_ID, PARTY_A);
        registry.attachCSA(CSA_ID_2, AGREEMENT_ID, PARTY_A);

        bytes32[] memory csas = registry.getAttachedCSAs(AGREEMENT_ID);
        assertEq(csas.length, 2);
        assertEq(csas[0], CSA_ID_1);
        assertEq(csas[1], CSA_ID_2);
    }

    function test_AttachCSA_RevertWhen_AgreementDoesNotExist() public {
        vm.expectRevert(AgreementRegistry.AgreementRegistry__AgreementDoesNotExist.selector);
        registry.attachCSA(CSA_ID_1, AGREEMENT_ID, PARTY_A);
    }

    function test_AttachCSA_RevertWhen_AgreementNotActive() public {
        _registerStandardAgreement();
        registry.updateAgreementStatus(AGREEMENT_ID, AgreementRegistry.AgreementStatusEnum.SUSPENDED, PARTY_A);

        vm.expectRevert(AgreementRegistry.AgreementRegistry__AgreementNotActive.selector);
        registry.attachCSA(CSA_ID_1, AGREEMENT_ID, PARTY_A);
    }

    function test_AttachCSA_RevertWhen_CSAAlreadyAttached() public {
        _registerStandardAgreement();
        registry.attachCSA(CSA_ID_1, AGREEMENT_ID, PARTY_A);

        vm.expectRevert(AgreementRegistry.AgreementRegistry__CSAAlreadyAttached.selector);
        registry.attachCSA(CSA_ID_1, AGREEMENT_ID, PARTY_A);
    }

    function test_DetachCSA_Success() public {
        _registerStandardAgreement();
        registry.attachCSA(CSA_ID_1, AGREEMENT_ID, PARTY_A);

        registry.detachCSA(CSA_ID_1, PARTY_A);

        bytes32[] memory csas = registry.getAttachedCSAs(AGREEMENT_ID);
        assertEq(csas.length, 0);

        assertEq(registry.getMasterAgreementForCSA(CSA_ID_1), bytes32(0));
    }

    function test_DetachCSA_RevertWhen_CSANotAttached() public {
        vm.expectRevert(AgreementRegistry.AgreementRegistry__CSANotAttached.selector);
        registry.detachCSA(CSA_ID_1, PARTY_A);
    }

    // =============================================================================
    // AGREEMENT LIFECYCLE TESTS
    // =============================================================================

    function test_UpdateAgreementStatus_Success() public {
        _registerStandardAgreement();

        registry.updateAgreementStatus(
            AGREEMENT_ID,
            AgreementRegistry.AgreementStatusEnum.SUSPENDED,
            PARTY_A
        );

        AgreementRegistry.MasterAgreement memory agreement = registry.getAgreement(AGREEMENT_ID);
        assertEq(uint8(agreement.status), uint8(AgreementRegistry.AgreementStatusEnum.SUSPENDED));
    }

    function test_UpdateAgreementStatus_RevertWhen_AgreementDoesNotExist() public {
        vm.expectRevert(AgreementRegistry.AgreementRegistry__AgreementDoesNotExist.selector);
        registry.updateAgreementStatus(
            AGREEMENT_ID,
            AgreementRegistry.AgreementStatusEnum.SUSPENDED,
            PARTY_A
        );
    }

    function test_TerminateAgreement_Success() public {
        _registerStandardAgreement();

        registry.terminateAgreement(AGREEMENT_ID, PARTY_A);

        AgreementRegistry.MasterAgreement memory agreement = registry.getAgreement(AGREEMENT_ID);
        assertEq(uint8(agreement.status), uint8(AgreementRegistry.AgreementStatusEnum.TERMINATED));
    }

    function test_TerminateAgreement_RevertWhen_AgreementDoesNotExist() public {
        vm.expectRevert(AgreementRegistry.AgreementRegistry__AgreementDoesNotExist.selector);
        registry.terminateAgreement(AGREEMENT_ID, PARTY_A);
    }

    // =============================================================================
    // QUERY FUNCTION TESTS
    // =============================================================================

    function test_GetAgreement_Success() public {
        _registerStandardAgreement();

        AgreementRegistry.MasterAgreement memory agreement = registry.getAgreement(AGREEMENT_ID);
        assertEq(agreement.agreementId, AGREEMENT_ID);
    }

    function test_GetAgreement_RevertWhen_DoesNotExist() public {
        vm.expectRevert(AgreementRegistry.AgreementRegistry__AgreementDoesNotExist.selector);
        registry.getAgreement(AGREEMENT_ID);
    }

    function test_GetPartyAgreements() public {
        _registerStandardAgreement();

        bytes32[] memory partyAAgreements = registry.getPartyAgreements(PARTY_A);
        assertEq(partyAAgreements.length, 1);
        assertEq(partyAAgreements[0], AGREEMENT_ID);

        bytes32[] memory partyBAgreements = registry.getPartyAgreements(PARTY_B);
        assertEq(partyBAgreements.length, 1);
        assertEq(partyBAgreements[0], AGREEMENT_ID);
    }

    function test_HasAgreement_Success() public {
        _registerStandardAgreement();

        (bool exists, bytes32 agreementId) = registry.hasAgreement(
            PARTY_A,
            PARTY_B,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER
        );

        assertTrue(exists);
        assertEq(agreementId, AGREEMENT_ID);
    }

    function test_HasAgreement_DifferentPartyOrder() public {
        _registerStandardAgreement();

        (bool exists, bytes32 agreementId) = registry.hasAgreement(
            PARTY_B,
            PARTY_A, // Reversed order
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER
        );

        assertTrue(exists);
        assertEq(agreementId, AGREEMENT_ID);
    }

    function test_HasAgreement_NotFound() public {
        _registerStandardAgreement();

        (bool exists, ) = registry.hasAgreement(
            PARTY_A,
            PARTY_C,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER
        );

        assertFalse(exists);
    }

    function test_HasAgreement_WrongType() public {
        _registerStandardAgreement();

        (bool exists, ) = registry.hasAgreement(
            PARTY_A,
            PARTY_B,
            AgreementRegistry.AgreementTypeEnum.GMRA
        );

        assertFalse(exists);
    }

    function test_GetPartyRelationship() public {
        _registerStandardAgreement();

        AgreementRegistry.PartyRelationship memory relationship = registry.getPartyRelationship(
            PARTY_A,
            PARTY_B
        );

        assertEq(relationship.agreementIds.length, 1);
        assertEq(relationship.agreementIds[0], AGREEMENT_ID);
        assertTrue(relationship.hasActiveAgreement);
    }

    function test_IsAgreementActive_True() public {
        _registerStandardAgreement();

        assertTrue(registry.isAgreementActive(AGREEMENT_ID));
    }

    function test_IsAgreementActive_False_Terminated() public {
        _registerStandardAgreement();
        registry.terminateAgreement(AGREEMENT_ID, PARTY_A);

        assertFalse(registry.isAgreementActive(AGREEMENT_ID));
    }

    function test_IsAgreementActive_False_DoesNotExist() public {
        assertFalse(registry.isAgreementActive(AGREEMENT_ID));
    }

    function test_GetAgreementByDocumentHash() public {
        _registerStandardAgreement();

        bytes32 agreementId = registry.getAgreementByDocumentHash(DOCUMENT_HASH);
        assertEq(agreementId, AGREEMENT_ID);
    }

    function test_HasActiveRelationship_True() public {
        _registerStandardAgreement();

        assertTrue(registry.hasActiveRelationship(PARTY_A, PARTY_B));
    }

    function test_HasActiveRelationship_False_AfterTermination() public {
        _registerStandardAgreement();
        registry.terminateAgreement(AGREEMENT_ID, PARTY_A);

        assertFalse(registry.hasActiveRelationship(PARTY_A, PARTY_B));
    }

    function test_HasActiveRelationship_False_NoRelationship() public {
        assertFalse(registry.hasActiveRelationship(PARTY_A, PARTY_C));
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _registerStandardAgreement() internal {
        bytes32[] memory parties = new bytes32[](2);
        parties[0] = PARTY_A;
        parties[1] = PARTY_B;

        registry.registerMasterAgreement(
            AGREEMENT_ID,
            AgreementRegistry.AgreementTypeEnum.ISDA_MASTER,
            parties,
            EFFECTIVE_DATE,
            TERMINATION_DATE,
            AgreementRegistry.JurisdictionEnum.NEW_YORK,
            bytes32(0),
            DOCUMENT_HASH,
            REGISTERED_BY
        );
    }
}
