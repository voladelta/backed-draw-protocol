import type { MarketEconomicPolicy } from "@/types/protocol"

export type BackedPosition = { backing: number }

const BPS = 10_000

export const economicProfiles = {
  legacyStress: {
    markupBps: 1_000,
    cashPayoutBps: 8_500,
    keepPayoutBps: 9_900,
  },
  fourPercent: {
    markupBps: 400,
    cashPayoutBps: 9_000,
    keepPayoutBps: 9_900,
  },
  flagship: {
    markupBps: 250,
    cashPayoutBps: 9_000,
    keepPayoutBps: 9_900,
  },
  pullerFirst: {
    markupBps: 150,
    cashPayoutBps: 9_000,
    keepPayoutBps: 9_900,
  },
} as const satisfies Record<string, MarketEconomicPolicy>

export type PullerEconomicsInput = {
  policy: MarketEconomicPolicy
  keepShareBps: number
  keptAssetValueBps: number
}

export type PullerEconomics = {
  pullPriceMultiplierBps: number
  guaranteedCashFloorRtpBps: number
  tokenIndependentExpectedRtpBps: number
  gapTo100Bps: number
  backerKeepSettlementFeeBps: number
}

function validateBps(name: string, value: number) {
  if (!Number.isInteger(value) || value < 0 || value > BPS) {
    throw new Error(`${name} must be an integer between 0 and 10,000 bps`)
  }
}

function validateAssetValueBps(value: number) {
  if (!Number.isSafeInteger(value) || value < 0 || value > Number.MAX_SAFE_INTEGER / BPS) {
    throw new Error("Kept asset value must be a non-negative integer bps value")
  }
}

export function calculatePullerEconomics({
  policy,
  keepShareBps,
  keptAssetValueBps,
}: PullerEconomicsInput): PullerEconomics {
  validateBps("Markup", policy.markupBps)
  validateBps("Cash payout", policy.cashPayoutBps)
  validateBps("Keep payout", policy.keepPayoutBps)
  validateBps("Keep share", keepShareBps)
  validateAssetValueBps(keptAssetValueBps)

  const pullPriceMultiplierBps = BPS + policy.markupBps
  const cashShareBps = BPS - keepShareBps
  const tokenIndependentReturnBps =
    (cashShareBps * policy.cashPayoutBps + keepShareBps * keptAssetValueBps) / BPS
  const guaranteedCashFloorRtpBps = (policy.cashPayoutBps * BPS) / pullPriceMultiplierBps
  const tokenIndependentExpectedRtpBps = (tokenIndependentReturnBps * BPS) / pullPriceMultiplierBps

  return {
    pullPriceMultiplierBps,
    guaranteedCashFloorRtpBps,
    tokenIndependentExpectedRtpBps,
    gapTo100Bps: BPS - tokenIndependentExpectedRtpBps,
    backerKeepSettlementFeeBps: BPS - policy.keepPayoutBps,
  }
}

export function calculateMarketEconomics(
  positions: BackedPosition[],
  markupBps: number = economicProfiles.flagship.markupBps,
) {
  validateBps("Markup", markupBps)
  if (positions.length === 0) {
    return { totalWeight: 0, expectedValue: 0, pullPrice: 0, probabilities: [] }
  }

  const weights = positions.map(({ backing }) => {
    if (!Number.isFinite(backing) || backing <= 0) throw new Error("Backing must be positive")
    return 1 / backing
  })
  const totalWeight = weights.reduce((sum, weight) => sum + weight, 0)
  const expectedValue = positions.length / totalWeight

  return {
    totalWeight,
    expectedValue,
    pullPrice: expectedValue * ((BPS + markupBps) / BPS),
    probabilities: weights.map((weight) => weight / totalWeight),
  }
}

export function allocatePull(
  expectedValue: number,
  positionCount: number,
  markupBps: number = economicProfiles.flagship.markupBps,
) {
  validateBps("Markup", markupBps)
  const markup = expectedValue * (markupBps / BPS)
  const rewardPurchase = markup * 0.1
  const remainder = markup - rewardPurchase
  return {
    basePerPosition: expectedValue / positionCount,
    markupPerPosition: (remainder * 0.94) / positionCount,
    rewardsPerPosition: rewardPurchase / positionCount,
    crown: remainder * 0.05,
    protocol: remainder * 0.01,
  }
}
