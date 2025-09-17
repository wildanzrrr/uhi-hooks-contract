// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {ERC6909} from "solmate/src/tokens/ERC6909.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

contract StreamFund is BaseHook, ERC6909 {
    struct RewardToken {
        address tokenAddress;
        uint256 ratePerPoint; // Amount of tokens per 1 point (in token's smallest unit)
    }

    address public owner;
    mapping(address => bool) public isRegistered;
    mapping(address => RewardToken) public rewardTokens;
    mapping(address => mapping(address => uint256)) public lastTradeTime; // streamer => buyer => timestamp
    mapping(address => mapping(address => uint256)) public streamerTokenVolume; // streamer => token => volume
    mapping(address => mapping(address => bool)) public tokenRewardUpdaters; // token => updater => bool

    uint256 public constant TRADE_COOLDOWN = 60; // 1 minute in seconds

    event Buy(
        address indexed user, address indexed referral, address tokenA, address tokenB, uint256 amountA, uint256 amountB
    );
    event Sell(
        address indexed user, address indexed referral, address tokenA, address tokenB, uint256 amountA, uint256 amountB
    );
    event StreamerRegistered(address indexed streamer);
    event RewardClaimed(
        address indexed streamer,
        uint256 pointsBurned,
        uint256 volumeReset,
        address indexed tokenAddress,
        uint256 rewardAmount
    );
    event NewOwner(address indexed oldOwner, address indexed newOwner);
    event RewardTokenSetup(address indexed tokenAddress, uint256 ratePerPoint);
    event RewardRateUpdated(address indexed tokenAddress, uint256 oldRate, uint256 newRate);
    event RewardUpdaterGranted(address indexed tokenAddress, address indexed updater);
    event RewardUpdaterRevoked(address indexed tokenAddress, address indexed updater);
    event PointsEarned(address indexed streamer, address indexed buyer, address indexed tokenAddress, uint256 points);
    event TradeCooldownActive(address indexed streamer);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyTokenRewardUpdater(address tokenAddress) {
        require(
            msg.sender == owner || tokenRewardUpdaters[tokenAddress][msg.sender],
            "Only owner or token reward updater can call this function"
        );
        _;
    }

    constructor(IPoolManager _manager) BaseHook(_manager) {
        // FOR TESTING PURPOSES ONLY AND LOCAL DEPLOYMENTS
        owner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    }

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

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner address");
        owner = newOwner;

        emit NewOwner(msg.sender, newOwner);
    }

    function grantTokenRewardUpdater(address tokenAddress, address updater) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(updater != address(0), "Invalid updater address");
        require(!tokenRewardUpdaters[tokenAddress][updater], "Already a reward updater for this token");

        tokenRewardUpdaters[tokenAddress][updater] = true;
        emit RewardUpdaterGranted(tokenAddress, updater);
    }

    function revokeTokenRewardUpdater(address tokenAddress, address updater) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        require(updater != address(0), "Invalid updater address");
        require(tokenRewardUpdaters[tokenAddress][updater], "Not a reward updater for this token");

        tokenRewardUpdaters[tokenAddress][updater] = false;
        emit RewardUpdaterRevoked(tokenAddress, updater);
    }

    function setupReward(address tokenAddress, uint256 ratePerPoint) external onlyTokenRewardUpdater(tokenAddress) {
        require(tokenAddress != address(0), "Invalid token address");
        require(ratePerPoint > 0, "Rate must be greater than 0");
        require(rewardTokens[tokenAddress].tokenAddress == address(0), "Token already added");

        // Create new reward token entry
        rewardTokens[tokenAddress] = RewardToken({tokenAddress: tokenAddress, ratePerPoint: ratePerPoint});

        emit RewardTokenSetup(tokenAddress, ratePerPoint);
    }

    function updateRewardRate(address tokenAddress, uint256 newRatePerPoint)
        external
        onlyTokenRewardUpdater(tokenAddress)
    {
        require(tokenAddress != address(0), "Invalid token address");
        require(newRatePerPoint > 0, "Rate must be greater than 0");
        require(rewardTokens[tokenAddress].tokenAddress != address(0), "Token not setup");

        uint256 oldRate = rewardTokens[tokenAddress].ratePerPoint;
        rewardTokens[tokenAddress].ratePerPoint = newRatePerPoint;

        emit RewardRateUpdated(tokenAddress, oldRate, newRatePerPoint);
    }

    function registerStreamer() external {
        require(!isRegistered[msg.sender], "Already registered");
        isRegistered[msg.sender] = true;
        emit StreamerRegistered(msg.sender);
    }

    function claimReward(address tokenAddress) external {
        require(isRegistered[msg.sender], "Not a registered streamer");
        require(rewardTokens[tokenAddress].tokenAddress != address(0), "Reward token not setup");

        uint256 volume = streamerTokenVolume[msg.sender][tokenAddress];
        require(volume > 0, "No referral volume to claim for this token");

        // Check how many points the streamer has for this token
        uint256 tokenId = uint256(uint160(tokenAddress));
        uint256 availablePoints = balanceOf[msg.sender][tokenId];

        RewardToken storage reward = rewardTokens[tokenAddress];

        // Calculate token amount to give based on points and rate
        uint256 tokenAmount = (availablePoints * reward.ratePerPoint) / (10 ** IERC20(tokenAddress).decimals());

        // Check contract's current token balance
        uint256 contractBalance = IERC20(tokenAddress).balanceOf(address(this));
        require(tokenAmount <= contractBalance, "Insufficient reward token balance");

        // Reset referral volume for this token
        streamerTokenVolume[msg.sender][tokenAddress] = 0;

        // Burn all available points for this token
        _burn(msg.sender, tokenId, availablePoints);

        // Transfer reward tokens to streamer
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);

        emit RewardClaimed(msg.sender, availablePoints, volume, tokenAddress, tokenAmount);
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

        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;

        // Emit event based on swap direction
        if (swapParams.zeroForOne) {
            // Buying TOKEN with currency0
            tokenA = Currency.unwrap(key.currency0);
            tokenB = Currency.unwrap(key.currency1);
            amountA = uint256(int256(-delta.amount0()));
            amountB = uint256(int256(delta.amount1()));
            emit Buy(msg.sender, referral, tokenA, tokenB, amountA, amountB);
        } else {
            // Selling TOKEN for currency0
            tokenA = Currency.unwrap(key.currency1);
            tokenB = Currency.unwrap(key.currency0);
            amountA = uint256(int256(-delta.amount1()));
            amountB = uint256(int256(delta.amount0()));
            emit Sell(msg.sender, referral, tokenA, tokenB, amountA, amountB);
        }

        // Only process ETH-TOKEN pools and valid referrals
        if (!key.currency0.isAddressZero() || referral == address(0) || !isRegistered[referral]) {
            return (this.afterSwap.selector, 0);
        }

        // Get the token address (non-ETH currency)
        address tokenAddress = Currency.unwrap(key.currency1);

        // Check if this token has reward setup
        if (rewardTokens[tokenAddress].tokenAddress == address(0)) {
            return (this.afterSwap.selector, 0);
        }

        // Check trade cooldown for fair play
        uint256 currentTime = block.timestamp;
        uint256 lastTrade = lastTradeTime[referral][msg.sender];

        if (lastTrade != 0 && currentTime - lastTrade < TRADE_COOLDOWN) {
            // Update last trade time but don't award points
            lastTradeTime[referral][msg.sender] = currentTime;
            emit TradeCooldownActive(referral);
            return (this.afterSwap.selector, 0);
        }

        // Update last trade time
        lastTradeTime[referral][msg.sender] = currentTime;

        uint256 ethAmount;
        uint256 pointsToMint;

        if (swapParams.zeroForOne) {
            // Buying TOKEN with ETH - 5 points per ETH
            ethAmount = uint256(int256(-delta.amount0()));
            pointsToMint = (ethAmount * 5);
        } else {
            // Selling TOKEN for ETH - 2 points per ETH
            ethAmount = uint256(int256(delta.amount0()));
            pointsToMint = (ethAmount * 2);
        }

        // Update referral volume for this specific token
        streamerTokenVolume[referral][tokenAddress] += ethAmount;

        // Use token address as token ID (convert address to uint256)
        uint256 tokenId = uint256(uint160(tokenAddress));

        // Mint points to the streamer for this specific token
        _mint(referral, tokenId, pointsToMint);

        emit PointsEarned(referral, msg.sender, tokenAddress, pointsToMint);

        return (this.afterSwap.selector, 0);
    }

    function getStreamerTokenVolume(address streamerAddress, address tokenAddress) external view returns (uint256) {
        return streamerTokenVolume[streamerAddress][tokenAddress];
    }

    function getStreamerPoints(address streamerAddress, address tokenAddress) external view returns (uint256) {
        uint256 tokenId = uint256(uint160(tokenAddress));
        return balanceOf[streamerAddress][tokenId];
    }

    function getRewardTokenInfo(address tokenAddress) external view returns (RewardToken memory) {
        return rewardTokens[tokenAddress];
    }

    function isTokenRewardUpdater(address tokenAddress, address account) external view returns (bool) {
        return tokenRewardUpdaters[tokenAddress][account];
    }
}
