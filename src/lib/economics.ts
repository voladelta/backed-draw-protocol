export type BackedPosition = { backing: number }

export function calculateMarketEconomics(positions: BackedPosition[], markupRate = 0.1) {
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
    pullPrice: expectedValue * (1 + markupRate),
    probabilities: weights.map((weight) => weight / totalWeight),
  }
}

export function allocatePull(expectedValue: number, positionCount: number) {
  const markup = expectedValue * 0.1
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
