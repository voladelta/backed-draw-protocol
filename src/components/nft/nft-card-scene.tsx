import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent as ReactKeyboardEvent,
  type PointerEvent as ReactPointerEvent,
  type Ref,
} from "react"
import { spinAudio } from "@/audio/spin-audio"
import {
  deckOrder,
  nextDeckIndex,
  resolveDeckRelease,
  rubberBandDrag,
  wrapIndex,
} from "@/components/nft/deck-motion"
import type { Market, Position, PullStage } from "@/types/protocol"
import "@/components/nft/nft-card.css"

export type DeckCycleRequest = { id: number; direction: -1 | 1; animate?: boolean }

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

type CardCssProperties = CSSProperties & Record<"--accent" | "--stack-index", string | number>

const VELOCITY_WINDOW_MS = 90
const DECK_COMMIT_DISTANCE_PX = 72
const THROW_DURATION_MS = 160
const FLIP_DURATION_MS = 680
const POINTER_IDLE_MS = 500
const RETURN_DURATION_MS = 180
const STACK_CARD_COUNT = 6

const prefersReducedMotion = () =>
  typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches

const hasFinePointer = () =>
  typeof window !== "undefined" && window.matchMedia("(hover: hover) and (pointer: fine)").matches

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

const setCardDrag = (card: HTMLDivElement, distance: number) => {
  card.style.setProperty("--drag-x", `${distance}px`)
  card.style.setProperty("--drag-rotation", `${distance * 0.025}deg`)
}

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
  interactive?: boolean
  onPointerDown?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerMove?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerUp?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerCancel?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onPointerLeave?: (event: ReactPointerEvent<HTMLDivElement>) => void
  onKeyDown?: (event: ReactKeyboardEvent<HTMLDivElement>) => void
  elementRef?: Ref<HTMLDivElement>
}

function TradingCard({
  position,
  asset,
  accent,
  faceUp,
  stackIndex,
  className = "",
  interactive = false,
  onPointerDown,
  onPointerMove,
  onPointerUp,
  onPointerCancel,
  onPointerLeave,
  onKeyDown,
  elementRef,
}: TradingCardProps) {
  const style: CardCssProperties = {
    "--accent": accent,
    "--stack-index": stackIndex,
  }

  return (
    <div
      ref={elementRef}
      className={`draw-card ${faceUp ? "is-face-up" : "is-face-down"} ${interactive ? "is-interactive" : ""} ${className}`}
      style={style}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerCancel}
      onPointerLeave={onPointerLeave}
      onKeyDown={onKeyDown}
      aria-label={
        interactive
          ? faceUp
            ? `Hide details for ${position.name}`
            : "Reveal the top collectible card"
          : undefined
      }
      aria-hidden={interactive ? undefined : true}
      aria-pressed={interactive ? faceUp : undefined}
      role={interactive ? "button" : undefined}
      tabIndex={interactive ? 0 : undefined}
    >
      <div className="draw-card__rotator">
        <CardBack hidden={faceUp} />
        <CardFront position={position} asset={asset} hidden={!faceUp} />
      </div>
      <span aria-hidden="true" className="draw-card__reveal-glow" />
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
  const finePointer = useMemo(hasFinePointer, [])
  const [faceUp, setFaceUp] = useState(stage === "revealed" || stage === "settled")
  const [throwDirection, setThrowDirection] = useState<-1 | 0 | 1>(0)
  const dragRef = useRef<DragState | null>(null)
  const throwingRef = useRef(false)
  const pointerFrameRef = useRef<number | null>(null)
  const pointerIdleTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const returnTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const throwTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const revealTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const lastCycleRequestRef = useRef(0)
  const revealAnnouncedRef = useRef(false)
  const activeCardRef = useRef<HTMLDivElement>(null)
  const restoreCardFocusRef = useRef(false)

  const positions = market.positions
  const selectedPosition =
    revealedPosition ?? positions[wrapIndex(activeIndex, positions.length)] ?? positions[0]
  const selectedAsset = selectedPosition?.asset ?? market.asset
  const stackOrder = deckOrder(positions.length, activeIndex).slice(0, STACK_CARD_COUNT)
  const canInspect = stage === "configure"
  const showFront = stage === "revealed" || stage === "settled" || (canInspect && faceUp)

  const resetCardPointer = useCallback((card: HTMLDivElement) => {
    if (pointerFrameRef.current !== null) cancelAnimationFrame(pointerFrameRef.current)
    pointerFrameRef.current = null
    if (pointerIdleTimerRef.current) clearTimeout(pointerIdleTimerRef.current)
    pointerIdleTimerRef.current = null
    card.classList.remove("is-pointer-active")
    card.querySelector<HTMLElement>(".draw-card__rotator")?.style.removeProperty("transform")
    card
      .querySelectorAll<HTMLElement>(
        ".draw-card__texture, .draw-card__shine, .draw-card__glare, .draw-card__art-foil",
      )
      .forEach((element) => {
        element.style.removeProperty("--pointer-x")
        element.style.removeProperty("--pointer-y")
        element.style.removeProperty("--background-x")
        element.style.removeProperty("--background-y")
        element.style.removeProperty("--pointer-distance")
      })
  }, [])

  const updateCardPointer = useCallback(
    (card: HTMLDivElement, clientX: number, clientY: number, pointerType: string) => {
      if (reducedMotion || !finePointer || pointerType !== "mouse") return
      const rect = card.getBoundingClientRect()
      const x = clamp((clientX - rect.left) / rect.width, 0, 1)
      const y = clamp((clientY - rect.top) / rect.height, 0, 1)
      const fromCenterX = x - 0.5
      const fromCenterY = y - 0.5
      const distance = clamp(Math.hypot(fromCenterX, fromCenterY) / 0.707, 0, 1)
      if (pointerFrameRef.current !== null) cancelAnimationFrame(pointerFrameRef.current)
      pointerFrameRef.current = requestAnimationFrame(() => {
        pointerFrameRef.current = null
        card.classList.add("is-pointer-active")
        const tiltX = -fromCenterY * 5
        const tiltY = fromCenterX * 6
        const rotationY = card.classList.contains("is-face-up") ? tiltY : 180 + tiltY
        const rotator = card.querySelector<HTMLElement>(".draw-card__rotator")
        if (rotator) {
          rotator.style.transform = `rotateX(${tiltX.toFixed(2)}deg) rotateY(${rotationY.toFixed(2)}deg)`
        }
        card
          .querySelectorAll<HTMLElement>(
            ".draw-card__texture, .draw-card__shine, .draw-card__glare, .draw-card__art-foil",
          )
          .forEach((element) => {
            element.style.setProperty("--pointer-x", `${(x * 100).toFixed(2)}%`)
            element.style.setProperty("--pointer-y", `${(y * 100).toFixed(2)}%`)
            element.style.setProperty("--background-x", `${(32 + x * 36).toFixed(2)}%`)
            element.style.setProperty("--background-y", `${(32 + y * 36).toFixed(2)}%`)
            element.style.setProperty("--pointer-distance", distance.toFixed(3))
          })
      })
      if (pointerIdleTimerRef.current) clearTimeout(pointerIdleTimerRef.current)
      pointerIdleTimerRef.current = setTimeout(() => resetCardPointer(card), POINTER_IDLE_MS)
    },
    [finePointer, reducedMotion, resetCardPointer],
  )

  const throwCard = useCallback(
    (exitDirection: -1 | 1, animate = true, preserveDrag = false) => {
      if (!canInspect || throwingRef.current || positions.length < 2) return
      throwingRef.current = true
      const activeCard = activeCardRef.current
      if (!preserveDrag && activeCard) setCardDrag(activeCard, 0)
      setFaceUp(false)
      onInspectionChange?.(false)
      spinAudio.prepare()
      spinAudio.start()
      spinAudio.settle()

      const finish = () => {
        if (activeCard) setCardDrag(activeCard, 0)
        onSelect(nextDeckIndex(activeIndex, positions.length))
        setThrowDirection(0)
        throwingRef.current = false
      }

      if (reducedMotion || !animate) {
        finish()
        return
      }
      setThrowDirection(exitDirection)
      throwTimerRef.current = setTimeout(finish, THROW_DURATION_MS)
    },
    [activeIndex, canInspect, onInspectionChange, onSelect, positions.length, reducedMotion],
  )

  const handlePointerDown = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      if (
        !canInspect ||
        throwingRef.current ||
        dragRef.current ||
        !event.isPrimary ||
        event.button !== 0
      )
        return
      if (returnTimerRef.current) clearTimeout(returnTimerRef.current)
      event.currentTarget.classList.remove("is-returning")
      event.currentTarget.classList.add("is-dragging")
      event.currentTarget.focus()
      event.currentTarget.setPointerCapture(event.pointerId)
      dragRef.current = {
        pointerId: event.pointerId,
        startX: event.clientX,
        samples: [{ x: event.clientX, time: performance.now() }],
        moved: false,
      }
      spinAudio.prepare()
      updateCardPointer(event.currentTarget, event.clientX, event.clientY, event.pointerType)
    },
    [canInspect, updateCardPointer],
  )

  const handlePointerMove = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>) => {
      updateCardPointer(event.currentTarget, event.clientX, event.clientY, event.pointerType)
      const drag = dragRef.current
      if (!drag || drag.pointerId !== event.pointerId) return
      const distance = event.clientX - drag.startX
      drag.moved ||= Math.abs(distance) > 5
      drag.samples.push({ x: event.clientX, time: performance.now() })
      if (drag.samples.length > 12) drag.samples.shift()
      setCardDrag(event.currentTarget, rubberBandDrag(distance, DECK_COMMIT_DISTANCE_PX))
    },
    [updateCardPointer],
  )

  const finishPointer = useCallback(
    (event: ReactPointerEvent<HTMLDivElement>, cancelled = false) => {
      const drag = dragRef.current
      if (!drag || drag.pointerId !== event.pointerId) return
      dragRef.current = null
      event.currentTarget.classList.remove("is-dragging")
      if (event.currentTarget.hasPointerCapture(event.pointerId)) {
        event.currentTarget.releasePointerCapture(event.pointerId)
      }

      const distance = event.clientX - drag.startX
      const release = resolveDeckRelease(
        distance,
        releaseVelocity(drag.samples),
        DECK_COMMIT_DISTANCE_PX,
      )
      resetCardPointer(event.currentTarget)

      if (!cancelled && release.commit) {
        throwCard(release.direction, true, true)
        return
      }

      const card = event.currentTarget
      card.classList.add("is-returning")
      requestAnimationFrame(() => setCardDrag(card, 0))
      returnTimerRef.current = setTimeout(
        () => card.classList.remove("is-returning"),
        RETURN_DURATION_MS,
      )
      if (!cancelled && !drag.moved) setFaceUp((current) => !current)
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
    throwCard(cycleRequest.direction, cycleRequest.animate)
  }, [cycleRequest, throwCard])

  useEffect(() => {
    if (!restoreCardFocusRef.current) return undefined
    restoreCardFocusRef.current = false
    const frame = window.requestAnimationFrame(() => activeCardRef.current?.focus())
    return () => window.cancelAnimationFrame(frame)
  }, [activeIndex])

  useEffect(() => {
    if (stage === "drawing") {
      if (activeCardRef.current) {
        resetCardPointer(activeCardRef.current)
        setCardDrag(activeCardRef.current, 0)
      }
      setFaceUp(false)
      revealAnnouncedRef.current = false
      onInspectionChange?.(false)
      return
    }
    if (stage === "revealed" || stage === "settled") setFaceUp(true)
  }, [onInspectionChange, resetCardPointer, stage])

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
      if (returnTimerRef.current) clearTimeout(returnTimerRef.current)
      if (pointerFrameRef.current !== null) cancelAnimationFrame(pointerFrameRef.current)
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
              interactive={canInspect}
              elementRef={activeCardRef}
              className={
                throwDirection ? `is-throwing-${throwDirection < 0 ? "left" : "right"}` : ""
              }
              onPointerDown={handlePointerDown}
              onPointerMove={handlePointerMove}
              onPointerUp={(event) => finishPointer(event)}
              onPointerCancel={(event) => finishPointer(event, true)}
              onPointerLeave={handlePointerLeave}
              onKeyDown={(event) => {
                if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
                  restoreCardFocusRef.current = true
                }
                if (event.key === "Enter" || event.key === " ") {
                  event.preventDefault()
                  setFaceUp((current) => !current)
                }
              }}
            />
          </div>
        )}
      </div>
    </div>
  )
}
