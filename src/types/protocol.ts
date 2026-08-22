export type SettlementAsset = "ETH" | "USDG"
export type MarketCategory = "Art" | "PFP" | "Trading cards" | "Game assets"

export type MarketEconomicPolicy = {
  markupBps: number
  cashPayoutBps: number
  /** Backing returned to the position owner when the puller keeps the collectible. */
  keepPayoutBps: number
}

export type Position = {
  id: string
  name: string
  collection: string
  image: string
  backing: number
  probability: number
  earnings: number
  accent: string
  asset?: SettlementAsset
  sourceMarketId?: string
  sourceMarketName?: string
}

export type Market = {
  id: string
  name: string
  description: string
  asset: SettlementAsset
  category: MarketCategory
  verified: boolean
  activePositions: number
  totalBacking: number
  pullPrice: number
  change24h: number
  crown: string
  heroImage: string
  accent: string
  economicPolicy: MarketEconomicPolicy | null
  positions: Position[]
}

export type PullStage = "configure" | "sign" | "drawing" | "revealed" | "settled"
export type SettlementChoice = "keep" | "cash" | "draw" | "relist"
