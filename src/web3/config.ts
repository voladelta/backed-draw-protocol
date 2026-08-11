import { QueryClient } from "@tanstack/react-query"
import { createConfig, http } from "wagmi"
import { defineChain } from "viem"
import { injected, walletConnect } from "wagmi/connectors"

const chainId = Number(import.meta.env.VITE_CHAIN_ID ?? 46630)
const rpcUrl = import.meta.env.VITE_RPC_URL ?? "https://rpc.testnet.robinhoodchain.com"

export const robinhoodChain = defineChain({
  id: chainId,
  name: import.meta.env.VITE_CHAIN_NAME ?? "Robinhood Chain Testnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [rpcUrl] } },
  blockExplorers: {
    default: {
      name: "Robinhood Explorer",
      url: import.meta.env.VITE_EXPLORER_URL ?? "https://explorer.testnet.robinhoodchain.com",
    },
  },
  testnet: true,
})

const connectors = [injected()]
const walletConnectProjectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID
if (walletConnectProjectId) connectors.push(walletConnect({ projectId: walletConnectProjectId }))

export const wagmiConfig = createConfig({
  chains: [robinhoodChain],
  connectors,
  transports: { [robinhoodChain.id]: http(rpcUrl) },
  ssr: false,
})

export const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 15_000, retry: 1 } },
})
