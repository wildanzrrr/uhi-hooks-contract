import { ethers } from "ethers";
import * as dotenv from "dotenv";

dotenv.config();

const POOL_MANAGER = process.env.POOL_MANAGER!;
const SWAP_ROUTER = process.env.SWAP_ROUTER!;
const STREAMFUND_HOOK = process.env.STREAMFUND_HOOK!;
const MOCK_TOKEN = process.env.MOCK_TOKEN!;
const POOL_CURRENCY0 = process.env.POOL_CURRENCY0!;
const POOL_CURRENCY1 = process.env.POOL_CURRENCY1!;
const TRADER_PK = process.env.TRADER_PK!;
const STREAMER_PK = process.env.STREAMER_PK!;
const RPC_URL = process.env.RPC_URL!;

const NUM_TRADES = 10;

const provider = new ethers.JsonRpcProvider(RPC_URL);
const traderWallet = new ethers.Wallet(TRADER_PK, provider);
const streamerWallet = new ethers.Wallet(STREAMER_PK, provider);

const swapRouterAbi = [
  // Add minimal ABI for swap function from PoolSwapTest
  "function swap(tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey, tuple(bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96) params, tuple(bool takeClaims, bool settleUsingBurn) testSettings, bytes hookData) external payable",
];
const streamFundAbi = [
  // Updated ABI for new StreamFund functions
  "function isRegistered(address) view returns (bool)",
  "function registerStreamer() external",
  "function getStreamerPoints(address streamerAddress, address tokenAddress) view returns (uint256)",
  "function getStreamerTokenVolume(address streamerAddress, address tokenAddress) view returns (uint256)",
  "function getRewardTokenInfo(address tokenAddress) view returns (tuple(address tokenAddress, uint256 ratePerPoint))",
];
const erc20Abi = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address, uint256) external returns (bool)",
];

const swapRouter = new ethers.Contract(
  SWAP_ROUTER,
  swapRouterAbi,
  traderWallet
);
const hook = new ethers.Contract(
  STREAMFUND_HOOK,
  streamFundAbi,
  streamerWallet
);
const token = new ethers.Contract(MOCK_TOKEN, erc20Abi, traderWallet);

const poolKey = {
  currency0: POOL_CURRENCY0,
  currency1: POOL_CURRENCY1,
  fee: 3000,
  tickSpacing: 60,
  hooks: STREAMFUND_HOOK,
};

// Add nonce tracking for each wallet
let traderNonce = await provider.getTransactionCount(traderWallet.address);
let streamerNonce = await provider.getTransactionCount(streamerWallet.address);

// Helper function for delay
function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
  console.log("=== StreamFund Trading Simulation ===");
  console.log("Pool Manager:", POOL_MANAGER);
  console.log("Swap Router:", SWAP_ROUTER);
  console.log("StreamFund Hook:", STREAMFUND_HOOK);
  console.log("Mock Token:", MOCK_TOKEN);
  console.log("Trader Address:", traderWallet.address);
  console.log("Streamer Address:", streamerWallet.address);
  console.log("");

  await setupAccounts();
  await registerStreamer();
  for (let i = 1; i <= NUM_TRADES; i++) {
    console.log(`=== Trade ${i} ===`);
    await performTrade(i);
    console.log("");
  }
  await showFinalResults();
}

async function setupAccounts() {
  console.log("Setting up accounts...");
  const traderBalance = await provider.getBalance(traderWallet.address);
  const streamerBalance = await provider.getBalance(streamerWallet.address);
  console.log("Trader ETH balance:", ethers.formatEther(traderBalance), "ETH");
  console.log(
    "Streamer ETH balance:",
    ethers.formatEther(streamerBalance),
    "ETH"
  );
  console.log("Trader setup complete");
}

async function registerStreamer() {
  console.log("Registering streamer...");
  const isRegistered = await hook.isRegistered(streamerWallet.address);
  if (!isRegistered) {
    const tx = await hook.registerStreamer({ nonce: streamerNonce });
    await tx.wait();
    streamerNonce++;
    console.log("Streamer registered successfully");
  } else {
    console.log("Streamer already registered");
  }
}

async function performTrade(tradeNumber: number) {
  const hookData = ethers.AbiCoder.defaultAbiCoder().encode(
    ["address"],
    [streamerWallet.address]
  );
  await logInitialState();
  await performBuyOperation(hookData);
  await delay(2000); // 2-second delay
  await performSellOperation(hookData);
  await logTradeSummary(tradeNumber);
}

async function logInitialState() {
  const points = await hook.getStreamerPoints(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const volume = await hook.getStreamerTokenVolume(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const traderEth = await provider.getBalance(traderWallet.address);
  const traderTokens = await token.balanceOf(traderWallet.address);
  console.log("Initial state:");
  console.log("  Streamer points:", ethers.formatEther(points));
  console.log("  Streamer referral volume:", ethers.formatEther(volume), "ETH");
  console.log("  Trader ETH:", ethers.formatEther(traderEth));
  console.log("  Trader tokens:", ethers.formatEther(traderTokens));
}

async function performBuyOperation(hookData: string) {
  // Randomize buy amount between 0.3 and 0.8 ETH
  const randomAmount = 0.3 + Math.random() * 0.5; // 0.3 to 0.8
  const tradeAmount = ethers.parseEther(randomAmount.toFixed(3));
  console.log(
    "Performing BUY operation with",
    ethers.formatEther(tradeAmount),
    "ETH..."
  );
  const tx = await swapRouter.swap(
    poolKey,
    {
      zeroForOne: true,
      amountSpecified: -tradeAmount,
      sqrtPriceLimitX96: 4295128739n + 1n,
    },
    { takeClaims: false, settleUsingBurn: false },
    hookData,
    { value: tradeAmount, nonce: traderNonce }
  );
  await tx.wait();
  traderNonce++;
  const points = await hook.getStreamerPoints(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const volume = await hook.getStreamerTokenVolume(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const traderTokens = await token.balanceOf(traderWallet.address);
  console.log("After BUY:");
  console.log("  Streamer points:", ethers.formatEther(points));
  console.log("  Streamer referral volume:", ethers.formatEther(volume), "ETH");
  console.log("  Trader tokens:", ethers.formatEther(traderTokens));
}

async function performSellOperation(hookData: string) {
  const tokenBalance = await token.balanceOf(traderWallet.address);
  // Randomize sell percentage between 10% and 50%
  const percentage = 0.1 + Math.random() * 0.4; // 10% to 50%
  const tokensToSell =
    (tokenBalance * BigInt(Math.floor(percentage * 100))) / 100n;
  console.log("Performing SELL operation...");
  console.log(
    "  Selling",
    ethers.formatEther(tokensToSell),
    "tokens (",
    (percentage * 100).toFixed(1),
    "% of balance)"
  );
  await token.approve(SWAP_ROUTER, tokensToSell, { nonce: traderNonce });
  traderNonce++;
  const tx = await swapRouter.swap(
    poolKey,
    {
      zeroForOne: false,
      amountSpecified: -tokensToSell,
      sqrtPriceLimitX96:
        1461446703485210103287273052203988822378723970342n - 1n,
    },
    { takeClaims: false, settleUsingBurn: false },
    hookData,
    { nonce: traderNonce }
  );
  await tx.wait();
  traderNonce++;
  const points = await hook.getStreamerPoints(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const volume = await hook.getStreamerTokenVolume(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const traderEth = await provider.getBalance(traderWallet.address);
  const traderTokens = await token.balanceOf(traderWallet.address);
  console.log("After SELL:");
  console.log("  Streamer points:", ethers.formatEther(points));
  console.log("  Streamer referral volume:", ethers.formatEther(volume), "ETH");
  console.log("  Trader ETH:", ethers.formatEther(traderEth));
  console.log("  Trader tokens:", ethers.formatEther(traderTokens));
}

async function logTradeSummary(tradeNumber: number) {
  const points = await hook.getStreamerPoints(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const volume = await hook.getStreamerTokenVolume(
    streamerWallet.address,
    MOCK_TOKEN
  );
  console.log("Trade Summary:");
  console.log("  Trade number:", tradeNumber);
  console.log("  Total points:", ethers.formatEther(points));
  console.log("  Total volume:", ethers.formatEther(volume), "ETH");
}

async function showFinalResults() {
  console.log("=== Final Results ===");
  const totalPoints = await hook.getStreamerPoints(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const totalVolume = await hook.getStreamerTokenVolume(
    streamerWallet.address,
    MOCK_TOKEN
  );
  const traderEth = await provider.getBalance(traderWallet.address);
  const traderTokens = await token.balanceOf(traderWallet.address);

  // Try to get reward token info
  try {
    const rewardInfo = await hook.getRewardTokenInfo(MOCK_TOKEN);
    console.log("Reward token setup:");
    console.log("  Token address:", rewardInfo.tokenAddress);
    console.log(
      "  Rate per point:",
      ethers.formatEther(rewardInfo.ratePerPoint)
    );

    if (rewardInfo.tokenAddress !== ethers.ZeroAddress) {
      const potentialReward = totalPoints * rewardInfo.ratePerPoint;
      console.log(
        "  Potential reward:",
        ethers.formatEther(potentialReward),
        "tokens"
      );
    }
  } catch (error) {
    console.log("Reward token not setup for this token");
  }

  console.log("Total streamer points:", ethers.formatEther(totalPoints));
  console.log("Total referral volume:", ethers.formatEther(totalVolume), "ETH");
  console.log("Final trader ETH balance:", ethers.formatEther(traderEth));
  console.log("Final trader token balance:", ethers.formatEther(traderTokens));
}

main().catch(console.error);
