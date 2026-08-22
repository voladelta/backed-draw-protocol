import {
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  CircleCheck,
  Coins,
  Crown,
  Dices,
  Layers3,
  Minus,
  Plus,
  ReceiptText,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  Trophy,
  WalletCards,
} from "lucide-react"
import * as stylex from "@stylexjs/stylex"
import { lazy, Suspense, useEffect, useRef, useState } from "react"
import { useAccount, useWriteContract } from "wagmi"
import { parseUnits, zeroHash } from "viem"
import { recentDraws } from "@/data/markets"
import { ALL_POOLS_ID, poolOptions } from "@/data/pool-selection"
import { spinAudio } from "@/audio/spin-audio"
import { launchRevealConfetti } from "@/lib/reveal-confetti"
import { formatValue } from "@/lib/utils"
import type { Market, Position, PullStage, SettlementAsset } from "@/types/protocol"
import { drawRouterAbi, drawRouterAddress, getPullRouteConfig } from "@/web3/contracts"
import type { DeckCycleRequest } from "@/components/nft/nft-card-scene"

const NftCardScene = lazy(() =>
  import("@/components/nft/nft-card-scene").then((module) => ({ default: module.NftCardScene })),
)
const shortenWallet = (address: string) => `${address.slice(0, 6)}…${address.slice(-4)}`

const accessibilityStyles = stylex.create({
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
})

type PullExperienceProps = {
  market: Market
  stage: PullStage
  count: number
  paymentAsset: SettlementAsset
  revealedPositionId?: string
  settlementChoice?: "keep" | "cash" | "draw" | "relist"
  onMarketChange: (marketId: string) => void
  onCount: (count: number) => void
  onPaymentAsset: (asset: SettlementAsset) => void
  onStage: (stage: PullStage) => void
  onReveal: () => void
  onSettle: (choice: "keep" | "cash" | "draw" | "relist") => void
  onReset: () => void
}

export function PullExperience(props: PullExperienceProps) {
  const [carouselIndex, setCarouselIndex] = useState(0)
  const revealedPosition = props.revealedPositionId
    ? props.market.positions.find((position) => position.id === props.revealedPositionId)
    : undefined
  const celebrateReveal = () => void launchRevealConfetti().catch(() => undefined)

  return (
    <div className="gacha-page">
      <h1 {...stylex.props(accessibilityStyles.visuallyHidden)}>
        Pull a collectible from {props.market.name}
      </h1>
      <PoolTabs activeMarketId={props.market.id} onMarketChange={props.onMarketChange} />
      <section
        aria-label={`${props.market.name} collectible pull machine`}
        aria-labelledby={`pool-tab-${props.market.id}`}
        className="gacha-shell"
        id="pool-panel"
        role="tabpanel"
      >
        <StageArtifact
          activeIndex={carouselIndex}
          key={`stage-${props.market.id}`}
          market={props.market}
          onRevealReady={celebrateReveal}
          onSelect={setCarouselIndex}
          position={revealedPosition}
          stage={props.stage}
        />
        <PullCommand {...props} key={`command-${props.market.id}`} position={revealedPosition} />
      </section>
      <RecentPulls />
      <p aria-live="polite" {...stylex.props(accessibilityStyles.visuallyHidden)} role="status">
        {props.stage === "configure"
          ? `${props.market.name} pull ready. ${props.count} ${props.count === 1 ? "pull" : "pulls"} selected.`
          : props.stage === "drawing"
            ? "Your pull is being verified against the committed pool root."
            : props.stage === "revealed"
              ? `${revealedPosition?.name ?? "A position"} revealed. Choose a settlement option.`
              : `${revealedPosition?.name ?? "Your position"} settlement complete.`}
      </p>
    </div>
  )
}

function PoolTabs({
  activeMarketId,
  onMarketChange,
}: {
  activeMarketId: string
  onMarketChange: (marketId: string) => void
}) {
  const selectTab = (index: number) => {
    const nextMarket = poolOptions[index]
    if (!nextMarket) return
    onMarketChange(nextMarket.id)
    window.requestAnimationFrame(() =>
      document.getElementById(`pool-tab-${nextMarket.id}`)?.focus(),
    )
  }

  return (
    <div className="pool-tabs-scroll">
      <div aria-label="Select a pool" className="pool-tabs" role="tablist">
        {poolOptions.map((item, index) => {
          const isActive = item.id === activeMarketId
          const isAllPools = item.id === ALL_POOLS_ID
          return (
            <button
              aria-controls="pool-panel"
              aria-selected={isActive}
              className={isActive ? "is-active" : ""}
              id={`pool-tab-${item.id}`}
              key={item.id}
              onClick={() => onMarketChange(item.id)}
              onKeyDown={(event) => {
                if (event.key === "ArrowLeft") {
                  event.preventDefault()
                  selectTab((index - 1 + poolOptions.length) % poolOptions.length)
                }
                if (event.key === "ArrowRight") {
                  event.preventDefault()
                  selectTab((index + 1) % poolOptions.length)
                }
                if (event.key === "Home") {
                  event.preventDefault()
                  selectTab(0)
                }
                if (event.key === "End") {
                  event.preventDefault()
                  selectTab(poolOptions.length - 1)
                }
              }}
              role="tab"
              tabIndex={isActive ? 0 : -1}
              type="button"
            >
              {isAllPools ? (
                <span aria-hidden="true" className="pool-tab-all-icon">
                  <Layers3 />
                </span>
              ) : (
                <img alt="" src={item.heroImage} />
              )}
              <span>
                <strong>{item.name}</strong>
                <small>
                  {isAllPools ? `${poolOptions.length - 1} pools` : `${item.activePositions} live`}
                </small>
              </span>
              <em>{isAllPools ? "Any card" : formatValue(item.pullPrice, item.asset)}</em>
            </button>
          )
        })}
      </div>
    </div>
  )
}

function StageArtifact({
  market,
  stage,
  position,
  activeIndex,
  onSelect,
  onRevealReady,
}: {
  market: Market
  stage: PullStage
  position?: Position
  activeIndex: number
  onSelect: (index: number) => void
  onRevealReady: () => void
}) {
  const isAllPools = market.id === ALL_POOLS_ID
  const [cycleRequest, setCycleRequest] = useState<DeckCycleRequest>({ id: 0, direction: 1 })
  const [inspected, setInspected] = useState(false)
  const selectedIndex =
    market.positions.length === 0
      ? 0
      : ((activeIndex % market.positions.length) + market.positions.length) %
        market.positions.length
  const selectedPosition = market.positions[selectedIndex]
  const cycleCard = (direction: -1 | 1) => {
    spinAudio.prepare()
    setCycleRequest((current) => ({ id: current.id + 1, direction }))
  }
  return (
    <section
      className={`gacha-arena stage-${stage}`}
      aria-label={`${market.name} collectible arena`}
    >
      <div className="artifact-stage">
        <div className="arena-market">
          <span>
            {stage === "configure"
              ? `${market.positions.length} featured · ${market.activePositions} live · ${
                  isAllPools ? `${poolOptions.length - 1} pools` : market.asset
                }`
              : stage === "drawing"
                ? "Verifiable draw"
                : "Your pull"}
          </span>
          <strong>
            {stage === "configure" ? (
              <>
                <Crown /> {inspected ? selectedPosition?.name : "Face-down card"}
              </>
            ) : stage === "drawing" ? (
              <>
                <Dices /> Pool root locked
              </>
            ) : (
              <>
                <Trophy /> {position?.name}
              </>
            )}
          </strong>
        </div>
        <div
          aria-label={`${market.name} card deck. Drag the top card left or right to peek, then release it to move that card to the back. Use either arrow key for the same action.`}
          className="artifact-canvas"
          onKeyDown={(event) => {
            if (stage !== "configure") return
            if (event.key === "ArrowLeft") {
              event.preventDefault()
              cycleCard(-1)
            }
            if (event.key === "ArrowRight") {
              event.preventDefault()
              cycleCard(1)
            }
          }}
          onPointerDown={(event) => event.currentTarget.focus()}
          role={stage === "configure" ? "group" : undefined}
          tabIndex={stage === "configure" ? 0 : -1}
        >
          <Suspense fallback={<div className="artifact-canvas-fallback" />}>
            <NftCardScene
              activeIndex={activeIndex}
              cycleRequest={cycleRequest}
              market={market}
              onRevealReady={onRevealReady}
              onInspectionChange={setInspected}
              onSelect={onSelect}
              revealedPosition={position}
              stage={stage}
            />
          </Suspense>
        </div>
        {stage === "configure" ? (
          <>
            <div className="arena-spin-controls">
              <button
                aria-label="Move the top card around the left side to the back"
                onClick={() => cycleCard(-1)}
                type="button"
              >
                <ChevronLeft aria-hidden="true" />
              </button>
              <span aria-live="polite">
                {selectedIndex + 1} / {market.positions.length}
              </span>
              <button
                aria-label="Move the top card around the right side to the back"
                onClick={() => cycleCard(1)}
                type="button"
              >
                <ChevronRight aria-hidden="true" />
              </button>
            </div>
            <div className="arena-gesture">
              <span>{inspected ? "Drag to throw · card returns to bottom" : "Click to flip"}</span>
              <strong>
                {inspected
                  ? [selectedPosition?.sourceMarketName, selectedPosition?.collection]
                      .filter(Boolean)
                      .join(" · ")
                  : "Top card is face-down"}
              </strong>
            </div>
          </>
        ) : (
          <div className="artifact-stage-copy">
            <p>
              {stage === "drawing"
                ? "Randomness requested"
                : stage === "settled"
                  ? "Settlement complete"
                  : "Position revealed"}
            </p>
            <strong>
              {stage === "drawing"
                ? "Shuffling the committed pack…"
                : stage === "settled"
                  ? "Your receipt is ready"
                  : position?.collection}
            </strong>
            <small>
              {stage === "drawing"
                ? "Five rapid shuffles before the top card turns over."
                : stage === "revealed"
                  ? `${formatValue(position?.backing ?? 0, position?.asset ?? market.asset)} backing`
                  : "Pull again whenever you are ready."}
            </small>
          </div>
        )}
      </div>
    </section>
  )
}

function PullCommand({
  market,
  stage,
  count,
  paymentAsset,
  position,
  settlementChoice,
  onCount,
  onPaymentAsset,
  onStage,
  onReveal,
  onSettle,
  onReset,
}: PullExperienceProps & { position?: Position }) {
  const isAllPools = market.id === ALL_POOLS_ID
  const { address, isConnected } = useAccount()
  const { writeContract, isPending } = useWriteContract()
  const [error, setError] = useState<string | null>(null)
  const [livePending, setLivePending] = useState(false)
  const [previewRevealReady, setPreviewRevealReady] = useState(false)
  const previewRevealTimer = useRef<number | null>(null)
  const settlementTotal = market.pullPrice * count
  const paymentTotal =
    paymentAsset === market.asset
      ? settlementTotal
      : paymentAsset === "ETH"
        ? settlementTotal / 3500
        : settlementTotal * 3500
  const route = isAllPools ? undefined : getPullRouteConfig(market.id, paymentAsset, market.asset)
  const canSubmit = Boolean(isConnected && address && route?.nativeInput)
  const resetLocally = () => {
    if (previewRevealTimer.current !== null) window.clearTimeout(previewRevealTimer.current)
    setLivePending(false)
    onReset()
  }
  const revealPreviewNow = () => {
    if (previewRevealTimer.current !== null) window.clearTimeout(previewRevealTimer.current)
    previewRevealTimer.current = null
    onReveal()
  }

  useEffect(() => {
    if (stage !== "drawing" || livePending) {
      setPreviewRevealReady(false)
      return undefined
    }
    const readyTimer = window.setTimeout(() => setPreviewRevealReady(true), 1400)
    return () => window.clearTimeout(readyTimer)
  }, [livePending, stage])

  useEffect(
    () => () => {
      if (previewRevealTimer.current !== null) window.clearTimeout(previewRevealTimer.current)
    },
    [],
  )
  const requestPull = () => {
    spinAudio.prepare()
    if (!canSubmit || !route || !address || !drawRouterAddress) {
      setLivePending(false)
      spinAudio.start()
      onStage("drawing")
      previewRevealTimer.current = window.setTimeout(revealPreviewNow, 1700)
      return
    }
    setError(null)
    const settlementDecimals = market.asset === "USDG" ? 6 : 18
    const paymentDecimals = paymentAsset === "USDG" ? 6 : 18
    const order = {
      receiver: address,
      drawCount: count,
      maxUnitPrice: parseUnits(
        (market.pullPrice * 1.005).toFixed(settlementDecimals),
        settlementDecimals,
      ),
      maxTotalPrice: parseUnits(
        (settlementTotal * 1.005).toFixed(settlementDecimals),
        settlementDecimals,
      ),
      deadline: Math.floor(Date.now() / 1000) + 1200,
      referralCode: zeroHash,
    }
    const maxAmountIn = parseUnits((paymentTotal * 1.005).toFixed(paymentDecimals), paymentDecimals)
    writeContract(
      {
        address: drawRouterAddress,
        abi: drawRouterAbi,
        functionName: "swapAndPull",
        args: [route.marketAddress, route.inputAsset, maxAmountIn, order, route.routeData],
        value: route.nativeInput ? maxAmountIn : 0n,
      },
      {
        onSuccess: () => {
          setLivePending(true)
          spinAudio.start()
          onStage("drawing")
        },
        onError: (cause) => setError(cause.message),
      },
    )
  }
  if (stage === "drawing")
    return (
      <aside aria-live="polite" className="pull-command command-state">
        <Dices />
        <p>{livePending ? "Pull order submitted" : "Randomness requested"}</p>
        <h2>{livePending ? "Waiting for epoch result…" : "Shuffling your pack…"}</h2>
        <small>
          {livePending ? (
            "The verified result will appear once the epoch and indexer confirm it."
          ) : (
            <>
              <code>Preview mode</code> · committed root <code>0x8f71…94c2</code>
            </>
          )}
        </small>
        {!livePending && previewRevealReady ? (
          <button onClick={revealPreviewNow} type="button">
            Reveal now <ChevronDown />
          </button>
        ) : null}
      </aside>
    )
  if (stage === "revealed" && position)
    return (
      <aside aria-labelledby="settlement-heading" className="pull-command settlement-command">
        <div className="command-heading">
          <div>
            <p>Choose settlement</p>
            <h2 id="settlement-heading">{position.name}</h2>
          </div>
          <span className="asset-chip">{position.asset ?? market.asset}</span>
        </div>
        <p className="settlement-intro">
          Your position is revealed. Choose an exit or put it back to work.
        </p>
        <SettlementActions onSettle={onSettle} />
      </aside>
    )
  if (stage === "settled") {
    const label =
      settlementChoice === "cash"
        ? "Cash settlement claimed"
        : settlementChoice === "draw"
          ? "$DRAW delivered"
          : settlementChoice === "relist"
            ? "Position relisted"
            : "Collectible secured"
    return (
      <aside aria-live="polite" className="pull-command command-state settlement-done">
        <CircleCheck />
        <p>Pull complete</p>
        <h2>{label}</h2>
        <small>{position?.name} is now in your activity receipt.</small>
        <button onClick={resetLocally} type="button">
          Pull again <RotateCcw />
        </button>
      </aside>
    )
  }
  return (
    <aside className="pull-command" aria-label="Configure your pull">
      <div className="command-heading">
        <div>
          <p>Your pull</p>
          <h2>{market.name}</h2>
        </div>
        <span className="asset-chip">
          {isAllPools ? `${poolOptions.length - 1} pools` : market.asset}
        </span>
      </div>
      <div className="command-price">
        <span>{isAllPools ? "Eligible inventory" : "Current pull price"}</span>
        <strong>
          {isAllPools
            ? `${market.activePositions.toLocaleString()} live cards`
            : formatValue(settlementTotal, market.asset)}
        </strong>
        <small>
          {isAllPools
            ? `One random result across ${poolOptions.length - 1} active pools`
            : "Expected value + 10% markup"}
        </small>
      </div>
      <div className="count-control">
        <span>Quantity</span>
        <div>
          <button
            aria-label="Decrease pull quantity"
            disabled={count === 1}
            onClick={() => onCount(count - 1)}
            type="button"
          >
            <Minus />
          </button>
          <strong>{count}</strong>
          <button
            aria-label="Increase pull quantity"
            disabled={count === 5}
            onClick={() => onCount(count + 1)}
            type="button"
          >
            <Plus />
          </button>
        </div>
      </div>
      {!isAllPools ? (
        <fieldset className="asset-switch">
          <legend>Pay with</legend>
          {(["ETH", "USDG"] as const).map((asset) => (
            <button
              aria-pressed={paymentAsset === asset}
              className={paymentAsset === asset ? "is-active" : ""}
              key={asset}
              onClick={() => onPaymentAsset(asset)}
              type="button"
            >
              {asset}
              {asset !== market.asset ? <small>routed</small> : null}
            </button>
          ))}
        </fieldset>
      ) : null}
      <div className="command-total">
        <span>{isAllPools ? "Pool scope" : "Max spend"}</span>
        <strong>
          {isAllPools ? "Any active pool" : formatValue(paymentTotal * 1.005, paymentAsset)}
        </strong>
        <small>
          {isAllPools
            ? "Preview draw · settlement asset follows the revealed card"
            : "0.5% slippage protection · unused funds return"}
        </small>
      </div>
      {error ? (
        <p className="command-error" id="pull-error" role="alert">
          Unable to submit the pull. {error}
        </p>
      ) : null}
      <button
        aria-busy={isPending}
        aria-describedby={error ? "pull-error" : undefined}
        className="pull-cta"
        disabled={isPending}
        onClick={requestPull}
        type="button"
      >
        <Sparkles />{" "}
        {isPending ? "Check wallet…" : canSubmit ? "Sign and pull" : "Run preview pull"}
      </button>
      <p className="command-foot">
        <ShieldCheck />{" "}
        {canSubmit
          ? "Ready to submit protected order"
          : isAllPools
            ? "Preview mode · aggregate orders require a multi-market router"
            : paymentAsset === "USDG"
              ? "Preview mode · USDG approval flow is not enabled yet"
              : "Preview mode · configure route to transact"}
      </p>
    </aside>
  )
}

function SettlementActions({ onSettle }: { onSettle: PullExperienceProps["onSettle"] }) {
  return (
    <div className="settlement-actions">
      <button onClick={() => onSettle("keep")} type="button">
        <WalletCards />
        <span>
          <strong>Keep collectible</strong>
          <small>NFT + proof of draw</small>
        </span>
        <ChevronDown />
      </button>
      <button onClick={() => onSettle("cash")} type="button">
        <Coins />
        <span>
          <strong>Take cash</strong>
          <small>85% of backing</small>
        </span>
        <ChevronDown />
      </button>
      <button onClick={() => onSettle("draw")} type="button">
        <Sparkles />
        <span>
          <strong>Take $DRAW</strong>
          <small>Protected market swap</small>
        </span>
        <ChevronDown />
      </button>
      <button onClick={() => onSettle("relist")} type="button">
        <RotateCcw />
        <span>
          <strong>Relist position</strong>
          <small>Stay active and earn</small>
        </span>
        <ChevronDown />
      </button>
    </div>
  )
}

function RecentPulls() {
  return (
    <section className="recent-pulls" id="activity" aria-labelledby="live-activity-title">
      <div className="recent-pulls-heading">
        <div>
          <ReceiptText aria-hidden="true" />
          <h2 id="live-activity-title">Live activity</h2>
        </div>
        <span>
          <i aria-hidden="true" /> Live
        </span>
      </div>
      <div
        aria-label="Recent protocol activity"
        className="recent-pulls-scroll"
        role="region"
        tabIndex={0}
      >
        <table>
          <thead>
            <tr>
              <th scope="col">Position</th>
              <th className="recent-pulls-pool" scope="col">
                Pool
              </th>
              <th scope="col">Wallet</th>
              <th className="recent-pulls-drawn" scope="col">
                Drawn
              </th>
              <th scope="col">Value</th>
            </tr>
          </thead>
          <tbody>
            {recentDraws.map((draw) => (
              <tr key={draw.name}>
                <td>
                  <span className="recent-position">
                    <img alt="" src={draw.image} />
                    <strong>{draw.name}</strong>
                  </span>
                </td>
                <td className="recent-pulls-pool">{draw.market}</td>
                <td>
                  <span aria-label={draw.wallet} className="recent-wallet" title={draw.wallet}>
                    {shortenWallet(draw.wallet)}
                  </span>
                </td>
                <td className="recent-pulls-drawn">{draw.ago} ago</td>
                <td>{draw.value}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}
