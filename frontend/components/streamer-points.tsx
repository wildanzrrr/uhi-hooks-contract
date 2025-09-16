"use client";

import { useEffect, useState } from "react";
import { createPublicClient, http, Address } from "viem";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useTransactionsStore } from "@/stores/transaction";

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
] as const;

interface StreamerPointsProps {
  userAddress: Address | undefined; // Pass the connected user's address
}

export default function StreamerPoints({ userAddress }: StreamerPointsProps) {
  const [points, setPoints] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { transactionCount } = useTransactionsStore(); // Get transaction count for reactivity

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
        const CONTRACT_ADDRESS = process.env
          .NEXT_PUBLIC_STREAMFUND_ADDRESS as Address;

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
  }, [userAddress, transactionCount]); // Add transactionCount to dependencies

  const progressPercentage =
    points !== null ? Math.min((points / TARGET_POINTS) * 100, 100) : 0;

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
      </CardContent>
    </Card>
  );
}
