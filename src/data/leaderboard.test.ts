import { describe, expect, it } from "vitest"

import { leaderboardFor, type LeaderboardPeriod, type LeaderboardRole } from "./leaderboard"

const roles: LeaderboardRole[] = ["pullers", "backers"]
const periods: LeaderboardPeriod[] = ["daily", "weekly", "monthly"]

describe("leaderboard preview data", () => {
  it.each(roles.flatMap((role) => periods.map((period) => [role, period] as const)))(
    "returns a sorted top 20 for %s over %s",
    (role, period) => {
      const entries = leaderboardFor(role, period)

      expect(entries).toHaveLength(20)
      expect(new Set(entries.map((entry) => entry.id)).size).toBe(20)
      expect(entries.every((entry) => entry.score > 0 && entry.activity > 0)).toBe(true)
      expect(entries).toEqual([...entries].sort((a, b) => b.score - a.score))
    },
  )

  it("returns fresh entries so callers cannot mutate the shared preview source", () => {
    const first = leaderboardFor("pullers", "weekly")
    first[0]!.score = 0

    expect(leaderboardFor("pullers", "weekly")[0]!.score).toBeGreaterThan(0)
  })
})
