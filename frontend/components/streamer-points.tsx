"use client";

import { useEffect, useState } from "react";
import {
  createPublicClient,
  http,
  Address,
  formatEther,
  formatUnits,
} from "viem";
import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useBalance,
} from "wagmi";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useTransactionsStore } from "@/stores/transaction";
import { cn } from "@/lib/utils";
import { Button } from "./ui/button";

// ABI snippet for getStreamerPoints (from StreamFund.sol)
const STREAMFUND_ABI = [
  {
    inputs: [
      { internalType: "address", name: "streamerAddress", type: "address" },
      { internalType: "address", name: "tokenAddress", type: "address" },
    ],
    name: "getStreamerPoints",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "streamerAddress", type: "address" },
      { internalType: "address", name: "tokenAddress", type: "address" },
    ],
    name: "getStreamerTokenVolume",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "tokenAddress", type: "address" },
    ],
    name: "claimReward",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { internalType: "address", name: "tokenAddress", type: "address" },
    ],
    name: "getRewardTokenInfo",
    outputs: [
      {
        components: [
          { internalType: "address", name: "tokenAddress", type: "address" },
          { internalType: "uint256", name: "ratePerPoint", type: "uint256" },
        ],
        internalType: "struct StreamFund.RewardToken",
        name: "",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
] as const;

// ERC20 ABI for checking balances
const ERC20_ABI = [
  {
    inputs: [{ internalType: "address", name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

interface RewardTokenInfo {
  tokenAddress: Address;
  ratePerPoint: bigint;
}

interface StreamerPointsProps {
  userAddress: Address | undefined; // Pass the connected user's address
}

export default function StreamerPoints({ userAddress }: StreamerPointsProps) {
  const [points, setPoints] = useState<bigint | null>(null);
  const [volume, setVolume] = useState<bigint | null>(null);
  const [rewardInfo, setRewardInfo] = useState<RewardTokenInfo | null>(null);
  const [potentialReward, setPotentialReward] = useState<bigint | null>(null);
  const [tokenBalance, setTokenBalance] = useState<bigint | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { transactionCount } = useTransactionsStore(); // Get transaction count for reactivity

  const CONTRACT_ADDRESS = process.env
    .NEXT_PUBLIC_STREAMFUND_ADDRESS as Address;

  const TOKEN_ADDRESS = process.env.NEXT_PUBLIC_MOCK_TOKEN as Address;

  // Check wallet balance
  const { data: balance } = useBalance({
    address: userAddress,
  });

  // Use wagmi hooks for contract interaction
  const {
    writeContract,
    data: hash,
    isPending,
    error: writeError,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed } =
    useWaitForTransactionReceipt({
      hash,
    });

  useEffect(() => {
    if (!userAddress) {
      setPoints(null);
      setVolume(null);
      setRewardInfo(null);
      setPotentialReward(null);
      setTokenBalance(null);
      setError("No user address provided");
      return;
    }

    const fetchData = async () => {
      console.log("🔄 Fetching streamer data...");
      console.log("User address:", userAddress);
      console.log("Contract address:", CONTRACT_ADDRESS);
      console.log("Token address:", TOKEN_ADDRESS);

      setLoading(true);
      setError(null);

      try {
        const RPC_URL =
          process.env.NEXT_PUBLIC_RPC_URL || "http://127.0.0.1:8545";

        console.log("🌐 RPC URL:", RPC_URL);

        if (!CONTRACT_ADDRESS) {
          throw new Error("StreamFund contract address not provided");
        }

        if (!TOKEN_ADDRESS) {
          throw new Error("Mock token address not provided");
        }

        const client = createPublicClient({
          transport: http(RPC_URL),
        });

        console.log("📞 Making contract calls...");

        // Fetch points
        console.log("🎯 Fetching points...");
        const pointsResult = await client.readContract({
          address: CONTRACT_ADDRESS,
          abi: STREAMFUND_ABI,
          functionName: "getStreamerPoints",
          args: [userAddress, TOKEN_ADDRESS],
        });

        // Fetch volume
        console.log("📊 Fetching volume...");
        const volumeResult = await client.readContract({
          address: CONTRACT_ADDRESS,
          abi: STREAMFUND_ABI,
          functionName: "getStreamerTokenVolume",
          args: [userAddress, TOKEN_ADDRESS],
        });

        // Fetch reward token info
        console.log("💰 Fetching reward token info...");
        const rewardTokenResult = await client.readContract({
          address: CONTRACT_ADDRESS,
          abi: STREAMFUND_ABI,
          functionName: "getRewardTokenInfo",
          args: [TOKEN_ADDRESS],
        });

        // Fetch user's token balance
        console.log("💳 Fetching token balance...");
        const tokenBalanceResult = await client.readContract({
          address: TOKEN_ADDRESS,
          abi: ERC20_ABI,
          functionName: "balanceOf",
          args: [userAddress],
        });

        console.log("📋 Raw results:");
        console.log("  - Points (wei):", pointsResult.toString());
        console.log("  - Volume (wei):", volumeResult.toString());
        console.log("  - Reward token result:", rewardTokenResult);
        console.log("  - Token balance (wei):", tokenBalanceResult.toString());

        // Process reward token info
        const rewardTokenInfo: RewardTokenInfo = {
          tokenAddress: rewardTokenResult.tokenAddress,
          ratePerPoint: rewardTokenResult.ratePerPoint,
        };

        console.log("🔄 Processing reward calculation...");
        console.log("  - Points (ether):", formatEther(pointsResult));
        console.log("  - Volume (ether):", formatEther(volumeResult));
        console.log(
          "  - Token balance (ether):",
          formatEther(tokenBalanceResult)
        );
        console.log("  - Reward token address:", rewardTokenInfo.tokenAddress);
        console.log(
          "  - Rate per point (wei):",
          rewardTokenInfo.ratePerPoint.toString()
        );

        // Calculate potential reward (similar to simulate-trades.ts)
        let potentialRewardAmount: bigint | null = null;
        if (
          rewardTokenInfo.tokenAddress !==
            "0x0000000000000000000000000000000000000000" &&
          pointsResult > BigInt(0)
        ) {
          console.log("💰 Calculating potential reward...");

          // Calculate reward: points * ratePerPoint (both in wei)
          potentialRewardAmount =
            (pointsResult * rewardTokenInfo.ratePerPoint) / BigInt(10 ** 18);

          console.log("  - Points (wei):", pointsResult.toString());
          console.log(
            "  - Rate per point (wei):",
            rewardTokenInfo.ratePerPoint.toString()
          );
          console.log("  - Calculation: points * rate");
          console.log(
            "  - Potential reward (wei):",
            potentialRewardAmount.toString()
          );
          console.log(
            "  - Potential reward (ether):",
            formatEther(potentialRewardAmount)
          );
        } else {
          console.log("⚠️ No reward calculation:");
          console.log(
            "  - Reward configured:",
            rewardTokenInfo.tokenAddress !==
              "0x0000000000000000000000000000000000000000"
          );
          console.log("  - Has points:", pointsResult > BigInt(0));
        }

        console.log("✅ Data fetch completed successfully");

        setPoints(pointsResult);
        setVolume(volumeResult);
        setRewardInfo(rewardTokenInfo);
        setPotentialReward(potentialRewardAmount);
        setTokenBalance(tokenBalanceResult);
      } catch (err) {
        console.error("❌ Error fetching data:", err);
        console.log("Error details:", {
          name: (err as Error).name,
          message: (err as Error).message,
          stack: (err as Error).stack,
        });
        setError("Error fetching data or user not registered");
        setPoints(null);
        setVolume(null);
        setRewardInfo(null);
        setPotentialReward(null);
        setTokenBalance(null);
      } finally {
        setLoading(false);
        console.log("🏁 Data fetch process completed");
      }
    };

    fetchData();
  }, [userAddress, transactionCount, CONTRACT_ADDRESS, TOKEN_ADDRESS]);

  // Refresh data when transaction is confirmed
  useEffect(() => {
    if (isConfirmed) {
      // Refresh data after successful claim
      setTimeout(() => {
        // Trigger a refetch by updating transaction count
        window.location.reload(); // Simple approach, or you could trigger the fetch manually
      }, 2000);
    }
  }, [isConfirmed]);

  useEffect(() => {
    if (writeError) {
      console.error("Write contract error:", writeError);
      setError(`Transaction failed: ${writeError.message}`);
    }
  }, [writeError]);

  const handleClaimReward = async () => {
    console.log("🚀 Starting claim reward process...");
    console.log("User address:", userAddress);
    console.log("Points (wei):", points?.toString());
    console.log("Volume (wei):", volume?.toString());
    console.log("Potential reward (wei):", potentialReward?.toString());
    console.log("Contract address:", CONTRACT_ADDRESS);
    console.log("Token address:", TOKEN_ADDRESS);

    if (
      !userAddress ||
      points === null ||
      points === BigInt(0) ||
      volume === null ||
      volume === BigInt(0) ||
      !CONTRACT_ADDRESS ||
      !TOKEN_ADDRESS ||
      !potentialReward ||
      potentialReward === BigInt(0)
    ) {
      const errorMsg =
        "Cannot claim: insufficient points, volume, or no reward configured";
      console.error("❌ Pre-flight check failed:", errorMsg);
      console.log("Pre-flight check details:", {
        userAddress: !!userAddress,
        points: points?.toString(),
        volume: volume?.toString(),
        potentialReward: potentialReward?.toString(),
        CONTRACT_ADDRESS: !!CONTRACT_ADDRESS,
        TOKEN_ADDRESS: !!TOKEN_ADDRESS,
      });
      setError(errorMsg);
      return;
    }

    // Check if user has enough ETH for gas (0.01 ETH minimum)
    const userBalance = balance ? parseFloat(formatEther(balance.value)) : 0;
    console.log("User ETH balance:", userBalance);

    if (balance && userBalance < 0.01) {
      const errorMsg = "Insufficient ETH balance for gas fees";
      console.error("❌ Insufficient gas:", errorMsg);
      console.log("Required: 0.01 ETH, Available:", userBalance);
      setError(errorMsg);
      return;
    }

    try {
      setError(null); // Clear previous errors
      console.log("✅ Pre-flight checks passed, initiating transaction...");

      // Log reward info details (similar to simulate-trades.ts)
      if (rewardInfo) {
        console.log("💰 Reward Info:");
        console.log("  - Reward token address:", rewardInfo.tokenAddress);
        console.log(
          "  - Rate per point (wei):",
          rewardInfo.ratePerPoint.toString()
        );
        console.log(
          "  - Rate per point (ether):",
          formatEther(rewardInfo.ratePerPoint)
        );
        console.log("  - Expected reward (wei):", potentialReward.toString());
        console.log(
          "  - Expected reward (ether):",
          formatEther(potentialReward)
        );
      }

      // Check pre-claim token balance
      if (tokenBalance !== null) {
        console.log(
          "  - Token balance before claim (ether):",
          formatEther(tokenBalance)
        );
      }

      // Prepare transaction parameters
      const args: [Address] = [TOKEN_ADDRESS];
      const txParams = {
        address: CONTRACT_ADDRESS,
        abi: STREAMFUND_ABI,
        functionName: "claimReward" as const,
        args,
        gas: BigInt(100000), // Set a reasonable gas limit
      };

      console.log("📝 Transaction parameters:", txParams);
      console.log("Gas limit set to:", txParams.gas.toString());

      // Execute the transaction
      console.log("📤 Sending transaction...");
      writeContract(txParams);

      console.log("✅ Transaction sent successfully!");
      console.log("Waiting for confirmation...");
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
    } catch (err: any) {
      console.error("❌ Error claiming reward:", err);

      // Detailed error logging (same as simulate-trades.ts)
      console.log("Error details:", {
        name: err.name,
        message: err.message,
        code: err.code,
        cause: err.cause,
        stack: err.stack,
      });

      // Check for specific error types
      if (err.message?.includes("User rejected")) {
        console.log("🚫 User rejected the transaction");
        setError("Transaction was rejected by user");
      } else if (err.message?.includes("insufficient funds")) {
        console.log("💸 Insufficient funds for gas");
        setError("Insufficient funds for gas fees");
      } else if (err.message?.includes("execution reverted")) {
        console.log("🔄 Transaction reverted by contract");
        setError("Transaction reverted - check contract conditions");
      } else {
        console.log("🤷 Unknown error occurred");
        setError("Error claiming reward. Please try again.");
      }
    }
  };

  // Add logging for transaction state changes
  useEffect(() => {
    if (isPending) {
      console.log("⏳ Transaction is pending...");
    }
  }, [isPending]);

  useEffect(() => {
    if (isConfirming) {
      console.log("🔍 Transaction is confirming...");
    }
  }, [isConfirming]);

  useEffect(() => {
    if (isConfirmed && hash) {
      console.log("✅ Transaction confirmed!");
      console.log("Transaction hash:", hash);
      console.log("Refreshing data in 2 seconds...");
    }
  }, [isConfirmed, hash]);

  useEffect(() => {
    if (writeError) {
      console.error("📝 Write contract error:", writeError);
      console.log("Write error details:", {
        name: writeError.name,
        message: writeError.message,
        cause: writeError.cause,
      });
      setError(`Transaction failed: ${writeError.message}`);
    }
  }, [writeError]);

  const progressPercentage =
    points !== null
      ? Math.min((Number(formatEther(points)) / 80) * 100, 100)
      : 0;

  const isClaimDisabled =
    isPending ||
    isConfirming ||
    points === null ||
    points === BigInt(0) ||
    volume === null ||
    volume === BigInt(0) ||
    potentialReward === null ||
    potentialReward === BigInt(0) ||
    loading;

  const isRewardConfigured =
    rewardInfo?.tokenAddress !== "0x0000000000000000000000000000000000000000";

  return (
    <Card className="w-full">
      <CardHeader className="py-3">
        <CardTitle>Help me buy Lambo 💀🔫</CardTitle>
      </CardHeader>
      <CardContent className="p-4">
        {loading ? (
          <p className="text-gray-500">Loading points...</p>
        ) : error ? (
          <p className="text-red-500">{error}</p>
        ) : points !== null ? (
          <div>
            <div className="flex justify-between text-sm mb-2">
              <span>
                Progress: {parseFloat(formatEther(points)).toFixed(6)} / 80.0
                points
              </span>
              <span>{progressPercentage.toFixed(1)}%</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-4 mb-2">
              <div
                className="bg-blue-500 h-4 rounded-full transition-all duration-300"
                style={{ width: `${progressPercentage}%` }}
              ></div>
            </div>
            {volume !== null && (
              <div className="text-xs text-gray-600 mb-2">
                Referral Volume: {parseFloat(formatEther(volume)).toFixed(6)}{" "}
                ETH
              </div>
            )}

            {/* Reward Information */}
            <div className="mt-3 p-2 bg-gray-50 rounded-lg">
              {isRewardConfigured ? (
                <div>
                  <div className="text-sm font-medium text-gray-700 mb-1">
                    Reward Estimation:
                  </div>
                  <div className="text-lg font-bold text-green-600">
                    {potentialReward !== null
                      ? parseFloat(formatUnits(potentialReward, 18)).toFixed(6)
                      : "0.000000"}{" "}
                    tokens
                  </div>
                  <div className="text-xs text-gray-500">
                    Rate:{" "}
                    {rewardInfo
                      ? formatUnits(rewardInfo.ratePerPoint, 18)
                      : "0"}{" "}
                    tokens per point
                  </div>
                </div>
              ) : (
                <div className="text-sm text-amber-600">
                  ⚠️ No reward token configured for this trading pair
                </div>
              )}
            </div>
          </div>
        ) : (
          <p className="text-gray-500">No points data available.</p>
        )}

        <div
          className={cn("flex w-full h-fit items-center justify-center mt-4")}
        >
          <Button onClick={handleClaimReward} disabled={isClaimDisabled}>
            {isPending
              ? "Confirming..."
              : isConfirming
              ? "Claiming..."
              : potentialReward && potentialReward > BigInt(0)
              ? `Claim ${parseFloat(formatUnits(potentialReward, 18)).toFixed(
                  6
                )} tokens!`
              : `Claim now! (${
                  points ? parseFloat(formatEther(points)).toFixed(6) : 0
                } points)`}
          </Button>
        </div>

        {!isRewardConfigured && rewardInfo && (
          <div className="mt-2 text-xs text-amber-600 bg-amber-50 p-2 rounded">
            Rewards are not configured for this token. Contact the administrator
            to set up reward distribution.
          </div>
        )}

        {hash && (
          <div className="mt-2 text-sm text-gray-600">
            <p className="break-all">Transaction Hash: {hash}</p>
            {isConfirming && <p>Waiting for confirmation...</p>}
            {isConfirmed && (
              <p className="text-green-600">Transaction confirmed!</p>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
