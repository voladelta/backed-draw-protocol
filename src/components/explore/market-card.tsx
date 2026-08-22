import { ArrowUpRight, Check, Crown, Dices, Layers3, Sparkles, type LucideIcon } from "lucide-react"
import * as stylex from "@stylexjs/stylex"
import type { StyleXStyles } from "@stylexjs/stylex"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { colors } from "../../styles/tokens.stylex"

import type { MarketData } from "./types"

export interface MarketCardProps {
  market: MarketData
  onPull?: (market: MarketData) => void
  onOpen?: (market: MarketData) => void
  style?: StyleXStyles
}

const statusCopy = {
  active: "Live",
  paused: "Paused",
  "coming-soon": "Coming soon",
} as const

const styles = stylex.create({
  card: {
    position: "relative",
    display: "flex",
    height: "100%",
    flexDirection: "column",
    overflow: "hidden",
    borderColor: "rgba(255,255,255,0.09)",
    boxShadow: "0 16px 50px rgba(0,0,0,0.18)",
  },
  body: { display: "flex", flex: 1, flexDirection: "column", padding: 20 },
  headingRow: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    gap: 12,
  },
  minWidth: { minWidth: 0 },
  collection: {
    display: "flex",
    alignItems: "center",
    columnGap: 6,
    color: colors.slate400,
    fontSize: 12,
  },
  truncate: { overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" },
  checkIcon: { width: 14, height: 14, color: colors.lime300 },
  title: {
    marginTop: 4,
    overflow: "hidden",
    color: colors.white,
    fontSize: 18,
    fontWeight: 600,
    letterSpacing: "-0.035em",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  stats: {
    display: "grid",
    gridTemplateColumns: "repeat(2, minmax(0, 1fr))",
    gap: 1,
    marginTop: 20,
    overflow: "hidden",
    borderRadius: 12,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.08)",
    backgroundColor: "rgba(255,255,255,0.08)",
  },
  pullRow: {
    display: "flex",
    alignItems: "flex-end",
    justifyContent: "space-between",
    gap: 12,
    marginTop: 20,
  },
  label: {
    color: colors.slate500,
    fontSize: 11,
    fontWeight: 600,
    textTransform: "uppercase",
    letterSpacing: "0.12em",
  },
  price: {
    marginTop: 4,
    color: colors.white,
    fontSize: 20,
    fontWeight: 600,
    letterSpacing: "-0.04em",
  },
  asset: { color: colors.slate400, fontSize: 14 },
  usdPrice: { marginTop: 2, color: colors.slate500, fontSize: 12 },
  footer: {
    display: "grid",
    gridTemplateColumns: "minmax(0, 1fr) auto",
    alignItems: "center",
    gap: 12,
    marginTop: 20,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopStyle: "solid",
    borderTopColor: "rgba(255,255,255,0.08)",
  },
  backing: {
    display: "flex",
    alignItems: "center",
    columnGap: 6,
    color: colors.slate400,
    fontSize: 12,
  },
  crownIcon: { width: 14, height: 14, color: colors.amber200 },
  actions: { display: "flex", alignItems: "center", columnGap: 8 },
  icon16: { width: 16, height: 16 },
  icon14: { width: 14, height: 14 },
  stat: { minWidth: 0, paddingBlock: 12, paddingInline: 14, backgroundColor: "rgba(13,19,32,0.9)" },
  statLabel: {
    display: "flex",
    alignItems: "center",
    columnGap: 6,
    color: colors.slate500,
    fontSize: 10,
    fontWeight: 600,
    textTransform: "uppercase",
    letterSpacing: "0.1em",
  },
  icon12: { width: 12, height: 12 },
  statValue: {
    marginTop: 4,
    overflow: "hidden",
    color: colors.slate100,
    fontSize: 14,
    fontWeight: 600,
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  preview: {
    position: "relative",
    aspectRatio: "16 / 10",
    overflow: "hidden",
    borderBottomWidth: 1,
    borderBottomStyle: "solid",
    borderBottomColor: "rgba(255,255,255,0.08)",
    backgroundColor: "#111827",
  },
  previewImage: { width: "100%", height: "100%", objectFit: "cover" },
  previewFallback: (accent: string) => ({
    position: "relative",
    width: "100%",
    height: "100%",
    overflow: "hidden",
    backgroundImage: `radial-gradient(circle at 68% 25%, ${accent}88, transparent 25%), linear-gradient(135deg, #111827 0%, #162033 48%, #080b12 100%)`,
  }),
  circle: {
    position: "absolute",
    top: -64,
    right: -48,
    width: 208,
    height: 208,
    borderRadius: "50%",
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.2)",
  },
  diamond: {
    position: "absolute",
    bottom: -64,
    left: "14%",
    width: 208,
    height: 208,
    borderRadius: 36,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.1)",
    backgroundColor: "rgba(255,255,255,0.035)",
    transform: "rotate(45deg)",
  },
  grid: {
    position: "absolute",
    inset: 0,
    opacity: 0.2,
    backgroundImage:
      "linear-gradient(rgba(255,255,255,.18) 1px,transparent 1px), linear-gradient(90deg,rgba(255,255,255,.18) 1px,transparent 1px)",
    backgroundSize: "28px 28px",
  },
  fallbackLabel: {
    position: "absolute",
    insetInline: 20,
    bottom: 20,
    display: "flex",
    alignItems: "flex-end",
    justifyContent: "space-between",
  },
  nftName: {
    maxWidth: "72%",
    color: "rgba(255,255,255,0.95)",
    fontSize: 24,
    fontWeight: 900,
    lineHeight: 0.85,
    textTransform: "uppercase",
    letterSpacing: "-0.08em",
  },
  tokenId: {
    borderRadius: 8,
    borderWidth: 1,
    borderStyle: "solid",
    borderColor: "rgba(255,255,255,0.2)",
    paddingBlock: 4,
    paddingInline: 8,
    backgroundColor: "rgba(2,6,23,0.35)",
    color: "rgba(255,255,255,0.75)",
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
    fontSize: 10,
  },
  previewShade: {
    pointerEvents: "none",
    position: "absolute",
    inset: 0,
    backgroundImage:
      "linear-gradient(to top, rgba(2,6,23,0.3), transparent, rgba(255,255,255,0.02))",
  },
})

export function MarketCard({ market, onPull, onOpen, style }: MarketCardProps) {
  const status = market.status ?? "active"
  const isLive = status === "active"

  return (
    <Card style={[styles.card, style]}>
      <NftPreview nft={market.featuredNft} />

      <div {...stylex.props(styles.body)}>
        <div {...stylex.props(styles.headingRow)}>
          <div {...stylex.props(styles.minWidth)}>
            <div {...stylex.props(styles.collection)}>
              <span {...stylex.props(styles.truncate)}>{market.collection.name}</span>
              {market.collection.verified ? (
                <Check aria-label="Verified collection" {...stylex.props(styles.checkIcon)} />
              ) : null}
            </div>
            <h3 {...stylex.props(styles.title)}>{market.name}</h3>
          </div>
          <Badge dot variant={isLive ? "success" : "muted"}>
            {statusCopy[status]}
          </Badge>
        </div>

        <div {...stylex.props(styles.stats)}>
          <Stat
            icon={Layers3}
            label="Active positions"
            value={market.activePositions.toLocaleString()}
          />
          <Stat icon={Sparkles} label="Total backing" value={market.totalBacking} />
        </div>

        <div {...stylex.props(styles.pullRow)}>
          <div>
            <p {...stylex.props(styles.label)}>Next pull</p>
            <p {...stylex.props(styles.price)}>
              {market.pullPrice}{" "}
              <span {...stylex.props(styles.asset)}>{market.settlementAsset}</span>
            </p>
            {market.pullPriceUsd ? (
              <p {...stylex.props(styles.usdPrice)}>{market.pullPriceUsd}</p>
            ) : null}
          </div>
          <Badge variant="currency">{market.settlementAsset}</Badge>
        </div>

        <div {...stylex.props(styles.footer)}>
          <div {...stylex.props(styles.backing)}>
            <Crown aria-hidden {...stylex.props(styles.crownIcon)} />
            <span>
              {market.crownBacking
                ? `Crown · ${market.crownBacking}`
                : market.apy
                  ? `${market.apy} depositor APY`
                  : "Equal-share rewards"}
            </span>
          </div>
          <div {...stylex.props(styles.actions)}>
            <Button
              aria-label={`Open ${market.name}`}
              onClick={() => onOpen?.(market)}
              size="icon"
              variant="ghost"
            >
              <ArrowUpRight aria-hidden {...stylex.props(styles.icon16)} />
            </Button>
            <Button disabled={!isLive} onClick={() => onPull?.(market)} size="sm">
              <Dices aria-hidden {...stylex.props(styles.icon14)} />
              Pull
            </Button>
          </div>
        </div>
      </div>
    </Card>
  )
}

function Stat({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div {...stylex.props(styles.stat)}>
      <div {...stylex.props(styles.statLabel)}>
        <Icon aria-hidden {...stylex.props(styles.icon12)} />
        <span {...stylex.props(styles.truncate)}>{label}</span>
      </div>
      <p {...stylex.props(styles.statValue)}>{value}</p>
    </div>
  )
}

function NftPreview({ nft }: { nft: MarketData["featuredNft"] }) {
  const accent = nft.accent ?? "#bef264"

  return (
    <div {...stylex.props(styles.preview)}>
      {nft.imageUrl ? (
        <img alt={nft.name} {...stylex.props(styles.previewImage)} src={nft.imageUrl} />
      ) : (
        <div
          aria-label={`${nft.name} preview`}
          {...stylex.props(styles.previewFallback(accent))}
          role="img"
        >
          <div aria-hidden {...stylex.props(styles.circle)} />
          <div aria-hidden {...stylex.props(styles.diamond)} />
          <div aria-hidden {...stylex.props(styles.grid)} />
          <div {...stylex.props(styles.fallbackLabel)}>
            <span {...stylex.props(styles.nftName)}>{nft.name}</span>
            <span {...stylex.props(styles.tokenId)}>{nft.tokenId ?? "1/1"}</span>
          </div>
        </div>
      )}
      <div aria-hidden {...stylex.props(styles.previewShade)} />
    </div>
  )
}
