import { describe, expect, it } from "vitest"
import { markets } from "@/data/markets"
import {
  ALL_POOLS_ID,
  allPoolsMarket,
  marketForPoolSelection,
  selectPreviewPosition,
} from "@/data/pool-selection"

describe("pool selection", () => {
  it("offers every position when all pools are selected", () => {
    expect(marketForPoolSelection(ALL_POOLS_ID)).toBe(allPoolsMarket)
    expect(allPoolsMarket.positions).toHaveLength(
      markets.reduce((total, market) => total + market.positions.length, 0),
    )
    expect(new Set(allPoolsMarket.positions.map((position) => position.sourceMarketId))).toEqual(
      new Set(markets.map((market) => market.id)),
    )
  })

  it("keeps a specific pool scoped to its own positions", () => {
    for (const market of markets) {
      expect(marketForPoolSelection(market.id).positions).toEqual(market.positions)
    }
  })

  it("does not broaden an unknown pool id to all pools", () => {
    expect(marketForPoolSelection("unknown-pool")).toBe(markets[0])
  })

  it("samples only from the selected scope", () => {
    const market = markets[1]
    expect(selectPreviewPosition(market, () => 0)).toBe(market.positions[0])
    expect(selectPreviewPosition(market, () => 0.999_999)).toBe(
      market.positions[market.positions.length - 1],
    )
  })
})
