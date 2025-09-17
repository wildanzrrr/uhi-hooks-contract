// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "v4-core/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolId.sol";
import {ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {StreamFund} from "../src/StreamFund.sol";

/// @notice Deploys MockERC20 token and sets up pool with initial liquidity
contract InitPool is Script {
    // Pool configuration constants (matching your test setup)
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // sqrt(1) * 2^96
    int24 constant TICK_SPACING = 60;
    uint24 constant POOL_FEE = 3000; // 0.3%

    // Liquidity parameters
    uint256 constant TOKEN_SUPPLY = 999_000_000e18; // 999 tokens
    uint256 constant TOKEN_REWARD = 1_000_000e18; // 1M tokens
    uint256 constant ETH_LIQUIDITY = 10 ether; // 10 ETH
    int24 constant TICK_LOWER = -60;
    int24 constant TICK_UPPER = 60;

    function run() public {
        vm.startBroadcast();

        // Get deployed contract addresses from environment
        address poolManagerAddr = vm.envAddress("POOL_MANAGER");
        address modifyLiquidityRouterAddr = vm.envAddress("MODIFY_LIQUIDITY_ROUTER");
        address streamFundAddr = vm.envAddress("STREAMFUND_HOOK");

        console.log("Using PoolManager at:", poolManagerAddr);
        console.log("Using StreamFund hook at:", streamFundAddr);

        // Cast to contract instances
        PoolManager manager = PoolManager(poolManagerAddr);
        PoolModifyLiquidityTest modifyLiquidityRouter = PoolModifyLiquidityTest(modifyLiquidityRouterAddr);
        StreamFund hook = StreamFund(streamFundAddr);

        // Deploy Mock Token
        MockERC20 token = new MockERC20("StreamFund Token", "SFT", 18);
        console.log("MockERC20 token deployed at:", address(token));

        // Mint tokens to deployer
        token.mint(msg.sender, TOKEN_SUPPLY);
        token.mint(streamFundAddr, TOKEN_REWARD);
        console.log("Minted", TOKEN_SUPPLY / 1e18, "tokens to deployer");

        // Set up currencies (following your test pattern)
        Currency ethCurrency = Currency.wrap(address(0)); // Native ETH
        Currency tokenCurrency = Currency.wrap(address(token));

        // Create pool key with proper currency ordering
        PoolKey memory poolKey = PoolKey({
            currency0: ethCurrency < tokenCurrency ? ethCurrency : tokenCurrency,
            currency1: ethCurrency < tokenCurrency ? tokenCurrency : ethCurrency,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: hook
        });

        console.log("Pool currencies:");
        console.log("  Currency0:", Currency.unwrap(poolKey.currency0));
        console.log("  Currency1:", Currency.unwrap(poolKey.currency1));

        // Initialize the pool
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        console.log("Pool initialized with 1:1 price ratio");

        // Approve token for liquidity operations
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        console.log("Token approved for ModifyLiquidityRouter");

        // Calculate liquidity delta (following your test setup)
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(TICK_UPPER);
        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, ETH_LIQUIDITY);

        console.log("Calculated liquidity delta:", liquidityDelta);

        // Add liquidity to the pool
        modifyLiquidityRouter.modifyLiquidity{value: ETH_LIQUIDITY}(
            poolKey,
            ModifyLiquidityParams({
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ""
        );

        console.log("Liquidity added successfully!");
        console.log("  ETH amount:", ETH_LIQUIDITY);

        // Setup token reward with 100 tokens per point
        hook.setupReward(address(token), 100e18);

        // Log deployment summary
        console.log("\n=== Pool Deployment Summary ===");
        console.log("Token Address:", address(token));
        console.log("Pool Key Hash:", uint256(keccak256(abi.encode(poolKey))));
        console.log("Initial Liquidity Added: 10 ETH + tokens in range [-60, 60]");

        console.log("\n=== Add to your .env file ===");
        console.log("MOCK_TOKEN=", address(token));
        console.log("POOL_CURRENCY0=", Currency.unwrap(poolKey.currency0));
        console.log("POOL_CURRENCY1=", Currency.unwrap(poolKey.currency1));

        vm.stopBroadcast();
    }
}
