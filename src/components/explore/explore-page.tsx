import {
  ArrowRight,
  ChevronDown,
  CircleHelp,
  Search,
  ShieldCheck,
  WalletCards,
  type LucideIcon,
} from "lucide-react"
import type { ChangeEvent } from "react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

import { MarketCard } from "./market-card"
import type { MarketData, SettlementAsset } from "./types"

export interface ExplorePageProps {
  markets: MarketData[]
  activeAsset?: SettlementAsset | "all"
  searchValue?: string
  onAssetChange?: (asset: SettlementAsset | "all") => void
  onSearchChange?: (value: string) => void
  onPull?: (market: MarketData) => void
  onOpenMarket?: (market: MarketData) => void
  onDeposit?: () => void
  className?: string
}

const assetFilters: Array<{ label: string; value: SettlementAsset | "all" }> = [
  { label: "All markets", value: "all" },
  { label: "ETH", value: "ETH" },
  { label: "USDG", value: "USDG" },
]

/** A controlled marketplace view: data and all wallet actions remain owned by the route. */
export function ExplorePage({
  markets,
  activeAsset = "all",
  searchValue = "",
  onAssetChange,
  onSearchChange,
  onPull,
  onOpenMarket,
  onDeposit,
  className,
}: ExplorePageProps) {
  const visibleMarkets = markets.filter(
    (market) => activeAsset === "all" || market.settlementAsset === activeAsset,
  )

  return (
    <div className={cn("explore-page space-y-10 sm:space-y-14", className)}>
      <section className="grid items-end gap-8 lg:grid-cols-[minmax(0,1fr)_auto]">
        <div className="max-w-3xl">
          <Badge dot variant="success">
            Verifiable draws, live now
          </Badge>
          <h1 className="mt-5 text-4xl font-semibold leading-[0.96] tracking-[-0.06em] text-white sm:text-5xl lg:text-6xl">
            Back a collectible. Enter the <span className="text-lime-300">draw</span>.
          </h1>
          <p className="mt-5 max-w-2xl text-base leading-7 text-slate-400 sm:text-lg">
            Deposit an NFT to earn from every pull, or enter a draw at a transparent pool-derived
            price. Each market settles in one asset.
          </p>
        </div>
        <Button className="w-full sm:w-auto" onClick={onDeposit} size="lg">
          <WalletCards aria-hidden className="size-4" />
          Deposit a collectible
          <ArrowRight aria-hidden className="size-4" />
        </Button>
      </section>

      <section aria-label="Protocol assurances" className="grid gap-3 sm:grid-cols-3">
        <TrustPoint icon={ShieldCheck} text="Proof-backed positions" />
        <TrustPoint icon={CircleHelp} text="Transparent pull pricing" />
        <TrustPoint icon={WalletCards} text="Pay with ETH or USDG" />
      </section>

      <section>
        <div className="flex flex-col justify-between gap-5 sm:flex-row sm:items-center">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.16em] text-lime-300">
              Marketplace
            </p>
            <h2 className="mt-2 text-2xl font-semibold tracking-[-0.045em] text-white">
              Explore active markets
            </h2>
          </div>
          <label className="market-search-label block w-full sm:w-[272px]">
            <span className="mb-2 block text-xs font-semibold text-slate-400">Search markets</span>
            <span className="relative block">
              <Search
                aria-hidden
                className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-slate-500"
              />
              <input
                aria-label="Search markets"
                className="h-10 w-full rounded-xl border border-white/[0.1] bg-white/[0.04] pl-10 pr-4 text-sm text-white outline-none placeholder:text-slate-600 transition-[border-color,box-shadow,background-color] duration-150 focus:border-lime-300/50 focus:bg-white/[0.06] focus:ring-2 focus:ring-lime-300/10"
                id="market-search"
                onChange={(event: ChangeEvent<HTMLInputElement>) =>
                  onSearchChange?.(event.target.value)
                }
                placeholder="Try CryptoPunks or Azuki"
                value={searchValue}
              />
            </span>
          </label>
        </div>

        <div className="mt-6 flex items-center justify-between gap-4 border-b border-white/[0.08] pb-4">
          <div aria-label="Settlement asset" className="flex gap-1 overflow-x-auto">
            {assetFilters.map((filter) => {
              const isActive = activeAsset === filter.value
              return (
                <button
                  aria-pressed={isActive}
                  className={cn(
                    "shrink-0 rounded-lg px-3 py-2 text-sm font-medium transition-[background-color,color] duration-150 ease-out focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-lime-300/70",
                    isActive
                      ? "bg-lime-300 text-slate-950"
                      : "text-slate-400 hover:bg-white/[0.06] hover:text-slate-100",
                  )}
                  key={filter.value}
                  onClick={() => onAssetChange?.(filter.value)}
                  type="button"
                >
                  {filter.label}
                </button>
              )
            })}
          </div>
          <button
            className="hidden items-center gap-1.5 text-sm font-medium text-slate-400 transition-colors hover:text-white sm:flex"
            type="button"
          >
            Most active <ChevronDown aria-hidden className="size-4" />
          </button>
        </div>

        <p aria-live="polite" className="sr-only" role="status">
          {visibleMarkets.length} {visibleMarkets.length === 1 ? "market" : "markets"} shown
        </p>
        {visibleMarkets.length ? (
          <div className="mt-6 grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
            {visibleMarkets.map((market) => (
              <MarketCard key={market.id} market={market} onOpen={onOpenMarket} onPull={onPull} />
            ))}
          </div>
        ) : (
          <div className="mt-6 grid min-h-64 place-items-center rounded-2xl border border-dashed border-white/[0.14] bg-white/[0.025] p-8 text-center">
            <div>
              <p className="font-semibold text-slate-200">No markets in this asset yet</p>
              <p className="mt-1 text-sm text-slate-500">
                Try another settlement asset or clear your search.
              </p>
              <Button
                className="mt-4"
                onClick={() => {
                  onAssetChange?.("all")
                  onSearchChange?.("")
                }}
                size="sm"
                variant="secondary"
              >
                Clear filters
              </Button>
            </div>
          </div>
        )}
      </section>
    </div>
  )
}

function TrustPoint({ icon: Icon, text }: { icon: LucideIcon; text: string }) {
  return (
    <div className="flex items-center gap-3 rounded-xl border border-white/[0.08] bg-white/[0.035] px-4 py-3.5 text-sm font-medium text-slate-300">
      <span className="grid size-7 shrink-0 place-items-center rounded-lg bg-lime-300/[0.1] text-lime-200">
        <Icon aria-hidden className="size-3.5" />
      </span>
      {text}
    </div>
  )
}
