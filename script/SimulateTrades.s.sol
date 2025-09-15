// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {PoolKey} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {StreamFund} from "../src/StreamFund.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract SimulateTrades is Script {
    // Environment variables
    address POOL_MANAGER = vm.envAddress("POOL_MANAGER");
    address SWAP_ROUTER = vm.envAddress("SWAP_ROUTER");
    address STREAMFUND_HOOK = vm.envAddress("STREAMFUND_HOOK");
    address MOCK_TOKEN = vm.envAddress("MOCK_TOKEN");
    address POOL_CURRENCY0 = vm.envAddress("POOL_CURRENCY0");
    address POOL_CURRENCY1 = vm.envAddress("POOL_CURRENCY1");

    // Trading parameters
    uint256 constant TRADE_AMOUNT = 0.5 ether; // 0.1 ETH per trade
    uint256 constant NUM_ROUNDS = 3;

    // Get addresses from private keys
    uint256 TRADER_PK = vm.envUint("TRADER_PK");
    uint256 STREAMER_PK = vm.envUint("STREAMER_PK");
    address TRADER = vm.addr(TRADER_PK);
    address STREAMER = vm.addr(STREAMER_PK);

    PoolSwapTest swapRouter;
    StreamFund hook;
    IERC20 token;
    PoolKey poolKey;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Initialize contracts
        swapRouter = PoolSwapTest(SWAP_ROUTER);
        hook = StreamFund(STREAMFUND_HOOK);
        token = IERC20(MOCK_TOKEN);

        // Setup pool key
        poolKey = PoolKey({
            currency0: Currency.wrap(POOL_CURRENCY0),
            currency1: Currency.wrap(POOL_CURRENCY1),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });

        console.log("=== StreamFund Trading Simulation ===");
        console.log("Pool Manager:", POOL_MANAGER);
        console.log("Swap Router:", SWAP_ROUTER);
        console.log("StreamFund Hook:", STREAMFUND_HOOK);
        console.log("Mock Token:", MOCK_TOKEN);
        console.log("Trader Address:", TRADER);
        console.log("Streamer Address:", STREAMER);
        console.log("");

        // Setup accounts
        setupAccounts();

        // Register streamer
        registerStreamer();

        // Perform trading rounds
        for (uint256 i = 1; i <= NUM_ROUNDS; i++) {
            console.log("=== Trading Round", i, "===");
            performTradingRound(i);
            console.log("");
        }

        // Show final results
        showFinalResults();

        vm.stopBroadcast();
    }

    function setupAccounts() internal view {
        console.log("Setting up accounts...");
        console.log("Trader ETH balance:", TRADER.balance / 1e18, "ETH");
        console.log("Streamer ETH balance:", STREAMER.balance / 1e18, "ETH");
        console.log("Trader setup complete");
    }

    function registerStreamer() internal {
        console.log("Registering streamer...");

        // Switch to streamer account
        vm.stopBroadcast();
        vm.startBroadcast(STREAMER_PK);

        if (!hook.isRegistered(STREAMER)) {
            hook.registerStreamer();
            console.log("Streamer registered successfully");
        } else {
            console.log("Streamer already registered");
        }

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
    }

    function performTradingRound(uint256 roundNumber) internal {
        bytes memory hookData = abi.encode(STREAMER);

        // Log initial state
        logInitialState();

        // Perform buy operation
        performBuyOperation(hookData);

        // Perform sell operation
        performSellOperation(hookData);

        // Log round summary
        logRoundSummary(roundNumber);
    }

    function logInitialState() internal view {
        uint256 points = hook.getStreamerPoints(STREAMER);
        StreamFund.Streamer memory info = hook.getStreamerInfo(STREAMER);

        console.log("Initial state:");
        console.log("  Streamer points:", points / 1e18);
        console.log("  Streamer referral volume:", info.referralVolume / 1e18, "ETH");
        console.log("  Trader ETH:", TRADER.balance / 1e18);
        console.log("  Trader tokens:", token.balanceOf(TRADER) / 1e18);
    }

    function performBuyOperation(bytes memory hookData) internal {
        console.log("Performing BUY operation...");

        vm.stopBroadcast();
        vm.startBroadcast(TRADER_PK);

        swapRouter.swap{value: TRADE_AMOUNT}(
            poolKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(TRADE_AMOUNT),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Log state after buy
        uint256 points = hook.getStreamerPoints(STREAMER);
        StreamFund.Streamer memory info = hook.getStreamerInfo(STREAMER);

        console.log("After BUY:");
        console.log("  Streamer points:", points / 1e18);
        console.log("  Streamer referral volume:", info.referralVolume / 1e18, "ETH");
        console.log("  Trader tokens:", token.balanceOf(TRADER) / 1e18);
    }

    function performSellOperation(bytes memory hookData) internal {
        uint256 tokensToSell = token.balanceOf(TRADER);

        console.log("Performing SELL operation...");
        console.log("  Selling", tokensToSell / 1e18, "tokens");

        vm.stopBroadcast();
        vm.startBroadcast(TRADER_PK);

        // Approve tokens for swap
        token.approve(SWAP_ROUTER, tokensToSell);

        swapRouter.swap(
            poolKey,
            SwapParams({
                zeroForOne: false,
                amountSpecified: -int256(tokensToSell),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Log state after sell
        uint256 points = hook.getStreamerPoints(STREAMER);
        StreamFund.Streamer memory info = hook.getStreamerInfo(STREAMER);

        console.log("After SELL:");
        console.log("  Streamer points:", points / 1e18);
        console.log("  Streamer referral volume:", info.referralVolume / 1e18, "ETH");
        console.log("  Trader ETH:", TRADER.balance / 1e18);
        console.log("  Trader tokens:", token.balanceOf(TRADER) / 1e18);
    }

    function logRoundSummary(uint256 roundNumber) internal view {
        uint256 points = hook.getStreamerPoints(STREAMER);
        StreamFund.Streamer memory info = hook.getStreamerInfo(STREAMER);

        console.log("Round Summary:");
        console.log("  Round number:", roundNumber);
        console.log("  Total points:", points / 1e18);
        console.log("  Total volume:", info.referralVolume / 1e18, "ETH");
    }

    function showFinalResults() internal {
        console.log("=== Final Results ===");

        uint256 totalPoints = hook.getStreamerPoints(STREAMER);
        StreamFund.Streamer memory finalStreamerInfo = hook.getStreamerInfo(STREAMER);

        console.log("Total streamer points:", totalPoints / 1e18);
        console.log("Total referral volume:", finalStreamerInfo.referralVolume / 1e18, "ETH");
        console.log("Final trader ETH balance:", TRADER.balance / 1e18);
        console.log("Final trader token balance:", token.balanceOf(TRADER) / 1e18);

        // Demonstrate reward claiming
        if (totalPoints > 0 && finalStreamerInfo.referralVolume > 0) {
            claimRewards();
        }
    }

    function claimRewards() internal {
        console.log("");
        console.log("Claiming rewards...");

        vm.stopBroadcast();
        vm.startBroadcast(STREAMER_PK);

        hook.claimReward();

        console.log("Rewards claimed successfully!");
        console.log("Streamer points after claim:", hook.getStreamerPoints(STREAMER));
        console.log("Streamer volume after claim:", hook.getStreamerInfo(STREAMER).referralVolume);

        vm.stopBroadcast();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
    }
}
