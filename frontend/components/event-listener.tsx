"use client";

import { useEffect, useRef } from "react";
import { toast } from "sonner";
import { Address, createPublicClient, http } from "viem";

interface ToastQueueItem {
  id: string;
  type: "buy" | "sell";
  user: Address;
  amount: string;
  timestamp: number;
}

export default function EventListener() {
  const toastQueueRef = useRef<ToastQueueItem[]>([]);
  const isProcessingRef = useRef(false);
  const currentToastRef = useRef<string | number | null>(null);

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

    // Toast queue management
    const addToQueue = (item: ToastQueueItem) => {
      toastQueueRef.current.push(item);
      processQueue();
    };

    const processQueue = async () => {
      if (isProcessingRef.current || toastQueueRef.current.length === 0) {
        return;
      }

      isProcessingRef.current = true;

      while (toastQueueRef.current.length > 0) {
        // Check if this is the last item BEFORE taking it
        const isLastItem = toastQueueRef.current.length === 1;

        // Take from the beginning of queue (FIFO - First In First Out)
        const item = toastQueueRef.current.shift()!;

        // Dismiss current toast if exists
        if (currentToastRef.current) {
          toast.dismiss(currentToastRef.current);
        }

        // Show new toast with custom styling
        const toastId =
          item.type === "buy"
            ? toast("💰 New Buy Transaction", {
                description: `User ${formatAddress(
                  item.user
                )} bought with ${formatAmount(item.amount)} ETH`,
                style: {
                  background: "#10b981", // green background
                  color: "white",
                  border: "1px solid #059669",
                },
              })
            : toast("📉 New Sell Transaction", {
                description: `User ${formatAddress(
                  item.user
                )} sold for ${formatAmount(item.amount)} ETH`,
                style: {
                  background: "#ef4444", // red background
                  color: "white",
                  border: "1px solid #dc2626",
                },
              });

        currentToastRef.current = toastId;

        // Display time: 3 seconds for last item, 0.5 seconds for others
        const displayTime = isLastItem ? 3000 : 500;

        // Wait for the display duration
        await new Promise((resolve) => setTimeout(resolve, displayTime));
      }

      isProcessingRef.current = false;
      currentToastRef.current = null;
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
          console.log("BUYY", args);

          addToQueue({
            id: `buy-${Date.now()}-${Math.random()}`,
            type: "buy",
            user: args.user as Address,
            amount: args.amountA!.toString(),
            timestamp: Date.now(),
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
          console.log("SELL", args);

          addToQueue({
            id: `sell-${Date.now()}-${Math.random()}`,
            type: "sell",
            user: args.user as Address,
            amount: args.amountB!.toString(),
            timestamp: Date.now(),
          });
        }
      },
    });

    // Cleanup function
    return () => {
      buyUnwatch();
      sellUnwatch();
      // Clear any remaining toasts
      if (currentToastRef.current) {
        toast.dismiss(currentToastRef.current);
      }
      toastQueueRef.current = [];
      isProcessingRef.current = false;
    };
  }, []);

  return null;
}
