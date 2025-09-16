import { create } from "zustand";

export interface Transaction {
  id: string;
  type: "buy" | "sell";
  user: string; // Formatted address (e.g., "0x1234...5678")
  amount: string; // Formatted amount (e.g., "0.5 ETH")
  timestamp: number; // Unix timestamp
}

interface TransactionsState {
  transactions: Transaction[];
  transactionCount: number; // New: Track transaction count for reactivity
  addTransaction: (transaction: Transaction) => void;
}

export const useTransactionsStore = create<TransactionsState>((set) => ({
  transactions: [],
  transactionCount: 0,
  addTransaction: (transaction) =>
    set((state) => ({
      transactions: [transaction, ...state.transactions], // Add to the beginning for latest-first display
      transactionCount: state.transactionCount + 1, // Increment on new transaction
    })),
}));
