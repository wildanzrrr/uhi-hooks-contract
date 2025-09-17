import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { anvil } from "viem/chains";
import { cookieStorage, createStorage, http } from "wagmi";

export const wagmiConfig = getDefaultConfig({
  appName: "StreamFund",
  projectId: process.env.NEXT_PUBLIC_PROJECT_ID!,
  chains: [anvil],
  storage: createStorage({
    storage: cookieStorage,
  }),
  transports: {
    [anvil.id]: http("http://127.0.0.1:8545"), // Explicit URL for anvil
  },
});
