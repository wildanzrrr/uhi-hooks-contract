"use client";

import { useEffect, useState } from "react";
import { createPublicClient, http, Address } from "viem";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useTransactionsStore } from "@/stores/transaction";
import { cn } from "@/lib/utils";
import { Button } from "./ui/button";

// ABI snippet for getStreamerPoints (from StreamFund.sol)
const STREAMFUND_ABI = [
  {
    inputs: [
      { internalType: "address", name: "streamerAddress", type: "address" },
    ],
    name: "getStreamerPoints",
    outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "claimReward",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

interface StreamerPointsProps {
  userAddress: Address | undefined; // Pass the connected user's address
}

export default function StreamerPoints({ userAddress }: StreamerPointsProps) {
  const [points, setPoints] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { transactionCount } = useTransactionsStore(); // Get transaction count for reactivity

  const CONTRACT_ADDRESS = process.env
    .NEXT_PUBLIC_STREAMFUND_ADDRESS as Address;

  // Use wagmi hooks for contract interaction
  const { writeContract, data: hash, isPending } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed } =
    useWaitForTransactionReceipt({
      hash,
    });

  const TARGET_POINTS = 80; // Fixed target

  useEffect(() => {
    if (!userAddress) {
      setPoints(null);
      setError("No user address provided");
      return;
    }

    const fetchPoints = async () => {
      setLoading(true);
      setError(null);

      try {
        const RPC_URL =
          process.env.NEXT_PUBLIC_RPC_URL || "https://ethereum.publicnode.com";

        if (!CONTRACT_ADDRESS) {
          throw new Error("StreamFund contract address not provided");
        }

        const client = createPublicClient({
          transport: http(RPC_URL),
        });

        const result = await client.readContract({
          address: CONTRACT_ADDRESS,
          abi: STREAMFUND_ABI,
          functionName: "getStreamerPoints",
          args: [userAddress],
        });

        console.log("result", result);

        setPoints(Number(result / BigInt(10) ** BigInt(18))); // Convert BigInt to number (points are whole numbers, no decimals)
      } catch (err) {
        console.error("Error fetching points:", err);
        setError("Error fetching points or user not registered");
        setPoints(null);
      } finally {
        setLoading(false);
      }
    };

    fetchPoints();
  }, [userAddress, transactionCount, CONTRACT_ADDRESS]); // Add transactionCount to dependencies

  // Refresh points when transaction is confirmed
  useEffect(() => {
    if (isConfirmed) {
      // Refresh points after successful claim
      setTimeout(() => {
        setPoints(0); // Reset points immediately for better UX
      }, 1000);
    }
  }, [isConfirmed]);

  const handleClaimReward = async () => {
    if (!userAddress || points === null || points === 0 || !CONTRACT_ADDRESS) {
      return;
    }

    try {
      writeContract({
        address: CONTRACT_ADDRESS,
        abi: STREAMFUND_ABI,
        functionName: "claimReward",
      });
    } catch (err) {
      console.error("Error claiming reward:", err);
      setError("Error claiming reward. Please try again.");
    }
  };

  const progressPercentage =
    points !== null ? Math.min((points / TARGET_POINTS) * 100, 100) : 0;

  const isClaimDisabled =
    isPending || isConfirming || points === null || points === 0 || loading;

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
                Progress: {points} / {TARGET_POINTS} points
              </span>
              <span>{progressPercentage.toFixed(0)}%</span>
            </div>
            <div className="w-full bg-gray-200 rounded-full h-4">
              <div
                className="bg-blue-500 h-4 rounded-full transition-all duration-300"
                style={{ width: `${progressPercentage}%` }}
              ></div>
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
              : "Claim now!"}
          </Button>
        </div>

        {hash && (
          <div className="mt-2 text-sm text-gray-600">
            <p>Transaction Hash: {hash}</p>
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
