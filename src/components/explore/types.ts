export type SettlementAsset = "ETH" | "USDG"

export interface MarketCollection {
  name: string
  floor?: string
  verified?: boolean
}

export interface MarketNft {
  name: string
  tokenId?: string
  imageUrl?: string
  accent?: string
}

export interface MarketData {
  id: string
  name: string
  description?: string
  settlementAsset: SettlementAsset
  collection: MarketCollection
  featuredNft: MarketNft
  activePositions: number
  totalPositions?: number
  totalBacking: string
  pullPrice: string
  pullPriceUsd?: string
  apy?: string
  crownBacking?: string
  status?: "active" | "paused" | "coming-soon"
}
