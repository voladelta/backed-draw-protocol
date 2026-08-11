import { describe, expect, it } from "vitest"
import { allocatePull, calculateMarketEconomics } from "./economics"

describe("market economics", () => {
  it("derives inverse-backing probability and EV", () => {
    const result = calculateMarketEconomics([{ backing: 1 }, { backing: 2 }, { backing: 4 }])
    expect(result.probabilities.reduce((a, b) => a + b, 0)).toBeCloseTo(1)
    expect(result.expectedValue).toBeCloseTo(3 / 1.75)
    expect(result.pullPrice).toBeCloseTo(result.expectedValue * 1.1)
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
    expect(total).toBeCloseTo(ev * 1.1)
  })
})
