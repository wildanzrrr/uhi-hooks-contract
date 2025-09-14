// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {StreamFund} from "../src/StreamFund.sol";

/// @notice Mines the address and deploys the StreamFund.sol Hook contract
contract DeployStreamFund is Script {
    // Constants
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() public {
        vm.startBroadcast();

        // Get addresses from environment variables
        address poolManager = vm.envAddress("POOL_MANAGER");
        bytes32 salt = vm.envBytes32("HOOK_SALT");

        console.log("Using PoolManager at:", poolManager);
        console.log("Using pre-mined salt:", vm.toString(salt));

        // Deploy the hook using the pre-mined salt
        StreamFund hook = new StreamFund{salt: salt}(IPoolManager(poolManager));

        console.log("StreamFund hook deployed at:", address(hook));

        console.log("\n=== Add these to your .env file ===");
        console.log("STREAMFUND_HOOK=", address(hook));

        vm.stopBroadcast();
    }
}
