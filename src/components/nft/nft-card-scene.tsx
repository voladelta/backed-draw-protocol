import { Suspense, useEffect, useMemo, useRef, useState, type ReactNode } from "react"
import { Canvas, useFrame, useThree } from "@react-three/fiber"
import { ContactShadows, Image, MeshReflectorMaterial, RoundedBox, Text } from "@react-three/drei"
import { a, useSpring, type SpringValue } from "@react-spring/three"
import {
  AdditiveBlending,
  CanvasTexture,
  DoubleSide,
  Shape,
  SRGBColorSpace,
  type Mesh,
  type MeshBasicMaterial,
} from "three"
import { spinAudio } from "@/audio/spin-audio"
import { deckOrder, resolveDeckRelease, riffleOrder, wrapIndex } from "@/components/nft/deck-motion"
import type { Market, Position, PullStage } from "@/types/protocol"

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

const CARD_WIDTH = 2.62
const CARD_HEIGHT = 3.38
const CARD_DEPTH = 0.12
const CARD_RADIUS = 0.16
const DECK_EDGE_COLORS = ["#344630", "#293a27", "#20301f"] as const
const VELOCITY_WINDOW_MS = 90
const DECK_COMMIT_DISTANCE_PX = 72
const FLIP_PHASE_DURATION_MS = 160
const SHUFFLE_ROUNDS = 5
const prefersReducedMotion = () =>
  typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches
const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max)
const easeInCubic = (value: number) => value * value * value
const easeOutCubic = (value: number) => 1 - Math.pow(1 - value, 3)
const easeInOutCubic = (value: number) =>
  value < 0.5 ? 4 * value * value * value : 1 - Math.pow(-2 * value + 2, 3) / 2
const releaseVelocity = (samples: DragState["samples"]) => {
  const cutoff = performance.now() - VELOCITY_WINDOW_MS
  const recent = samples.filter((sample) => sample.time >= cutoff)
  if (recent.length < 2) return 0
  const last = recent[recent.length - 1]
  const first = recent[0]
  const elapsed = Math.max(last.time - first.time, 1)
  return ((last.x - first.x) / elapsed) * 1000
}

function createRoundedRectShape(width: number, height: number, radius: number) {
  const shape = new Shape()
  const left = -width / 2
  const right = width / 2
  const top = height / 2
  const bottom = -height / 2

  shape.moveTo(left + radius, top)
  shape.lineTo(right - radius, top)
  shape.quadraticCurveTo(right, top, right, top - radius)
  shape.lineTo(right, bottom + radius)
  shape.quadraticCurveTo(right, bottom, right - radius, bottom)
  shape.lineTo(left + radius, bottom)
  shape.quadraticCurveTo(left, bottom, left, bottom + radius)
  shape.lineTo(left, top - radius)
  shape.quadraticCurveTo(left, top, left + radius, top)
  return shape
}

function createBottomRoundedRectShape(width: number, height: number, radius: number) {
  const shape = new Shape()
  const left = -width / 2
  const right = width / 2
  const top = height / 2
  const bottom = -height / 2

  shape.moveTo(left, top)
  shape.lineTo(right, top)
  shape.lineTo(right, bottom + radius)
  shape.quadraticCurveTo(right, bottom, right - radius, bottom)
  shape.lineTo(left + radius, bottom)
  shape.quadraticCurveTo(left, bottom, left, bottom + radius)
  shape.lineTo(left, top)
  return shape
}

function drawRoundedRect(
  context: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  radius: number,
) {
  context.beginPath()
  context.moveTo(x + radius, y)
  context.arcTo(x + width, y, x + width, y + height, radius)
  context.arcTo(x + width, y + height, x, y + height, radius)
  context.arcTo(x, y + height, x, y, radius)
  context.arcTo(x, y, x + width, y, radius)
  context.closePath()
}

function createCanvasTexture(
  size: [number, number],
  draw: (context: CanvasRenderingContext2D, width: number, height: number) => void,
) {
  const canvas = document.createElement("canvas")
  canvas.width = size[0]
  canvas.height = size[1]
  const context = canvas.getContext("2d")
  if (context) draw(context, size[0], size[1])
  const texture = new CanvasTexture(canvas)
  texture.colorSpace = SRGBColorSpace
  return texture
}

function useCardTextures(accent: string) {
  return useMemo(() => {
    if (typeof document === "undefined") return null

    const fade = createCanvasTexture([8, 256], (context, width, height) => {
      const gradient = context.createLinearGradient(0, 0, 0, height)
      gradient.addColorStop(0, "rgba(4, 8, 4, 0)")
      gradient.addColorStop(0.68, "rgba(4, 8, 4, 0)")
      gradient.addColorStop(1, "rgba(4, 8, 4, 0.58)")
      context.fillStyle = gradient
      context.fillRect(0, 0, width, height)
    })

    const sheen = createCanvasTexture([256, 340], (context, width, height) => {
      context.clearRect(0, 0, width, height)
      drawRoundedRect(context, 0, 0, width, height, 22)
      context.clip()
      const gradient = context.createLinearGradient(0, 0, width * 0.92, height)
      gradient.addColorStop(0, "rgba(255, 255, 255, 0.13)")
      gradient.addColorStop(0.22, "rgba(255, 255, 255, 0.04)")
      gradient.addColorStop(0.46, "rgba(255, 255, 255, 0)")
      gradient.addColorStop(0.74, "rgba(255, 255, 255, 0.05)")
      gradient.addColorStop(1, "rgba(255, 255, 255, 0.01)")
      context.fillStyle = gradient
      context.fillRect(0, 0, width, height)
    })

    const hoverSheen = createCanvasTexture([512, 512], (context, width, height) => {
      context.clearRect(0, 0, width, height)
      context.save()
      context.translate(width / 2, height / 2)
      context.rotate(-0.24)
      const gradient = context.createLinearGradient(-82, 0, 82, 0)
      gradient.addColorStop(0, "rgba(255, 255, 255, 0)")
      gradient.addColorStop(0.38, "rgba(226, 255, 201, 0.08)")
      gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.72)")
      gradient.addColorStop(0.62, "rgba(210, 245, 255, 0.1)")
      gradient.addColorStop(1, "rgba(255, 255, 255, 0)")
      context.fillStyle = gradient
      context.fillRect(-100, -height, 200, height * 2)
      context.restore()
    })
    hoverSheen.offset.x = 0.45

    const back = createCanvasTexture([512, 680], (context, width, height) => {
      context.fillStyle = "#0b110b"
      context.fillRect(0, 0, width, height)
      context.save()
      drawRoundedRect(context, 0, 0, width, height, 44)
      context.clip()

      const glow = context.createRadialGradient(
        width / 2,
        height / 2,
        40,
        width / 2,
        height / 2,
        width * 0.72,
      )
      glow.addColorStop(0, "rgba(255, 255, 255, 0.06)")
      glow.addColorStop(1, "rgba(255, 255, 255, 0)")
      context.fillStyle = glow
      context.fillRect(0, 0, width, height)

      context.strokeStyle = "rgba(236, 246, 228, 0.05)"
      context.lineWidth = 2
      for (let x = -height; x < width + height; x += 46) {
        context.beginPath()
        context.moveTo(x, 0)
        context.lineTo(x + height, height)
        context.stroke()
      }

      context.strokeStyle = "rgba(236, 246, 228, 0.16)"
      context.lineWidth = 3
      drawRoundedRect(context, 26, 26, width - 52, height - 52, 30)
      context.stroke()

      context.save()
      context.translate(width / 2, height / 2)
      context.rotate(Math.PI / 4)
      const diamond = 92
      context.strokeStyle = accent
      context.globalAlpha = 0.9
      context.lineWidth = 5
      context.strokeRect(-diamond / 2, -diamond / 2, diamond, diamond)
      context.globalAlpha = 0.28
      context.lineWidth = 2
      context.strokeRect(-diamond, -diamond, diamond * 2, diamond * 2)
      context.restore()

      context.fillStyle = "rgba(232, 241, 226, 0.34)"
      context.font = "700 24px ui-monospace, SFMono-Regular, Menlo, monospace"
      context.textAlign = "center"
      if ("letterSpacing" in context) {
        ;(context as CanvasRenderingContext2D & { letterSpacing: string }).letterSpacing = "8px"
      }
      context.fillText("BACKED", width / 2, height - 66)
      context.restore()
    })

    return { fade, sheen, hoverSheen, back }
  }, [accent])
}

type HoverShine = {
  opacity: SpringValue<number>
  offset: SpringValue<number>
}

function AnimatedHoverSheen({ texture, shine }: { texture: CanvasTexture; shine: HoverShine }) {
  const material = useRef<MeshBasicMaterial>(null)
  const shape = useMemo(
    () => createRoundedRectShape(CARD_WIDTH - 0.1, CARD_HEIGHT - 0.1, CARD_RADIUS - 0.05),
    [],
  )

  useFrame(() => {
    texture.offset.x = shine.offset.get()
    if (material.current) material.current.opacity = shine.opacity.get()
  })

  return (
    <mesh position={[0, 0, 0.079]}>
      <shapeGeometry args={[shape, 8]} />
      <meshBasicMaterial
        ref={material}
        blending={AdditiveBlending}
        depthWrite={false}
        map={texture}
        opacity={0}
        toneMapped={false}
        transparent
      />
    </mesh>
  )
}

function CardFace({
  position,
  asset,
  shine,
  edgeColor,
}: {
  position: Position
  asset: Market["asset"]
  shine?: HoverShine
  edgeColor?: string
}) {
  const cardAsset = position.asset ?? asset
  const backing =
    cardAsset === "ETH"
      ? `${position.backing.toFixed(position.backing < 1 ? 3 : 2)} ETH`
      : `$${position.backing.toLocaleString("en-US", { maximumFractionDigits: 0 })}`
  const name = position.name.length > 25 ? `${position.name.slice(0, 24)}…` : position.name
  const collection =
    position.collection.length > 26 ? `${position.collection.slice(0, 25)}…` : position.collection
  const frameColor = edgeColor ?? position.accent
  const textures = useCardTextures(position.accent)
  const labelShape = useMemo(() => createBottomRoundedRectShape(2.5, 0.6, 0.1), [])
  return (
    <>
      {/* Body */}
      <RoundedBox args={[CARD_WIDTH, CARD_HEIGHT, CARD_DEPTH]} radius={CARD_RADIUS} smoothness={5}>
        <meshStandardMaterial
          color={frameColor}
          emissive={frameColor}
          emissiveIntensity={0.04}
          metalness={0.35}
          roughness={0.42}
        />
      </RoundedBox>

      {/* Back face */}
      <mesh position={[0, 0, -CARD_DEPTH / 2 - 0.002]} rotation-y={Math.PI}>
        <planeGeometry args={[CARD_WIDTH - 0.02, CARD_HEIGHT - 0.02]} />
        {textures ? (
          <meshBasicMaterial map={textures.back} toneMapped={false} />
        ) : (
          <meshBasicMaterial color="#0b110b" />
        )}
      </mesh>

      {/* Art inset directly into the single accent frame. */}
      <Image
        url={position.image}
        position={[0, 0.2, 0.07]}
        scale={[2.5, 2.86]}
        radius={0.1}
        toneMapped={false}
        transparent
      />
      {textures ? (
        <mesh position={[0, 0.2, 0.073]}>
          <planeGeometry args={[2.5, 2.86]} />
          <meshBasicMaterial map={textures.fade} transparent toneMapped={false} />
        </mesh>
      ) : null}

      {/* Label plate */}
      <group position={[0, -1.35, 0.072]}>
        <mesh>
          <shapeGeometry args={[labelShape, 8]} />
          <meshBasicMaterial color="#0a120a" toneMapped={false} />
        </mesh>
        <mesh position={[0, 0.295, 0.004]}>
          <planeGeometry args={[2.5, 0.016]} />
          <meshBasicMaterial color={position.accent} toneMapped={false} />
        </mesh>
        <Text
          anchorX="left"
          anchorY="middle"
          color="#93a28c"
          fontSize={0.072}
          letterSpacing={0.22}
          maxWidth={2.2}
          position={[-1.13, 0.175, 0.008]}
        >
          {collection.toUpperCase()}
        </Text>
        <Text
          anchorX="left"
          anchorY="middle"
          color="#f2f7ed"
          fontSize={0.152}
          fontWeight={700}
          maxWidth={2.2}
          position={[-1.13, 0.03, 0.008]}
        >
          {name}
        </Text>
        <Text
          anchorX="left"
          anchorY="middle"
          color="#8a9784"
          fontSize={0.088}
          position={[-1.13, -0.16, 0.008]}
        >{`${position.probability.toFixed(2)}% odds`}</Text>
        <Text
          anchorX="right"
          anchorY="middle"
          color={position.accent}
          fontSize={0.104}
          fontWeight={700}
          position={[1.13, -0.16, 0.008]}
        >
          {backing}
        </Text>
      </group>

      {/* Foil sheen */}
      {textures ? (
        <mesh position={[0, 0, 0.078]}>
          <planeGeometry args={[CARD_WIDTH, CARD_HEIGHT]} />
          <meshBasicMaterial
            blending={AdditiveBlending}
            depthWrite={false}
            map={textures.sheen}
            opacity={0.5}
            transparent
          />
        </mesh>
      ) : null}
      {textures && shine ? (
        <AnimatedHoverSheen shine={shine} texture={textures.hoverSheen} />
      ) : null}
    </>
  )
}

function FocusCard({
  position,
  asset,
  reveal,
  reduced,
  initialVelocity,
  onRest,
}: {
  position: Position
  asset: Market["asset"]
  reveal: boolean
  reduced: boolean
  initialVelocity: number
  onRest?: () => void
}) {
  const inner = useRef<import("three").Group>(null)
  const [tiltSpring, tiltApi] = useSpring(() => ({
    tiltX: 0,
    tiltY: 0,
    config: { tension: 210, friction: 18 },
  }))
  const onRestRef = useRef(onRest)
  const [spring, revealApi] = useSpring(() => ({
    rotation: reveal
      ? ([0.025, Math.PI, 0] as [number, number, number])
      : ([0.025, 0, 0] as [number, number, number]),
    scale: reveal ? 0.9 : 1.06,
    immediate: true,
  }))

  useEffect(() => {
    onRestRef.current = onRest
  }, [onRest])

  useEffect(() => {
    let cancelled = false
    revealApi.stop()

    if (!reveal) {
      revealApi.set({ rotation: [0.025, 0, 0], scale: 1.06 })
      return undefined
    }

    revealApi.set({ rotation: [0.025, Math.PI, 0], scale: 0.9 })
    void Promise.all(
      revealApi.start({
        rotation: [0.025, 0, 0],
        scale: 1.06,
        config: {
          tension: 190,
          friction: 15,
          velocity: clamp(initialVelocity, -3, 3) * 0.4,
        },
        immediate: reduced,
      }),
    ).then((results) => {
      if (!cancelled && results.every((result) => result.finished)) {
        onRestRef.current?.()
      }
    })

    return () => {
      cancelled = true
      revealApi.stop()
    }
  }, [initialVelocity, reduced, reveal, revealApi])

  useEffect(() => {
    if (reduced) return undefined
    const onMove = (event: PointerEvent) => {
      const nx = (event.clientX / window.innerWidth) * 2 - 1
      const ny = (event.clientY / window.innerHeight) * 2 - 1
      tiltApi.start({ tiltX: -ny * 0.07, tiltY: nx * 0.11 })
    }
    const onLeave = () => tiltApi.start({ tiltX: 0, tiltY: 0 })
    window.addEventListener("pointermove", onMove)
    document.documentElement.addEventListener("pointerleave", onLeave)
    return () => {
      window.removeEventListener("pointermove", onMove)
      document.documentElement.removeEventListener("pointerleave", onLeave)
    }
  }, [reduced, tiltApi])

  useFrame(({ clock }) => {
    const group = inner.current
    if (!group) return
    group.position.y = reduced ? 0 : Math.sin(clock.elapsedTime * 1.1) * 0.035
    group.rotation.x = tiltSpring.tiltX.get()
    group.rotation.y = tiltSpring.tiltY.get()
  })

  return (
    <a.group rotation={spring.rotation as never} scale={spring.scale}>
      <group ref={inner}>
        <CardFace asset={asset} position={position} />
      </group>
    </a.group>
  )
}

type DeckSlot = {
  x: number
  y: number
  z: number
  rotationX: number
  rotationY: number
  rotationZ: number
  scale: number
}

function deckSlot(slot: number, count: number, topFaceUp = false): DeckSlot {
  const depth = Math.min(slot, 11)
  const buried = slot > 11 ? (slot - 11) * 0.004 : 0
  const stackWeight = clamp((count - 1) / 10, 0, 1)
  const lateralStep = 0.006 + stackWeight * 0.007
  const verticalStep = 0.012 + stackWeight * 0.009
  const depthStep = 0.012 + stackWeight * 0.006
  return {
    x: depth * lateralStep,
    y: depth * -verticalStep,
    z: 0.18 - depth * depthStep - buried,
    rotationX: 0.025,
    rotationY: slot === 0 && topFaceUp ? 0 : Math.PI,
    rotationZ: 0,
    scale: slot === 0 ? 1.025 : 1.018,
  }
}

function PeekResponse({
  active,
  progress,
  children,
}: {
  active: boolean
  progress: SpringValue<number>
  children: ReactNode
}) {
  const group = useRef<import("three").Group>(null)
  useFrame(() => {
    if (!group.current) return
    const value = active ? progress.get() : 0
    group.current.position.y = value * -0.045
    group.current.position.z = value * 0.16
    group.current.rotation.y = value * -0.2
    group.current.scale.setScalar(1 + value * 0.012)
  })
  return <group ref={group}>{children}</group>
}

function DeckCard({
  position,
  asset,
  slot,
  count,
  peek,
  reduced,
  cycleRequest,
  faceUp,
  onAdvance,
  onCycleRequestHandled,
  onDraggingChange,
  onFlip,
  onPeek,
}: {
  position: Position
  asset: Market["asset"]
  slot: number
  count: number
  peek: SpringValue<number>
  reduced: boolean
  cycleRequest?: DeckCycleRequest
  faceUp: boolean
  onAdvance: () => void
  onCycleRequestHandled: (requestId: number) => void
  onDraggingChange: (dragging: boolean) => void
  onFlip: () => void
  onPeek: (progress: number, immediate?: boolean) => void
}) {
  const { size, viewport } = useThree()
  const drag = useRef<DragState | null>(null)
  const flipping = useRef(false)
  const routing = useRef(false)
  const mounted = useRef(true)
  const lastCycleRequest = useRef(cycleRequest?.id ?? 0)
  const base = deckSlot(slot, count, faceUp)
  const [{ x, y, z, rotationX, rotationY, rotationZ, scale, shineOpacity, shineOffset }, api] =
    useSpring(() => ({
      ...base,
      shineOpacity: 0,
      shineOffset: 0,
      config: { tension: 280, friction: 29, mass: 0.92 },
      immediate: reduced,
    }))

  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
      drag.current = null
      flipping.current = false
      onDraggingChange(false)
    }
  }, [onDraggingChange])

  useEffect(() => {
    if (routing.current || flipping.current || drag.current) return
    void api.start({
      ...deckSlot(slot, count, faceUp),
      shineOpacity: slot === 0 ? shineOpacity.get() : 0,
      config: { tension: slot === 0 ? 250 : 300, friction: 30, mass: 0.92 },
      immediate: reduced,
    })
  }, [api, count, faceUp, reduced, shineOpacity, slot])

  const returnToSlot = () => {
    onPeek(0)
    return api.start({
      ...deckSlot(slot, count, faceUp),
      shineOpacity: 0,
      shineOffset: 0,
      config: {
        tension: 310,
        friction: 29,
        mass: 0.9,
      },
      immediate: reduced,
    })
  }

  const flipToFront = async () => {
    if (slot !== 0 || faceUp || flipping.current || routing.current) return
    flipping.current = true
    onPeek(0, true)
    spinAudio.stop()
    onFlip()
    const front = deckSlot(0, count, true)

    if (reduced) {
      api.set({ ...front, shineOpacity: 0, shineOffset: 0 })
      flipping.current = false
      return
    }

    await Promise.all(
      api.start({
        z: 0.32,
        rotationX: 0.04,
        rotationY: Math.PI / 2,
        rotationZ: -0.012,
        scale: 1.04,
        shineOpacity: 0,
        config: (key) => ({
          duration: FLIP_PHASE_DURATION_MS,
          easing: key === "rotationY" ? easeInCubic : easeOutCubic,
        }),
      }),
    )
    if (!mounted.current) return
    await Promise.all(
      api.start({
        ...front,
        shineOpacity: 0,
        shineOffset: 0,
        config: (key) => ({
          duration: FLIP_PHASE_DURATION_MS,
          easing: key === "rotationY" ? easeOutCubic : easeInOutCubic,
        }),
      }),
    )
    flipping.current = false
  }

  const cycleToBack = async (direction: -1 | 1, velocityPx = 0) => {
    if (slot !== 0 || routing.current || flipping.current) return
    routing.current = true
    drag.current = null
    onDraggingChange(false)
    spinAudio.start()
    const worldVelocity = (velocityPx * viewport.width) / Math.max(size.width, 1)

    if (!reduced) {
      await Promise.all(
        api.start({
          x: direction * 2.35,
          y: 0.16,
          z: 0.62,
          rotationX: -0.035,
          rotationY: (faceUp ? 0 : Math.PI) + direction * 0.34,
          rotationZ: direction * -0.18,
          scale: 1.055,
          shineOpacity: 0,
          config: (key) => ({
            tension: 235,
            friction: 24,
            mass: 0.88,
            velocity: key === "x" ? direction * clamp(Math.abs(worldVelocity), 0, 2.4) : 0,
          }),
        }),
      )
    }
    if (!mounted.current) return

    onAdvance()
    onPeek(0, true)
    const back = deckSlot(count - 1, count)
    await Promise.all(
      api.start({
        x: direction * 2.55,
        y: back.y + 0.08,
        z: back.z - 0.18,
        rotationX: back.rotationX,
        rotationY: Math.PI + direction * 0.12,
        rotationZ: direction * 0.08,
        scale: back.scale,
        config: { tension: 245, friction: 27, mass: 0.94 },
        immediate: reduced,
      }),
    )
    if (!mounted.current) return
    await Promise.all(
      api.start({
        ...back,
        shineOpacity: 0,
        shineOffset: 0,
        config: { tension: 270, friction: 30, mass: 0.95 },
        immediate: reduced,
      }),
    )
    routing.current = false
    onPeek(0, true)
    spinAudio.settle()
  }

  useEffect(() => {
    if (
      !cycleRequest ||
      slot !== 0 ||
      routing.current ||
      cycleRequest.id === lastCycleRequest.current
    )
      return
    lastCycleRequest.current = cycleRequest.id
    onCycleRequestHandled(cycleRequest.id)
    void cycleToBack(cycleRequest.direction)
  })

  const settleDrag = () => {
    const current = drag.current
    if (!current) return
    drag.current = null
    onDraggingChange(false)
    const lastSample = current.samples[current.samples.length - 1]
    const distance = (lastSample?.x ?? current.startX) - current.startX
    const velocity = releaseVelocity(current.samples)
    const release = resolveDeckRelease(distance, velocity, DECK_COMMIT_DISTANCE_PX)
    if (!current.moved) {
      onPeek(0)
      spinAudio.stop()
      if (!faceUp) void flipToFront()
      else void returnToSlot()
      return
    }
    if (!release.commit) {
      void returnToSlot()
      spinAudio.stop()
      return
    }
    void cycleToBack(release.direction, velocity)
  }

  const interactive = slot === 0 && !routing.current
  return (
    <a.group
      onPointerCancel={interactive ? settleDrag : undefined}
      onPointerDown={
        interactive
          ? (event) => {
              if (routing.current || flipping.current) return
              event.stopPropagation()
              ;(
                event.target as unknown as {
                  setPointerCapture?: (pointerId: number) => void
                } | null
              )?.setPointerCapture?.(event.pointerId)
              api.stop()
              spinAudio.prepare()
              onDraggingChange(true)
              drag.current = {
                pointerId: event.pointerId,
                startX: event.clientX,
                samples: [{ x: event.clientX, time: performance.now() }],
                moved: false,
              }
              void api.start({
                z: z.get() + 0.06,
                scale: 1.035,
                shineOpacity: reduced ? 0 : 0.58,
                config: { tension: 360, friction: 29 },
                immediate: reduced,
              })
            }
          : undefined
      }
      onPointerMove={
        interactive
          ? (event) => {
              if (routing.current || flipping.current) return
              const current = drag.current
              if (!current || current.pointerId !== event.pointerId) {
                if (event.uv && !reduced) {
                  void api.start({ shineOffset: clamp(0.5 - event.uv.x, -0.42, 0.42) })
                }
                return
              }
              event.stopPropagation()
              const now = performance.now()
              const distancePx = event.clientX - current.startX
              const worldDistance = (distancePx * viewport.width) / Math.max(size.width, 1)
              const progress = clamp(Math.abs(distancePx) / DECK_COMMIT_DISTANCE_PX, 0, 1)
              current.samples.push({ x: event.clientX, time: now })
              current.samples = current.samples.filter(
                (sample) => now - sample.time <= VELOCITY_WINDOW_MS,
              )
              current.moved ||= Math.abs(distancePx) > 8
              onPeek(progress, true)
              api.set({
                x: worldDistance,
                y: Math.abs(worldDistance) * 0.055,
                z: 0.26 + Math.abs(worldDistance) * 0.11,
                rotationX: 0.025 - Math.abs(worldDistance) * 0.014,
                rotationY: (faceUp ? 0 : Math.PI) + worldDistance * 0.085,
                rotationZ: worldDistance * -0.11,
                shineOffset: clamp(-worldDistance * 0.18, -0.42, 0.42),
              })
            }
          : undefined
      }
      onPointerOut={
        interactive
          ? () => {
              if (routing.current || flipping.current) return
              if (!drag.current) void api.start({ shineOpacity: 0, shineOffset: 0 })
            }
          : undefined
      }
      onPointerOver={
        interactive
          ? () => {
              if (routing.current || flipping.current) return
              if (!drag.current && !reduced) void api.start({ shineOpacity: 0.72 })
            }
          : undefined
      }
      onPointerUp={
        interactive
          ? (event) => {
              if (routing.current || flipping.current) return
              if (drag.current?.pointerId !== event.pointerId) return
              settleDrag()
            }
          : undefined
      }
      position-x={x}
      position-y={y}
      position-z={z}
      rotation-x={rotationX}
      rotation-y={rotationY}
      rotation-z={rotationZ}
      scale={scale}
    >
      <PeekResponse active={slot === 1} progress={peek}>
        <CardFace
          asset={asset}
          edgeColor={
            slot === 0 ? undefined : DECK_EDGE_COLORS[(slot - 1) % DECK_EDGE_COLORS.length]
          }
          position={position}
          shine={{ offset: shineOffset, opacity: shineOpacity }}
        />
      </PeekResponse>
    </a.group>
  )
}

function InspectableDeck({
  positions,
  asset,
  activeIndex,
  reduced,
  cycleRequest,
  onInspectionChange,
  onSelect,
  onDraggingChange,
}: {
  positions: Position[]
  asset: Market["asset"]
  activeIndex: number
  reduced: boolean
  cycleRequest?: DeckCycleRequest
  onInspectionChange?: (inspected: boolean) => void
  onSelect: (index: number) => void
  onDraggingChange: (dragging: boolean) => void
}) {
  const [faceUp, setFaceUp] = useState(false)
  const order = deckOrder(positions.length, activeIndex)
  const slotByIndex = useMemo(
    () => new Map(order.map((positionIndex, slot) => [positionIndex, slot])),
    [order],
  )
  const [{ peek }, peekApi] = useSpring(() => ({
    peek: 0,
    config: { tension: 320, friction: 31 },
    immediate: reduced,
  }))
  const handledCycleRequest = useRef(cycleRequest?.id ?? 0)
  const pendingCycleRequest =
    cycleRequest && cycleRequest.id > handledCycleRequest.current
      ? { id: handledCycleRequest.current + 1, direction: cycleRequest.direction }
      : undefined
  const updatePeek = (progress: number, immediate = false) => {
    if (immediate) peek.set(reduced ? 0 : progress)
    else void peekApi.start({ peek: reduced ? 0 : progress })
  }

  useEffect(() => {
    setFaceUp(false)
    onInspectionChange?.(false)
  }, [activeIndex, onInspectionChange])

  return (
    <group position={[0, -0.08, 0]}>
      {positions
        .map((position, positionIndex) => ({
          position,
          positionIndex,
          slot: slotByIndex.get(positionIndex) ?? positions.length - 1,
        }))
        .sort((a, b) => b.slot - a.slot)
        .map(({ position, slot }) => (
          <DeckCard
            asset={asset}
            count={positions.length}
            cycleRequest={slot === 0 ? pendingCycleRequest : undefined}
            faceUp={slot === 0 && faceUp}
            key={position.id}
            onAdvance={() => {
              setFaceUp(false)
              onInspectionChange?.(false)
              onSelect(wrapIndex(activeIndex + 1, positions.length))
            }}
            onCycleRequestHandled={(requestId) => {
              handledCycleRequest.current = requestId
            }}
            onDraggingChange={onDraggingChange}
            onFlip={() => {
              setFaceUp(true)
              onInspectionChange?.(true)
            }}
            onPeek={updatePeek}
            peek={peek}
            position={position}
            reduced={reduced}
            slot={slot}
          />
        ))}
    </group>
  )
}

function ShuffleCard({
  position,
  asset,
  index,
  count,
  finalSlot,
  reduced,
  progress,
}: {
  position: Position
  asset: Market["asset"]
  index: number
  count: number
  finalSlot: number
  reduced: boolean
  progress: SpringValue<number>
}) {
  const group = useRef<import("three").Group>(null)
  const split = Math.ceil(count / 2)
  const inLeftPacket = index < split
  const packetIndex = inLeftPacket ? index : index - split
  const packetSide = inLeftPacket ? -1 : 1
  const start = deckSlot(index, count)
  const target = deckSlot(finalSlot, count)
  const smooth = (value: number) => value * value * (3 - 2 * value)

  useFrame(() => {
    const card = group.current
    if (!card) return
    const overall = reduced ? 1 : clamp(progress.get(), 0, 1)
    const scaled = overall * SHUFFLE_ROUNDS
    const round = overall >= 1 ? SHUFFLE_ROUNDS - 1 : Math.floor(scaled)
    const value = overall >= 1 ? 1 : scaled - round
    const side = packetSide * (round % 2 === 0 ? 1 : -1)
    const roundTarget = round === SHUFFLE_ROUNDS - 1 ? target : start
    let x = start.x
    let y = start.y
    let z = start.z
    let rotationX = start.rotationX
    let rotationZ = start.rotationZ
    let scale = start.scale

    if (value < 0.28) {
      const phase = smooth(value / 0.28)
      x = start.x + (side * 1.2 - start.x) * phase
      y = start.y + (0.1 + packetIndex * 0.04 - start.y) * phase
      z = start.z + (0.28 - packetIndex * 0.06 - start.z) * phase
      rotationX = start.rotationX + (side * -0.12 - start.rotationX) * phase
      rotationZ = start.rotationZ + (side * 0.11 - start.rotationZ) * phase
      scale = start.scale + (1 - start.scale) * phase
    } else if (value < 0.62) {
      const phase = smooth((value - 0.28) / 0.34)
      x = side * (1.2 - phase * 0.9)
      y = 0.1 + packetIndex * 0.04 + Math.sin(phase * Math.PI) * 0.17
      z = 0.28 - packetIndex * 0.06 + Math.sin(phase * Math.PI) * 0.16
      rotationX = side * (-0.12 + phase * 0.055)
      rotationZ = side * (0.11 - phase * 0.07)
      scale = 1
    } else {
      const stagger = (finalSlot / Math.max(count - 1, 1)) * 0.11
      const phase = smooth(clamp((value - 0.62 - stagger) / 0.22, 0, 1))
      x = side * 0.3 + (roundTarget.x - side * 0.3) * phase
      y = 0.1 + packetIndex * 0.035 + (roundTarget.y - 0.1 - packetIndex * 0.035) * phase
      z = 0.28 - packetIndex * 0.055 + (roundTarget.z - 0.28 + packetIndex * 0.055) * phase
      rotationX = side * -0.065 + (roundTarget.rotationX - side * -0.065) * phase
      rotationZ = side * 0.04 + (roundTarget.rotationZ - side * 0.04) * phase
      scale = 1 + (roundTarget.scale - 1) * phase
    }

    card.position.set(x, y, z)
    card.rotation.set(rotationX, Math.PI, rotationZ)
    card.scale.setScalar(scale)
  })

  return (
    <group ref={group}>
      <CardFace asset={asset} position={position} />
    </group>
  )
}

function ShufflingDeck({
  positions,
  asset,
  activeIndex,
  reduced,
}: {
  positions: Position[]
  asset: Market["asset"]
  activeIndex: number
  reduced: boolean
}) {
  const visibleCount = Math.min(positions.length, 10)
  const orderedIndices = deckOrder(positions.length, activeIndex).slice(0, visibleCount)
  const interleaved = riffleOrder(visibleCount)
  const finalSlotByInitialSlot = new Map(
    interleaved.map((initialSlot, finalSlot) => [initialSlot, finalSlot]),
  )
  const previousProgress = useRef(0)
  const [{ progress }] = useSpring(() => ({
    from: { progress: 0 },
    to: { progress: 1 },
    config: { duration: reduced ? 1 : 1450 },
    immediate: reduced,
    onRest: () => spinAudio.settle(),
  }))

  useFrame((_, delta) => {
    if (reduced) return
    const current = progress.get()
    const speed = ((current - previousProgress.current) / Math.max(delta, 0.001)) * 9
    previousProgress.current = current
    spinAudio.update(speed, current * SHUFFLE_ROUNDS * 12, 1)
  })
  useEffect(() => () => spinAudio.stop(), [])

  return (
    <group position={[0, -0.08, 0]}>
      {orderedIndices
        .map((positionIndex, initialSlot) => ({
          position: positions[positionIndex],
          initialSlot,
          finalSlot: finalSlotByInitialSlot.get(initialSlot) ?? initialSlot,
        }))
        .sort((a, b) => b.finalSlot - a.finalSlot)
        .map(({ position, initialSlot, finalSlot }) => (
          <ShuffleCard
            asset={asset}
            count={visibleCount}
            finalSlot={finalSlot}
            index={initialSlot}
            key={position.id}
            position={position}
            progress={progress}
            reduced={reduced}
          />
        ))}
    </group>
  )
}

function ArtifactDeck({
  market,
  activeIndex,
  stage,
  revealedPosition,
  onSelect,
  cycleRequest,
  onInspectionChange,
  onDraggingChange,
  onRevealReady,
}: Omit<NftCardSceneProps, "onRevealReady"> & {
  onDraggingChange: (dragging: boolean) => void
  onRevealReady: () => void
}) {
  const positions = market.positions
  const positionCount = positions.length
  const selectedIndex = positionCount === 0 ? 0 : wrapIndex(activeIndex, positionCount)
  const selectedPosition = positions[selectedIndex]
  const revealAnnounced = useRef(false)
  const reduced = prefersReducedMotion()

  useEffect(() => {
    if (stage === "drawing") revealAnnounced.current = false
  }, [stage])

  if (!selectedPosition) return null
  if (stage === "drawing") {
    return (
      <ShufflingDeck
        activeIndex={selectedIndex}
        asset={market.asset}
        positions={positions}
        reduced={reduced}
      />
    )
  }
  if (stage === "revealed" || stage === "settled") {
    const handleRevealRest =
      stage === "revealed"
        ? () => {
            if (revealAnnounced.current) return
            revealAnnounced.current = true
            onRevealReady()
          }
        : undefined
    return (
      <FocusCard
        asset={market.asset}
        initialVelocity={0}
        onRest={handleRevealRest}
        position={revealedPosition ?? selectedPosition}
        reduced={reduced}
        reveal={stage === "revealed"}
      />
    )
  }
  return (
    <InspectableDeck
      activeIndex={selectedIndex}
      asset={market.asset}
      cycleRequest={cycleRequest}
      onInspectionChange={onInspectionChange}
      onDraggingChange={onDraggingChange}
      onSelect={onSelect}
      positions={positions}
      reduced={reduced}
    />
  )
}

export function NftCardScene({ onRevealReady, ...props }: NftCardSceneProps) {
  const [dragging, setDragging] = useState(false)
  const { revealCard } = useCardRevealEffects()
  const handleRevealReady = () => {
    revealCard.trigger()
    onRevealReady?.()
  }
  return (
    <Canvas
      camera={{ position: [0, 0.1, 7.7], fov: 38 }}
      dpr={[1, 1.7]}
      gl={{ antialias: true, alpha: true }}
      style={{
        cursor: props.stage === "configure" ? (dragging ? "grabbing" : "grab") : "default",
        touchAction: "none",
      }}
    >
      <ambientLight intensity={0.55} />
      <hemisphereLight args={["#eaffcc", "#071007", 1.2]} />
      <directionalLight castShadow position={[4.5, 5.5, 6]} intensity={3.2} color="#eeffd2" />
      <pointLight position={[-4, 1.5, 2]} intensity={6} color="#caff3a" distance={8} />
      <pointLight position={[3, -1, 1]} intensity={2.5} color="#70b9ff" distance={7} />
      <mesh position={[0, -2.08, -1.2]} rotation-x={-Math.PI / 2}>
        <planeGeometry args={[24, 18]} />
        <MeshReflectorMaterial
          blur={[260, 70]}
          color="#091009"
          mixBlur={1}
          mixStrength={0.4}
          mirror={0.25}
          roughness={0.72}
        />
      </mesh>
      <ContactShadows opacity={0.46} position={[0, -2.02, 0]} scale={10} blur={2.5} far={4} />
      <RevealGlow effects={revealCard.effects} />
      <Suspense fallback={null}>
        <ArtifactDeck {...props} onDraggingChange={setDragging} onRevealReady={handleRevealReady} />
      </Suspense>
    </Canvas>
  )
}

/** Shared spring that drives the glow burst + shockwave ring on reveal. */
function useCardRevealEffects() {
  const reduced = useMemo(prefersReducedMotion, [])
  const [effects, api] = useSpring(() => ({
    progress: 0,
    config: { tension: 120, friction: 26 },
    immediate: true,
  }))
  const trigger = () => {
    if (reduced) return
    void api.start({
      from: { progress: 0 },
      to: { progress: 1 },
      config: { tension: 120, friction: 26 },
      immediate: false,
    })
  }
  return { revealCard: { effects, trigger }, reduced }
}

function RevealGlow({ effects }: { effects: { progress: SpringValue<number> } }) {
  const glowTexture = useMemo(() => {
    if (typeof document === "undefined") return null
    return createCanvasTexture([256, 256], (context, width, height) => {
      const gradient = context.createRadialGradient(
        width / 2,
        height / 2,
        8,
        width / 2,
        height / 2,
        width / 2,
      )
      gradient.addColorStop(0, "rgba(233, 255, 188, 0.9)")
      gradient.addColorStop(0.35, "rgba(202, 255, 58, 0.32)")
      gradient.addColorStop(1, "rgba(202, 255, 58, 0)")
      context.fillStyle = gradient
      context.fillRect(0, 0, width, height)
    })
  }, [])

  const glowMesh = useRef<Mesh>(null)
  const glowMaterial = useRef<MeshBasicMaterial>(null)
  const ringMesh = useRef<Mesh>(null)
  const ringMaterial = useRef<MeshBasicMaterial>(null)

  useFrame(() => {
    const value = clamp(effects.progress.get(), 0, 1)
    if (glowMesh.current && glowMaterial.current) {
      glowMaterial.current.opacity = Math.sin(value * Math.PI) * 0.5
      const scale = 1.5 + value * 1.3
      glowMesh.current.scale.set(scale, scale, 1)
    }
    if (ringMesh.current && ringMaterial.current) {
      ringMaterial.current.opacity =
        Math.max(0, Math.sin(Math.min(value * 1.15, 1) * Math.PI)) * 0.85
      const scale = 0.32 + value * 1.05
      ringMesh.current.scale.set(scale, scale, 1)
    }
  })

  return (
    <group position={[0, 0, -0.7]}>
      {glowTexture ? (
        <mesh ref={glowMesh}>
          <planeGeometry args={[3.6, 3.6]} />
          <meshBasicMaterial
            ref={glowMaterial}
            blending={AdditiveBlending}
            depthWrite={false}
            map={glowTexture}
            opacity={0}
            transparent
          />
        </mesh>
      ) : null}
      <mesh ref={ringMesh}>
        <ringGeometry args={[2.2, 2.28, 72]} />
        <meshBasicMaterial
          ref={ringMaterial}
          blending={AdditiveBlending}
          color="#e9ffbc"
          depthWrite={false}
          opacity={0}
          side={DoubleSide}
          transparent
        />
      </mesh>
    </group>
  )
}
