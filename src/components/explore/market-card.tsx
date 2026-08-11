import { ArrowUpRight, Check, Crown, Dices, Layers3, Sparkles, type LucideIcon } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { cn } from "@/lib/utils"

import type { MarketData } from "./types"

export interface MarketCardProps {
  market: MarketData
  onPull?: (market: MarketData) => void
  onOpen?: (market: MarketData) => void
  className?: string
}

const statusCopy = {
  active: "Live",
  paused: "Paused",
  "coming-soon": "Coming soon",
} as const

export function MarketCard({ market, onPull, onOpen, className }: MarketCardProps) {
  const status = market.status ?? "active"
  const isLive = status === "active"

  return (
    <Card
      className={cn(
        "group relative flex h-full flex-col overflow-hidden transition-[border-color,box-shadow] duration-200 ease-out hover:border-lime-300/25 hover:shadow-[0_22px_60px_rgba(0,0,0,0.35)]",
        className,
      )}
    >
      <NftPreview nft={market.featuredNft} />

      <div className="flex flex-1 flex-col p-5">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex items-center gap-1.5 text-xs text-slate-400">
              <span className="truncate">{market.collection.name}</span>
              {market.collection.verified ? (
                <Check aria-label="Verified collection" className="size-3.5 text-lime-300" />
              ) : null}
            </div>
            <h3 className="mt-1 truncate text-lg font-semibold tracking-[-0.035em] text-white">
              {market.name}
            </h3>
          </div>
          <Badge dot variant={isLive ? "success" : "muted"}>
            {statusCopy[status]}
          </Badge>
        </div>

        <div className="mt-5 grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-white/[0.08] bg-white/[0.08]">
          <Stat
            icon={Layers3}
            label="Active positions"
            value={market.activePositions.toLocaleString()}
          />
          <Stat icon={Sparkles} label="Total backing" value={market.totalBacking} />
        </div>

        <div className="mt-5 flex items-end justify-between gap-3">
          <div>
            <p className="text-[11px] font-semibold uppercase tracking-[0.12em] text-slate-500">
              Next pull
            </p>
            <p className="mt-1 text-xl font-semibold tracking-[-0.04em] text-white">
              {market.pullPrice}{" "}
              <span className="text-sm text-slate-400">{market.settlementAsset}</span>
            </p>
            {market.pullPriceUsd ? (
              <p className="mt-0.5 text-xs text-slate-500">{market.pullPriceUsd}</p>
            ) : null}
          </div>
          <Badge variant="currency">{market.settlementAsset}</Badge>
        </div>

        <div className="mt-5 grid grid-cols-[1fr_auto] items-center gap-3 border-t border-white/[0.08] pt-4">
          <div className="flex items-center gap-1.5 text-xs text-slate-400">
            <Crown aria-hidden className="size-3.5 text-amber-200" />
            <span>
              {market.crownBacking
                ? `Crown · ${market.crownBacking}`
                : market.apy
                  ? `${market.apy} depositor APY`
                  : "Equal-share rewards"}
            </span>
          </div>
          <div className="flex items-center gap-2">
            <Button
              aria-label={`Open ${market.name}`}
              onClick={() => onOpen?.(market)}
              size="icon"
              variant="ghost"
            >
              <ArrowUpRight aria-hidden className="size-4" />
            </Button>
            <Button disabled={!isLive} onClick={() => onPull?.(market)} size="sm">
              <Dices aria-hidden className="size-3.5" />
              Pull
            </Button>
          </div>
        </div>
      </div>
    </Card>
  )
}

function Stat({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div className="min-w-0 bg-[#0d1320]/90 px-3.5 py-3">
      <div className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-[0.1em] text-slate-500">
        <Icon aria-hidden className="size-3" />
        <span className="truncate">{label}</span>
      </div>
      <p className="mt-1 truncate text-sm font-semibold text-slate-100">{value}</p>
    </div>
  )
}

function NftPreview({ nft }: { nft: MarketData["featuredNft"] }) {
  const accent = nft.accent ?? "#bef264"

  return (
    <div className="relative aspect-[16/10] overflow-hidden border-b border-white/[0.08] bg-[#111827]">
      {nft.imageUrl ? (
        <img alt={nft.name} className="size-full object-cover" src={nft.imageUrl} />
      ) : (
        <div
          aria-label={`${nft.name} preview`}
          className="relative size-full overflow-hidden"
          role="img"
          style={{
            background: `radial-gradient(circle at 68% 25%, ${accent}88, transparent 25%), linear-gradient(135deg, #111827 0%, #162033 48%, #080b12 100%)`,
          }}
        >
          <div
            aria-hidden
            className="absolute -right-12 -top-16 size-52 rounded-full border border-white/20"
          />
          <div
            aria-hidden
            className="absolute -bottom-16 left-[14%] size-52 rotate-45 rounded-[36px] border border-white/10 bg-white/[0.035]"
          />
          <div
            aria-hidden
            className="absolute inset-0 opacity-20 [background-image:linear-gradient(rgba(255,255,255,.18)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,.18)_1px,transparent_1px)] [background-size:28px_28px]"
          />
          <div className="absolute inset-x-5 bottom-5 flex items-end justify-between">
            <span className="max-w-[72%] text-2xl font-black uppercase leading-[0.85] tracking-[-0.08em] text-white/95">
              {nft.name}
            </span>
            <span className="rounded-lg border border-white/20 bg-slate-950/35 px-2 py-1 font-mono text-[10px] text-white/75">
              {nft.tokenId ?? "1/1"}
            </span>
          </div>
        </div>
      )}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 bg-gradient-to-t from-slate-950/30 via-transparent to-white/[0.02]"
      />
    </div>
  )
}
