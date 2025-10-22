// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Party, Identifier} from "../types/CDMTypes.sol";

/**
 * @title ICDMStaticData
 * @notice Interface for CDM static reference data registry
 * @dev External interface for interacting with CDMStaticData contract
 */
interface ICDMStaticData {
    // =============================================================================
    // EVENTS
    // =============================================================================

    event PartyRegistered(
        bytes32 indexed partyId,
        address indexed account,
        bytes32 nameHash,
        uint256 identifierCount
    );

    event PartyUpdated(
        bytes32 indexed partyId,
        address indexed newAccount,
        bytes32 newNameHash
    );

    event PartyDeactivated(bytes32 indexed partyId);

    event AssetRegistered(bytes32 indexed assetId, bytes32 identifierValue);

    event IndexRegistered(bytes32 indexed indexId, bytes32 identifierValue);

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
    // PARTY FUNCTIONS
    // =============================================================================

    function registerParty(Party memory party) external returns (bytes32);

    function updateParty(
        bytes32 partyId,
        address newAccount,
        bytes32 newNameHash
    ) external;

    function getParty(bytes32 partyId) external view returns (Party memory);

    function getPartyIdByAccount(address account) external view returns (bytes32);

    function getPartyIdByIdentifier(bytes32 identifierValue) external view returns (bytes32);

    function partyExists(bytes32 partyId) external view returns (bool);

    function getAllPartyIds() external view returns (bytes32[] memory);

    function getPartyCount() external view returns (uint256);

    // =============================================================================
    // ASSET FUNCTIONS
    // =============================================================================

    function registerAsset(bytes32 assetId, Identifier memory identifier) external;

    function getAsset(bytes32 assetId) external view returns (Identifier memory);

    function assetExists(bytes32 assetId) external view returns (bool);

    function getAllAssetIds() external view returns (bytes32[] memory);

    // =============================================================================
    // INDEX FUNCTIONS
    // =============================================================================

    function registerIndex(bytes32 indexId, Identifier memory identifier) external;

    function getIndex(bytes32 indexId) external view returns (Identifier memory);

    function indexExists(bytes32 indexId) external view returns (bool);

    function getAllIndexIds() external view returns (bytes32[] memory);

    // =============================================================================
    // ADMIN FUNCTIONS
    // =============================================================================

    function pause() external;

    function unpause() external;

    function version() external pure returns (string memory);
}
