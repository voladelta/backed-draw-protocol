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
        aria-label={`Disconnect wallet ${compactAddress(address)}`}
        className="wallet-button wallet-connected"
        onClick={() => disconnect()}
        title="Disconnect wallet"
      >
        <span className="wallet-status">
          <Check aria-hidden size={12} />
        </span>
        {compactAddress(address)}
        <LogOut aria-hidden className="wallet-hover-icon" size={14} />
      </button>
    )
  }

  return (
    <button
      className="wallet-button"
      disabled={!connector || isPending}
      onClick={() => connector && connect({ connector })}
    >
      <Wallet aria-hidden size={15} />
      {isPending ? "Opening…" : "Connect"}
      <ChevronDown aria-hidden size={13} />
    </button>
  )
}
