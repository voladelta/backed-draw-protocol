import { create } from "zustand"
import { ALL_POOLS_ID, marketForPoolSelection, selectPreviewPosition } from "@/data/pool-selection"
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
  selectedMarketId: ALL_POOLS_ID,
  assetFilter: "ALL",
  pullOpen: false,
  pullCount: 1,
  paymentAsset: "ETH",
  pullStage: "configure",
  selectMarket: (selectedMarketId) =>
    set((state) =>
      state.selectedMarketId === selectedMarketId
        ? state
        : {
            selectedMarketId,
            pullStage: "configure",
            settlementChoice: undefined,
            revealedPositionId: undefined,
          },
    ),
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
      const market = marketForPoolSelection(state.selectedMarketId)
      const position = selectPreviewPosition(market)
      return { pullStage: "revealed", revealedPositionId: position?.id }
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
