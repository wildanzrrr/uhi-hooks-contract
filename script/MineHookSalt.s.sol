// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";
import {StreamFund} from "../src/StreamFund.sol";

/// @notice Mines a salt for the StreamFund hook
contract MineHookSalt is Script {
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    function run() public view {
        address poolManager = vm.envAddress("POOL_MANAGER");
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        console.log("Mining salt for StreamFund hook...");
        console.log("PoolManager:", poolManager);
        console.log("Flags:", flags);

        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(StreamFund).creationCode, constructorArgs);

        console.log("Found hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));
        console.log("\nAdd this to your .env:");
        console.log("HOOK_SALT=", vm.toString(salt));
    }
}
