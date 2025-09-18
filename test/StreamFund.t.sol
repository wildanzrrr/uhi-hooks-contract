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
        token.mint(address(this), 1_000_000_000e18);
        token.mint(trader, 1_000e18);

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
        uint256 ethToAdd = 10 ether;
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

        // Configure token reward updater
        vm.prank(owner);
        hook.grantTokenRewardUpdater(address(token), updater);

        // Set up token reward with 100 tokens per point
        vm.prank(updater);
        hook.setupReward(address(token), 100e18); // 100 tokens per point

        // Check initial state
        StreamFund.RewardToken memory rewardToken = hook.getRewardTokenInfo(address(token));
        assertEq(rewardToken.tokenAddress, address(token));
        assertEq(rewardToken.ratePerPoint, 100e18);
    }

    function testTransferOwnershipNoOwner() public {
        vm.prank(stranger);

        vm.expectRevert("Only owner can call this function");
        hook.transferOwnership(stranger);
    }

    function testTransferOwnershipZeroAddress() public {
        vm.prank(owner);

        vm.expectRevert("Invalid new owner address");
        hook.transferOwnership(address(0));
    }

    function testTransferOwnershipSuccess() public {
        vm.prank(owner);

        vm.expectEmit();
        emit StreamFund.NewOwner(owner, stranger);
        hook.transferOwnership(stranger);

        // Check new owner can perform owner actions
        // Create a new token to avoid conflicts with existing setup
        MockERC20 newToken = new MockERC20("Owner Test Token", "OTT", 18);
        vm.prank(stranger);
        hook.grantTokenRewardUpdater(address(newToken), address(0x999));
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
        // The updater is already granted in setUp, so this should fail
        vm.prank(owner);
        vm.expectRevert("Already a reward updater for this token");
        hook.grantTokenRewardUpdater(address(token), updater);
    }

    function testGrantTokenRewardUpdaterSuccess() public {
        vm.prank(owner);

        vm.expectEmit();
        emit StreamFund.RewardUpdaterGranted(address(token), stranger);
        hook.grantTokenRewardUpdater(address(token), stranger);

        assertTrue(hook.isTokenRewardUpdater(address(token), stranger));
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
        hook.revokeTokenRewardUpdater(address(token), stranger); // stranger was never granted updater role
    }

    function testRevokeTokenRewardUpdaterSuccess() public {
        // The updater was already granted in setUp, so we can revoke it directly
        vm.prank(owner);
        vm.expectEmit();
        emit StreamFund.RewardUpdaterRevoked(address(token), updater);
        hook.revokeTokenRewardUpdater(address(token), updater);

        assertFalse(hook.isTokenRewardUpdater(address(token), updater));
    }

    function testSetupRewardNoTokenRewardUpdater() public {
        vm.prank(stranger);

        vm.expectRevert("Only owner or token reward updater can call this function");
        hook.setupReward(address(token), 1e18);
    }

    function testSetupRewardZeroToken() public {
        vm.prank(owner);

        vm.expectRevert("Invalid token address");
        hook.setupReward(address(0), 1e18);
    }

    function testSetupRewardZeroRate() public {
        vm.prank(owner);

        vm.expectRevert("Rate must be greater than 0");
        hook.setupReward(address(token), 0);
    }

    function testSetupRewardTokenAlreadyAdded() public {
        // Token is already setup in setUp, so trying to setup again should fail
        vm.prank(owner);
        vm.expectRevert("Token already added");
        hook.setupReward(address(token), 2e18);
    }

    function testSetupRewardSuccess() public {
        // Create a new token since the original is already setup
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        vm.prank(owner);
        vm.expectEmit();
        emit StreamFund.RewardTokenSetup(address(newToken), 1e18);
        hook.setupReward(address(newToken), 1e18);

        StreamFund.RewardToken memory rewardToken = hook.getRewardTokenInfo(address(newToken));
        assertEq(rewardToken.tokenAddress, address(newToken));
        assertEq(rewardToken.ratePerPoint, 1e18);
    }

    function testUpdateRewardRateNoTokenRewardUpdater() public {
        vm.prank(stranger);

        vm.expectRevert("Only owner or token reward updater can call this function");
        hook.updateRewardRate(address(token), 2e18);
    }

    function testUpdateRewardRateZeroToken() public {
        vm.prank(owner);

        vm.expectRevert("Invalid token address");
        hook.updateRewardRate(address(0), 2e18);
    }

    function testUpdateRewardRateZeroRate() public {
        // Use the token that's already setup in setUp (rate: 100e18)
        vm.prank(owner);
        vm.expectRevert("Rate must be greater than 0");
        hook.updateRewardRate(address(token), 0);
    }

    function testUpdateRewardRateTokenNotSetup() public {
        // Create a new token that hasn't been setup
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        vm.prank(owner);
        vm.expectRevert("Token not setup");
        hook.updateRewardRate(address(newToken), 2e18);
    }

    function testUpdateRewardRateSuccess() public {
        // Use the token that's already setup in setUp
        vm.prank(owner);
        vm.expectEmit();
        emit StreamFund.RewardRateUpdated(address(token), 100e18, 2e18); // Current rate is 100e18 from setUp
        hook.updateRewardRate(address(token), 2e18);

        StreamFund.RewardToken memory rewardToken = hook.getRewardTokenInfo(address(token));
        assertEq(rewardToken.ratePerPoint, 2e18);
    }

    function testGetStreamerTokenVolumeNotRegistered() public {
        vm.startPrank(streamer1);
        assertEq(hook.getStreamerTokenVolume(streamer1, address(token)), 0);
    }

    function testGetStreamerPointsNotRegistered() public {
        vm.startPrank(streamer1);
        assertEq(hook.getStreamerPoints(streamer1, address(token)), 0);
    }

    function testClaimRewardNotRegistered() public {
        vm.prank(stranger);

        vm.expectRevert("Not a registered streamer");
        hook.claimReward(address(token));
    }

    function testClaimRewardTokenNotSetup() public {
        // Register streamer first
        vm.prank(streamer1);
        hook.registerStreamer();

        // Create a new token that hasn't been setup
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        vm.prank(streamer1);
        vm.expectRevert("Reward token not setup");
        hook.claimReward(address(newToken));
    }

    function testClaimRewardNoVolume() public {
        // Register streamer first
        vm.prank(streamer1);
        hook.registerStreamer();

        // Now claim should fail with "No referral volume to claim for this token"
        vm.prank(streamer1);
        vm.expectRevert("No referral volume to claim for this token");
        hook.claimReward(address(token));
    }

    function testClaimRewardInsufficientContractBalance() public {
        // Register streamer
        vm.prank(streamer1);
        hook.registerStreamer();

        bytes memory hookData = abi.encode(streamer1);

        // Generate some trading volume and points first
        vm.prank(trader);
        swapRouter.swap{value: 1 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify we have points and volume
        assertGt(hook.getStreamerPoints(streamer1, address(token)), 0);
        assertGt(hook.getStreamerTokenVolume(streamer1, address(token)), 0);

        // Ensure contract has zero token balance to trigger insufficient balance
        uint256 contractTokenBalance = token.balanceOf(address(hook));
        if (contractTokenBalance > 0) {
            token.transfer(address(0xdead), contractTokenBalance);
        }
        assertEq(token.balanceOf(address(hook)), 0);

        // Now claim should fail with "Insufficient reward token balance"
        vm.prank(streamer1);
        vm.expectRevert("Insufficient reward token balance");
        hook.claimReward(address(token));
    }

    function testClaimRewardSuccess() public {
        // Register streamer
        vm.prank(streamer1);
        hook.registerStreamer();

        bytes memory hookData = abi.encode(streamer1);

        // Generate some trading volume and points first
        vm.prank(trader);
        swapRouter.swap{value: 1 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify we have points and volume
        uint256 points = hook.getStreamerPoints(streamer1, address(token));
        uint256 volume = hook.getStreamerTokenVolume(streamer1, address(token));
        assertGt(points, 0);
        assertGt(volume, 0);

        // Fund contract with some reward tokens (ensure enough for the claim)
        uint256 requiredTokens = points * 100e18 / 1e18; // Corrected: rate is 100e18 tokens per point, divided by 1e18 for decimals
        token.mint(address(hook), requiredTokens);
        assertEq(token.balanceOf(address(hook)), requiredTokens);

        // Claim rewards
        vm.prank(streamer1);

        vm.expectEmit();
        emit StreamFund.RewardClaimed(streamer1, points, volume, address(token), requiredTokens);
        hook.claimReward(address(token));

        // Verify referral volume reset to 0
        assertEq(hook.getStreamerTokenVolume(streamer1, address(token)), 0);

        // Verify points are burned (should be 0 now)
        assertEq(hook.getStreamerPoints(streamer1, address(token)), 0);

        // Verify streamer received the tokens
        assertEq(token.balanceOf(streamer1), requiredTokens);

        // Verify contract token balance is now 0
        assertEq(token.balanceOf(address(hook)), 0);
    }

    function testBuyAndThenSellWithCooldown() public {
        // Register streamer
        vm.prank(streamer1);
        hook.registerStreamer();

        bytes memory hookData = abi.encode(streamer1);

        // Generate some trading volume and points first
        vm.prank(trader);
        swapRouter.swap{value: 1 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify we have points and volume
        uint256 pointsAfterBuy = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeAfterBuy = hook.getStreamerTokenVolume(streamer1, address(token));
        assertGt(pointsAfterBuy, 0);
        assertGt(volumeAfterBuy, 0);

        // Wait for cooldown period to pass (60 seconds + 1 for safety)
        vm.warp(block.timestamp + 61);

        // Now do a sell swap to generate more volume and points
        vm.prank(trader);
        swapRouter.swap(
            ethTokenKey,
            SwapParams({
                zeroForOne: false,
                amountSpecified: int256(100e18),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify we have more points and volume after the sell
        uint256 pointsAfterSell = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeAfterSell = hook.getStreamerTokenVolume(streamer1, address(token));
        assertGt(pointsAfterSell, pointsAfterBuy);
        assertGt(volumeAfterSell, volumeAfterBuy);
    }

    function testBuyAndSellWithoutCooldown() public {
        // Register streamer
        vm.prank(streamer1);
        hook.registerStreamer();

        bytes memory hookData = abi.encode(streamer1);

        // Generate some trading volume and points first
        vm.prank(trader);
        swapRouter.swap{value: 1 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify we have points and volume
        uint256 pointsAfterBuy = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeAfterBuy = hook.getStreamerTokenVolume(streamer1, address(token));
        assertGt(pointsAfterBuy, 0);
        assertGt(volumeAfterBuy, 0);

        // Now do a sell swap immediately - this should succeed but not award points due to cooldown
        vm.expectEmit();
        emit StreamFund.TradeCooldownActive(streamer1);

        swapRouter.swap(
            ethTokenKey,
            SwapParams({
                zeroForOne: false,
                amountSpecified: int256(100e18),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify points and volume remain unchanged after sell during cooldown
        uint256 pointsAfterCooldownSell = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeAfterCooldownSell = hook.getStreamerTokenVolume(streamer1, address(token));
        assertEq(pointsAfterCooldownSell, pointsAfterBuy);
        assertEq(volumeAfterCooldownSell, volumeAfterBuy);
    }

    function testAfterSwapEarlyReturnNonETHCurrency0() public {
        // Register streamer
        vm.prank(streamer1);
        hook.registerStreamer();

        bytes memory hookData = abi.encode(streamer1);

        // Create a TOKEN-TOKEN pool (both currencies are non-zero addresses)
        // This should trigger the early return on line 217 since currency0 is not ETH
        MockERC20 token2 = new MockERC20("Test Token 2", "TEST2", 18);
        Currency token2Currency = Currency.wrap(address(token2));

        token2.mint(address(this), 1_000_000e18);
        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize TOKEN-TOKEN2 pool (no ETH involved)
        (PoolKey memory tokenToKey2,) = initPool(tokenCurrency, token2Currency, hook, 3000, SQRT_PRICE_1_1);

        // Add liquidity to TOKEN-TOKEN2 pool
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint256 tokensToAdd = 1000e18;
        uint128 liquidityDelta =
            LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, tokensToAdd);

        modifyLiquidityRouter.modifyLiquidity(
            tokenToKey2,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        // Get initial points and volume (should be 0)
        uint256 pointsBefore = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeBefore = hook.getStreamerTokenVolume(streamer1, address(token));

        // Do a swap on TOKEN-TOKEN2 pool - this should trigger early return
        swapRouter.swap(
            tokenToKey2,
            SwapParams({zeroForOne: true, amountSpecified: -100e18, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify no points or volume were awarded due to early return
        uint256 pointsAfter = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeAfter = hook.getStreamerTokenVolume(streamer1, address(token));
        assertEq(pointsAfter, pointsBefore);
        assertEq(volumeAfter, volumeBefore);
    }

    function testAfterSwapEarlyReturnZeroReferral() public {
        bytes memory hookDataZeroReferral = abi.encode(address(0));

        // Get initial points and volume (should be 0)
        uint256 pointsBefore = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeBefore = hook.getStreamerTokenVolume(streamer1, address(token));

        // Do a swap with zero referral - this should trigger early return
        vm.prank(trader);
        swapRouter.swap{value: 1 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookDataZeroReferral
        );

        // Verify no points or volume were awarded due to early return
        uint256 pointsAfter = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeAfter = hook.getStreamerTokenVolume(streamer1, address(token));
        assertEq(pointsAfter, pointsBefore);
        assertEq(volumeAfter, volumeBefore);
    }

    function testAfterSwapEarlyReturnUnregisteredReferral() public {
        // Don't register streamer1 - they should be unregistered
        assertFalse(hook.isRegistered(streamer1));

        bytes memory hookData = abi.encode(streamer1);

        // Get initial points and volume (should be 0)
        uint256 pointsBefore = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeBefore = hook.getStreamerTokenVolume(streamer1, address(token));

        // Do a swap with unregistered referral - this should trigger early return
        vm.prank(trader);
        swapRouter.swap{value: 1 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify no points or volume were awarded due to early return
        uint256 pointsAfter = hook.getStreamerPoints(streamer1, address(token));
        uint256 volumeAfter = hook.getStreamerTokenVolume(streamer1, address(token));
        assertEq(pointsAfter, pointsBefore);
        assertEq(volumeAfter, volumeBefore);
    }

    function testAfterSwapEarlyReturnTokenNotSetup() public {
        // Create a new token that hasn't been setup for rewards
        MockERC20 newToken = new MockERC20("Unsetup Token", "UNSETUP", 18);
        Currency newTokenCurrency = Currency.wrap(address(newToken));

        newToken.mint(address(this), 1_000_000e18);
        newToken.approve(address(swapRouter), type(uint256).max);
        newToken.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize ETH-NEWTOKEN pool
        (PoolKey memory ethNewTokenKey,) = initPool(ethCurrency, newTokenCurrency, hook, 3000, SQRT_PRICE_1_1);

        // Add liquidity to ETH-NEWTOKEN pool
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);
        uint256 ethToAdd = 10 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, ethToAdd);

        modifyLiquidityRouter.modifyLiquidity{value: ethToAdd}(
            ethNewTokenKey,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );

        // Register streamer
        vm.prank(streamer1);
        hook.registerStreamer();

        bytes memory hookData = abi.encode(streamer1);

        // Get initial points and volume (should be 0)
        uint256 pointsBefore = hook.getStreamerPoints(streamer1, address(newToken));
        uint256 volumeBefore = hook.getStreamerTokenVolume(streamer1, address(newToken));

        // Do a swap with a token that doesn't have reward setup - this should trigger early return
        vm.prank(trader);
        swapRouter.swap{value: 1 ether}(
            ethNewTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Verify no points or volume were awarded due to early return
        uint256 pointsAfter = hook.getStreamerPoints(streamer1, address(newToken));
        uint256 volumeAfter = hook.getStreamerTokenVolume(streamer1, address(newToken));
        assertEq(pointsAfter, pointsBefore);
        assertEq(volumeAfter, volumeBefore);
    }
}
