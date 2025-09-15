"use client";

import { useEffect } from "react";
import { toast, Toaster } from "sonner";
import { Address, createPublicClient, http } from "viem";

export default function EventListener() {
  useEffect(() => {
    // Get the environment variables
    const RPC_URL =
      process.env.NEXT_PUBLIC_RPC_URL || "https://ethereum.publicnode.com";
    const CONTRACT_ADDRESS = process.env
      .NEXT_PUBLIC_STREAMFUND_ADDRESS as Address;

    // Exit if no contract address
    if (!CONTRACT_ADDRESS) {
      console.error(
        "StreamFund contract address not provided in environment variables"
      );
      return;
    }

    // Create viem public client
    const client = createPublicClient({
      transport: http(RPC_URL),
    });

    // Function to format addresses and amounts for display
    const formatAddress = (address: Address) => {
      return `${address.slice(0, 6)}...${address.slice(-4)}`;
    };

    const formatAmount = (amount: string) => {
      // Convert to ETH and format
      const ethAmount = Number(amount) / 1e18;
      return ethAmount.toFixed(4);
    };

    // Set up event listeners
    const buyUnwatch = client.watchEvent({
      address: CONTRACT_ADDRESS,
      event: {
        type: "event",
        name: "Buy",
        inputs: [
          { type: "address", name: "user", indexed: true },
          { type: "address", name: "referral", indexed: true },
          { type: "address", name: "tokenA" },
          { type: "address", name: "tokenB" },
          { type: "uint256", name: "amountA" },
          { type: "uint256", name: "amountB" },
        ],
      },
      onLogs: (logs) => {
        for (const log of logs) {
          const { args } = log;
          toast.success("New Buy Transaction", {
            description: `User ${formatAddress(
              args.user as Address
            )} bought with ${formatAmount(args.amountA!.toString())} ETH`,
          });
        }
      },
    });

    const sellUnwatch = client.watchEvent({
      address: CONTRACT_ADDRESS,
      event: {
        type: "event",
        name: "Sell",
        inputs: [
          { type: "address", name: "user", indexed: true },
          { type: "address", name: "referral", indexed: true },
          { type: "address", name: "tokenA" },
          { type: "address", name: "tokenB" },
          { type: "uint256", name: "amountA" },
          { type: "uint256", name: "amountB" },
        ],
      },
      onLogs: (logs) => {
        for (const log of logs) {
          const { args } = log;
          toast.error("New Sell Transaction", {
            description: `User ${formatAddress(
              args.user as Address
            )} sold for ${formatAmount(args.amountB!.toString())} ETH`,
          });
        }
      },
    });

    // Cleanup function
    return () => {
      buyUnwatch();
      sellUnwatch();
    };
  }, []);

  return <Toaster position="top-center" />;
}
