import { describe, expect, it } from "vitest"
import { markets } from "@/data/markets"
import {
  allocatePull,
  calculateMarketEconomics,
  calculatePullerEconomics,
  economicProfiles,
} from "./economics"

describe("market economics", () => {
  it("derives inverse-backing probability and EV", () => {
    const result = calculateMarketEconomics([{ backing: 1 }, { backing: 2 }, { backing: 4 }])
    expect(result.probabilities.reduce((a, b) => a + b, 0)).toBeCloseTo(1)
    expect(result.expectedValue).toBeCloseTo(3 / 1.75)
    expect(result.pullPrice).toBeCloseTo(result.expectedValue * 1.025)
  })

  it("conserves pull allocation", () => {
    const ev = 2
    const count = 10
    const allocation = allocatePull(ev, count)
    const total =
      allocation.basePerPosition * count +
      allocation.markupPerPosition * count +
      allocation.rewardsPerPosition * count +
      allocation.crown +
      allocation.protocol
    expect(total).toBeCloseTo(ev * 1.025)
  })

  it("uses one explicit markup override for price and allocation", () => {
    const markupBps = economicProfiles.legacyStress.markupBps
    const market = calculateMarketEconomics([{ backing: 2 }], markupBps)
    const allocation = allocatePull(market.expectedValue, 1, markupBps)
    const allocatedTotal =
      allocation.basePerPosition +
      allocation.markupPerPosition +
      allocation.rewardsPerPosition +
      allocation.crown +
      allocation.protocol

    expect(market.pullPrice).toBeCloseTo(2.2)
    expect(allocatedTotal).toBeCloseTo(market.pullPrice)
  })

  it.each([1.5, -1, 10_001])("rejects invalid helper markup bps: %s", (markupBps) => {
    expect(() => calculateMarketEconomics([{ backing: 1 }], markupBps)).toThrow(
      "Markup must be an integer between 0 and 10,000 bps",
    )
    expect(() => allocatePull(1, 1, markupBps)).toThrow(
      "Markup must be an integer between 0 and 10,000 bps",
    )
  })

  it("defines the exact candidate policies", () => {
    expect(economicProfiles).toEqual({
      legacyStress: { markupBps: 1_000, cashPayoutBps: 8_500, keepPayoutBps: 9_900 },
      fourPercent: { markupBps: 400, cashPayoutBps: 9_000, keepPayoutBps: 9_900 },
      flagship: { markupBps: 250, cashPayoutBps: 9_000, keepPayoutBps: 9_900 },
      pullerFirst: { markupBps: 150, cashPayoutBps: 9_000, keepPayoutBps: 9_900 },
    })
  })

  it("assigns the 2.5%/90%/99% policy to every mock flagship market", () => {
    expect(markets).not.toHaveLength(0)
    expect(markets.every((market) => market.economicPolicy === economicProfiles.flagship)).toBe(
      true,
    )
  })

  it.each([
    ["legacy stress", economicProfiles.legacyStress, (8_500 * 10_000) / 11_000],
    ["four percent", economicProfiles.fourPercent, (9_000 * 10_000) / 10_400],
    ["flagship", economicProfiles.flagship, (9_000 * 10_000) / 10_250],
    ["puller-first", economicProfiles.pullerFirst, (9_000 * 10_000) / 10_150],
  ])("calculates the exact %s cash floor", (_label, policy, expectedCashFloorRtpBps) => {
    const result = calculatePullerEconomics({ policy, keepShareBps: 0, keptAssetValueBps: 0 })

    expect(result.guaranteedCashFloorRtpBps).toBeCloseTo(expectedCashFloorRtpBps)
    expect(result.tokenIndependentExpectedRtpBps).toBeCloseTo(expectedCashFloorRtpBps)
    expect(result.gapTo100Bps).toBeCloseTo(10_000 - expectedCashFloorRtpBps)
  })

  it("calculates the cash floor and token-independent keep mix in basis points", () => {
    const result = calculatePullerEconomics({
      policy: economicProfiles.flagship,
      keepShareBps: 2_000,
      keptAssetValueBps: 10_000,
    })

    expect(result.pullPriceMultiplierBps).toBe(10_250)
    expect(result.guaranteedCashFloorRtpBps).toBeCloseTo(8_780.48780487805)
    expect(result.tokenIndependentExpectedRtpBps).toBeCloseTo(8_975.60975609756)
    expect(result.gapTo100Bps).toBeCloseTo(1_024.39024390244)
    expect(result.backerKeepSettlementFeeBps).toBe(100)
  })

  it("does not count the backer's keep payout as puller return", () => {
    const result = calculatePullerEconomics({
      policy: { markupBps: 0, cashPayoutBps: 0, keepPayoutBps: 10_000 },
      keepShareBps: 10_000,
      keptAssetValueBps: 6_000,
    })

    expect(result.tokenIndependentExpectedRtpBps).toBe(6_000)
  })

  it.each([
    ["fractional markup", { markupBps: 1.5, cashPayoutBps: 9_000, keepPayoutBps: 9_900 }, 0, 0],
    ["negative cash payout", { markupBps: 250, cashPayoutBps: -1, keepPayoutBps: 9_900 }, 0, 0],
    [
      "oversized keep payout",
      { markupBps: 250, cashPayoutBps: 9_000, keepPayoutBps: 10_001 },
      0,
      0,
    ],
    ["oversized keep share", economicProfiles.flagship, 10_001, 0],
  ])("rejects invalid policy bps input: %s", (_label, policy, keepShareBps, keptAssetValueBps) => {
    expect(() => calculatePullerEconomics({ policy, keepShareBps, keptAssetValueBps })).toThrow(
      /must be an integer between 0 and 10,000 bps/,
    )
  })

  it.each([-1, 9_999.5, Number.MAX_SAFE_INTEGER])(
    "rejects invalid kept asset value bps: %s",
    (keptAssetValueBps) => {
      expect(() =>
        calculatePullerEconomics({
          policy: economicProfiles.flagship,
          keepShareBps: 1_000,
          keptAssetValueBps,
        }),
      ).toThrow("Kept asset value must be a non-negative integer bps value")
    },
  )

  it("allows collectible value above backing without calling it guaranteed", () => {
    const result = calculatePullerEconomics({
      policy: economicProfiles.flagship,
      keepShareBps: 10_000,
      keptAssetValueBps: 15_000,
    })

    expect(result.tokenIndependentExpectedRtpBps).toBeCloseTo(14_634.1463414634)
    expect(result.gapTo100Bps).toBeCloseTo(-4_634.1463414634)
  })
})
