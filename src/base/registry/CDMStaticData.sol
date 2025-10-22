// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {Party, PartyIdentifier, Identifier} from "../types/CDMTypes.sol";
import {CDMRoles} from "../access/CDMRoles.sol";
import {CDMValidation} from "../libraries/CDMValidation.sol";

/**
 * @title CDMStaticData
 * @notice Static reference data registry for FINOS CDM EVM Framework
 * @dev UUPS upgradeable contract for managing parties, assets, and other reference data
 *
 * FEATURES:
 * - Party registration and management
 * - Asset identifier registration
 * - Index registration
 * - Reverse lookups (address → partyId, identifier → partyId)
 * - Role-based access control
 * - Pausable for emergency scenarios
 * - Upgradeable via UUPS pattern
 *
 * ARCHITECTURE:
 * - Uses UUPS proxy pattern for upgradeability
 * - Implements AccessControl for role management
 * - Emits events for all state changes
 * - Optimized storage layout for gas efficiency
 *
 * @custom:security-contact security@finos.org
 * @author FINOS CDM EVM Framework Team
 */
contract CDMStaticData is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    using CDMValidation for Party;
    using CDMValidation for PartyIdentifier;
    using CDMValidation for Identifier;

    // =============================================================================
    // VERSION
    // =============================================================================

    /// @notice Contract version for upgrade tracking
    string public constant VERSION = "1.0.0";

    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    // --- Party Registry ---

    /// @notice Main party storage: partyId => Party
    mapping(bytes32 => Party) private _parties;

    /// @notice Reverse lookup: account => partyId
    mapping(address => bytes32) private _accountToPartyId;

    /// @notice Reverse lookup: identifier value => partyId
    mapping(bytes32 => bytes32) private _identifierToPartyId;

    /// @notice Track all registered party IDs
    bytes32[] private _allPartyIds;

    /// @notice Check if partyId exists
    mapping(bytes32 => bool) private _partyExists;

    // --- Asset Registry ---

    /// @notice Asset identifiers: assetId => Identifier
    mapping(bytes32 => Identifier) private _assets;

    /// @notice Track all registered asset IDs
    bytes32[] private _allAssetIds;

    /// @notice Check if assetId exists
    mapping(bytes32 => bool) private _assetExists;

    // --- Index Registry ---

    /// @notice Index identifiers: indexId => Identifier
    mapping(bytes32 => Identifier) private _indices;

    /// @notice Track all registered index IDs
    bytes32[] private _allIndexIds;

    /// @notice Check if indexId exists
    mapping(bytes32 => bool) private _indexExists;

    // =============================================================================
    // EVENTS
    // =============================================================================

    /// @notice Emitted when a party is registered
    event PartyRegistered(
        bytes32 indexed partyId,
        address indexed account,
        bytes32 nameHash,
        uint256 identifierCount
    );

    /// @notice Emitted when a party is updated
    event PartyUpdated(
        bytes32 indexed partyId,
        address indexed newAccount,
        bytes32 newNameHash
    );

    /// @notice Emitted when a party is deactivated
    event PartyDeactivated(bytes32 indexed partyId);

    /// @notice Emitted when an asset is registered
    event AssetRegistered(
        bytes32 indexed assetId,
        bytes32 identifierValue
    );

    /// @notice Emitted when an index is registered
    event IndexRegistered(
        bytes32 indexed indexId,
        bytes32 identifierValue
    );

    // =============================================================================
    // ERRORS
    // =============================================================================

    error CDMStaticData__PartyAlreadyExists();
    error CDMStaticData__PartyNotFound();
    error CDMStaticData__AccountAlreadyRegistered();
    error CDMStaticData__IdentifierAlreadyRegistered();
    error CDMStaticData__AssetAlreadyExists();
    error CDMStaticData__AssetNotFound();
    error CDMStaticData__IndexAlreadyExists();
    error CDMStaticData__IndexNotFound();
    error CDMStaticData__InvalidPartyId();
    error CDMStaticData__Unauthorized();

    // =============================================================================
    // INITIALIZATION
    // =============================================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @dev Called once during deployment by proxy
     * @param admin Address to be granted ADMIN_ROLE
     */
    function initialize(address admin) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();

        // Grant admin all roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CDMRoles.ADMIN_ROLE, admin);
        _grantRole(CDMRoles.GOVERNANCE_ROLE, admin);
        _grantRole(CDMRoles.UPGRADER_ROLE, admin);
    }

    // =============================================================================
    // PARTY REGISTRATION
    // =============================================================================

    /**
     * @notice Register a new party
     * @dev Only PARTY_MANAGER_ROLE can register parties
     * @param party Party data to register
     * @return partyId The registered party ID
     */
    function registerParty(Party memory party)
        external
        whenNotPaused
        onlyRole(CDMRoles.PARTY_MANAGER_ROLE)
        returns (bytes32)
    {
        // Validate party data
        CDMValidation.validateParty(party);

        // Check party doesn't already exist
        if (_partyExists[party.partyId]) {
            revert CDMStaticData__PartyAlreadyExists();
        }

        // Check account not already registered
        if (party.account != address(0)) {
            if (_accountToPartyId[party.account] != bytes32(0)) {
                revert CDMStaticData__AccountAlreadyRegistered();
            }
        }

        // Check identifiers not already registered
        for (uint256 i = 0; i < party.identifiers.length; i++) {
            bytes32 idValue = party.identifiers[i].identifier.value;
            if (_identifierToPartyId[idValue] != bytes32(0)) {
                revert CDMStaticData__IdentifierAlreadyRegistered();
            }
        }

        // Store party (manual copy due to dynamic array)
        Party storage storedParty = _parties[party.partyId];
        storedParty.partyId = party.partyId;
        storedParty.account = party.account;
        storedParty.partyType = party.partyType;
        storedParty.nameHash = party.nameHash;
        storedParty.metaKey = party.metaKey;

        // Copy identifiers array
        for (uint256 i = 0; i < party.identifiers.length; i++) {
            storedParty.identifiers.push(party.identifiers[i]);
        }

        _partyExists[party.partyId] = true;
        _allPartyIds.push(party.partyId);

        // Store reverse lookups
        if (party.account != address(0)) {
            _accountToPartyId[party.account] = party.partyId;
        }

        for (uint256 i = 0; i < party.identifiers.length; i++) {
            bytes32 idValue = party.identifiers[i].identifier.value;
            _identifierToPartyId[idValue] = party.partyId;
        }

        emit PartyRegistered(
            party.partyId,
            party.account,
            party.nameHash,
            party.identifiers.length
        );

        return party.partyId;
    }

    /**
     * @notice Update an existing party
     * @dev Can update account and nameHash, but not identifiers
     * @param partyId Party ID to update
     * @param newAccount New account address (address(0) to keep current)
     * @param newNameHash New name hash (bytes32(0) to keep current)
     */
    function updateParty(
        bytes32 partyId,
        address newAccount,
        bytes32 newNameHash
    )
        external
        whenNotPaused
        onlyRole(CDMRoles.PARTY_MANAGER_ROLE)
    {
        if (!_partyExists[partyId]) {
            revert CDMStaticData__PartyNotFound();
        }

        Party storage party = _parties[partyId];

        // Update account if provided
        if (newAccount != address(0) && newAccount != party.account) {
            // Check new account not already registered
            if (_accountToPartyId[newAccount] != bytes32(0)) {
                revert CDMStaticData__AccountAlreadyRegistered();
            }

            // Remove old account mapping
            if (party.account != address(0)) {
                delete _accountToPartyId[party.account];
            }

            // Set new account
            party.account = newAccount;
            _accountToPartyId[newAccount] = partyId;
        }

        // Update name hash if provided
        if (newNameHash != bytes32(0)) {
            party.nameHash = newNameHash;
        }

        emit PartyUpdated(partyId, newAccount, newNameHash);
    }

    /**
     * @notice Get party by ID
     * @param partyId Party ID to lookup
     * @return Party data
     */
    function getParty(bytes32 partyId) external view returns (Party memory) {
        if (!_partyExists[partyId]) {
            revert CDMStaticData__PartyNotFound();
        }
        return _parties[partyId];
    }

    /**
     * @notice Get party ID by account address
     * @param account Account address to lookup
     * @return partyId Associated party ID (bytes32(0) if not found)
     */
    function getPartyIdByAccount(address account) external view returns (bytes32) {
        return _accountToPartyId[account];
    }

    /**
     * @notice Get party ID by identifier
     * @param identifierValue Identifier value to lookup
     * @return partyId Associated party ID (bytes32(0) if not found)
     */
    function getPartyIdByIdentifier(bytes32 identifierValue) external view returns (bytes32) {
        return _identifierToPartyId[identifierValue];
    }

    /**
     * @notice Check if party exists
     * @param partyId Party ID to check
     * @return true if party exists
     */
    function partyExists(bytes32 partyId) external view returns (bool) {
        return _partyExists[partyId];
    }

    /**
     * @notice Get all registered party IDs
     * @return Array of all party IDs
     */
    function getAllPartyIds() external view returns (bytes32[] memory) {
        return _allPartyIds;
    }

    /**
     * @notice Get total number of registered parties
     * @return Count of registered parties
     */
    function getPartyCount() external view returns (uint256) {
        return _allPartyIds.length;
    }

    // =============================================================================
    // ASSET REGISTRATION
    // =============================================================================

    /**
     * @notice Register a new asset
     * @dev Only ASSET_MANAGER_ROLE can register assets
     * @param assetId Asset ID (hash of identifier)
     * @param identifier Asset identifier (ISIN, CUSIP, etc.)
     */
    function registerAsset(bytes32 assetId, Identifier memory identifier)
        external
        whenNotPaused
        onlyRole(CDMRoles.ASSET_MANAGER_ROLE)
    {
        CDMValidation.validateIdentifier(identifier);

        if (_assetExists[assetId]) {
            revert CDMStaticData__AssetAlreadyExists();
        }

        _assets[assetId] = identifier;
        _assetExists[assetId] = true;
        _allAssetIds.push(assetId);

        emit AssetRegistered(assetId, identifier.value);
    }

    /**
     * @notice Get asset identifier
     * @param assetId Asset ID to lookup
     * @return Asset identifier
     */
    function getAsset(bytes32 assetId) external view returns (Identifier memory) {
        if (!_assetExists[assetId]) {
            revert CDMStaticData__AssetNotFound();
        }
        return _assets[assetId];
    }

    /**
     * @notice Check if asset exists
     * @param assetId Asset ID to check
     * @return true if asset exists
     */
    function assetExists(bytes32 assetId) external view returns (bool) {
        return _assetExists[assetId];
    }

    /**
     * @notice Get all registered asset IDs
     * @return Array of all asset IDs
     */
    function getAllAssetIds() external view returns (bytes32[] memory) {
        return _allAssetIds;
    }

    // =============================================================================
    // INDEX REGISTRATION
    // =============================================================================

    /**
     * @notice Register a new index
     * @dev Only INDEX_MANAGER_ROLE can register indices
     * @param indexId Index ID (hash of identifier)
     * @param identifier Index identifier (e.g., USD-SOFR, EUR-ESTR)
     */
    function registerIndex(bytes32 indexId, Identifier memory identifier)
        external
        whenNotPaused
        onlyRole(CDMRoles.INDEX_MANAGER_ROLE)
    {
        CDMValidation.validateIdentifier(identifier);

        if (_indexExists[indexId]) {
            revert CDMStaticData__IndexAlreadyExists();
        }

        _indices[indexId] = identifier;
        _indexExists[indexId] = true;
        _allIndexIds.push(indexId);

        emit IndexRegistered(indexId, identifier.value);
    }

    /**
     * @notice Get index identifier
     * @param indexId Index ID to lookup
     * @return Index identifier
     */
    function getIndex(bytes32 indexId) external view returns (Identifier memory) {
        if (!_indexExists[indexId]) {
            revert CDMStaticData__IndexNotFound();
        }
        return _indices[indexId];
    }

    /**
     * @notice Check if index exists
     * @param indexId Index ID to check
     * @return true if index exists
     */
    function indexExists(bytes32 indexId) external view returns (bool) {
        return _indexExists[indexId];
    }

    /**
     * @notice Get all registered index IDs
     * @return Array of all index IDs
     */
    function getAllIndexIds() external view returns (bytes32[] memory) {
        return _allIndexIds;
    }

    // =============================================================================
    // PAUSABLE
    // =============================================================================

    /**
     * @notice Pause contract (emergency use only)
     * @dev Only PAUSE_GUARDIAN_ROLE can pause
     */
    function pause() external onlyRole(CDMRoles.PAUSE_GUARDIAN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract
     * @dev Only ADMIN_ROLE can unpause
     */
    function unpause() external onlyRole(CDMRoles.ADMIN_ROLE) {
        _unpause();
    }

    // =============================================================================
    // UPGRADE AUTHORIZATION
    // =============================================================================

    /**
     * @notice Authorize upgrade to new implementation
     * @dev Only UPGRADER_ROLE can upgrade
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(CDMRoles.UPGRADER_ROLE)
    {
        // Additional upgrade validation could go here
    }

    // =============================================================================
    // VIEW FUNCTIONS
    // =============================================================================

    /**
     * @notice Get contract version
     * @return Version string
     */
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
