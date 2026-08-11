import { Suspense, useEffect, useMemo, useRef, useState } from "react"
import { Canvas, useFrame, useThree } from "@react-three/fiber"
import { ContactShadows, Image, MeshReflectorMaterial, RoundedBox, Text } from "@react-three/drei"
import { a, useSpring, type SpringValue } from "@react-spring/three"
import {
  AdditiveBlending,
  CanvasTexture,
  DoubleSide,
  SRGBColorSpace,
  type Mesh,
  type MeshBasicMaterial,
} from "three"
import { spinAudio } from "@/audio/spin-audio"
import type { Market, Position, PullStage } from "@/types/protocol"

type NftCardSceneProps = {
  market: Market
  activeIndex: number
  stage: PullStage
  revealedPosition?: Position
  onSelect: (index: number) => void
  /** Fires once the reveal flip lands face-up (glow burst + confetti moment). */
  onRevealReady?: () => void
}

type DragState = {
  pointerId: number
  startX: number
  startRotation: number
  targetRotation: number
  samples: Array<{ x: number; time: number }>
  moved: boolean
}

const CARD_WIDTH = 2.62
const CARD_HEIGHT = 3.38
const CARD_DEPTH = 0.12
const CARD_RADIUS = 0.16
const DRAG_RADIANS_PER_PIXEL = 0.0035
const IDLE_RADIANS_PER_SECOND = 0.012
const VELOCITY_WINDOW_MS = 90
const DECELERATION_RATE = 0.984
const MAX_RELEASE_VELOCITY = 4.4
const MOTION_BLUR_THRESHOLD = 0.15
const MAX_MOTION_BLUR_PX = 1.25
const BANK_LEAN = 0.05
const BANK_TILT = 0.016
const BANK_LERP_SPEED = 9
const prefersReducedMotion = () =>
  typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches
const modulo = (value: number, divisor: number) => ((value % divisor) + divisor) % divisor
const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max)
const nearestEquivalent = (target: number, current: number) =>
  target + Math.round((current - target) / (Math.PI * 2)) * Math.PI * 2
const projectMomentum = (velocity: number) =>
  (velocity / 1000) * (DECELERATION_RATE / (1 - DECELERATION_RATE))
const releaseVelocity = (samples: DragState["samples"]) => {
  const cutoff = performance.now() - VELOCITY_WINDOW_MS
  const recent = samples.filter((sample) => sample.time >= cutoff)
  if (recent.length < 2) return 0
  const last = recent[recent.length - 1]
  const first = recent[0]
  const elapsed = Math.max(last.time - first.time, 1)
  return ((last.x - first.x) / elapsed) * 1000 * DRAG_RADIANS_PER_PIXEL
}

function useMotionBlur(reduced: boolean) {
  const { gl } = useThree()
  const blur = useRef(0)
  const renderedBlur = useRef(0)

  useEffect(() => {
    const canvas = gl.domElement
    return () => {
      canvas.style.filter = ""
    }
  }, [gl])

  return (angularVelocity: number, delta: number) => {
    const target = reduced
      ? 0
      : Math.min(
          MAX_MOTION_BLUR_PX,
          Math.max(0, Math.abs(angularVelocity) - MOTION_BLUR_THRESHOLD) * 0.55,
        )
    const smoothing = 1 - Math.exp(-Math.min(delta, 0.05) * (target > blur.current ? 24 : 14))
    blur.current += (target - blur.current) * smoothing

    const nextBlur = blur.current < 0.02 ? 0 : Math.round(blur.current * 100) / 100
    if (nextBlur === renderedBlur.current) return
    renderedBlur.current = nextBlur
    gl.domElement.style.filter = nextBlur === 0 ? "" : `blur(${nextBlur}px)`
  }
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

    return { fade, sheen, back }
  }, [accent])
}

function CardFace({ position, asset }: { position: Position; asset: Market["asset"] }) {
  const backing =
    asset === "ETH"
      ? `${position.backing.toFixed(position.backing < 1 ? 3 : 2)} ETH`
      : `$${position.backing.toLocaleString("en-US", { maximumFractionDigits: 0 })}`
  const name = position.name.length > 25 ? `${position.name.slice(0, 24)}…` : position.name
  const collection =
    position.collection.length > 26 ? `${position.collection.slice(0, 25)}…` : position.collection
  const textures = useCardTextures(position.accent)
  return (
    <>
      {/* Body */}
      <RoundedBox args={[CARD_WIDTH, CARD_HEIGHT, CARD_DEPTH]} radius={CARD_RADIUS} smoothness={5}>
        <meshStandardMaterial color="#111611" metalness={0.55} roughness={0.34} />
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

      {/* Art with accent frame */}
      <mesh position={[0, 0.14, 0.066]}>
        <planeGeometry args={[2.5, 2.84]} />
        <meshBasicMaterial color={position.accent} toneMapped={false} />
      </mesh>
      <Image
        url={position.image}
        position={[0, 0.14, 0.07]}
        scale={[2.42, 2.76]}
        radius={0.1}
        toneMapped={false}
      />
      {textures ? (
        <mesh position={[0, 0.14, 0.073]}>
          <planeGeometry args={[2.42, 2.76]} />
          <meshBasicMaterial map={textures.fade} transparent toneMapped={false} />
        </mesh>
      ) : null}

      {/* Label plate */}
      <group position={[0, -1.35, 0.072]}>
        <mesh>
          <planeGeometry args={[2.5, 0.6]} />
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
            opacity={0.85}
            transparent
          />
        </mesh>
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
  const spring = useSpring({
    from: reveal
      ? { rotation: [0.025, Math.PI, 0] as [number, number, number], scale: 0.9 }
      : undefined,
    to: { rotation: [0.025, 0, 0] as [number, number, number], scale: 1.06 },
    config: { tension: 190, friction: 15, velocity: clamp(initialVelocity, -3, 3) * 0.4 },
    immediate: reduced,
    onRest: () => onRest?.(),
  })

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

function RingCard({
  position,
  asset,
  index,
  count,
  rotation,
  hovered,
  reduced,
  onHover,
  onSelect,
}: {
  position: Position
  asset: Market["asset"]
  index: number
  count: number
  rotation: SpringValue<number>
  hovered: boolean
  reduced: boolean
  onHover: (index: number | null) => void
  onSelect: (index: number) => void
}) {
  const { viewport } = useThree()
  const radiusX = Math.min(4.45, viewport.width * 0.43)
  const radiusZ = 3.25
  const baseAngle = (index / count) * Math.PI * 2
  const hover = useSpring({
    scale: hovered ? 1.055 : 1,
    y: hovered ? 0.09 : 0,
    config: { tension: 280, friction: 24 },
    immediate: reduced,
  })
  const orbitPosition = rotation.to((value) => {
    const angle = baseAngle + value
    const depth = (Math.cos(angle) + 1) / 2
    return [Math.sin(angle) * radiusX, -0.26 + depth * 0.34, -3.12 + Math.cos(angle) * radiusZ] as [
      number,
      number,
      number,
    ]
  })
  const orbitScale = rotation.to((value) => {
    const depth = (Math.cos(baseAngle + value) + 1) / 2
    return 0.42 + depth * 0.62
  })
  const orbitRotationY = rotation.to((value) => -Math.sin(baseAngle + value) * 0.56)
  const orbitRotationZ = rotation.to((value) => Math.sin(baseAngle + value) * -0.035)
  const orbitOpacity = rotation.to((value) => {
    const depth = (Math.cos(baseAngle + value) + 1) / 2
    return 0.34 + depth * 0.66
  })

  return (
    <a.group
      position={orbitPosition as never}
      rotation-y={orbitRotationY}
      rotation-z={orbitRotationZ}
      scale={orbitScale}
    >
      <a.group
        onClick={(event) => {
          event.stopPropagation()
          onSelect(index)
        }}
        onPointerOut={() => onHover(null)}
        onPointerOver={(event) => {
          event.stopPropagation()
          onHover(index)
        }}
        position-y={hover.y}
        scale={hover.scale}
      >
        {/* Depth veil: dims cards as they recede */}
        <a.mesh position={[0, 0, 0.082]}>
          <planeGeometry args={[CARD_WIDTH + 0.02, CARD_HEIGHT + 0.02]} />
          <a.meshBasicMaterial
            color="#050905"
            depthWrite={false}
            opacity={orbitOpacity.to((value) => 1 - value)}
            transparent
          />
        </a.mesh>
        <CardFace asset={asset} position={position} />
      </a.group>
    </a.group>
  )
}

function CircularRing({
  positions,
  asset,
  rotation,
  hovered,
  reduced,
  onHover,
  onSelect,
}: {
  positions: Position[]
  asset: Market["asset"]
  rotation: SpringValue<number>
  hovered: number | null
  reduced: boolean
  onHover: (index: number | null) => void
  onSelect: (index: number) => void
}) {
  return positions.map((position, index) => (
    <RingCard
      count={positions.length}
      asset={asset}
      hovered={hovered === index}
      index={index}
      key={position.id}
      onHover={onHover}
      onSelect={onSelect}
      position={position}
      reduced={reduced}
      rotation={rotation}
    />
  ))
}

/** Applies velocity-proportional lean/tilt banking to a spinning group. */
function useBanking(rotation: SpringValue<number>, reduced: boolean) {
  const group = useRef<import("three").Group>(null)
  const bank = useRef(0)
  const previousRotation = useRef(rotation.get())

  useFrame((_, delta) => {
    const currentRotation = rotation.get()
    const speed = (currentRotation - previousRotation.current) / Math.max(delta, 0.001)
    previousRotation.current = currentRotation
    const target = reduced ? 0 : clamp(speed * 0.04, -1, 1)
    const smoothing = 1 - Math.exp(-Math.min(delta, 0.05) * BANK_LERP_SPEED)
    bank.current += (target - bank.current) * smoothing
    if (group.current) {
      group.current.rotation.z = bank.current * BANK_LEAN
      group.current.rotation.x = -Math.abs(bank.current) * BANK_TILT
    }
  })

  return { group, bank }
}

function SpinningRing({
  positions,
  asset,
  activeIndex,
  reduced,
  onVelocity,
}: {
  positions: Position[]
  asset: Market["asset"]
  activeIndex: number
  reduced: boolean
  onVelocity?: (velocity: number) => void
}) {
  const step = (Math.PI * 2) / positions.length
  const previousRotation = useRef(-activeIndex * step)
  const applyMotionBlur = useMotionBlur(reduced)
  const spin = useSpring({
    from: { rotation: -activeIndex * step, scale: 0.96 },
    to: {
      rotation: -activeIndex * step + (reduced ? 0 : Math.PI * 2 * 3),
      scale: 1.015,
    },
    config: { mass: 2.1, tension: 26, friction: 11.5 },
    immediate: reduced,
    onRest: () => spinAudio.settle(),
  })
  const { group } = useBanking(spin.rotation, reduced)

  useFrame((_, delta) => {
    const currentRotation = spin.rotation.get()
    const speed = (currentRotation - previousRotation.current) / Math.max(delta, 0.001)
    previousRotation.current = currentRotation
    applyMotionBlur(speed, delta)
    spinAudio.update(speed, currentRotation, step)
    onVelocity?.(speed)
  })

  useEffect(() => () => spinAudio.stop(), [])

  return (
    <a.group scale={spin.scale}>
      <group ref={group}>
        <CircularRing
          asset={asset}
          hovered={null}
          onHover={() => undefined}
          onSelect={() => undefined}
          positions={positions}
          reduced={reduced}
          rotation={spin.rotation}
        />
      </group>
    </a.group>
  )
}

function ArtifactOrbit({
  market,
  activeIndex,
  stage,
  revealedPosition,
  onSelect,
  onDraggingChange,
  onRevealReady,
}: Omit<NftCardSceneProps, "onRevealReady"> & {
  onDraggingChange: (dragging: boolean) => void
  onRevealReady: () => void
}) {
  const positions = market.positions
  const positionCount = positions.length
  const selectedIndex = positionCount === 0 ? 0 : modulo(activeIndex, positionCount)
  const selectedPosition = positions[selectedIndex]
  const step = (Math.PI * 2) / Math.max(positionCount, 1)
  const drag = useRef<DragState | null>(null)
  const isSettling = useRef(false)
  const motionGeneration = useRef(0)
  const audioActive = useRef(false)
  const previousAudioRotation = useRef(-selectedIndex * step)
  const lastSelectedIndex = useRef(selectedIndex)
  const suppressClickUntil = useRef(0)
  const drawVelocity = useRef(0)
  const revealAnnounced = useRef(false)
  const [hovered, setHovered] = useState<number | null>(null)
  const reduced = prefersReducedMotion()
  const applyMotionBlur = useMotionBlur(reduced)
  const supportsHover =
    typeof window !== "undefined" && window.matchMedia("(hover: hover) and (pointer: fine)").matches
  const [{ rotation }, api] = useSpring(() => ({
    rotation: -selectedIndex * step,
    config: { tension: 175, friction: 24 },
    immediate: reduced,
  }))
  const { group: bankGroup } = useBanking(rotation, reduced)

  useEffect(() => {
    if (stage === "drawing") revealAnnounced.current = false
  }, [stage])

  useFrame((_, delta) => {
    if (stage !== "configure" || positionCount === 0) return
    const activeDrag = drag.current
    if (activeDrag) {
      rotation.set(activeDrag.targetRotation)
    } else if (!reduced && !isSettling.current) {
      const nextRotation = rotation.get() + IDLE_RADIANS_PER_SECOND * Math.min(delta, 0.05)
      rotation.set(nextRotation)
      const nextIndex = modulo(-Math.round(nextRotation / step), positionCount)
      if (nextIndex !== lastSelectedIndex.current) {
        lastSelectedIndex.current = nextIndex
        onSelect(nextIndex)
      }
    }
    const currentRotation = rotation.get()
    const speed = (currentRotation - previousAudioRotation.current) / Math.max(delta, 0.001)
    applyMotionBlur(speed, delta)
    if (audioActive.current) {
      spinAudio.update(speed, currentRotation, step)
    }
    previousAudioRotation.current = currentRotation
  })

  useEffect(() => () => spinAudio.stop(), [])

  useEffect(() => {
    if (drag.current || lastSelectedIndex.current === selectedIndex) return
    lastSelectedIndex.current = selectedIndex
    spinAudio.start()
    audioActive.current = true
    previousAudioRotation.current = rotation.get()
    const generation = ++motionGeneration.current
    isSettling.current = true
    void api.start({
      rotation: nearestEquivalent(-selectedIndex * step, rotation.get()),
      config: { tension: 175, friction: 24 },
      immediate: reduced,
      onRest: () => {
        if (motionGeneration.current === generation) {
          isSettling.current = false
          if (audioActive.current) {
            audioActive.current = false
            spinAudio.settle()
          }
        }
      },
    })
  }, [api, reduced, rotation, selectedIndex, step])

  if (!selectedPosition) return null
  if (stage === "drawing") {
    return (
      <SpinningRing
        activeIndex={selectedIndex}
        asset={market.asset}
        onVelocity={(velocity) => {
          drawVelocity.current = velocity
        }}
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
        initialVelocity={stage === "revealed" ? drawVelocity.current : 0}
        onRest={handleRevealRest}
        position={revealedPosition ?? selectedPosition}
        reduced={reduced}
        reveal={stage === "revealed"}
      />
    )
  }

  const selectCard = (index: number) => {
    if (performance.now() < suppressClickUntil.current) return
    const nextIndex = modulo(index, positionCount)
    lastSelectedIndex.current = nextIndex
    spinAudio.start()
    audioActive.current = true
    previousAudioRotation.current = rotation.get()
    const generation = ++motionGeneration.current
    isSettling.current = true
    void api.start({
      rotation: nearestEquivalent(-nextIndex * step, rotation.get()),
      config: { tension: 175, friction: 24 },
      immediate: reduced,
      onRest: () => {
        if (motionGeneration.current === generation) {
          isSettling.current = false
          audioActive.current = false
          spinAudio.settle()
        }
      },
    })
    onSelect(nextIndex)
  }

  const settleDrag = () => {
    const current = drag.current
    if (!current) return
    drag.current = null
    onDraggingChange(false)
    if (!current.moved) {
      isSettling.current = false
      audioActive.current = false
      spinAudio.stop()
      return
    }
    rotation.set(current.targetRotation)
    const velocity = clamp(
      releaseVelocity(current.samples),
      -MAX_RELEASE_VELOCITY,
      MAX_RELEASE_VELOCITY,
    )
    const currentRotation = current.targetRotation
    const projectedRotation = reduced
      ? currentRotation
      : currentRotation + projectMomentum(velocity)
    const snappedRotation = Math.round(projectedRotation / step) * step
    const nextIndex = modulo(-Math.round(snappedRotation / step), positionCount)
    if (current.moved) suppressClickUntil.current = performance.now() + 180
    lastSelectedIndex.current = nextIndex
    const generation = ++motionGeneration.current
    isSettling.current = true
    void api.start({
      rotation: snappedRotation,
      config: {
        mass: 1.4,
        tension: 58,
        friction: 13,
        velocity: reduced ? 0 : velocity,
      },
      immediate: reduced,
      onRest: () => {
        if (motionGeneration.current === generation) {
          isSettling.current = false
          audioActive.current = false
          spinAudio.settle()
        }
      },
    })
    onSelect(nextIndex)
  }

  return (
    <group
      onPointerCancel={settleDrag}
      onPointerDown={(event) => {
        event.stopPropagation()
        ;(
          event.target as unknown as { setPointerCapture?: (pointerId: number) => void } | null
        )?.setPointerCapture?.(event.pointerId)
        motionGeneration.current += 1
        api.stop()
        isSettling.current = false
        spinAudio.start()
        audioActive.current = true
        previousAudioRotation.current = rotation.get()
        onDraggingChange(true)
        const now = performance.now()
        drag.current = {
          pointerId: event.pointerId,
          startX: event.clientX,
          startRotation: rotation.get(),
          targetRotation: rotation.get(),
          samples: [{ x: event.clientX, time: now }],
          moved: false,
        }
      }}
      onPointerMove={(event) => {
        const current = drag.current
        if (!current || current.pointerId !== event.pointerId) return
        const now = performance.now()
        const delta = event.clientX - current.startX
        current.targetRotation = current.startRotation + delta * DRAG_RADIANS_PER_PIXEL
        current.samples.push({ x: event.clientX, time: now })
        current.samples = current.samples.filter(
          (sample) => now - sample.time <= VELOCITY_WINDOW_MS,
        )
        current.moved ||= Math.abs(delta) > 5
      }}
      onPointerUp={(event) => {
        if (drag.current?.pointerId !== event.pointerId) return
        settleDrag()
      }}
    >
      <group ref={bankGroup}>
        <CircularRing
          asset={market.asset}
          hovered={hovered}
          onHover={(index) => setHovered(supportsHover ? index : null)}
          onSelect={selectCard}
          positions={positions}
          reduced={reduced}
          rotation={rotation}
        />
      </group>
    </group>
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
        <ArtifactOrbit
          {...props}
          onDraggingChange={setDragging}
          onRevealReady={handleRevealReady}
        />
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
