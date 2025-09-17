// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolKey} from "v4-core/types/PoolId.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "forge-std/console.sol";
import {StreamFund} from "../src/StreamFund.sol";

contract TestStreamFund is Test, Deployers {
    MockERC20 token;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    StreamFund hook;

    PoolKey ethTokenKey;
    PoolKey tokenTokenKey;

    address owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address stranger = address(0x1234);
    address streamer1 = address(1);
    address streamer2 = address(2);
    address trader = address(3);
    address updater = address(4);

    function setUp() public {
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy our TOKEN contract
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Mint tokens
        token.mint(address(this), 1000 ether);
        token.mint(trader, 1000 ether);

        // Deploy hook
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("StreamFund.sol", abi.encode(manager), address(flags));
        hook = StreamFund(address(flags));

        // Approve tokens
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Set up approvals for trader
        vm.startPrank(trader);
        token.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        // Initialize ETH-TOKEN pool
        (ethTokenKey,) = initPool(ethCurrency, tokenCurrency, hook, 3000, SQRT_PRICE_1_1);

        // Add liquidity to ETH-TOKEN pool
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint256 ethToAdd = 1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, ethToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            ethTokenKey,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        // Fund trader with ETH
        vm.deal(trader, 10 ether);
    }

    function testRegisterStreamer() public {
        vm.startPrank(streamer1);

        // Register streamer
        vm.expectEmit();
        emit StreamFund.StreamerRegistered(streamer1);

        hook.registerStreamer();

        // Check registration
        assertTrue(hook.isRegistered(streamer1));
    }

    function testRegisterStreamerAlreadyRegistered() public {
        vm.startPrank(streamer1);

        // First registration should succeed
        hook.registerStreamer();

        // Second registration should fail with "Already registered"
        vm.expectRevert("Already registered");
        hook.registerStreamer();
    }

    function testGrantTokenRewardUpdaterNoOwner() public {
        vm.prank(stranger);

        vm.expectRevert("Only owner can call this function");
        hook.grantTokenRewardUpdater(address(token), updater);
    }

    function testGrantTokenRewardUpdaterZeroToken() public {
        vm.prank(owner);

        vm.expectRevert("Invalid token address");
        hook.grantTokenRewardUpdater(address(0), updater);
    }

    function testGrantTokenRewardUpdaterZeroUpdater() public {
        vm.prank(owner);

        vm.expectRevert("Invalid updater address");
        hook.grantTokenRewardUpdater(address(token), address(0));
    }

    function testGrantTokenRewardUpdaterAlreadyUpdater() public {
        vm.prank(owner);
        hook.grantTokenRewardUpdater(address(token), updater);

        vm.prank(owner);
        vm.expectRevert("Already a reward updater for this token");
        hook.grantTokenRewardUpdater(address(token), updater);
    }

    function testGrantTokenRewardUpdaterSuccess() public {
        vm.prank(owner);

        vm.expectEmit();
        emit StreamFund.RewardUpdaterGranted(address(token), updater);
        hook.grantTokenRewardUpdater(address(token), updater);

        assertTrue(hook.isTokenRewardUpdater(address(token), updater));
    }

    function testRevokeTokenRewardUpdaterNoOwner() public {
        vm.prank(stranger);

        vm.expectRevert("Only owner can call this function");
        hook.revokeTokenRewardUpdater(address(token), updater);
    }

    function testRevokeTokenRewardUpdaterZeroToken() public {
        vm.prank(owner);

        vm.expectRevert("Invalid token address");
        hook.revokeTokenRewardUpdater(address(0), updater);
    }

    function testRevokeTokenRewardUpdaterZeroUpdater() public {
        vm.prank(owner);

        vm.expectRevert("Invalid updater address");
        hook.revokeTokenRewardUpdater(address(token), address(0));
    }

    function testRevokeTokenRewardUpdaterNotAnUpdater() public {
        vm.prank(owner);

        vm.expectRevert("Not a reward updater for this token");
        hook.revokeTokenRewardUpdater(address(token), updater);
    }

    function testRevokeTokenRewardUpdaterSuccess() public {
        // First grant
        vm.prank(owner);
        hook.grantTokenRewardUpdater(address(token), updater);

        // Now revoke
        vm.prank(owner);
        vm.expectEmit();
        emit StreamFund.RewardUpdaterRevoked(address(token), updater);
        hook.revokeTokenRewardUpdater(address(token), updater);

        assertFalse(hook.isTokenRewardUpdater(address(token), updater));
    }

    // function testGetNotRegisteredStreamerInfo() public {
    //     vm.startPrank(streamer1);
    //     vm.expectRevert("Streamer not registered");
    //     hook.getStreamerInfo(streamer1);
    // }

    // function testSwapBuyWithReferralMintsPoints() public {
    //     // Register streamer
    //     vm.prank(streamer1);
    //     hook.registerStreamer();

    //     // Check initial points
    //     uint256 initialPoints = hook.getStreamerPoints(streamer1);
    //     assertEq(initialPoints, 0);

    //     // Prepare referral data
    //     bytes memory hookData = abi.encode(streamer1);

    //     // trader swaps 0.1 ETH for tokens using streamer1's referral
    //     vm.prank(trader);
    //     swapRouter.swap{value: 0.1 ether}(
    //         ethTokenKey,
    //         SwapParams({zeroForOne: true, amountSpecified: -0.1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
    //         PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
    //         hookData
    //     );

    //     // Check streamer got 5 points per ETH (0.1 * 5 = 0.5 ETH worth of points)
    //     uint256 pointsAfterBuy = hook.getStreamerPoints(streamer1);
    //     assertEq(pointsAfterBuy, 0.5 ether);

    //     // Check referral volume increased
    //     StreamFund.Streamer memory streamerInfo = hook.getStreamerInfo(streamer1);
    //     assertEq(streamerInfo.referralVolume, 0.1 ether);
    // }

    // function testSwapSellWithReferralMintsPoints() public {
    //     // Register streamer
    //     vm.prank(streamer1);
    //     hook.registerStreamer();

    //     bytes memory hookData = abi.encode(streamer1);

    //     // First buy some tokens
    //     vm.startPrank(trader);
    //     swapRouter.swap{value: 0.1 ether}(
    //         ethTokenKey,
    //         SwapParams({zeroForOne: true, amountSpecified: -0.1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
    //         PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
    //         hookData
    //     );

    //     uint256 pointsAfterBuy = hook.getStreamerPoints(streamer1);

    //     // Now sell tokens for ETH (this should give 2 points per ETH)
    //     swapRouter.swap(
    //         ethTokenKey,
    //         SwapParams({
    //             zeroForOne: false,
    //             amountSpecified: -50 ether, // Sell some tokens
    //             sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
    //         }),
    //         PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
    //         hookData
    //     );

    //     vm.stopPrank();

    //     // Points should have increased (buy gives 5x, sell gives 2x per ETH)
    //     uint256 pointsAfterSell = hook.getStreamerPoints(streamer1);
    //     assertGt(pointsAfterSell, pointsAfterBuy);

    //     // Check referral volume includes both buy and sell
    //     StreamFund.Streamer memory streamerInfo = hook.getStreamerInfo(streamer1);
    //     assertGt(streamerInfo.referralVolume, 0.1 ether);
    // }

    // function testClaimReward() public {
    //     // Register streamer
    //     vm.prank(streamer1);
    //     hook.registerStreamer();

    //     bytes memory hookData = abi.encode(streamer1);

    //     // Generate some trading volume and points
    //     vm.prank(trader);
    //     swapRouter.swap{value: 1 ether}(
    //         ethTokenKey,
    //         SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
    //         PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
    //         hookData
    //     );

    //     // Check initial state
    //     StreamFund.Streamer memory streamerInfoBefore = hook.getStreamerInfo(streamer1);
    //     uint256 pointsBefore = hook.getStreamerPoints(streamer1);

    //     assertEq(streamerInfoBefore.referralVolume, 1 ether);
    //     assertEq(pointsBefore, 5 ether); // 1 ETH * 5 points per ETH

    //     // Claim reward
    //     vm.startPrank(streamer1);

    //     vm.expectEmit(true, false, false, false);
    //     emit StreamFund.RewardClaimed(streamer1, 5 ether, 1 ether);

    //     hook.claimReward();

    //     vm.stopPrank();

    //     // Check state after claim
    //     StreamFund.Streamer memory streamerInfoAfter = hook.getStreamerInfo(streamer1);
    //     uint256 pointsAfter = hook.getStreamerPoints(streamer1);

    //     assertEq(streamerInfoAfter.referralVolume, 0); // Volume reset
    //     assertEq(pointsAfter, 0); // Points burned
    // }

    // function testClaimRewardNotRegistered() public {
    //     vm.startPrank(streamer1);
    //     vm.expectRevert("Not a registered streamer");
    //     hook.claimReward();
    //     vm.stopPrank();
    // }

    // function testClaimRewardNoVolume() public {
    //     vm.startPrank(streamer1);
    //     hook.registerStreamer();

    //     vm.expectRevert("No referral volume to claim");
    //     hook.claimReward();
    //     vm.stopPrank();
    // }

    // function testClaimRewardNoPoints() public {
    //     // Register streamer
    //     vm.prank(streamer1);
    //     hook.registerStreamer();

    //     bytes memory hookData = abi.encode(streamer1);

    //     // Generate some trading volume and points first
    //     vm.prank(trader);
    //     swapRouter.swap{value: 1 ether}(
    //         ethTokenKey,
    //         SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
    //         PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
    //         hookData
    //     );

    //     // Verify we have points and volume
    //     assertGt(hook.getStreamerPoints(streamer1), 0);
    //     assertGt(hook.getStreamerInfo(streamer1).referralVolume, 0);

    //     // Manually burn all points to simulate having volume but no points
    //     vm.startPrank(streamer1);

    //     // Use low-level storage manipulation to burn points without going through the contract
    //     bytes32 balanceSlot = keccak256(abi.encode(hook.POINTS_TOKEN_ID(), keccak256(abi.encode(streamer1, 1))));
    //     vm.store(address(hook), balanceSlot, bytes32(0));

    //     // Verify points are now 0 but volume remains
    //     assertEq(hook.getStreamerPoints(streamer1), 0);
    //     assertGt(hook.getStreamerInfo(streamer1).referralVolume, 0);

    //     // Now claim should fail with "No points available to burn"
    //     vm.expectRevert("No points available to burn");
    //     hook.claimReward();
    //     vm.stopPrank();
    // }

    // function testSwapWithoutReferral() public {
    //     // Register streamer
    //     vm.prank(streamer1);
    //     hook.registerStreamer();

    //     uint256 initialPoints = hook.getStreamerPoints(streamer1);

    //     // Swap without referral (empty hookData)
    //     vm.prank(trader);
    //     swapRouter.swap{value: 0.1 ether}(
    //         ethTokenKey,
    //         SwapParams({zeroForOne: true, amountSpecified: -0.1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
    //         PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
    //         ZERO_BYTES
    //     );

    //     // Streamer should get no points or volume
    //     StreamFund.Streamer memory streamerInfo = hook.getStreamerInfo(streamer1);
    //     uint256 finalPoints = hook.getStreamerPoints(streamer1);

    //     assertEq(streamerInfo.referralVolume, 0);
    //     assertEq(finalPoints, initialPoints);
    // }

    // function testPointsCalculationPrecision() public {
    //     // Register streamer
    //     vm.prank(streamer1);
    //     hook.registerStreamer();

    //     bytes memory hookData = abi.encode(streamer1);

    //     // Test with small amount: 0.001 ETH
    //     vm.prank(trader);
    //     swapRouter.swap{value: 0.001 ether}(
    //         ethTokenKey,
    //         SwapParams({zeroForOne: true, amountSpecified: -0.001 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
    //         PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
    //         hookData
    //     );

    //     // Should get exactly 5x the ETH amount in points
    //     uint256 expectedPoints = 0.001 ether * 5;
    //     uint256 actualPoints = hook.getStreamerPoints(streamer1);
    //     assertEq(actualPoints, expectedPoints);
    // }
}
