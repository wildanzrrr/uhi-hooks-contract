"use client";

import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useState, useEffect } from "react";
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from "wagmi";
import { parseEther, formatEther, Address } from "viem";
import { toast } from "sonner";
import { ethers } from "ethers";

// ABI for swap router and ERC20
const SWAP_ROUTER_ABI = [
  {
    inputs: [
      {
        components: [
          { name: "currency0", type: "address" },
          { name: "currency1", type: "address" },
          { name: "fee", type: "uint24" },
          { name: "tickSpacing", type: "int24" },
          { name: "hooks", type: "address" },
        ],
        name: "poolKey",
        type: "tuple",
      },
      {
        components: [
          { name: "zeroForOne", type: "bool" },
          { name: "amountSpecified", type: "int256" },
          { name: "sqrtPriceLimitX96", type: "uint160" },
        ],
        name: "params",
        type: "tuple",
      },
      {
        components: [
          { name: "takeClaims", type: "bool" },
          { name: "settleUsingBurn", type: "bool" },
        ],
        name: "testSettings",
        type: "tuple",
      },
      { name: "hookData", type: "bytes" },
    ],
    name: "swap",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
] as const;

const ERC20_ABI = [
  {
    inputs: [{ name: "owner", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

export default function BuySellWidget() {
  const [buyAmount, setBuyAmount] = useState("");
  const [sellAmount, setSellAmount] = useState("");
  const [isApproving, setIsApproving] = useState(false);

  const { address } = useAccount();

  // Contract addresses from env
  const SWAP_ROUTER = process.env.NEXT_PUBLIC_SWAP_ROUTER as Address;
  const STREAMFUND_HOOK = process.env.NEXT_PUBLIC_STREAMFUND_ADDRESS as Address;
  const MOCK_TOKEN = process.env.NEXT_PUBLIC_MOCK_TOKEN as Address;
  const POOL_CURRENCY0 = process.env.NEXT_PUBLIC_POOL_CURRENCY0 as Address;
  const POOL_CURRENCY1 = process.env.NEXT_PUBLIC_POOL_CURRENCY1 as Address;

  // Debug: Log environment variables
  console.log("Environment variables:", {
    SWAP_ROUTER,
    STREAMFUND_HOOK,
    MOCK_TOKEN,
    POOL_CURRENCY0,
    POOL_CURRENCY1,
  });

  // Pool key configuration
  const poolKey = {
    currency0: POOL_CURRENCY0,
    currency1: POOL_CURRENCY1,
    fee: 3000,
    tickSpacing: 60,
    hooks: STREAMFUND_HOOK,
  };

  // Contract write hooks
  const {
    writeContract: executeSwap,
    data: swapHash,
    isPending: swapPending,
    error: swapError,
  } = useWriteContract();
  const {
    writeContract: executeApproval,
    data: approvalHash,
    isPending: approvalPending,
  } = useWriteContract();

  // Transaction receipt hooks
  const { isLoading: swapConfirming, isSuccess: swapSuccess } =
    useWaitForTransactionReceipt({ hash: swapHash });
  const { isLoading: approvalConfirming, isSuccess: approvalSuccess } =
    useWaitForTransactionReceipt({ hash: approvalHash });

  // Read token balance
  const { data: tokenBalance, refetch: refetchBalance } = useReadContract({
    address: MOCK_TOKEN,
    abi: ERC20_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
  });

  // Debug: Log swap error
  useEffect(() => {
    if (swapError) {
      console.error("Swap error:", swapError);
      toast.error(`Swap failed: ${swapError.message}`);
    }
  }, [swapError]);

  // Refetch balance after successful transactions
  useEffect(() => {
    if (swapSuccess || approvalSuccess) {
      refetchBalance();
      if (swapSuccess) {
        setBuyAmount("");
        setSellAmount("");
        toast.success("Transaction completed successfully!");
      }
    }
  }, [swapSuccess, approvalSuccess, refetchBalance]);

  const handleBuy = async () => {
    console.log("handleBuy called"); // Debug log

    if (!address || !buyAmount || parseFloat(buyAmount) <= 0) {
      toast.error("Please enter a valid amount");
      return;
    }

    // Check if all required environment variables are present
    if (
      !SWAP_ROUTER ||
      !STREAMFUND_HOOK ||
      !POOL_CURRENCY0 ||
      !POOL_CURRENCY1
    ) {
      toast.error("Missing contract configuration");
      console.error("Missing environment variables:", {
        SWAP_ROUTER,
        STREAMFUND_HOOK,
        POOL_CURRENCY0,
        POOL_CURRENCY1,
      });
      return;
    }

    try {
      const amountWei = parseEther(buyAmount);
      console.log("Amount in wei:", amountWei.toString()); // Debug log

      // Encode hook data with user's address as referral
      const hookData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address"],
        ["0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"]
      );
      console.log("Hook data:", hookData); // Debug log

      console.log("Executing swap with:", {
        address: SWAP_ROUTER,
        poolKey,
        value: amountWei.toString(),
      }); // Debug log

      executeSwap({
        address: SWAP_ROUTER,
        abi: SWAP_ROUTER_ABI,
        functionName: "swap",
        args: [
          poolKey,
          {
            zeroForOne: true,
            amountSpecified: -amountWei, // Negative for exact input
            sqrtPriceLimitX96: BigInt("4295128739") + BigInt(1), // Min price limit
          },
          {
            takeClaims: false,
            settleUsingBurn: false,
          },
          hookData as `0x${string}`,
        ],
        value: amountWei,
      });
    } catch (error) {
      console.error("Buy error:", error);
      toast.error("Failed to execute buy transaction");
    }
  };

  const handleSell = async () => {
    if (!address || !sellAmount || parseFloat(sellAmount) <= 0) {
      toast.error("Please enter a valid amount");
      return;
    }

    try {
      const amountWei = parseEther(sellAmount);

      // Check if we need to approve first
      setIsApproving(true);

      // Approve tokens for swap router
      executeApproval({
        address: MOCK_TOKEN,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [SWAP_ROUTER, amountWei],
      });
    } catch (error) {
      console.error("Approval error:", error);
      toast.error("Failed to approve tokens");
      setIsApproving(false);
    }
  };

  // Execute sell after approval is confirmed
  useEffect(() => {
    if (approvalSuccess && isApproving && sellAmount) {
      executeSellAfterApproval();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [approvalSuccess, isApproving, sellAmount]);

  const executeSellAfterApproval = async () => {
    if (!address || !sellAmount) return;

    try {
      const amountWei = parseEther(sellAmount);

      // Encode hook data with user's address as referral
      const hookData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address"],
        ["0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"]
      );

      executeSwap({
        address: SWAP_ROUTER,
        abi: SWAP_ROUTER_ABI,
        functionName: "swap",
        args: [
          poolKey,
          {
            zeroForOne: false,
            amountSpecified: -amountWei, // Negative for exact input
            sqrtPriceLimitX96:
              BigInt("1461446703485210103287273052203988822378723970342") -
              BigInt(1), // Max price limit
          },
          {
            takeClaims: false,
            settleUsingBurn: false,
          },
          hookData as `0x${string}`,
        ],
      });

      setIsApproving(false);
    } catch (error) {
      console.error("Sell error:", error);
      toast.error("Failed to execute sell transaction");
      setIsApproving(false);
    }
  };

  const maxTokenBalance = tokenBalance ? formatEther(tokenBalance) : "0";

  const isButtonDisabled =
    !address ||
    swapPending ||
    swapConfirming ||
    !buyAmount ||
    parseFloat(buyAmount) <= 0;

  console.log("Button disabled state:", {
    address: !!address,
    swapPending,
    swapConfirming,
    buyAmount,
    parseFloat: parseFloat(buyAmount) <= 0,
    isButtonDisabled,
  });

  return (
    <Card className="w-full h-full">
      <CardHeader className="py-3">
        <CardTitle>APE Now, Think Later 📈</CardTitle>
      </CardHeader>
      <CardContent>
        <Tabs defaultValue="buy" className="w-full">
          <TabsList className="grid grid-cols-2 mb-4">
            <TabsTrigger value="buy">Buy</TabsTrigger>
            <TabsTrigger value="sell">Sell</TabsTrigger>
          </TabsList>
          <TabsContent value="buy">
            <div className="space-y-4">
              <div>
                <Label htmlFor="buyAmount">Amount (ETH)</Label>
                <Input
                  id="buyAmount"
                  placeholder="0.0"
                  type="number"
                  value={buyAmount}
                  onChange={(e) => setBuyAmount(e.target.value)}
                />
              </div>
              <div>
                <Label htmlFor="buyEstimated">Estimated Receive</Label>
                <Input id="buyEstimated" placeholder="~Tokens" disabled />
              </div>
              <Button
                className="w-full bg-green-600 hover:bg-green-700"
                onClick={() => {
                  console.log("Button clicked!"); // Debug log
                  handleBuy();
                }}
                disabled={isButtonDisabled}
              >
                {swapPending || swapConfirming ? "Processing..." : "Buy Token"}
              </Button>
            </div>
          </TabsContent>
          <TabsContent value="sell">
            <div className="space-y-4">
              <div>
                <Label htmlFor="sellAmount">Amount (Token)</Label>
                <div className="flex gap-2">
                  <Input
                    id="sellAmount"
                    placeholder="0.0"
                    type="number"
                    value={sellAmount}
                    onChange={(e) => setSellAmount(e.target.value)}
                  />
                  <Button
                    variant="noShadow"
                    size="sm"
                    onClick={() => setSellAmount(maxTokenBalance)}
                    disabled={!tokenBalance || tokenBalance === BigInt(0)}
                  >
                    Max
                  </Button>
                </div>
                <p className="text-xs text-gray-500 mt-1">
                  Balance: {maxTokenBalance} tokens
                </p>
              </div>
              <div>
                <Label htmlFor="sellEstimated">Estimated Receive (ETH)</Label>
                <Input id="sellEstimated" placeholder="~ETH" disabled />
              </div>
              <Button
                className="w-full bg-red-600 hover:bg-red-700"
                onClick={handleSell}
                disabled={
                  !address ||
                  swapPending ||
                  swapConfirming ||
                  approvalPending ||
                  approvalConfirming ||
                  isApproving ||
                  !sellAmount ||
                  parseFloat(sellAmount) <= 0 ||
                  !tokenBalance ||
                  tokenBalance === BigInt(0)
                }
              >
                {approvalPending || approvalConfirming
                  ? "Approving..."
                  : swapPending || swapConfirming
                  ? "Processing..."
                  : "Sell Token"}
              </Button>
            </div>
          </TabsContent>
        </Tabs>

        <div className="flex w-full h-fit items-center justify-center mt-4">
          <ConnectButton />
        </div>
      </CardContent>
    </Card>
  );
}
