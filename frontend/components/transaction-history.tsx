"use client";

import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default function TransactionsHistory() {
  // Dummy transactions for demonstration
  const [transactions] = useState([
    {
      id: 1,
      type: "Buy",
      user: "0x1234...5678",
      amount: "0.5 ETH",
      time: "5m ago",
    },
    {
      id: 2,
      type: "Sell",
      user: "0xabcd...ef01",
      amount: "0.2 ETH",
      time: "7m ago",
    },
    {
      id: 3,
      type: "Buy",
      user: "0x9876...5432",
      amount: "1.0 ETH",
      time: "15m ago",
    },
  ]);

  return (
    <Card className="w-full h-full">
      <CardHeader className="py-3">
        <CardTitle>Transactions Buy/Sell</CardTitle>
      </CardHeader>
      <CardContent className="p-0">
        <div className="space-y-2 max-h-[120px] overflow-y-auto p-4">
          {transactions.map((tx) => (
            <div
              key={tx.id}
              className={`flex justify-between items-center p-2 rounded ${
                tx.type === "Buy" ? "bg-green-100" : "bg-red-100"
              }`}
            >
              <div>
                <span className="font-medium">{tx.type}</span> by {tx.user}
              </div>
              <div className="flex items-center gap-2">
                <span className="font-medium">{tx.amount}</span>
                <span className="text-xs text-gray-500">{tx.time}</span>
              </div>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
