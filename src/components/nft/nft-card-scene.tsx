import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
} from "react"
import { spinAudio } from "@/audio/spin-audio"
import { deckOrder, resolveDeckRelease, wrapIndex } from "@/components/nft/deck-motion"
import type { Market, Position, PullStage } from "@/types/protocol"
import "@/components/nft/nft-card.css"

export type DeckCycleRequest = { id: number; direction: -1 | 1 }

type NftCardSceneProps = {
  market: Market
  activeIndex: number
  stage: PullStage
  revealedPosition?: Position
  onSelect: (index: number) => void
  cycleRequest?: DeckCycleRequest
  onInspectionChange?: (inspected: boolean) => void
  /** Fires once the reveal flip lands face-up (glow burst + confetti moment). */
  onRevealReady?: () => void
}

type DragState = {
  pointerId: number
  startX: number
  samples: Array<{ x: number; time: number }>
  moved: boolean
}

type CardCssProperties = CSSProperties &
  Record<
    | "--accent"
    | "--pointer-x"
    | "--pointer-y"
    | "--background-x"
    | "--background-y"
    | "--pointer-distance"
    | "--tilt-x"
    | "--tilt-y"
    | "--drag-x"
    | "--drag-rotation"
    | "--stack-index",
    string | number
  >

const VELOCITY_WINDOW_MS = 90
const DECK_COMMIT_DISTANCE_PX = 72
const THROW_DURATION_MS = 360
const FLIP_DURATION_MS = 680
const POINTER_IDLE_MS = 500
const STACK_CARD_COUNT = 6

const prefersReducedMotion = () =>
  typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches

const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max)

const releaseVelocity = (samples: DragState["samples"]) => {
  const cutoff = performance.now() - VELOCITY_WINDOW_MS
  const recent = samples.filter((sample) => sample.time >= cutoff)
  if (recent.length < 2) return 0
  const first = recent[0]
  const last = recent[recent.length - 1]
  return ((last.x - first.x) / Math.max(last.time - first.time, 1)) * 1000
}

const formatBacking = (value: number, asset: string) =>
  new Intl.NumberFormat("en-US", {
    maximumFractionDigits: asset === "ETH" ? 2 : 0,
  }).format(value)

const shortId = (id: string) => id.replace(/^#/, "").slice(-6).toUpperCase()

function CardBack({ hidden }: { hidden: boolean }) {
  return (
    <div className="draw-card__back" aria-hidden={hidden}>
      <div className="draw-card__back-inset">
        <div className="draw-card__back-orbit draw-card__back-orbit--outer" />
        <div className="draw-card__back-orbit draw-card__back-orbit--inner" />
        <div className="draw-card__back-mark">
          <span />
        </div>
        <strong>BACKED</strong>
        <small>DRAW PROTOCOL</small>
      </div>
    </div>
  )
}

function CardFront({
  position,
  asset,
  hidden,
}: {
  position: Position
  asset: string
  hidden: boolean
}) {
  return (
    <article className="draw-card__front" aria-hidden={hidden}>
      <div className="draw-card__frame">
        <header className="draw-card__header">
          <div>
            <span className="draw-card__eyebrow">{position.collection}</span>
            <h3>{position.name}</h3>
          </div>
          <div className="draw-card__value">
            <span>BACKED</span>
            <strong>{formatBacking(position.backing, asset)}</strong>
            <small>{asset}</small>
          </div>
        </header>

        <div className="draw-card__art">
          <img src={position.image} alt="" draggable="false" />
          <span className="draw-card__art-foil" aria-hidden="true" />
          <span className="draw-card__edition">1 / 1</span>
        </div>

        <div className="draw-card__details">
          <div className="draw-card__rarity-line">
            <span>ASSET-BACKED COLLECTIBLE</span>
            <span>{position.probability.toFixed(1)}% DRAW RATE</span>
          </div>

          <div className="draw-card__ability">
            <span className="draw-card__ability-gem" aria-hidden="true" />
            <div>
              <strong>Perpetual backing</strong>
              <p>Redeem the position for its underlying reserve or keep it in the draw.</p>
            </div>
          </div>

          <dl className="draw-card__stats">
            <div>
              <dt>Yield</dt>
              <dd>+{formatBacking(position.earnings, asset)}</dd>
            </div>
            <div>
              <dt>Reserve</dt>
              <dd>VERIFIED</dd>
            </div>
            <div>
              <dt>Serial</dt>
              <dd>#{shortId(position.id)}</dd>
            </div>
          </dl>

          <footer className="draw-card__footer">
            <span>BACKED DRAW</span>
            <span>ONCHAIN POSITION</span>
          </footer>
        </div>
      </div>
      <div className="draw-card__texture" aria-hidden="true" />
      <div className="draw-card__shine" aria-hidden="true" />
      <div className="draw-card__glare" aria-hidden="true" />
    </article>
  )
}

type TradingCardProps = {
  position: Position
  asset: string
  accent: string
  faceUp: boolean
  stackIndex: number
  className?: string
  dragX?: number
  interactive?: boolean
  onPointerDown?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerMove?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerUp?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerCancel?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerLeave?: (event: ReactPointerEvent<HTMLDivElement>) => void
}

function TradingCard({
  position,
  asset,
  accent,
  faceUp,
  stackIndex,
  className = "",
  dragX = 0,
  interactive = false,
  onPointerDown,
  onPointerMove,
  onPointerUp,
  onPointerCancel,
  onPointerLeave,
}: TradingCardProps) {
  const style: CardCssProperties = {
    "--accent": accent,
    "--pointer-x": "50%",
    "--pointer-y": "50%",
    "--background-x": "50%",
    "--background-y": "50%",
    "--pointer-distance": 0,
    "--tilt-x": "0deg",
    "--tilt-y": "0deg",
    "--drag-x": `${dragX}px`,
    "--drag-rotation": `${dragX * 0.025}deg`,
    "--stack-index": stackIndex,
  }

  return (
    <div
      className={`draw-card ${faceUp ? "is-face-up" : "is-face-down"} ${interactive ? "is-interactive" : ""} ${className}`}
      style={style}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerCancel}
      onPointerLeave={onPointerLeave}
      aria-label={interactive ? `${position.name} collectible card` : undefined}
      aria-hidden={interactive ? undefined : true}
    >
      <div className="draw-card__rotator">
        <CardBack hidden={faceUp} />
        <CardFront position={position} asset={asset} hidden={!faceUp} />
      </div>
    </div>
  )
}

export function NftCardScene({
  market,
  activeIndex,
  stage,
  revealedPosition,
  onSelect,
  cycleRequest,
  onInspectionChange,
  onRevealReady,
}: NftCardSceneProps) {
  const reducedMotion = useMemo(prefersReducedMotion, [])
  const [faceUp, setFaceUp] = useState(stage === "revealed" || stage === "settled")
  const [dragX, setDragX] = useState(0)
  const [throwDirection, setThrowDirection] = useState<-1 | 0 | 1>(0)
  const dragRef = useRef<DragState | null>(null)
  const throwingRef = useRef(false)
  const pointerIdleTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const throwTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const revealTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastCycleRequestRef = useRef(0)
  const revealAnnouncedRef = useRef(false)

  const positions = market.positions
  const selectedPosition =
    revealedPosition ?? positions[wrapIndex(activeIndex, positions.length)] ?? positions[0]
  const selectedAsset = selectedPosition?.asset ?? market.asset
  const stackOrder = deckOrder(positions.length, activeIndex).slice(0, STACK_CARD_COUNT)
  const canInspect = stage === "configure"
  const showFront = stage === "revealed" || stage === "settled" || (canInspect && faceUp)

  const resetCardPointer = useCallback((card: HTMLDivElement) => {
    if (pointerIdleTimerRef.current) clearTimeout(pointerIdleTimerRef.current)
    pointerIdleTimerRef.current = null
    card.classList.remove("is-pointer-active")
    card.style.setProperty("--pointer-x", "50%")
    card.style.setProperty("--pointer-y", "50%")
    card.style.setProperty("--background-x", "50%")
    card.style.setProperty("--background-y", "50%")
    card.style.setProperty("--pointer-distance", "0")
    card.style.setProperty("--tilt-x", "0deg")
    card.style.setProperty("--tilt-y", "0deg")
  }, [])

  const updateCardPointer = useCallback(
    (card: HTMLDivElement, clientX: number, clientY: number) => {
      if (reducedMotion) return
      card.classList.add("is-pointer-active")
      const rect = card.getBoundingClientRect()
      const x = clamp((clientX - rect.left) / rect.width, 0, 1)
      const y = clamp((clientY - rect.top) / rect.height, 0, 1)
      const fromCenterX = x - 0.5
      const fromCenterY = y - 0.5
      const distance = clamp(Math.hypot(fromCenterX, fromCenterY) / 0.707, 0, 1)
      card.style.setProperty("--pointer-x", `${(x * 100).toFixed(2)}%`)
      card.style.setProperty("--pointer-y", `${(y * 100).toFixed(2)}%`)
      card.style.setProperty("--background-x", `${(32 + x * 36).toFixed(2)}%`)
      card.style.setProperty("--background-y", `${(32 + y * 36).toFixed(2)}%`)
      card.style.setProperty("--pointer-distance", distance.toFixed(3))
      card.style.setProperty("--tilt-x", `${(-fromCenterY * 14).toFixed(2)}deg`)
      card.style.setProperty("--tilt-y", `${(fromCenterX * 16).toFixed(2)}deg`)
      if (pointerIdleTimerRef.current) clearTimeout(pointerIdleTimerRef.current)
      pointerIdleTimerRef.current = setTimeout(() => resetCardPointer(card), POINTER_IDLE_MS)
    },
    [reducedMotion, resetCardPointer],
  )

  const throwCard = useCallback(
    (direction: -1 | 1) => {
      if (!canInspect || throwingRef.current || positions.length < 2) return
      throwingRef.current = true
      setThrowDirection(direction)
      setDragX(0)
      setFaceUp(false)
      onInspectionChange?.(false)
      spinAudio.prepare()
      spinAudio.start()
      spinAudio.settle()

      const finish = () => {
        onSelect(wrapIndex(activeIndex + direction, positions.length))
        setThrowDirection(0)
        throwingRef.current = false
      }

      if (reducedMotion) {
        finish()
        return
      }
      throwTimerRef.current = setTimeout(finish, THROW_DURATION_MS)
    },
    [activeIndex, canInspect, onInspectionChange, onSelect, positions.length, reducedMotion],
  )

  const handlePointerDown = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (!canInspect || throwingRef.current) return
      event.currentTarget.setPointerCapture(event.pointerId)
      dragRef.current = {
        pointerId: event.pointerId,
        startX: event.clientX,
        samples: [{ x: event.clientX, time: performance.now() }],
        moved: false,
      }
      spinAudio.prepare()
      updateCardPointer(event.currentTarget, event.clientX, event.clientY)
    },
    [canInspect, updateCardPointer],
  )

  const handlePointerMove = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      updateCardPointer(event.currentTarget, event.clientX, event.clientY)
      const drag = dragRef.current
      if (!drag || drag.pointerId !== event.pointerId) return
      const distance = event.clientX - drag.startX
      drag.moved ||= Math.abs(distance) > 5
      drag.samples.push({ x: event.clientX, time: performance.now() })
      if (drag.samples.length > 12) drag.samples.shift()
      setDragX(distance)
    },
    [updateCardPointer],
  )

  const finishPointer = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>, cancelled = false) => {
      const drag = dragRef.current
      if (!drag || drag.pointerId !== event.pointerId) return
      dragRef.current = null
      if (event.currentTarget.hasPointerCapture(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId)
      }

      const distance = event.clientX - drag.startX
      const release = resolveDeckRelease(
        distance,
        releaseVelocity(drag.samples),
        DECK_COMMIT_DISTANCE_PX,
      )
      setDragX(0)
      resetCardPointer(event.currentTarget)

      if (!cancelled && release.commit) {
        throwCard(release.direction)
      } else if (!cancelled && !drag.moved) {
        setFaceUp((current) => !current)
      }
    },
    [resetCardPointer, throwCard],
  )

  const handlePointerLeave = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (!dragRef.current) resetCardPointer(event.currentTarget)
    },
    [resetCardPointer],
  )

  useEffect(() => {
    if (!cycleRequest || cycleRequest.id === lastCycleRequestRef.current) return
    lastCycleRequestRef.current = cycleRequest.id
    throwCard(cycleRequest.direction)
  }, [cycleRequest, throwCard])

  useEffect(() => {
    if (stage === "drawing") {
      setFaceUp(false)
      revealAnnouncedRef.current = false
      onInspectionChange?.(false)
      return
    }
    if (stage === "revealed" || stage === "settled") setFaceUp(true)
  }, [onInspectionChange, stage])

  useEffect(() => {
    if (stage !== "revealed" || revealAnnouncedRef.current) return
    revealAnnouncedRef.current = true
    const announce = () => onRevealReady?.()
    if (reducedMotion) {
      announce()
      return
    }
    revealTimerRef.current = setTimeout(announce, FLIP_DURATION_MS)
  }, [onRevealReady, reducedMotion, stage])

  useEffect(() => {
    if (stage === "configure") onInspectionChange?.(faceUp)
  }, [faceUp, onInspectionChange, stage])

  useEffect(
    () => () => {
      if (throwTimerRef.current) clearTimeout(throwTimerRef.current)
      if (revealTimerRef.current) clearTimeout(revealTimerRef.current)
      if (pointerIdleTimerRef.current) clearTimeout(pointerIdleTimerRef.current)
      spinAudio.stop()
    },
    [],
  )

  if (!selectedPosition) return null

  return (
    <div
      className={`draw-card-scene draw-card-scene--${stage} ${showFront ? "has-face-up-card" : ""}`}
    >
      <div className="draw-card-stage" aria-live="polite">
        {stage === "drawing" ? (
          <div className="draw-card-shuffle" aria-label="Shuffling draw positions">
            {stackOrder.slice(0, 5).map((positionIndex, index) => {
              const position = positions[positionIndex]
              return (
                <TradingCard
                  key={`${position.id}-${index}`}
                  position={position}
                  asset={position.asset ?? market.asset}
                  accent={position.accent || market.accent}
                  faceUp={false}
                  stackIndex={index}
                  className={`draw-card--shuffle draw-card--shuffle-${index + 1}`}
                />
              )
            })}
          </div>
        ) : (
          <div className="draw-card-stack">
            {stage === "configure" &&
              stackOrder
                .slice(1)
                .reverse()
                .map((positionIndex, reverseIndex) => {
                  const position = positions[positionIndex]
                  const stackIndex = stackOrder.length - reverseIndex - 1
                  return (
                    <TradingCard
                      key={`${position.id}-${stackIndex}`}
                      position={position}
                      asset={position.asset ?? market.asset}
                      accent={position.accent || market.accent}
                      faceUp={false}
                      stackIndex={stackIndex}
                      className="draw-card--stacked"
                    />
                  )
                })}

            <TradingCard
              key={`${selectedPosition.id}-${stage}`}
              position={selectedPosition}
              asset={selectedAsset}
              accent={selectedPosition.accent || market.accent}
              faceUp={showFront}
              stackIndex={0}
              dragX={dragX}
              interactive={canInspect}
              className={`${throwDirection ? `is-throwing-${throwDirection < 0 ? "left" : "right"}` : ""} ${dragRef.current ? "is-dragging" : ""}`}
              onPointerDown={handlePointerDown}
              onPointerMove={handlePointerMove}
              onPointerUp={(event) => finishPointer(event)}
              onPointerCancel={(event) => finishPointer(event, true)}
              onPointerLeave={handlePointerLeave}
            />
          </div>
        )}
      </div>
    </div>
  )
}
