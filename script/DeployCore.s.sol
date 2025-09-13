// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {PoolDonateTest} from "v4-core/test/PoolDonateTest.sol";

/// @notice Deploys PoolManager and router contracts
contract DeployCore is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address OWNER = vm.envAddress("ADMIN_ADDRESS");

        // Deploy PoolManager
        PoolManager manager = new PoolManager(OWNER);
        console.log("PoolManager deployed at:", address(manager));

        // Deploy Router contracts
        PoolModifyLiquidityTest modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        console.log("ModifyLiquidityRouter deployed at:", address(modifyLiquidityRouter));

        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        console.log("SwapRouter deployed at:", address(swapRouter));

        PoolDonateTest donateRouter = new PoolDonateTest(manager);
        console.log("DonateRouter deployed at:", address(donateRouter));

        console.log("\n=== Add these to your .env file ===");
        console.log("POOL_MANAGER=", address(manager));
        console.log("MODIFY_LIQUIDITY_ROUTER=", address(modifyLiquidityRouter));
        console.log("SWAP_ROUTER=", address(swapRouter));
        console.log("DONATE_ROUTER=", address(donateRouter));

        vm.stopBroadcast();
    }
}
