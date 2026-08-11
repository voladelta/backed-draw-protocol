import { useAccount, useConnect, useDisconnect } from "wagmi"
import { Check, ChevronDown, LogOut, Wallet } from "lucide-react"
import { compactAddress } from "@/lib/utils"

export function WalletButton() {
  const { address, isConnected } = useAccount()
  const { connectors, connect, isPending } = useConnect()
  const { disconnect } = useDisconnect()
  const connector = connectors[0]

  if (isConnected) {
    return (
      <button
        className="wallet-button wallet-connected"
        onClick={() => disconnect()}
        title="Disconnect wallet"
      >
        <span className="wallet-status">
          <Check size={12} />
        </span>
        {compactAddress(address)}
        <LogOut className="wallet-hover-icon" size={14} />
      </button>
    )
  }

  return (
    <button
      className="wallet-button"
      disabled={!connector || isPending}
      onClick={() => connector && connect({ connector })}
    >
      <Wallet size={15} />
      {isPending ? "Opening…" : "Connect"}
      <ChevronDown size={13} />
    </button>
  )
}
