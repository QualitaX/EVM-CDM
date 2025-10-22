// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CDMStaticData} from "../../../src/base/registry/CDMStaticData.sol";
import {CDMRoles} from "../../../src/base/access/CDMRoles.sol";
import {Party, PartyIdentifier, Identifier, CDMTypesLib} from "../../../src/base/types/CDMTypes.sol";
import {
    PartyTypeEnum,
    PartyRoleEnum,
    IdentifierTypeEnum
} from "../../../src/base/types/Enums.sol";

/**
 * @title CDMStaticDataTest
 * @notice Unit tests for CDMStaticData registry contract
 * @dev Tests party, asset, and index registration with UUPS proxy
 */
contract CDMStaticDataTest is Test {
    using CDMTypesLib for *;

    // =============================================================================
    // CONTRACTS
    // =============================================================================

    CDMStaticData public implementation;
    ERC1967Proxy public proxy;
    CDMStaticData public staticData;

    // =============================================================================
    // TEST ACCOUNTS
    // =============================================================================

    address public admin = makeAddr("admin");
    address public partyManager = makeAddr("partyManager");
    address public assetManager = makeAddr("assetManager");
    address public indexManager = makeAddr("indexManager");
    address public pauseGuardian = makeAddr("pauseGuardian");
    address public unauthorized = makeAddr("unauthorized");

    // =============================================================================
    // TEST DATA
    // =============================================================================

    bytes32 public constant PARTY_ID_1 = keccak256("PARTY_1");
    bytes32 public constant PARTY_ID_2 = keccak256("PARTY_2");
    address public partyAccount1 = makeAddr("partyAccount1");
    address public partyAccount2 = makeAddr("partyAccount2");

    bytes32 public constant ASSET_ID_1 = keccak256("ASSET_1");
    bytes32 public constant INDEX_ID_1 = keccak256("INDEX_1");

    // =============================================================================
    // SETUP
    // =============================================================================

    function setUp() public {
        // Deploy implementation
        implementation = new CDMStaticData();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            CDMStaticData.initialize.selector,
            admin
        );
        proxy = new ERC1967Proxy(address(implementation), initData);

        // Get proxy interface
        staticData = CDMStaticData(address(proxy));

        // Grant roles as admin
        vm.startPrank(admin);
        staticData.grantRole(CDMRoles.PARTY_MANAGER_ROLE, partyManager);
        staticData.grantRole(CDMRoles.ASSET_MANAGER_ROLE, assetManager);
        staticData.grantRole(CDMRoles.INDEX_MANAGER_ROLE, indexManager);
        staticData.grantRole(CDMRoles.PAUSE_GUARDIAN_ROLE, pauseGuardian);
        vm.stopPrank();
    }

    // =============================================================================
    // INITIALIZATION TESTS
    // =============================================================================

    function test_Initialize_Success() public view {
        assertEq(staticData.version(), "1.0.0", "Version should be 1.0.0");
        assertTrue(staticData.hasRole(CDMRoles.ADMIN_ROLE, admin), "Admin should have ADMIN_ROLE");
        assertTrue(
            staticData.hasRole(CDMRoles.PARTY_MANAGER_ROLE, partyManager),
            "Party manager should have PARTY_MANAGER_ROLE"
        );
    }

    function test_Initialize_CannotReinitialize() public {
        vm.expectRevert();
        staticData.initialize(admin);
    }

    // =============================================================================
    // PARTY REGISTRATION TESTS
    // =============================================================================

    function test_RegisterParty_Success() public {
        Party memory party = _createTestParty1();

        vm.prank(partyManager);
        bytes32 returnedPartyId = staticData.registerParty(party);

        assertEq(returnedPartyId, PARTY_ID_1, "Should return party ID");
        assertTrue(staticData.partyExists(PARTY_ID_1), "Party should exist");
        assertEq(staticData.getPartyCount(), 1, "Party count should be 1");
    }

    function test_RegisterParty_EmitsEvent() public {
        Party memory party = _createTestParty1();

        vm.prank(partyManager);
        vm.expectEmit(true, true, false, true);
        emit CDMStaticData.PartyRegistered(
            PARTY_ID_1,
            partyAccount1,
            party.nameHash,
            party.identifiers.length
        );

        staticData.registerParty(party);
    }

    function test_RegisterParty_RevertsIfUnauthorized() public {
        Party memory party = _createTestParty1();

        vm.prank(unauthorized);
        vm.expectRevert();
        staticData.registerParty(party);
    }

    function test_RegisterParty_RevertsIfDuplicate() public {
        Party memory party = _createTestParty1();

        vm.startPrank(partyManager);
        staticData.registerParty(party);

        vm.expectRevert(CDMStaticData.CDMStaticData__PartyAlreadyExists.selector);
        staticData.registerParty(party);
        vm.stopPrank();
    }

    function test_RegisterParty_RevertsIfAccountAlreadyRegistered() public {
        Party memory party1 = _createTestParty1();
        Party memory party2 = _createTestParty2();
        party2.account = partyAccount1; // Same account as party1

        vm.startPrank(partyManager);
        staticData.registerParty(party1);

        vm.expectRevert(CDMStaticData.CDMStaticData__AccountAlreadyRegistered.selector);
        staticData.registerParty(party2);
        vm.stopPrank();
    }

    function test_GetParty_Success() public {
        Party memory party = _createTestParty1();

        vm.prank(partyManager);
        staticData.registerParty(party);

        Party memory retrieved = staticData.getParty(PARTY_ID_1);
        assertEq(retrieved.partyId, party.partyId, "Party ID should match");
        assertEq(retrieved.account, party.account, "Account should match");
        assertEq(retrieved.nameHash, party.nameHash, "Name hash should match");
    }

    function test_GetParty_RevertsIfNotFound() public view {
        vm.expectRevert(CDMStaticData.CDMStaticData__PartyNotFound.selector);
        staticData.getParty(keccak256("NONEXISTENT"));
    }

    function test_GetPartyIdByAccount_Success() public {
        Party memory party = _createTestParty1();

        vm.prank(partyManager);
        staticData.registerParty(party);

        bytes32 partyId = staticData.getPartyIdByAccount(partyAccount1);
        assertEq(partyId, PARTY_ID_1, "Should return correct party ID");
    }

    function test_GetPartyIdByAccount_ReturnsZeroIfNotFound() public view {
        bytes32 partyId = staticData.getPartyIdByAccount(makeAddr("nonexistent"));
        assertEq(partyId, bytes32(0), "Should return zero for nonexistent account");
    }

    function test_UpdateParty_Success() public {
        Party memory party = _createTestParty1();

        vm.startPrank(partyManager);
        staticData.registerParty(party);

        address newAccount = makeAddr("newAccount");
        bytes32 newNameHash = keccak256("New Party Name");

        vm.expectEmit(true, true, false, true);
        emit CDMStaticData.PartyUpdated(PARTY_ID_1, newAccount, newNameHash);

        staticData.updateParty(PARTY_ID_1, newAccount, newNameHash);
        vm.stopPrank();

        Party memory updated = staticData.getParty(PARTY_ID_1);
        assertEq(updated.account, newAccount, "Account should be updated");
        assertEq(updated.nameHash, newNameHash, "Name hash should be updated");
    }

    // =============================================================================
    // ASSET REGISTRATION TESTS
    // =============================================================================

    function test_RegisterAsset_Success() public {
        Identifier memory identifier = Identifier({
            value: keccak256("US0378331005"), // Apple Inc ISIN
            idType: IdentifierTypeEnum.ISIN
        });

        vm.prank(assetManager);
        staticData.registerAsset(ASSET_ID_1, identifier);

        assertTrue(staticData.assetExists(ASSET_ID_1), "Asset should exist");
        assertEq(staticData.getAllAssetIds().length, 1, "Should have 1 asset");
    }

    function test_RegisterAsset_EmitsEvent() public {
        Identifier memory identifier = Identifier({
            value: keccak256("US0378331005"),
            idType: IdentifierTypeEnum.ISIN
        });

        vm.prank(assetManager);
        vm.expectEmit(true, false, false, true);
        emit CDMStaticData.AssetRegistered(ASSET_ID_1, identifier.value);

        staticData.registerAsset(ASSET_ID_1, identifier);
    }

    function test_RegisterAsset_RevertsIfUnauthorized() public {
        Identifier memory identifier = Identifier({
            value: keccak256("US0378331005"),
            idType: IdentifierTypeEnum.ISIN
        });

        vm.prank(unauthorized);
        vm.expectRevert();
        staticData.registerAsset(ASSET_ID_1, identifier);
    }

    function test_RegisterAsset_RevertsIfDuplicate() public {
        Identifier memory identifier = Identifier({
            value: keccak256("US0378331005"),
            idType: IdentifierTypeEnum.ISIN
        });

        vm.startPrank(assetManager);
        staticData.registerAsset(ASSET_ID_1, identifier);

        vm.expectRevert(CDMStaticData.CDMStaticData__AssetAlreadyExists.selector);
        staticData.registerAsset(ASSET_ID_1, identifier);
        vm.stopPrank();
    }

    function test_GetAsset_Success() public {
        Identifier memory identifier = Identifier({
            value: keccak256("US0378331005"),
            idType: IdentifierTypeEnum.ISIN
        });

        vm.prank(assetManager);
        staticData.registerAsset(ASSET_ID_1, identifier);

        Identifier memory retrieved = staticData.getAsset(ASSET_ID_1);
        assertEq(retrieved.value, identifier.value, "Identifier value should match");
        assertEq(uint256(retrieved.idType), uint256(identifier.idType), "Identifier type should match");
    }

    // =============================================================================
    // INDEX REGISTRATION TESTS
    // =============================================================================

    function test_RegisterIndex_Success() public {
        Identifier memory identifier = Identifier({
            value: keccak256("USD-SOFR"),
            idType: IdentifierTypeEnum.RIC
        });

        vm.prank(indexManager);
        staticData.registerIndex(INDEX_ID_1, identifier);

        assertTrue(staticData.indexExists(INDEX_ID_1), "Index should exist");
        assertEq(staticData.getAllIndexIds().length, 1, "Should have 1 index");
    }

    function test_RegisterIndex_EmitsEvent() public {
        Identifier memory identifier = Identifier({
            value: keccak256("USD-SOFR"),
            idType: IdentifierTypeEnum.RIC
        });

        vm.prank(indexManager);
        vm.expectEmit(true, false, false, true);
        emit CDMStaticData.IndexRegistered(INDEX_ID_1, identifier.value);

        staticData.registerIndex(INDEX_ID_1, identifier);
    }

    // =============================================================================
    // PAUSABLE TESTS
    // =============================================================================

    function test_Pause_Success() public {
        vm.prank(pauseGuardian);
        staticData.pause();

        // Try to register party while paused
        Party memory party = _createTestParty1();
        vm.prank(partyManager);
        vm.expectRevert();
        staticData.registerParty(party);
    }

    function test_Unpause_Success() public {
        vm.prank(pauseGuardian);
        staticData.pause();

        vm.prank(admin);
        staticData.unpause();

        // Should be able to register now
        Party memory party = _createTestParty1();
        vm.prank(partyManager);
        staticData.registerParty(party);

        assertTrue(staticData.partyExists(PARTY_ID_1), "Party should exist after unpause");
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _createTestParty1() internal view returns (Party memory) {
        PartyIdentifier[] memory identifiers = new PartyIdentifier[](1);
        identifiers[0] = PartyIdentifier({
            identifier: Identifier({
                value: keccak256("5493001KJTIIGC8Y1R12"), // Sample LEI
                idType: IdentifierTypeEnum.LEI
            }),
            meta: bytes32(0)
        });

        return Party({
            partyId: PARTY_ID_1,
            account: partyAccount1,
            partyType: PartyTypeEnum.LEGAL_ENTITY,
            nameHash: keccak256("Test Party 1"),
            metaKey: bytes32(0),
            identifiers: identifiers
        });
    }

    function _createTestParty2() internal view returns (Party memory) {
        PartyIdentifier[] memory identifiers = new PartyIdentifier[](1);
        identifiers[0] = PartyIdentifier({
            identifier: Identifier({
                value: keccak256("549300ABCDEFGHIJKLMN"), // Different LEI
                idType: IdentifierTypeEnum.LEI
            }),
            meta: bytes32(0)
        });

        return Party({
            partyId: PARTY_ID_2,
            account: partyAccount2,
            partyType: PartyTypeEnum.LEGAL_ENTITY,
            nameHash: keccak256("Test Party 2"),
            metaKey: bytes32(0),
            identifiers: identifiers
        });
    }
}
