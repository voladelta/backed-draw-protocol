export type LeaderboardRole = "pullers" | "backers"
export type LeaderboardPeriod = "daily" | "weekly" | "monthly"

export interface LeaderboardEntry {
  id: string
  name: string
  address: string
  score: number
  activity: number
  movement: number
}

interface LeaderboardParticipant {
  id: string
  name: string
  address: string
  weeklyScore: number
  weeklyActivity: number
  movement: number
}

const pullers: LeaderboardParticipant[] = [
  {
    id: "p01",
    name: "Lucky Index",
    address: "0x71A9…3F2A",
    weeklyScore: 184920,
    weeklyActivity: 428,
    movement: 2,
  },
  {
    id: "p02",
    name: "Mint Condition",
    address: "0xAC14…947E",
    weeklyScore: 176480,
    weeklyActivity: 401,
    movement: 0,
  },
  {
    id: "p03",
    name: "Rare Orbit",
    address: "0x4B82…A120",
    weeklyScore: 163770,
    weeklyActivity: 372,
    movement: 4,
  },
  {
    id: "p04",
    name: "Drawn Together",
    address: "0xD913…07CE",
    weeklyScore: 151260,
    weeklyActivity: 351,
    movement: -1,
  },
  {
    id: "p05",
    name: "Neon Receipt",
    address: "0x29F0…B18D",
    weeklyScore: 143840,
    weeklyActivity: 334,
    movement: 3,
  },
  {
    id: "p06",
    name: "Proof Please",
    address: "0x88C2…60A1",
    weeklyScore: 136510,
    weeklyActivity: 318,
    movement: 1,
  },
  {
    id: "p07",
    name: "Poolside",
    address: "0x1E7B…52F9",
    weeklyScore: 129960,
    weeklyActivity: 299,
    movement: -2,
  },
  {
    id: "p08",
    name: "Soft Reveal",
    address: "0xF491…D044",
    weeklyScore: 121730,
    weeklyActivity: 281,
    movement: 5,
  },
  {
    id: "p09",
    name: "Lucky Packet",
    address: "0x63A0…910B",
    weeklyScore: 115420,
    weeklyActivity: 269,
    movement: 0,
  },
  {
    id: "p10",
    name: "One More Pull",
    address: "0xB7E4…3CC2",
    weeklyScore: 108890,
    weeklyActivity: 252,
    movement: -3,
  },
  {
    id: "p11",
    name: "Verified Vibes",
    address: "0x05D1…72AF",
    weeklyScore: 101340,
    weeklyActivity: 238,
    movement: 2,
  },
  {
    id: "p12",
    name: "Green Candle",
    address: "0xC462…E118",
    weeklyScore: 94760,
    weeklyActivity: 221,
    movement: 1,
  },
  {
    id: "p13",
    name: "Open Edition",
    address: "0x9A33…4D80",
    weeklyScore: 89120,
    weeklyActivity: 207,
    movement: -1,
  },
  {
    id: "p14",
    name: "Chain Reaction",
    address: "0x327B…F552",
    weeklyScore: 82490,
    weeklyActivity: 192,
    movement: 3,
  },
  {
    id: "p15",
    name: "Final Form",
    address: "0xE8A1…0BC9",
    weeklyScore: 75840,
    weeklyActivity: 176,
    movement: -2,
  },
  {
    id: "p16",
    name: "Golden Block",
    address: "0x741F…A833",
    weeklyScore: 69270,
    weeklyActivity: 161,
    movement: 1,
  },
  {
    id: "p17",
    name: "The Reveal",
    address: "0x16C4…D702",
    weeklyScore: 63110,
    weeklyActivity: 149,
    movement: 4,
  },
  {
    id: "p18",
    name: "Odds On",
    address: "0xA208…1EF6",
    weeklyScore: 57980,
    weeklyActivity: 136,
    movement: -1,
  },
  {
    id: "p19",
    name: "Pool Runner",
    address: "0x5F92…63B4",
    weeklyScore: 52430,
    weeklyActivity: 124,
    movement: 2,
  },
  {
    id: "p20",
    name: "Afterglow",
    address: "0xDB40…998A",
    weeklyScore: 47860,
    weeklyActivity: 113,
    movement: 0,
  },
]

const backers: LeaderboardParticipant[] = [
  {
    id: "b01",
    name: "Deep Reserve",
    address: "0x0B12…A4F9",
    weeklyScore: 218640,
    weeklyActivity: 482.4,
    movement: 1,
  },
  {
    id: "b02",
    name: "Vault Native",
    address: "0x7E80…11C2",
    weeklyScore: 204310,
    weeklyActivity: 451.8,
    movement: 3,
  },
  {
    id: "b03",
    name: "Crown Chaser",
    address: "0x34A6…9DF0",
    weeklyScore: 193870,
    weeklyActivity: 428.1,
    movement: -1,
  },
  {
    id: "b04",
    name: "Floor Support",
    address: "0xF120…77BE",
    weeklyScore: 182460,
    weeklyActivity: 401.6,
    movement: 2,
  },
  {
    id: "b05",
    name: "Patient Capital",
    address: "0x8D41…C903",
    weeklyScore: 171950,
    weeklyActivity: 377.2,
    movement: 0,
  },
  {
    id: "b06",
    name: "Yield Gallery",
    address: "0x22CE…51A8",
    weeklyScore: 160820,
    weeklyActivity: 352.9,
    movement: 4,
  },
  {
    id: "b07",
    name: "Long Canvas",
    address: "0xA5B9…ED14",
    weeklyScore: 149760,
    weeklyActivity: 329.4,
    movement: -2,
  },
  {
    id: "b08",
    name: "Proof of Taste",
    address: "0x6C70…0F33",
    weeklyScore: 139240,
    weeklyActivity: 307.8,
    movement: 1,
  },
  {
    id: "b09",
    name: "Liquid Frame",
    address: "0xD821…A670",
    weeklyScore: 128670,
    weeklyActivity: 284.3,
    movement: 2,
  },
  {
    id: "b10",
    name: "Backing Track",
    address: "0x49EF…3B05",
    weeklyScore: 119530,
    weeklyActivity: 263.9,
    movement: -3,
  },
  {
    id: "b11",
    name: "Quiet Vault",
    address: "0x91C3…D842",
    weeklyScore: 110860,
    weeklyActivity: 241.7,
    movement: 0,
  },
  {
    id: "b12",
    name: "Rare Assets",
    address: "0x137A…6E99",
    weeklyScore: 102140,
    weeklyActivity: 223.5,
    movement: 3,
  },
  {
    id: "b13",
    name: "Open Ledger",
    address: "0xBC62…18F1",
    weeklyScore: 93820,
    weeklyActivity: 205.2,
    movement: -1,
  },
  {
    id: "b14",
    name: "Epoch House",
    address: "0x5A10…C47D",
    weeklyScore: 85690,
    weeklyActivity: 188.6,
    movement: 2,
  },
  {
    id: "b15",
    name: "Still Holding",
    address: "0xE742…0A56",
    weeklyScore: 77940,
    weeklyActivity: 171.4,
    movement: 1,
  },
  {
    id: "b16",
    name: "Pool Curator",
    address: "0x2F08…B731",
    weeklyScore: 70480,
    weeklyActivity: 154.8,
    movement: -2,
  },
  {
    id: "b17",
    name: "Value Locked",
    address: "0xC094…53EA",
    weeklyScore: 63810,
    weeklyActivity: 139.5,
    movement: 4,
  },
  {
    id: "b18",
    name: "Gallery Node",
    address: "0x781D…9B20",
    weeklyScore: 57430,
    weeklyActivity: 124.9,
    movement: 0,
  },
  {
    id: "b19",
    name: "Reserve One",
    address: "0x14B8…FC62",
    weeklyScore: 51620,
    weeklyActivity: 111.7,
    movement: -1,
  },
  {
    id: "b20",
    name: "Lasting Value",
    address: "0xAD35…720C",
    weeklyScore: 46290,
    weeklyActivity: 99.8,
    movement: 2,
  },
]

const periodScale: Record<LeaderboardPeriod, { score: number; activity: number; seed: number }> = {
  daily: { score: 0.15, activity: 0.14, seed: 2 },
  weekly: { score: 1, activity: 1, seed: 0 },
  monthly: { score: 3.9, activity: 3.75, seed: 5 },
}

/** Stable preview data that can be replaced by the leaderboard indexer without changing the page. */
export function leaderboardFor(
  role: LeaderboardRole,
  period: LeaderboardPeriod,
): LeaderboardEntry[] {
  const participants = role === "pullers" ? pullers : backers
  const scale = periodScale[period]
  const roleSeed = role === "pullers" ? 1 : 4

  return participants
    .map((participant, index) => {
      const adjustment = 1 + (((index * 7 + roleSeed + scale.seed) % 9) - 4) * 0.012
      return {
        id: participant.id,
        name: participant.name,
        address: participant.address,
        score: Math.round(participant.weeklyScore * scale.score * adjustment),
        activity: participant.weeklyActivity * scale.activity * adjustment,
        movement:
          period === "weekly" ? participant.movement : participant.movement - scale.seed + 3,
      }
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, 20)
}
