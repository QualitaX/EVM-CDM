// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AgreementRegistry
 * @notice Central registry for legal agreements between parties
 * @dev Manages master agreements (ISDA, GMRA, etc.) and their relationships
 *
 * KEY FEATURES:
 * - Master agreement registration (ISDA, GMRA, MRA, etc.)
 * - Party relationship tracking
 * - CSA linkage to master agreements
 * - Agreement lifecycle management
 * - Document hash storage (IPFS/Arweave)
 * - Bi-directional party lookups
 *
 * AGREEMENT HIERARCHY:
 * MasterAgreement (ISDA, GMRA, etc.)
 *   ├── Parties (typically bilateral)
 *   ├── Governing law and jurisdiction
 *   ├── Effective/termination dates
 *   ├── Document hash (legal evidence)
 *   └── Attached CSAs (credit support)
 *
 * TYPICAL USE CASES:
 * - Register ISDA Master Agreement between counterparties
 * - Attach Credit Support Annex (CSA)
 * - Query agreements by parties
 * - Validate trading relationships
 * - Track agreement lifecycle
 *
 * @author QualitaX Team
 */
contract AgreementRegistry {
    // =============================================================================
    // ENUMS
    // =============================================================================

    /// @notice Type of master agreement
    enum AgreementTypeEnum {
        ISDA_MASTER,            // ISDA Master Agreement (derivatives)
        GMRA,                   // Global Master Repurchase Agreement (repo)
        GMSLA,                  // Global Master Securities Lending Agreement
        MRA,                    // Master Repurchase Agreement
        MSLA,                   // Master Securities Lending Agreement
        MSFTA,                  // Master Securities Forward Transaction Agreement
        CUSTOM                  // Custom bilateral agreement
    }

    /// @notice Agreement status
    enum AgreementStatusEnum {
        PENDING,                // Pending execution
        ACTIVE,                 // Active and enforceable
        SUSPENDED,              // Temporarily suspended
        TERMINATED,             // Terminated
        EXPIRED                 // Expired (past termination date)
    }

    /// @notice Jurisdiction for governing law
    enum JurisdictionEnum {
        NEW_YORK,               // New York law
        ENGLISH_LAW,            // English law
        JAPANESE_LAW,           // Japanese law
        GERMAN_LAW,             // German law
        FRENCH_LAW,             // French law
        SINGAPORE_LAW,          // Singapore law
        HONG_KONG_LAW,          // Hong Kong law
        CUSTOM                  // Other jurisdiction
    }

    // =============================================================================
    // STRUCTS
    // =============================================================================

    /// @notice Master agreement between parties
    /// @dev Core legal agreement structure
    struct MasterAgreement {
        bytes32 agreementId;                    // Unique agreement identifier
        AgreementTypeEnum agreementType;        // Type of agreement
        bytes32[] parties;                      // Counterparties (typically 2, can be more)
        uint256 effectiveDate;                  // Agreement effective date
        uint256 terminationDate;                // Agreement end (0 = evergreen)
        JurisdictionEnum governingLaw;          // Governing law jurisdiction
        bytes32 governingLawCustom;             // Custom jurisdiction if CUSTOM
        bytes32 documentHash;                   // IPFS/Arweave hash of signed doc
        bytes32[] attachedCSAs;                 // CSA IDs attached to this master
        AgreementStatusEnum status;             // Current status
        uint256 registrationTimestamp;          // When registered on-chain
        bytes32 registeredBy;                   // Who registered
        bytes32 metaGlobalKey;                  // CDM global key
    }

    /// @notice Party relationship record
    /// @dev Tracks all agreements between two parties
    struct PartyRelationship {
        bytes32 party1;
        bytes32 party2;
        bytes32[] agreementIds;                 // All agreements between parties
        uint256 relationshipStart;              // First agreement date
        bool hasActiveAgreement;                // Quick check
    }

    // =============================================================================
    // STORAGE
    // =============================================================================

    /// @notice Mapping from agreement ID to agreement data
    mapping(bytes32 => MasterAgreement) public agreements;

    /// @notice Mapping from agreement ID to existence check
    mapping(bytes32 => bool) public agreementExists;

    /// @notice Mapping from party to their agreement IDs
    mapping(bytes32 => bytes32[]) public partyAgreements;

    /// @notice Mapping from party pair to relationship
    /// @dev Key is keccak256(abi.encodePacked(smaller, larger)) for consistency
    mapping(bytes32 => PartyRelationship) public partyRelationships;

    /// @notice Mapping from CSA ID to master agreement ID
    mapping(bytes32 => bytes32) public csaToMasterAgreement;

    /// @notice Mapping from document hash to agreement ID
    mapping(bytes32 => bytes32) public documentHashToAgreement;

    /// @notice Counter for total agreements
    uint256 public totalAgreements;

    // =============================================================================
    // EVENTS
    // =============================================================================

    event MasterAgreementRegistered(
        bytes32 indexed agreementId,
        AgreementTypeEnum agreementType,
        bytes32[] parties,
        uint256 effectiveDate,
        bytes32 registeredBy
    );

    event CSAAttached(
        bytes32 indexed csaId,
        bytes32 indexed masterAgreementId,
        bytes32 attachedBy
    );

    event CSADetached(
        bytes32 indexed csaId,
        bytes32 indexed masterAgreementId,
        bytes32 detachedBy
    );

    event AgreementStatusChanged(
        bytes32 indexed agreementId,
        AgreementStatusEnum oldStatus,
        AgreementStatusEnum newStatus,
        bytes32 changedBy
    );

    event AgreementTerminated(
        bytes32 indexed agreementId,
        uint256 terminationDate,
        bytes32 terminatedBy
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error AgreementRegistry__AgreementAlreadyExists();
    error AgreementRegistry__AgreementDoesNotExist();
    error AgreementRegistry__InvalidParties();
    error AgreementRegistry__InvalidDates();
    error AgreementRegistry__InvalidStatus();
    error AgreementRegistry__CSAAlreadyAttached();
    error AgreementRegistry__CSANotAttached();
    error AgreementRegistry__DocumentHashAlreadyUsed();
    error AgreementRegistry__AgreementNotActive();

    // =============================================================================
    // CONSTRUCTOR
    // =============================================================================

    /**
     * @notice Initialize AgreementRegistry contract
     */
    constructor() {}

    // =============================================================================
    // AGREEMENT REGISTRATION
    // =============================================================================

    /**
     * @notice Register a new master agreement
     * @dev Creates master agreement between parties
     * @param agreementId Unique agreement identifier
     * @param agreementType Type of agreement (ISDA, GMRA, etc.)
     * @param parties Array of party identifiers (typically 2)
     * @param effectiveDate Agreement effective date
     * @param terminationDate Agreement end date (0 for evergreen)
     * @param governingLaw Governing law jurisdiction
     * @param governingLawCustom Custom jurisdiction if CUSTOM
     * @param documentHash IPFS/Arweave hash of signed agreement
     * @param registeredBy Party registering the agreement
     * @return agreement Created master agreement
     */
    function registerMasterAgreement(
        bytes32 agreementId,
        AgreementTypeEnum agreementType,
        bytes32[] memory parties,
        uint256 effectiveDate,
        uint256 terminationDate,
        JurisdictionEnum governingLaw,
        bytes32 governingLawCustom,
        bytes32 documentHash,
        bytes32 registeredBy
    ) public returns (MasterAgreement memory agreement) {
        // Validate
        _validateAgreementRegistration(
            agreementId,
            parties,
            effectiveDate,
            terminationDate,
            documentHash
        );

        // Create agreement
        agreement = MasterAgreement({
            agreementId: agreementId,
            agreementType: agreementType,
            parties: parties,
            effectiveDate: effectiveDate,
            terminationDate: terminationDate,
            governingLaw: governingLaw,
            governingLawCustom: governingLawCustom,
            documentHash: documentHash,
            attachedCSAs: new bytes32[](0),
            status: AgreementStatusEnum.ACTIVE,
            registrationTimestamp: block.timestamp,
            registeredBy: registeredBy,
            metaGlobalKey: keccak256(abi.encode(agreementId, parties))
        });

        // Store agreement
        _storeAgreement(agreement);

        // Emit event
        emit MasterAgreementRegistered(
            agreementId,
            agreementType,
            parties,
            effectiveDate,
            registeredBy
        );

        return agreement;
    }

    /**
     * @notice Attach a CSA to a master agreement
     * @dev Links CSA to its governing master agreement
     * @param csaId CSA identifier
     * @param masterAgreementId Master agreement identifier
     * @param attachedBy Party attaching the CSA
     */
    function attachCSA(
        bytes32 csaId,
        bytes32 masterAgreementId,
        bytes32 attachedBy
    ) public {
        // Validate master agreement exists
        if (!agreementExists[masterAgreementId]) {
            revert AgreementRegistry__AgreementDoesNotExist();
        }

        // Validate master agreement is active
        if (agreements[masterAgreementId].status != AgreementStatusEnum.ACTIVE) {
            revert AgreementRegistry__AgreementNotActive();
        }

        // Check CSA not already attached to another master
        if (csaToMasterAgreement[csaId] != bytes32(0)) {
            revert AgreementRegistry__CSAAlreadyAttached();
        }

        // Attach CSA
        agreements[masterAgreementId].attachedCSAs.push(csaId);
        csaToMasterAgreement[csaId] = masterAgreementId;

        emit CSAAttached(csaId, masterAgreementId, attachedBy);
    }

    /**
     * @notice Detach a CSA from a master agreement
     * @dev Removes CSA linkage
     * @param csaId CSA identifier
     * @param detachedBy Party detaching the CSA
     */
    function detachCSA(
        bytes32 csaId,
        bytes32 detachedBy
    ) public {
        bytes32 masterAgreementId = csaToMasterAgreement[csaId];

        if (masterAgreementId == bytes32(0)) {
            revert AgreementRegistry__CSANotAttached();
        }

        // Remove from attached CSAs array
        bytes32[] storage attachedCSAs = agreements[masterAgreementId].attachedCSAs;
        for (uint256 i = 0; i < attachedCSAs.length; i++) {
            if (attachedCSAs[i] == csaId) {
                attachedCSAs[i] = attachedCSAs[attachedCSAs.length - 1];
                attachedCSAs.pop();
                break;
            }
        }

        // Remove mapping
        delete csaToMasterAgreement[csaId];

        emit CSADetached(csaId, masterAgreementId, detachedBy);
    }

    // =============================================================================
    // AGREEMENT LIFECYCLE
    // =============================================================================

    /**
     * @notice Update agreement status
     * @dev Change agreement status (ACTIVE, SUSPENDED, etc.)
     * @param agreementId Agreement identifier
     * @param newStatus New status
     * @param changedBy Party making the change
     */
    function updateAgreementStatus(
        bytes32 agreementId,
        AgreementStatusEnum newStatus,
        bytes32 changedBy
    ) public {
        if (!agreementExists[agreementId]) {
            revert AgreementRegistry__AgreementDoesNotExist();
        }

        MasterAgreement storage agreement = agreements[agreementId];
        AgreementStatusEnum oldStatus = agreement.status;

        agreement.status = newStatus;

        emit AgreementStatusChanged(agreementId, oldStatus, newStatus, changedBy);
    }

    /**
     * @notice Terminate a master agreement
     * @dev Sets status to TERMINATED
     * @param agreementId Agreement identifier
     * @param terminatedBy Party terminating the agreement
     */
    function terminateAgreement(
        bytes32 agreementId,
        bytes32 terminatedBy
    ) public {
        if (!agreementExists[agreementId]) {
            revert AgreementRegistry__AgreementDoesNotExist();
        }

        MasterAgreement storage agreement = agreements[agreementId];
        AgreementStatusEnum oldStatus = agreement.status;

        agreement.status = AgreementStatusEnum.TERMINATED;

        // Update party relationships
        _updatePartyRelationshipStatus(agreement.parties);

        emit AgreementStatusChanged(agreementId, oldStatus, AgreementStatusEnum.TERMINATED, terminatedBy);
        emit AgreementTerminated(agreementId, block.timestamp, terminatedBy);
    }

    // =============================================================================
    // INTERNAL FUNCTIONS
    // =============================================================================

    /**
     * @notice Validate agreement registration
     * @dev Internal validation helper
     */
    function _validateAgreementRegistration(
        bytes32 agreementId,
        bytes32[] memory parties,
        uint256 effectiveDate,
        uint256 terminationDate,
        bytes32 documentHash
    ) internal view {
        // Check agreement doesn't exist
        if (agreementExists[agreementId]) {
            revert AgreementRegistry__AgreementAlreadyExists();
        }

        // Validate parties
        if (parties.length < 2) {
            revert AgreementRegistry__InvalidParties();
        }
        for (uint256 i = 0; i < parties.length; i++) {
            if (parties[i] == bytes32(0)) {
                revert AgreementRegistry__InvalidParties();
            }
            // Check for duplicates
            for (uint256 j = i + 1; j < parties.length; j++) {
                if (parties[i] == parties[j]) {
                    revert AgreementRegistry__InvalidParties();
                }
            }
        }

        // Validate dates
        if (effectiveDate == 0) {
            revert AgreementRegistry__InvalidDates();
        }
        if (terminationDate != 0 && terminationDate <= effectiveDate) {
            revert AgreementRegistry__InvalidDates();
        }

        // Check document hash not already used
        if (documentHash != bytes32(0) && documentHashToAgreement[documentHash] != bytes32(0)) {
            revert AgreementRegistry__DocumentHashAlreadyUsed();
        }
    }

    /**
     * @notice Store agreement and update indexes
     * @dev Internal storage helper
     */
    function _storeAgreement(MasterAgreement memory agreement) internal {
        // Store agreement
        agreements[agreement.agreementId] = agreement;
        agreementExists[agreement.agreementId] = true;

        // Update party indexes
        for (uint256 i = 0; i < agreement.parties.length; i++) {
            partyAgreements[agreement.parties[i]].push(agreement.agreementId);
        }

        // Update party relationships (for bilateral agreements)
        if (agreement.parties.length == 2) {
            _updatePartyRelationship(agreement.parties[0], agreement.parties[1], agreement.agreementId);
        }

        // Update document hash index
        if (agreement.documentHash != bytes32(0)) {
            documentHashToAgreement[agreement.documentHash] = agreement.agreementId;
        }

        totalAgreements++;
    }

    /**
     * @notice Update party relationship
     * @dev Internal helper for bilateral relationships
     */
    function _updatePartyRelationship(
        bytes32 party1,
        bytes32 party2,
        bytes32 agreementId
    ) internal {
        bytes32 relationshipKey = _getRelationshipKey(party1, party2);

        PartyRelationship storage relationship = partyRelationships[relationshipKey];

        if (relationship.party1 == bytes32(0)) {
            // New relationship
            relationship.party1 = party1 < party2 ? party1 : party2;
            relationship.party2 = party1 < party2 ? party2 : party1;
            relationship.relationshipStart = block.timestamp;
        }

        relationship.agreementIds.push(agreementId);
        relationship.hasActiveAgreement = true;
    }

    /**
     * @notice Update party relationship status
     * @dev Check if any active agreements remain
     */
    function _updatePartyRelationshipStatus(bytes32[] memory parties) internal {
        if (parties.length != 2) return;

        bytes32 relationshipKey = _getRelationshipKey(parties[0], parties[1]);
        PartyRelationship storage relationship = partyRelationships[relationshipKey];

        // Check if any agreements are still active
        bool hasActive = false;
        for (uint256 i = 0; i < relationship.agreementIds.length; i++) {
            if (agreements[relationship.agreementIds[i]].status == AgreementStatusEnum.ACTIVE) {
                hasActive = true;
                break;
            }
        }

        relationship.hasActiveAgreement = hasActive;
    }

    /**
     * @notice Get relationship key for party pair
     * @dev Ensures consistent ordering
     */
    function _getRelationshipKey(bytes32 party1, bytes32 party2) internal pure returns (bytes32) {
        return party1 < party2
            ? keccak256(abi.encodePacked(party1, party2))
            : keccak256(abi.encodePacked(party2, party1));
    }

    // =============================================================================
    // QUERY FUNCTIONS
    // =============================================================================

    /**
     * @notice Get master agreement by ID
     * @param agreementId Agreement identifier
     * @return agreement Master agreement data
     */
    function getAgreement(
        bytes32 agreementId
    ) public view returns (MasterAgreement memory agreement) {
        if (!agreementExists[agreementId]) {
            revert AgreementRegistry__AgreementDoesNotExist();
        }
        return agreements[agreementId];
    }

    /**
     * @notice Get all agreements for a party
     * @param party Party identifier
     * @return agreementIds Array of agreement IDs
     */
    function getPartyAgreements(
        bytes32 party
    ) public view returns (bytes32[] memory agreementIds) {
        return partyAgreements[party];
    }

    /**
     * @notice Check if agreement exists between parties
     * @param party1 First party
     * @param party2 Second party
     * @param agreementType Type of agreement to check
     * @return exists True if agreement exists
     * @return agreementId Agreement ID if exists
     */
    function hasAgreement(
        bytes32 party1,
        bytes32 party2,
        AgreementTypeEnum agreementType
    ) public view returns (bool exists, bytes32 agreementId) {
        bytes32 relationshipKey = _getRelationshipKey(party1, party2);
        PartyRelationship storage relationship = partyRelationships[relationshipKey];

        for (uint256 i = 0; i < relationship.agreementIds.length; i++) {
            bytes32 agmtId = relationship.agreementIds[i];
            MasterAgreement storage agreement = agreements[agmtId];

            if (agreement.agreementType == agreementType &&
                agreement.status == AgreementStatusEnum.ACTIVE) {
                return (true, agmtId);
            }
        }

        return (false, bytes32(0));
    }

    /**
     * @notice Get party relationship
     * @param party1 First party
     * @param party2 Second party
     * @return relationship Party relationship data
     */
    function getPartyRelationship(
        bytes32 party1,
        bytes32 party2
    ) public view returns (PartyRelationship memory relationship) {
        bytes32 relationshipKey = _getRelationshipKey(party1, party2);
        return partyRelationships[relationshipKey];
    }

    /**
     * @notice Get master agreement for a CSA
     * @param csaId CSA identifier
     * @return masterAgreementId Master agreement ID
     */
    function getMasterAgreementForCSA(
        bytes32 csaId
    ) public view returns (bytes32 masterAgreementId) {
        return csaToMasterAgreement[csaId];
    }

    /**
     * @notice Get all CSAs attached to a master agreement
     * @param masterAgreementId Master agreement identifier
     * @return csaIds Array of CSA IDs
     */
    function getAttachedCSAs(
        bytes32 masterAgreementId
    ) public view returns (bytes32[] memory csaIds) {
        if (!agreementExists[masterAgreementId]) {
            revert AgreementRegistry__AgreementDoesNotExist();
        }
        return agreements[masterAgreementId].attachedCSAs;
    }

    /**
     * @notice Check if agreement is active
     * @param agreementId Agreement identifier
     * @return active True if agreement is active
     */
    function isAgreementActive(
        bytes32 agreementId
    ) public view returns (bool active) {
        if (!agreementExists[agreementId]) {
            return false;
        }
        return agreements[agreementId].status == AgreementStatusEnum.ACTIVE;
    }

    /**
     * @notice Get agreement by document hash
     * @param documentHash Document hash
     * @return agreementId Agreement ID
     */
    function getAgreementByDocumentHash(
        bytes32 documentHash
    ) public view returns (bytes32 agreementId) {
        return documentHashToAgreement[documentHash];
    }

    /**
     * @notice Check if parties have active relationship
     * @param party1 First party
     * @param party2 Second party
     * @return hasActive True if active agreement exists
     */
    function hasActiveRelationship(
        bytes32 party1,
        bytes32 party2
    ) public view returns (bool hasActive) {
        bytes32 relationshipKey = _getRelationshipKey(party1, party2);
        return partyRelationships[relationshipKey].hasActiveAgreement;
    }
}
