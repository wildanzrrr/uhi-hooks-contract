"use client";

import { wagmiConfig } from "@/config/wagmi";
import React from "react";
import { cookieToInitialState, WagmiProvider } from "wagmi";
import { RainbowKitProvider as NextRainbowKitProvider } from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";
import QueryProvider from "./query";

interface RainbowKitProviderProps {
  children: React.ReactNode;
  cookie: string;
}

const RainbowKitProvider = ({ children, cookie }: RainbowKitProviderProps) => {
  const initialState = cookieToInitialState(wagmiConfig, cookie);
  const customTheme = {
    colors: {
      accentColor: "hsl(291 100% 71%)",
      accentColorForeground: "hsl(225, 0%, 0%)",
      actionButtonBorder: "hsl(0, 0%, 100%)",
      actionButtonBorderMobile: "hsl(0, 0%, 100%)",
      actionButtonSecondaryBackground: "hsl(225, 0%, 0%)",
      closeButton: "hsl(180, 3%, 39%)",
      closeButtonBackground: "hsl(0, 0%, 94%)",
      connectButtonBackground: "hsl(0, 0%, 100%)",
      connectButtonBackgroundError: "hsl(360,100%,64%)",
      connectButtonInnerBackground: "hsl(0, 0%, 95%)",
      connectButtonText: "hsl(225, 0%, 0%)",
      connectButtonTextError: "hsl(0,0%,100%)",
      error: "hsl(0,0%,100%)",
      generalBorder: "hsl(180, 0%, 94%)",
      generalBorderDim: "rgba(0, 0, 0, 0.03)",
      menuItemBackground: "hsl(180, 3%, 92%)",
      modalBackdrop: "rgba(0, 0, 0, 0.5)",
      modalBackground: "hsl(0, 0%, 100%)",
      modalBorder: "hsl(0, 0%, 100%)",
      modalText: "hsl(213, 11%, 16%)",
      modalTextDim: "rgba(60, 66, 66, 0.3)",
      modalTextSecondary: "hsl(200, 1%, 55%)",
      profileAction: "hsl(0, 0%, 100%)",
      profileActionHover: "hsl(0, 0%, 98%)",
      profileForeground: "hsl(0, 0%, 96%)",
      selectedOptionBorder: "hsl(291 100% 71%)",
      downloadBottomCardBackground:
        '"linear-gradient(126deg, rgba(255, 255, 255, 0) 9.49%, rgba(171, 171, 171, 0.04) 71.04%), #FFFFFF"',
      downloadTopCardBackground:
        '"linear-gradient(126deg, rgba(171, 171, 171, 0.2) 9.49%, rgba(255, 255, 255, 0) 71.04%), #FFFFFF"',
      connectionIndicator: "hsl(107, 100%, 44%)",
      standby: "hsl(47, 100%, 63%)",
    },
    radii: {
      actionButton: "9999px",
      connectButton: "12px",
      menuButton: "12px",
      modal: "24px",
      modalMobile: "24px",
    },
    shadows: {
      connectButton: "0px 8px 32px rgba(0, 0, 0, 0.32)",
      dialog: "0px 8px 32px rgba(0, 0, 0, 0.32)",
      profileDetailsAction: "0px 2px 6px rgba(37, 41, 46, 0.04)",
      selectedOption: "0px 2px 6px rgba(0, 0, 0, 0.24)",
      selectedWallet: "0px 2px 6px rgba(0, 0, 0, 0.12)",
      walletLogo: "0px 2px 16px rgba(0, 0, 0, 0.16)",
    },
    blurs: {
      modalOverlay: "blur(0px)", // e.g. 'blur(4px)'
    },
    fonts: {
      body: "...", // default
    },
  };

  return (
    <WagmiProvider config={wagmiConfig} initialState={initialState}>
      <QueryProvider>
        <NextRainbowKitProvider theme={customTheme}>
          {children}
        </NextRainbowKitProvider>
      </QueryProvider>
    </WagmiProvider>
  );
};

export default RainbowKitProvider;
