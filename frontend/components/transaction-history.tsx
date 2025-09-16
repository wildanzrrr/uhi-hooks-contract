"use client";

import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useTransactionsStore } from "@/stores/transaction";

// Utility to format timestamp as relative time (simple implementation)
const formatRelativeTime = (timestamp: number): string => {
  const now = Date.now();
  const diffMs = now - timestamp;
  const diffSeconds = Math.floor(diffMs / 1000);
  if (diffSeconds < 60) return `${diffSeconds}s ago`;
  const diffMins = Math.floor(diffSeconds / 60);
  if (diffMins < 60) return `${diffMins}m ago`;
  const diffHours = Math.floor(diffMins / 60);
  if (diffHours < 24) return `${diffHours}h ago`;
  const diffDays = Math.floor(diffHours / 24);
  return `${diffDays}d ago`;
};

export default function TransactionsHistory() {
  const { transactions } = useTransactionsStore(); // Get transactions from store
  const [, setTick] = useState(0); // State to trigger re-renders for time updates

  // Update every second to refresh relative times
  useEffect(() => {
    const interval = setInterval(() => {
      setTick((prev) => prev + 1);
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <Card className="w-full h-full">
      <CardHeader className="py-3">
        <CardTitle>Transactions Buy/Sell</CardTitle>
      </CardHeader>
      <CardContent className="p-0">
        <div className="space-y-2 max-h-[120px] overflow-y-auto p-4">
          {transactions.length === 0 ? (
            <p className="text-gray-500 text-center">No transactions yet.</p>
          ) : (
            transactions
              .slice(0, 10) // Limit to 10 for performance
              .map((tx) => (
                <div
                  key={tx.id}
                  className="flex justify-between items-center p-2 rounded"
                  style={{
                    backgroundColor: tx.type === "buy" ? "#10b981" : "#ef4444",
                    border: `1px solid ${
                      tx.type === "buy" ? "#059669" : "#dc2626"
                    }`,
                    color: "white", // Match toast text color for contrast
                  }}
                >
                  <div>
                    <span className="font-medium">
                      {tx.type === "buy" ? "Buy" : "Sell"}
                    </span>{" "}
                    by {tx.user}
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{tx.amount}</span>
                    <span className="text-xs opacity-75">
                      {formatRelativeTime(tx.timestamp)}
                    </span>
                  </div>
                </div>
              ))
          )}
        </div>
      </CardContent>
    </Card>
  );
}
