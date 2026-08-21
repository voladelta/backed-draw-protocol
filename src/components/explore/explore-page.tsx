import {
  ArrowRight,
  ChevronDown,
  CircleHelp,
  Search,
  ShieldCheck,
  WalletCards,
  type LucideIcon,
} from "lucide-react"
import * as stylex from "@stylexjs/stylex"
import type { StyleXStyles } from "@stylexjs/stylex"
import type { ChangeEvent } from "react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { breakpoints, colors } from "../../styles/tokens.stylex"

import { MarketCard } from "./market-card"
import type { MarketData, SettlementAsset } from "./types"

export interface ExplorePageProps {
  markets: MarketData[]
  activeAsset?: SettlementAsset | "all"
  searchValue?: string
  onAssetChange?: (asset: SettlementAsset | "all") => void
  onSearchChange?: (value: string) => void
  onPull?: (market: MarketData) => void
  onOpenMarket?: (market: MarketData) => void
  onDeposit?: () => void
  style?: StyleXStyles
}

const assetFilters: Array<{ label: string; value: SettlementAsset | "all" }> = [
  { label: "All markets", value: "all" },
  { label: "ETH", value: "ETH" },
  { label: "USDG", value: "USDG" },
]

const styles = stylex.create({
  root: {
    display: "flex",
    flexDirection: "column",
    rowGap: { default: 40, [breakpoints.sm]: 56 },
  },
  hero: {
    display: "grid",
    alignItems: "end",
    gap: 32,
    gridTemplateColumns: { default: "minmax(0, 1fr)", [breakpoints.lg]: "minmax(0, 1fr) auto" },
  },
  heroCopy: { maxWidth: 768 },
  heroTitle: {
    marginTop: 20,
    color: colors.white,
    fontSize: { default: 36, [breakpoints.sm]: 48, [breakpoints.lg]: 60 },
    fontWeight: 600,
    lineHeight: 0.96,
    letterSpacing: "-0.06em",
  },
  accent: { color: colors.lime300 },
  heroDescription: {
    maxWidth: 672,
    marginTop: 20,
    color: colors.slate400,
    fontSize: { default: 16, [breakpoints.sm]: 18 },
    lineHeight: "28px",
  },
  depositButton: { width: { default: "100%", [breakpoints.sm]: "auto" } },
  icon16: { width: 16, height: 16 },
  icon14: { width: 14, height: 14 },
  assurances: {
    display: "grid",
    gap: 12,
    gridTemplateColumns: {
      default: "minmax(0, 1fr)",
      [breakpoints.sm]: "repeat(3, minmax(0, 1fr))",
    },
  },
  marketHeader: {
    display: "flex",
    flexDirection: { default: "column", [breakpoints.sm]: "row" },
    alignItems: { default: "stretch", [breakpoints.sm]: "center" },
    justifyContent: "space-between",
    gap: 20,
  },
  eyebrow: {
    color: colors.lime300,
    fontSize: 12,
    fontWeight: 700,
    textTransform: "uppercase",
    letterSpacing: "0.16em",
  },
  sectionTitle: {
    marginTop: 8,
    color: colors.white,
    fontSize: 24,
    fontWeight: 600,
    letterSpacing: "-0.045em",
  },
  searchLabel: { display: "block", width: { default: "100%", [breakpoints.sm]: 272 } },
  searchLabelText: {
    display: "block",
    marginBottom: 8,
    color: colors.slate400,
    fontSize: 12,
    fontWeight: 600,
  },
  searchField: { position: "relative", display: "block" },
  searchIcon: {
    pointerEvents: "none",
    position: "absolute",
    left: 14,
    top: "50%",
    width: 16,
    height: 16,
    color: colors.slate500,
    transform: "translateY(-50%)",
  },
  searchInput: {
    width: "100%",
    height: 44,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: { default: "rgba(255,255,255,0.1)", ":focus": "rgba(190,242,100,0.5)" },
    paddingLeft: 40,
    paddingRight: 16,
    backgroundColor: { default: "rgba(255,255,255,0.04)", ":focus": "rgba(255,255,255,0.06)" },
    color: colors.white,
    fontSize: 14,
    outline: { default: "none", ":focus": "2px solid rgba(190,242,100,0.1)" },
    transitionProperty: "border-color, box-shadow, background-color",
    transitionDuration: "150ms",
    "::placeholder": { color: colors.slate600 },
  },
  filterBar: {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
    gap: 16,
    marginTop: 24,
    paddingBottom: 16,
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: "rgba(255,255,255,0.08)",
  },
  filters: { display: "flex", columnGap: 4, overflowX: "auto" },
  filter: {
    flexShrink: 0,
    borderWidth: 0,
    borderRadius: 8,
    paddingBlock: 8,
    paddingInline: 12,
    fontSize: 14,
    fontWeight: 500,
    transitionProperty: "background-color, color",
    transitionDuration: "150ms",
    transitionTimingFunction: "ease-out",
    outline: { default: "none", ":focus-visible": `2px solid ${colors.lime300}` },
  },
  filterActive: { backgroundColor: colors.lime300, color: colors.slate950 },
  filterIdle: {
    backgroundColor: { default: "transparent", ":hover": "rgba(255,255,255,0.06)" },
    color: { default: colors.slate400, ":hover": colors.slate100 },
  },
  sortButton: {
    display: { default: "none", [breakpoints.sm]: "flex" },
    alignItems: "center",
    columnGap: 6,
    borderWidth: 0,
    backgroundColor: "transparent",
    color: { default: colors.slate400, ":hover": colors.white },
    fontSize: 14,
    fontWeight: 500,
    transitionProperty: "color",
  },
  visuallyHidden: {
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
  marketGrid: {
    display: "grid",
    gap: 20,
    marginTop: 24,
    gridTemplateColumns: {
      default: "minmax(0, 1fr)",
      [breakpoints.sm]: "repeat(2, minmax(0, 1fr))",
      [breakpoints.xl]: "repeat(3, minmax(0, 1fr))",
    },
  },
  empty: {
    display: "grid",
    minHeight: 256,
    placeItems: "center",
    marginTop: 24,
    borderRadius: 16,
    borderWidth: 1,
    borderStyle: "dashed",
    borderColor: "rgba(255,255,255,0.14)",
    padding: 32,
    backgroundColor: "rgba(255,255,255,0.025)",
    textAlign: "center",
  },
  emptyTitle: { color: colors.slate200, fontWeight: 600 },
  emptyText: { marginTop: 4, color: colors.slate500, fontSize: 14 },
  clearButton: { marginTop: 16 },
  trustPoint: {
    display: "flex",
    alignItems: "center",
    columnGap: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.08)",
    paddingBlock: 14,
    paddingInline: 16,
    backgroundColor: "rgba(255,255,255,0.035)",
    color: colors.slate300,
    fontSize: 14,
    fontWeight: 500,
  },
  trustIcon: {
    display: "grid",
    width: 28,
    height: 28,
    flexShrink: 0,
    placeItems: "center",
    borderRadius: 8,
    backgroundColor: "rgba(190,242,100,0.1)",
    color: colors.lime200,
  },
})

/** A controlled marketplace view: data and all wallet actions remain owned by the route. */
export function ExplorePage({
  markets,
  activeAsset = "all",
  searchValue = "",
  onAssetChange,
  onSearchChange,
  onPull,
  onOpenMarket,
  onDeposit,
  style,
}: ExplorePageProps) {
  const visibleMarkets = markets.filter(
    (market) => activeAsset === "all" || market.settlementAsset === activeAsset,
  )

  return (
    <div {...stylex.props(styles.root, style)}>
      <section {...stylex.props(styles.hero)}>
        <div {...stylex.props(styles.heroCopy)}>
          <Badge dot variant="success">
            Verifiable draws, live now
          </Badge>
          <h1 {...stylex.props(styles.heroTitle)}>
            Back a collectible. Enter the <span {...stylex.props(styles.accent)}>draw</span>.
          </h1>
          <p {...stylex.props(styles.heroDescription)}>
            Deposit an NFT to earn from every pull, or enter a draw at a transparent pool-derived
            price. Each market settles in one asset.
          </p>
        </div>
        <Button style={styles.depositButton} onClick={onDeposit} size="lg">
          <WalletCards aria-hidden {...stylex.props(styles.icon16)} />
          Deposit a collectible
          <ArrowRight aria-hidden {...stylex.props(styles.icon16)} />
        </Button>
      </section>

      <section aria-label="Protocol assurances" {...stylex.props(styles.assurances)}>
        <TrustPoint icon={ShieldCheck} text="Proof-backed positions" />
        <TrustPoint icon={CircleHelp} text="Transparent pull pricing" />
        <TrustPoint icon={WalletCards} text="Pay with ETH or USDG" />
      </section>

      <section>
        <div {...stylex.props(styles.marketHeader)}>
          <div>
            <p {...stylex.props(styles.eyebrow)}>Marketplace</p>
            <h2 {...stylex.props(styles.sectionTitle)}>Explore active markets</h2>
          </div>
          <label {...stylex.props(styles.searchLabel)}>
            <span {...stylex.props(styles.searchLabelText)}>Search markets</span>
            <span {...stylex.props(styles.searchField)}>
              <Search aria-hidden {...stylex.props(styles.searchIcon)} />
              <input
                aria-label="Search markets"
                {...stylex.props(styles.searchInput)}
                id="market-search"
                onChange={(event: ChangeEvent<HTMLInputElement>) =>
                  onSearchChange?.(event.target.value)
                }
                placeholder="Try CryptoPunks or Azuki"
                value={searchValue}
              />
            </span>
          </label>
        </div>

        <div {...stylex.props(styles.filterBar)}>
          <div aria-label="Settlement asset" {...stylex.props(styles.filters)}>
            {assetFilters.map((filter) => {
              const isActive = activeAsset === filter.value
              return (
                <button
                  aria-pressed={isActive}
                  {...stylex.props(
                    styles.filter,
                    isActive ? styles.filterActive : styles.filterIdle,
                  )}
                  key={filter.value}
                  onClick={() => onAssetChange?.(filter.value)}
                  type="button"
                >
                  {filter.label}
                </button>
              )
            })}
          </div>
          <button {...stylex.props(styles.sortButton)} type="button">
            Most active <ChevronDown aria-hidden {...stylex.props(styles.icon16)} />
          </button>
        </div>

        <p aria-live="polite" {...stylex.props(styles.visuallyHidden)} role="status">
          {visibleMarkets.length} {visibleMarkets.length === 1 ? "market" : "markets"} shown
        </p>
        {visibleMarkets.length ? (
          <div {...stylex.props(styles.marketGrid)}>
            {visibleMarkets.map((market) => (
              <MarketCard key={market.id} market={market} onOpen={onOpenMarket} onPull={onPull} />
            ))}
          </div>
        ) : (
          <div {...stylex.props(styles.empty)}>
            <div>
              <p {...stylex.props(styles.emptyTitle)}>No markets in this asset yet</p>
              <p {...stylex.props(styles.emptyText)}>
                Try another settlement asset or clear your search.
              </p>
              <Button
                style={styles.clearButton}
                onClick={() => {
                  onAssetChange?.("all")
                  onSearchChange?.("")
                }}
                size="sm"
                variant="secondary"
              >
                Clear filters
              </Button>
            </div>
          </div>
        )}
      </section>
    </div>
  )
}

function TrustPoint({ icon: Icon, text }: { icon: LucideIcon; text: string }) {
  return (
    <div {...stylex.props(styles.trustPoint)}>
      <span {...stylex.props(styles.trustIcon)}>
        <Icon aria-hidden {...stylex.props(styles.icon14)} />
      </span>
      {text}
    </div>
  )
}
