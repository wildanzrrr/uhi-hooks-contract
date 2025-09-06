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

import "forge-std/console.sol";
import {PointsHook} from "../src/PointsHook.sol";

contract TestPointsHook is Test, Deployers {
    MockERC20 token;
    MockERC20 token2; // Second token for TOKEN-TOKEN swaps

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;
    Currency token2Currency;

    PointsHook hook;

    // Pool keys for different pools
    PoolKey ethTokenKey; // ETH-TOKEN pool
    PoolKey tokenTokenKey; // TOKEN-TOKEN pool

    function setUp() public {
        // Step 1 + 2
        // Deploy PoolManager and Router contracts
        deployFreshManagerAndRouters();

        // Deploy our TOKEN contract
        token = new MockERC20("Test Token", "TEST", 18);
        tokenCurrency = Currency.wrap(address(token));

        // Deploy second TOKEN contract for TOKEN-TOKEN swaps
        token2 = new MockERC20("Test Token 2", "TEST2", 18);
        token2Currency = Currency.wrap(address(token2));

        // Mint a bunch of TOKEN to ourselves and to address(1)
        token.mint(address(this), 1000 ether);
        token.mint(address(1), 1000 ether);
        token2.mint(address(this), 1000 ether);
        token2.mint(address(1), 1000 ether);

        // Deploy hook to an address that has the proper flags set
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        deployCodeTo("PointsHook.sol", abi.encode(manager), address(flags));

        // Deploy our hook
        hook = PointsHook(address(flags));

        // Approve our TOKEN for spending on the swap router and modify liquidity router
        // These variables are coming from the `Deployers` contract
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token2.approve(address(swapRouter), type(uint256).max);
        token2.approve(address(modifyLiquidityRouter), type(uint256).max);

        // Initialize a pool
        (ethTokenKey,) = initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        // Add some liquidity to the pool
        // uint160 sqrtPriceAtTickLower = TickMath.getSqrtPriceAtTick(-60);
        uint160 sqrtPriceAtTickUpper = TickMath.getSqrtPriceAtTick(60);

        uint256 ethToAdd = 0.1 ether;
        uint128 liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, ethToAdd);
        // uint256 tokenToAdd =
        //     LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceAtTickLower, SQRT_PRICE_1_1, liquidityDelta);

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

        // Initialize TOKEN-TOKEN pool
        (tokenTokenKey,) = initPool(
            tokenCurrency, // Currency 0 = TOKEN
            token2Currency, // Currency 1 = TOKEN2
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        // Add liquidity to TOKEN-TOKEN pool
        uint256 tokenToAdd = 10 ether;
        liquidityDelta = LiquidityAmounts.getLiquidityForAmount0(SQRT_PRICE_1_1, sqrtPriceAtTickUpper, tokenToAdd);

        modifyLiquidityRouter.modifyLiquidity(
            tokenTokenKey,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: int256(uint256(liquidityDelta)),
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    function test_swap() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(ethTokenKey.toId()));
        uint256 pointsBalanceOriginal = hook.balanceOf(address(this), poolIdUint);

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Now we swap
        // We will swap 0.001 ether for tokens
        // We should get 20% of 0.001 * 10**18 points
        // = 2 * 10**14
        swapRouter.swap{value: 0.001 ether}(
            ethTokenKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
        uint256 pointsBalanceAfterSwap = hook.balanceOf(address(this), poolIdUint);
        assertEq(pointsBalanceAfterSwap - pointsBalanceOriginal, 2 * 10 ** 14);
    }

    function test_swap_buy_event() public {
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Expect the Buy event to be emitted
        vm.expectEmit(true, true, false, false); // Check event signature and indexed user
        emit PointsHook.Buy(
            address(this),
            address(0), // ETH
            address(token), // TOKEN
            0, // amountA - don't check
            0 // amountB - don't check
        );

        // Now we swap
        // We will swap 0.001 ether for tokens
        swapRouter.swap{value: 0.001 ether}(
            ethTokenKey,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -0.001 ether, // Exact input for output swap
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
    }

    function test_swap_sell_event() public {
        // First, get some tokens by doing a buy swap
        bytes memory hookData = abi.encode(address(this));
        swapRouter.swap{value: 0.001 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -0.001 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Approve the swap router to spend our tokens
        token.approve(address(swapRouter), type(uint256).max);

        // Now sell tokens for ETH
        vm.expectEmit(true, true, false, false); // Check event signature and indexed user
        emit PointsHook.Sell(
            address(this),
            address(token), // TOKEN
            address(0), // ETH
            0, // amountA - don't check
            0 // amountB - don't check
        );

        // Swap tokens for ETH
        swapRouter.swap(
            ethTokenKey,
            SwapParams({
                zeroForOne: false, // Selling TOKEN for ETH
                amountSpecified: -100 ether, // Exact input
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
    }

    function test_erc6909_transfer() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(ethTokenKey.toId()));

        // First earn some points
        bytes memory hookData = abi.encode(address(this));
        swapRouter.swap{value: 0.001 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -0.001 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 pointsEarned = hook.balanceOf(address(this), poolIdUint);
        assertGt(pointsEarned, 0);

        // Transfer half the points to address(1)
        uint256 transferAmount = pointsEarned / 2;
        hook.transfer(address(1), poolIdUint, transferAmount);

        // Check balances
        assertEq(hook.balanceOf(address(this), poolIdUint), pointsEarned - transferAmount);
        assertEq(hook.balanceOf(address(1), poolIdUint), transferAmount);
    }

    function test_erc6909_approve_and_transferFrom() public {
        uint256 poolIdUint = uint256(PoolId.unwrap(ethTokenKey.toId()));

        // First earn some points
        bytes memory hookData = abi.encode(address(this));
        swapRouter.swap{value: 0.001 ether}(
            ethTokenKey,
            SwapParams({zeroForOne: true, amountSpecified: -0.001 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        uint256 pointsEarned = hook.balanceOf(address(this), poolIdUint);
        assertGt(pointsEarned, 0);

        // Approve address(1) to spend some points
        uint256 approveAmount = pointsEarned / 2;
        hook.approve(address(1), poolIdUint, approveAmount);

        // Check allowance
        assertEq(hook.allowance(address(this), address(1), poolIdUint), approveAmount);

        // Transfer from this address to address(2) via address(1)
        vm.startPrank(address(1));
        hook.transferFrom(address(this), address(2), poolIdUint, approveAmount);
        vm.stopPrank();

        // Check balances and allowance
        assertEq(hook.balanceOf(address(this), poolIdUint), pointsEarned - approveAmount);
        assertEq(hook.balanceOf(address(2), poolIdUint), approveAmount);
        assertEq(hook.allowance(address(this), address(1), poolIdUint), 0);
    }

    function test_swap_token_to_token_event() public {
        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Expect the Buy event to be emitted for TOKEN -> TOKEN2 swap
        vm.expectEmit(true, true, false, false); // Check event signature and indexed user
        emit PointsHook.Buy(
            address(this),
            address(token), // TOKEN (input)
            address(token2), // TOKEN2 (output)
            0, // amountA - don't check exact
            0 // amountB - don't check exact
        );

        // Swap TOKEN for TOKEN2
        swapRouter.swap(
            tokenTokenKey,
            SwapParams({
                zeroForOne: true, // TOKEN -> TOKEN2
                amountSpecified: -10 ether, // Exact input
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
    }

    function test_swap_token_to_token_sell_event() public {
        // First get some TOKEN2 by swapping TOKEN -> TOKEN2
        bytes memory hookData = abi.encode(address(this));
        swapRouter.swap(
            tokenTokenKey,
            SwapParams({
                zeroForOne: true, // TOKEN -> TOKEN2
                amountSpecified: -10 ether,
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );

        // Approve TOKEN2 for spending
        token2.approve(address(swapRouter), type(uint256).max);

        // Now sell TOKEN2 for TOKEN
        vm.expectEmit(true, true, false, false); // Check event signature and indexed user
        emit PointsHook.Sell(
            address(this),
            address(token2), // TOKEN2 (input)
            address(token), // TOKEN (output)
            0, // amountA - don't check
            0 // amountB - don't check
        );

        // Swap TOKEN2 for TOKEN
        swapRouter.swap(
            tokenTokenKey,
            SwapParams({
                zeroForOne: false, // TOKEN2 -> TOKEN
                amountSpecified: -5 ether, // Exact input
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            hookData
        );
    }
}
