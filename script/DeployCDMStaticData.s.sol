// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {CDMStaticData} from "../src/base/registry/CDMStaticData.sol";
import {CDMRoles} from "../src/base/access/CDMRoles.sol";

/**
 * @title DeployCDMStaticData
 * @notice Deployment script for CDMStaticData with UUPS proxy
 * @dev Deploys implementation and proxy, initializes with admin roles
 *
 * USAGE:
 *   # Deploy to local testnet
 *   forge script script/DeployCDMStaticData.s.sol:DeployCDMStaticData --rpc-url http://localhost:8545 --broadcast
 *
 *   # Deploy to testnet (e.g., Sepolia)
 *   forge script script/DeployCDMStaticData.s.sol:DeployCDMStaticData \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY
 *
 *   # Deploy to mainnet
 *   forge script script/DeployCDMStaticData.s.sol:DeployCDMStaticData \
 *     --rpc-url $MAINNET_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $ETHERSCAN_API_KEY
 */
contract DeployCDMStaticData is Script {
    // =============================================================================
    // STATE VARIABLES
    // =============================================================================

    CDMStaticData public implementation;
    ERC1967Proxy public proxy;
    CDMStaticData public staticData;

    address public admin;
    address public partyManager;
    address public assetManager;
    address public indexManager;
    address public pauseGuardian;

    // =============================================================================
    // MAIN DEPLOYMENT
    // =============================================================================

    function run() external {
        // Get deployment configuration from environment or use defaults
        admin = vm.envOr("ADMIN_ADDRESS", msg.sender);
        partyManager = vm.envOr("PARTY_MANAGER_ADDRESS", msg.sender);
        assetManager = vm.envOr("ASSET_MANAGER_ADDRESS", msg.sender);
        indexManager = vm.envOr("INDEX_MANAGER_ADDRESS", msg.sender);
        pauseGuardian = vm.envOr("PAUSE_GUARDIAN_ADDRESS", msg.sender);

        console2.log("========================================");
        console2.log("Deploying CDMStaticData with UUPS Proxy");
        console2.log("========================================");
        console2.log("Deployer:", msg.sender);
        console2.log("Admin:", admin);
        console2.log("Party Manager:", partyManager);
        console2.log("Asset Manager:", assetManager);
        console2.log("Index Manager:", indexManager);
        console2.log("Pause Guardian:", pauseGuardian);
        console2.log("");

        vm.startBroadcast();

        // 1. Deploy implementation
        implementation = new CDMStaticData();
        console2.log("Implementation deployed at:", address(implementation));

        // 2. Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            CDMStaticData.initialize.selector,
            admin
        );

        // 3. Deploy proxy
        proxy = new ERC1967Proxy(address(implementation), initData);
        console2.log("Proxy deployed at:", address(proxy));

        // 4. Get proxy interface
        staticData = CDMStaticData(address(proxy));
        console2.log("CDMStaticData ready at:", address(staticData));
        console2.log("Version:", staticData.version());

        // 5. Grant operational roles (if admin is deployer)
        if (admin == msg.sender) {
            console2.log("");
            console2.log("Granting operational roles...");

            if (partyManager != admin) {
                staticData.grantRole(CDMRoles.PARTY_MANAGER_ROLE, partyManager);
                console2.log("- PARTY_MANAGER_ROLE granted to:", partyManager);
            }

            if (assetManager != admin) {
                staticData.grantRole(CDMRoles.ASSET_MANAGER_ROLE, assetManager);
                console2.log("- ASSET_MANAGER_ROLE granted to:", assetManager);
            }

            if (indexManager != admin) {
                staticData.grantRole(CDMRoles.INDEX_MANAGER_ROLE, indexManager);
                console2.log("- INDEX_MANAGER_ROLE granted to:", indexManager);
            }

            if (pauseGuardian != admin) {
                staticData.grantRole(CDMRoles.PAUSE_GUARDIAN_ROLE, pauseGuardian);
                console2.log("- PAUSE_GUARDIAN_ROLE granted to:", pauseGuardian);
            }
        }

        vm.stopBroadcast();

        console2.log("");
        console2.log("========================================");
        console2.log("Deployment Complete!");
        console2.log("========================================");
        console2.log("Save these addresses:");
        console2.log("- Implementation:", address(implementation));
        console2.log("- Proxy:", address(proxy));
        console2.log("- Use Proxy address for interactions");
        console2.log("");
    }

    // =============================================================================
    // UPGRADE HELPERS
    // =============================================================================

    /**
     * @notice Deploy new implementation for upgrade
     * @dev Call this when you want to upgrade to a new version
     */
    function deployNewImplementation() external {
        console2.log("Deploying new implementation...");

        vm.startBroadcast();

        CDMStaticData newImplementation = new CDMStaticData();
        console2.log("New implementation deployed at:", address(newImplementation));

        vm.stopBroadcast();

        console2.log("");
        console2.log("To upgrade, call upgradeToAndCall on the proxy:");
        console2.log("  CDMStaticData(proxy).upgradeToAndCall(", address(newImplementation), ", \"\")");
    }
}
