// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC6909} from "solmate/src/tokens/ERC6909.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

contract StreamFund is BaseHook, ERC6909 {
    struct Streamer {
        address streamerAddress;
        uint256 referralVolume; // in ETH wei
    }

    mapping(address => Streamer) public streamers;
    mapping(address => bool) public isRegistered;

    // Use a fixed token ID for points across all pools
    uint256 public constant POINTS_TOKEN_ID = 1;

    event Buy(
        address indexed user, address indexed referral, address tokenA, address tokenB, uint256 amountA, uint256 amountB
    );
    event Sell(
        address indexed user, address indexed referral, address tokenA, address tokenB, uint256 amountA, uint256 amountB
    );
    event StreamerRegistered(address indexed streamer);
    event RewardClaimed(address indexed streamer, uint256 pointsBurned, uint256 volumeReset);

    constructor(IPoolManager _manager) BaseHook(_manager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function registerStreamer() external {
        require(!isRegistered[msg.sender], "Already registered");

        streamers[msg.sender] = Streamer({streamerAddress: msg.sender, referralVolume: 0});
        isRegistered[msg.sender] = true;

        emit StreamerRegistered(msg.sender);
    }

    function claimReward() external {
        require(isRegistered[msg.sender], "Not a registered streamer");

        Streamer storage streamer = streamers[msg.sender];
        uint256 volume = streamer.referralVolume;
        require(volume > 0, "No referral volume to claim");

        // Check how many points the streamer has
        uint256 availablePoints = balanceOf[msg.sender][POINTS_TOKEN_ID];
        require(availablePoints > 0, "No points available to burn");

        // Reset referral volume
        streamer.referralVolume = 0;

        // Burn all available points
        _burn(msg.sender, POINTS_TOKEN_ID, availablePoints);

        emit RewardClaimed(msg.sender, availablePoints, volume);
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        // Extract referral address from hookData
        address referral = address(0);
        if (hookData.length > 0) {
            referral = abi.decode(hookData, (address));
        }

        // Emit event based on swap direction
        if (swapParams.zeroForOne) {
            // Buying TOKEN with currency0
            address tokenA = Currency.unwrap(key.currency0);
            address tokenB = Currency.unwrap(key.currency1);
            uint256 amountA = uint256(int256(-delta.amount0()));
            uint256 amountB = uint256(int256(delta.amount1()));
            emit Buy(msg.sender, referral, tokenA, tokenB, amountA, amountB);
        } else {
            // Selling TOKEN for currency0
            address tokenA = Currency.unwrap(key.currency1);
            address tokenB = Currency.unwrap(key.currency0);
            uint256 amountA = uint256(int256(-delta.amount1()));
            uint256 amountB = uint256(int256(delta.amount0()));
            emit Sell(msg.sender, referral, tokenA, tokenB, amountA, amountB);
        }

        // Only process ETH-TOKEN pools and valid referrals
        if (!key.currency0.isAddressZero() || referral == address(0) || !isRegistered[referral]) {
            return (this.afterSwap.selector, 0);
        }

        uint256 ethAmount;
        uint256 pointsToMint;

        if (swapParams.zeroForOne) {
            // Buying TOKEN with ETH - 5 points per ETH
            ethAmount = uint256(int256(-delta.amount0()));
            pointsToMint = ethAmount * 5;
        } else {
            // Selling TOKEN for ETH - 2 points per ETH
            ethAmount = uint256(int256(delta.amount0()));
            pointsToMint = ethAmount * 2;
        }

        // Update referral volume
        streamers[referral].referralVolume += ethAmount;

        // Mint points to the streamer
        _mint(referral, POINTS_TOKEN_ID, pointsToMint);

        return (this.afterSwap.selector, 0);
    }

    function getStreamerInfo(address streamerAddress) external view returns (Streamer memory) {
        require(isRegistered[streamerAddress], "Streamer not registered");
        return streamers[streamerAddress];
    }

    function getStreamerPoints(address streamerAddress) external view returns (uint256) {
        return balanceOf[streamerAddress][POINTS_TOKEN_ID];
    }
}
