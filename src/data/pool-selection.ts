import { markets } from "@/data/markets"
import type { Market, Position } from "@/types/protocol"

export const ALL_POOLS_ID = "all-pools"

const positions = markets.flatMap((market) =>
  market.positions.map((position) => ({
    ...position,
    id: `${market.id}:${position.id}`,
    probability: position.probability / markets.length,
    sourceMarketId: market.id,
    sourceMarketName: market.name,
    asset: market.asset,
  })),
)

export const allPoolsMarket: Market = {
  id: ALL_POOLS_ID,
  name: "All pools",
  description: "Pull from every active collectible pool.",
  asset: "ETH",
  category: "Art",
  verified: true,
  activePositions: markets.reduce((total, market) => total + market.activePositions, 0),
  totalBacking: 0,
  pullPrice: 0,
  change24h: 0,
  crown: "Any active collectible",
  heroImage: markets[0]?.heroImage ?? "",
  accent: "#ccff00",
  positions,
}

export const poolOptions = [allPoolsMarket, ...markets]

export function marketForPoolSelection(poolId: string): Market {
  if (poolId === ALL_POOLS_ID) return allPoolsMarket
  return markets.find((market) => market.id === poolId) ?? markets[0] ?? allPoolsMarket
}

export function selectPreviewPosition(market: Market, random = Math.random): Position | undefined {
  if (market.positions.length === 0) return undefined
  const index = Math.min(
    Math.floor(random() * market.positions.length),
    market.positions.length - 1,
  )
  return market.positions[Math.max(0, index)]
}
