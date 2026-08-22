import { ArrowDown, ArrowUp, Crown, Minus, ShieldCheck, Sparkles, Trophy } from "lucide-react"
import * as stylex from "@stylexjs/stylex"
import { useMemo, useState } from "react"

import { Badge } from "@/components/ui/badge"
import {
  leaderboardFor,
  type LeaderboardEntry,
  type LeaderboardPeriod,
  type LeaderboardRole,
} from "@/data/leaderboard"
import { breakpoints, colors } from "../../styles/tokens.stylex"

const periods: Array<{ label: string; value: LeaderboardPeriod }> = [
  { label: "Daily", value: "daily" },
  { label: "Weekly", value: "weekly" },
  { label: "Monthly", value: "monthly" },
]

const roles: Array<{ label: string; value: LeaderboardRole }> = [
  { label: "Pullers", value: "pullers" },
  { label: "Backers", value: "backers" },
]

const periodNames: Record<LeaderboardPeriod, string> = {
  daily: "Daily",
  weekly: "Weekly",
  monthly: "Monthly",
}

const roleContent = {
  pullers: {
    name: "Pullers",
    singular: "Puller",
    metric: "Pulls",
    description: "Points from completed pulls and settlement activity.",
  },
  backers: {
    name: "Backers",
    singular: "Backer",
    metric: "Backing",
    description: "Points from active backing and position earnings.",
  },
} satisfies Record<
  LeaderboardRole,
  { name: string; singular: string; metric: string; description: string }
>

const numberFormatter = new Intl.NumberFormat("en-US")
const compactFormatter = new Intl.NumberFormat("en-US", {
  notation: "compact",
  maximumFractionDigits: 1,
})

const styles = stylex.create({
  page: {
    width: "100%",
    maxWidth: 1240,
    marginInline: "auto",
    paddingBlockStart: { default: 48, [breakpoints.sm]: 64, [breakpoints.lg]: 80 },
    paddingBlockEnd: { default: 80, [breakpoints.sm]: 112 },
    paddingInline: { default: 16, [breakpoints.sm]: 24, [breakpoints.lg]: 32 },
  },
  hero: {
    display: "grid",
    alignItems: "end",
    gap: 32,
    gridTemplateColumns: { default: "minmax(0, 1fr)", [breakpoints.lg]: "minmax(0, 1fr) auto" },
  },
  heroCopy: { maxWidth: 740 },
  eyebrow: {
    margin: 0,
    color: colors.lime300,
    fontSize: 11,
    fontWeight: 800,
    letterSpacing: "0.15em",
    textTransform: "uppercase",
  },
  title: {
    maxWidth: 720,
    marginBlockStart: 14,
    marginBlockEnd: 0,
    color: colors.white,
    fontSize: { default: 42, [breakpoints.sm]: 58, [breakpoints.lg]: 68 },
    fontWeight: 620,
    lineHeight: 0.98,
    letterSpacing: "-0.06em",
    textWrap: "balance",
    outline: "none",
  },
  lede: {
    maxWidth: 650,
    marginBlockStart: 20,
    marginBlockEnd: 0,
    color: colors.slate400,
    fontSize: { default: 15, [breakpoints.sm]: 17 },
    lineHeight: 1.6,
    textWrap: "pretty",
  },
  heroMeta: {
    display: "flex",
    alignItems: { default: "flex-start", [breakpoints.lg]: "flex-end" },
    flexDirection: "column",
    rowGap: 8,
  },
  heroMetaText: { color: colors.slate400, fontSize: 12 },
  controls: {
    display: "flex",
    flexDirection: { default: "column", [breakpoints.md]: "row" },
    alignItems: { default: "stretch", [breakpoints.md]: "center" },
    justifyContent: "space-between",
    gap: 20,
    marginBlockStart: { default: 40, [breakpoints.sm]: 52 },
    padding: 8,
    borderRadius: 18,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.09)",
    backgroundColor: "rgba(255,255,255,0.035)",
  },
  group: { display: "flex", minWidth: 0, margin: 0, padding: 0, borderWidth: 0 },
  roleGroup: { flex: 1 },
  periodGroup: { overflowX: "auto" },
  legend: {
    position: "absolute",
    width: 1,
    height: 1,
    padding: 0,
    margin: -1,
    overflow: "hidden",
    clip: "rect(0, 0, 0, 0)",
    whiteSpace: "nowrap",
    borderWidth: 0,
  },
  segmented: {
    display: "flex",
    width: "100%",
    minWidth: 0,
    columnGap: 4,
  },
  roleButton: {
    minWidth: 0,
    flex: 1,
    minHeight: 44,
    borderRadius: 12,
    borderWidth: 0,
    paddingInline: 18,
    fontSize: 14,
    fontWeight: 650,
    outline: { default: "none", ":focus-visible": `2px solid ${colors.lime300}` },
    outlineOffset: 2,
    transitionProperty: "background-color, color, transform",
    transitionDuration: "150ms",
    transitionTimingFunction: "cubic-bezier(0.2, 0, 0, 1)",
    transform: {
      default: "scale(1)",
      ":active": "scale(0.96)",
      [breakpoints.reducedMotion]: "none",
    },
  },
  periodButton: { flex: "0 0 auto", paddingInline: { default: 14, [breakpoints.sm]: 18 } },
  selectedButton: { backgroundColor: colors.lime300, color: colors.slate950 },
  idleButton: {
    backgroundColor: {
      default: "transparent",
      "@media (hover: hover) and (pointer: fine)": "rgba(255,255,255,0.06)",
    },
    color: {
      default: colors.slate400,
      "@media (hover: hover) and (pointer: fine)": colors.slate100,
    },
  },
  status: {
    position: "absolute",
    width: 1,
    height: 1,
    padding: 0,
    margin: -1,
    overflow: "hidden",
    clip: "rect(0, 0, 0, 0)",
    whiteSpace: "nowrap",
    borderWidth: 0,
  },
  boardHeader: {
    display: "flex",
    flexDirection: { default: "column", [breakpoints.sm]: "row" },
    alignItems: { default: "flex-start", [breakpoints.sm]: "end" },
    justifyContent: "space-between",
    gap: 12,
    marginBlockStart: { default: 44, [breakpoints.sm]: 56 },
  },
  boardTitle: {
    margin: 0,
    color: colors.white,
    fontSize: { default: 26, [breakpoints.sm]: 32 },
    fontWeight: 620,
    lineHeight: 1.1,
    letterSpacing: "-0.045em",
  },
  boardDescription: {
    marginBlockStart: 8,
    marginBlockEnd: 0,
    color: colors.slate400,
    fontSize: 14,
    lineHeight: 1.5,
  },
  boardCount: {
    display: "inline-flex",
    minHeight: 32,
    alignItems: "center",
    columnGap: 7,
    color: colors.slate400,
    fontSize: 12,
    fontWeight: 650,
    whiteSpace: "nowrap",
  },
  boardCountIcon: { width: 15, height: 15, color: colors.lime300 },
  podium: {
    display: "grid",
    gap: 16,
    marginBlockStart: 24,
    gridTemplateColumns: { default: "minmax(0, 1fr)", [breakpoints.md]: "1.15fr 1fr 1fr" },
  },
  podiumCard: {
    position: "relative",
    minWidth: 0,
    overflow: "hidden",
    borderRadius: 20,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.1)",
    padding: { default: 20, [breakpoints.sm]: 24 },
    backgroundColor: "rgba(255,255,255,0.045)",
    boxShadow: "0 20px 54px rgba(0,0,0,0.18)",
  },
  winnerCard: {
    borderColor: "rgba(190,242,100,0.28)",
    backgroundImage: "radial-gradient(circle at 10% 0%, rgba(190,242,100,0.15), transparent 52%)",
  },
  podiumTop: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    columnGap: 16,
  },
  rankBadge: {
    display: "inline-flex",
    height: 32,
    minWidth: 32,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 999,
    backgroundColor: "rgba(255,255,255,0.08)",
    color: colors.slate200,
    fontSize: 12,
    fontWeight: 800,
    fontVariantNumeric: "tabular-nums",
  },
  winnerBadge: { backgroundColor: colors.lime300, color: colors.slate950 },
  crown: { width: 20, height: 20, color: colors.lime300 },
  podiumIdentity: {
    display: "flex",
    minWidth: 0,
    alignItems: "center",
    columnGap: 12,
    marginBlockStart: 24,
  },
  avatar: {
    display: "grid",
    width: 44,
    height: 44,
    flexShrink: 0,
    placeItems: "center",
    borderRadius: 14,
    outlineWidth: 1,
    outlineStyle: "solid",
    outlineColor: "rgba(255,255,255,0.12)",
    backgroundColor: "rgba(190,242,100,0.11)",
    color: colors.lime200,
    fontSize: 13,
    fontWeight: 800,
  },
  identityText: { minWidth: 0 },
  participantName: {
    display: "block",
    overflow: { default: "visible", [breakpoints.sm]: "hidden" },
    color: colors.white,
    fontSize: 15,
    fontWeight: 650,
    lineHeight: 1.35,
    overflowWrap: "break-word",
    textOverflow: { default: "clip", [breakpoints.sm]: "ellipsis" },
    whiteSpace: { default: "normal", [breakpoints.sm]: "nowrap" },
  },
  participantAddress: {
    display: "block",
    marginBlockStart: 2,
    color: colors.slate400,
    fontSize: 12,
    fontVariantNumeric: "tabular-nums",
  },
  mobileActivity: { display: { default: "inline", [breakpoints.sm]: "none" } },
  scoreLabel: {
    display: "block",
    marginBlockStart: 24,
    color: colors.slate400,
    fontSize: 11,
    fontWeight: 700,
    letterSpacing: "0.1em",
    textTransform: "uppercase",
  },
  podiumScore: {
    display: "block",
    marginBlockStart: 5,
    color: colors.white,
    fontSize: { default: 30, [breakpoints.lg]: 34 },
    fontWeight: 680,
    lineHeight: 1,
    letterSpacing: "-0.04em",
    fontVariantNumeric: "tabular-nums",
  },
  podiumStats: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    columnGap: 12,
    marginBlockStart: 22,
    paddingBlockStart: 16,
    borderTopWidth: 1,
    borderTopStyle: "solid",
    borderTopColor: "rgba(255,255,255,0.08)",
  },
  stat: { color: colors.slate400, fontSize: 12, fontVariantNumeric: "tabular-nums" },
  movement: {
    display: "inline-flex",
    alignItems: "center",
    columnGap: 4,
    fontSize: 12,
    fontWeight: 650,
    whiteSpace: "nowrap",
  },
  movementUp: { color: colors.lime200 },
  movementDown: { color: colors.rose100 },
  movementFlat: { color: colors.slate400 },
  movementIcon: { width: 13, height: 13 },
  listSection: { marginBlockStart: { default: 40, [breakpoints.sm]: 52 } },
  listHeading: {
    display: "flex",
    alignItems: "end",
    justifyContent: "space-between",
    columnGap: 16,
  },
  listTitle: {
    margin: 0,
    color: colors.white,
    fontSize: 20,
    fontWeight: 620,
    letterSpacing: "-0.025em",
  },
  listRange: { color: colors.slate400, fontSize: 12, fontVariantNumeric: "tabular-nums" },
  listShell: {
    overflow: "hidden",
    marginBlockStart: 16,
    borderRadius: 18,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.09)",
    backgroundColor: "rgba(255,255,255,0.025)",
  },
  columnHeader: {
    display: "grid",
    alignItems: "center",
    columnGap: 12,
    gridTemplateColumns: {
      default: "40px minmax(0, 1fr) auto",
      [breakpoints.sm]: "52px minmax(0, 1fr) 110px 110px 78px",
    },
    minHeight: 44,
    paddingInline: { default: 14, [breakpoints.sm]: 20 },
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: "rgba(255,255,255,0.08)",
    color: colors.slate400,
    fontSize: 10,
    fontWeight: 750,
    letterSpacing: "0.1em",
    textTransform: "uppercase",
  },
  headerMetric: { display: { default: "none", [breakpoints.sm]: "block" }, textAlign: "end" },
  headerScore: { textAlign: "end" },
  rankList: { margin: 0, padding: 0, listStyle: "none" },
  rankRow: {
    display: "grid",
    minHeight: 72,
    alignItems: "center",
    columnGap: 12,
    gridTemplateColumns: {
      default: "40px minmax(0, 1fr) auto",
      [breakpoints.sm]: "52px minmax(0, 1fr) 110px 110px 78px",
    },
    paddingBlock: 10,
    paddingInline: { default: 14, [breakpoints.sm]: 20 },
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: "rgba(255,255,255,0.065)",
    backgroundColor: {
      default: "transparent",
      "@media (hover: hover) and (pointer: fine)": "rgba(255,255,255,0.025)",
    },
  },
  rankRowLast: { borderBottomWidth: 0 },
  rowRank: {
    color: colors.slate400,
    fontSize: 13,
    fontWeight: 700,
    fontVariantNumeric: "tabular-nums",
  },
  rowIdentity: { display: "flex", minWidth: 0, alignItems: "center", columnGap: 10 },
  rowAvatar: { width: 36, height: 36, borderRadius: 11, fontSize: 11 },
  rowActivity: {
    display: { default: "none", [breakpoints.sm]: "block" },
    color: colors.slate300,
    fontSize: 13,
    textAlign: "end",
    fontVariantNumeric: "tabular-nums",
  },
  scoreCell: { textAlign: "end" },
  rowScore: {
    display: "block",
    color: colors.slate100,
    fontSize: 13,
    fontWeight: 700,
    fontVariantNumeric: "tabular-nums",
  },
  scoreUnit: { color: colors.slate400, fontSize: 10, fontWeight: 600 },
  desktopMovement: {
    display: { default: "none", [breakpoints.sm]: "inline-flex" },
    justifyContent: "flex-end",
  },
  mobileMovement: {
    display: { default: "inline-flex", [breakpoints.sm]: "none" },
    marginBlockStart: 4,
  },
  scoringNote: {
    display: "flex",
    alignItems: "flex-start",
    columnGap: 12,
    marginBlockStart: 24,
    borderRadius: 14,
    padding: 16,
    backgroundColor: "rgba(190,242,100,0.055)",
    color: colors.slate400,
    fontSize: 12,
    lineHeight: 1.55,
  },
  noteIcon: { width: 17, height: 17, flexShrink: 0, marginBlockStart: 1, color: colors.lime300 },
  noteStrong: { color: colors.slate200, fontWeight: 650 },
})

export function LeaderboardPage() {
  const [role, setRole] = useState<LeaderboardRole>("pullers")
  const [period, setPeriod] = useState<LeaderboardPeriod>("weekly")
  const entries = useMemo(() => leaderboardFor(role, period), [period, role])
  const copy = roleContent[role]

  return (
    <div {...stylex.props(styles.page)}>
      <header {...stylex.props(styles.hero)}>
        <div {...stylex.props(styles.heroCopy)}>
          <p {...stylex.props(styles.eyebrow)}>Community standings</p>
          <h1 tabIndex={-1} {...stylex.props(styles.title)}>
            See who’s setting the pace.
          </h1>
          <p {...stylex.props(styles.lede)}>
            Compare the top Pullers and Backers by points earned from verified protocol activity.
          </p>
        </div>
        <div {...stylex.props(styles.heroMeta)}>
          <Badge variant="muted">Preview data</Badge>
          <span {...stylex.props(styles.heroMetaText)}>Top 20 · Static mock activity</span>
        </div>
      </header>

      <section aria-label="Leaderboard filters" {...stylex.props(styles.controls)}>
        <fieldset {...stylex.props(styles.group, styles.roleGroup)}>
          <legend {...stylex.props(styles.legend)}>Choose participant type</legend>
          <div {...stylex.props(styles.segmented)}>
            {roles.map((option) => (
              <button
                aria-pressed={role === option.value}
                key={option.value}
                onClick={() => setRole(option.value)}
                type="button"
                {...stylex.props(
                  styles.roleButton,
                  role === option.value ? styles.selectedButton : styles.idleButton,
                )}
              >
                {option.label}
              </button>
            ))}
          </div>
        </fieldset>
        <fieldset {...stylex.props(styles.group, styles.periodGroup)}>
          <legend {...stylex.props(styles.legend)}>Choose ranking period</legend>
          <div {...stylex.props(styles.segmented)}>
            {periods.map((option) => (
              <button
                aria-pressed={period === option.value}
                key={option.value}
                onClick={() => setPeriod(option.value)}
                type="button"
                {...stylex.props(
                  styles.roleButton,
                  styles.periodButton,
                  period === option.value ? styles.selectedButton : styles.idleButton,
                )}
              >
                {option.label}
              </button>
            ))}
          </div>
        </fieldset>
      </section>

      <p aria-live="polite" aria-atomic="true" {...stylex.props(styles.status)}>
        Showing the {period} {copy.name} leaderboard.
      </p>

      <section aria-labelledby="leaderboard-title">
        <div {...stylex.props(styles.boardHeader)}>
          <div>
            <h2 id="leaderboard-title" {...stylex.props(styles.boardTitle)}>
              {periodNames[period]} {copy.name}
            </h2>
            <p {...stylex.props(styles.boardDescription)}>{copy.description}</p>
          </div>
          <span {...stylex.props(styles.boardCount)}>
            <Trophy aria-hidden {...stylex.props(styles.boardCountIcon)} />
            Top 20 ranked by points
          </span>
        </div>

        <div aria-label={`Top three ${copy.name}`} {...stylex.props(styles.podium)}>
          {entries.slice(0, 3).map((entry, index) => (
            <PodiumCard entry={entry} key={entry.id} rank={index + 1} role={role} />
          ))}
        </div>
      </section>

      <section aria-labelledby="more-standings" {...stylex.props(styles.listSection)}>
        <div {...stylex.props(styles.listHeading)}>
          <h2 id="more-standings" {...stylex.props(styles.listTitle)}>
            More standings
          </h2>
          <span {...stylex.props(styles.listRange)}>Ranks 4–20</span>
        </div>
        <div {...stylex.props(styles.listShell)}>
          <div aria-hidden="true" {...stylex.props(styles.columnHeader)}>
            <span>Rank</span>
            <span>{copy.singular}</span>
            <span {...stylex.props(styles.headerMetric)}>{copy.metric}</span>
            <span {...stylex.props(styles.headerScore)}>Points</span>
            <span {...stylex.props(styles.headerMetric)}>Change</span>
          </div>
          <ol
            aria-label={`${copy.name} ranked 4 through 20`}
            start={4}
            {...stylex.props(styles.rankList)}
          >
            {entries.slice(3).map((entry, index, rows) => (
              <RankRow
                entry={entry}
                isLast={index === rows.length - 1}
                key={entry.id}
                rank={index + 4}
                role={role}
              />
            ))}
          </ol>
        </div>
      </section>

      <aside {...stylex.props(styles.scoringNote)}>
        <ShieldCheck aria-hidden {...stylex.props(styles.noteIcon)} />
        <span>
          <strong {...stylex.props(styles.noteStrong)}>Scoring preview.</strong> Puller points
          reflect completed pulls and settlements. Backer points reflect active backing and earned
          proceeds. Final weights will be published before launch.
        </span>
      </aside>
    </div>
  )
}

function PodiumCard({
  entry,
  rank,
  role,
}: {
  entry: LeaderboardEntry
  rank: number
  role: LeaderboardRole
}) {
  return (
    <article {...stylex.props(styles.podiumCard, rank === 1 && styles.winnerCard)}>
      <div {...stylex.props(styles.podiumTop)}>
        <span
          aria-label={`Rank ${rank}`}
          {...stylex.props(styles.rankBadge, rank === 1 && styles.winnerBadge)}
        >
          {String(rank).padStart(2, "0")}
        </span>
        {rank === 1 ? (
          <Crown aria-hidden {...stylex.props(styles.crown)} />
        ) : (
          <Sparkles aria-hidden {...stylex.props(styles.crown)} />
        )}
      </div>
      <div {...stylex.props(styles.podiumIdentity)}>
        <Avatar name={entry.name} />
        <div {...stylex.props(styles.identityText)}>
          <strong {...stylex.props(styles.participantName)}>{entry.name}</strong>
          <bdi {...stylex.props(styles.participantAddress)}>{entry.address}</bdi>
        </div>
      </div>
      <span {...stylex.props(styles.scoreLabel)}>Leaderboard points</span>
      <strong {...stylex.props(styles.podiumScore)}>{numberFormatter.format(entry.score)}</strong>
      <div {...stylex.props(styles.podiumStats)}>
        <span {...stylex.props(styles.stat)}>{formatActivity(entry.activity, role)}</span>
        <Movement value={entry.movement} />
      </div>
    </article>
  )
}

function RankRow({
  entry,
  isLast,
  rank,
  role,
}: {
  entry: LeaderboardEntry
  isLast: boolean
  rank: number
  role: LeaderboardRole
}) {
  return (
    <li {...stylex.props(styles.rankRow, isLast && styles.rankRowLast)}>
      <span aria-label={`Rank ${rank}`} {...stylex.props(styles.rowRank)}>
        {String(rank).padStart(2, "0")}
      </span>
      <div {...stylex.props(styles.rowIdentity)}>
        <Avatar compact name={entry.name} />
        <div {...stylex.props(styles.identityText)}>
          <strong {...stylex.props(styles.participantName)}>{entry.name}</strong>
          <span {...stylex.props(styles.participantAddress)}>
            <bdi>{entry.address}</bdi>
            <span {...stylex.props(styles.mobileActivity)}>
              {" "}
              · {formatActivity(entry.activity, role)}
            </span>
          </span>
        </div>
      </div>
      <span {...stylex.props(styles.rowActivity)}>{formatActivity(entry.activity, role)}</span>
      <div {...stylex.props(styles.scoreCell)}>
        <strong {...stylex.props(styles.rowScore)}>
          {compactFormatter.format(entry.score)}{" "}
          <span {...stylex.props(styles.scoreUnit)}>pts</span>
        </strong>
        <Movement mobile value={entry.movement} />
      </div>
      <Movement value={entry.movement} />
    </li>
  )
}

function Avatar({ compact = false, name }: { compact?: boolean; name: string }) {
  const initials = name
    .split(" ")
    .map((word) => word[0])
    .join("")
    .slice(0, 2)
  return (
    <span aria-hidden="true" {...stylex.props(styles.avatar, compact && styles.rowAvatar)}>
      {initials}
    </span>
  )
}

function Movement({ mobile = false, value }: { mobile?: boolean; value: number }) {
  const Icon = value > 0 ? ArrowUp : value < 0 ? ArrowDown : Minus
  const label =
    value > 0
      ? `Up ${value} places`
      : value < 0
        ? `Down ${Math.abs(value)} places`
        : "No rank change"
  return (
    <span
      aria-label={label}
      {...stylex.props(
        styles.movement,
        value > 0 ? styles.movementUp : value < 0 ? styles.movementDown : styles.movementFlat,
        mobile ? styles.mobileMovement : styles.desktopMovement,
      )}
    >
      <Icon aria-hidden {...stylex.props(styles.movementIcon)} />
      {value === 0 ? "—" : Math.abs(value)}
    </span>
  )
}

function formatActivity(activity: number, role: LeaderboardRole) {
  return role === "pullers"
    ? `${numberFormatter.format(Math.round(activity))} pulls`
    : `${activity.toFixed(1)} ETH backed`
}
