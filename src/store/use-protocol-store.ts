import { create } from "zustand"
import { markets } from "@/data/markets"
import type { PullStage, SettlementAsset, SettlementChoice } from "@/types/protocol"

type ProtocolState = {
  selectedMarketId: string
  assetFilter: "ALL" | SettlementAsset
  pullOpen: boolean
  pullCount: number
  paymentAsset: SettlementAsset
  pullStage: PullStage
  settlementChoice?: SettlementChoice
  revealedPositionId?: string
  selectMarket: (id: string) => void
  setAssetFilter: (asset: "ALL" | SettlementAsset) => void
  openPull: (marketId?: string) => void
  closePull: () => void
  setPullCount: (count: number) => void
  setPaymentAsset: (asset: SettlementAsset) => void
  setPullStage: (stage: PullStage) => void
  reveal: () => void
  settle: (choice: SettlementChoice) => void
  resetPull: () => void
}

export const useProtocolStore = create<ProtocolState>((set) => ({
  selectedMarketId: markets[0].id,
  assetFilter: "ALL",
  pullOpen: false,
  pullCount: 1,
  paymentAsset: "ETH",
  pullStage: "configure",
  selectMarket: (selectedMarketId) => set({ selectedMarketId }),
  setAssetFilter: (assetFilter) => set({ assetFilter }),
  openPull: (marketId) =>
    set((state) => ({
      pullOpen: true,
      selectedMarketId: marketId ?? state.selectedMarketId,
      pullStage: "configure",
      pullCount: 1,
      settlementChoice: undefined,
      revealedPositionId: undefined,
    })),
  closePull: () =>
    set({
      pullOpen: false,
      pullStage: "configure",
      settlementChoice: undefined,
      revealedPositionId: undefined,
    }),
  setPullCount: (pullCount) => set({ pullCount: Math.min(10, Math.max(1, pullCount)) }),
  setPaymentAsset: (paymentAsset) => set({ paymentAsset }),
  setPullStage: (pullStage) => set({ pullStage }),
  reveal: () =>
    set((state) => {
      const market = markets.find((item) => item.id === state.selectedMarketId) ?? markets[0]
      const position =
        market.positions[(state.pullCount + market.activePositions) % market.positions.length]
      return { pullStage: "revealed", revealedPositionId: position.id }
    }),
  settle: (settlementChoice) => set({ settlementChoice, pullStage: "settled" }),
  resetPull: () =>
    set({
      pullStage: "configure",
      pullCount: 1,
      settlementChoice: undefined,
      revealedPositionId: undefined,
    }),
}))
