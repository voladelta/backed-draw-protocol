import type { PropsWithChildren } from "react"
import { QueryClientProvider } from "@tanstack/react-query"
import { WagmiProvider } from "wagmi"
import { queryClient, wagmiConfig } from "./config"

export function Web3Provider({ children }: PropsWithChildren) {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  )
}
