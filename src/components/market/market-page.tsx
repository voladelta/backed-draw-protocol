import { ArrowUpRight, ShieldCheck } from "lucide-react"
import type { Market } from "@/types/protocol"
import { formatValue } from "@/lib/utils"

/** Kept as a typed embeddable market detail for integrations outside the primary pull route. */
export function MarketPage({ market, onPull }: { market: Market; onPull: () => void }) {
  return (
    <main className="support-page">
      <p className="support-eyebrow">{market.asset} settlement pool</p>
      <h1>{market.name}</h1>
      <section className="market-detail">
        <img alt={market.crown} src={market.heroImage} />
        <div>
          <p>{market.description}</p>
          <strong>Pull price · {formatValue(market.pullPrice, market.asset)}</strong>
          <span>
            <ShieldCheck /> {market.activePositions} committed active positions
          </span>
          <button onClick={onPull} type="button">
            Pull this pool <ArrowUpRight />
          </button>
        </div>
      </section>
    </main>
  )
}
