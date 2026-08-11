import { Suspense, useEffect, useRef, useState } from "react"
import { Canvas, useFrame, useThree } from "@react-three/fiber"
import { ContactShadows, Image, MeshReflectorMaterial, RoundedBox, Text } from "@react-three/drei"
import { a, useSpring, type SpringValue } from "@react-spring/three"
import { spinAudio } from "@/audio/spin-audio"
import type { Market, Position, PullStage } from "@/types/protocol"

type NftCardSceneProps = {
  market: Market
  activeIndex: number
  stage: PullStage
  revealedPosition?: Position
  onSelect: (index: number) => void
}

type DragState = {
  pointerId: number
  startX: number
  startRotation: number
  targetRotation: number
  samples: Array<{ x: number; time: number }>
  moved: boolean
}

const DRAG_RADIANS_PER_PIXEL = 0.0035
const IDLE_RADIANS_PER_SECOND = 0.012
const VELOCITY_WINDOW_MS = 90
const DECELERATION_RATE = 0.982
const MOTION_BLUR_THRESHOLD = 0.15
const MAX_MOTION_BLUR_PX = 1.25
const prefersReducedMotion = () =>
  typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches
const modulo = (value: number, divisor: number) => ((value % divisor) + divisor) % divisor
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

function CardFace({ position, asset }: { position: Position; asset: Market["asset"] }) {
  const backing =
    asset === "ETH"
      ? `${position.backing.toFixed(position.backing < 1 ? 3 : 2)} ETH`
      : `$${position.backing.toLocaleString("en-US", { maximumFractionDigits: 0 })}`
  const name = position.name.length > 25 ? `${position.name.slice(0, 24)}…` : position.name
  return (
    <>
      <RoundedBox args={[2.62, 3.38, 0.12]} radius={0.16} smoothness={5}>
        <meshStandardMaterial color="#101510" metalness={0.76} roughness={0.19} />
      </RoundedBox>
      <Image
        url={position.image}
        position={[0, 0.12, 0.071]}
        scale={[2.39, 2.7]}
        radius={0.08}
        toneMapped={false}
      />
      <mesh position={[0, -1.33, 0.08]}>
        <planeGeometry args={[2.4, 0.06]} />
        <meshBasicMaterial color={position.accent} />
      </mesh>
      <group position={[0, -1.39, 0.095]}>
        <mesh>
          <planeGeometry args={[2.3, 0.46]} />
          <meshBasicMaterial color="#071007" opacity={0.88} transparent />
        </mesh>
        <Text
          anchorX="left"
          anchorY="middle"
          color="#f0f5eb"
          fontSize={0.145}
          maxWidth={1.9}
          position={[-1.02, 0.085, 0.008]}
        >
          {name}
        </Text>
        <Text
          anchorX="left"
          anchorY="middle"
          color="#a8b5a1"
          fontSize={0.09}
          position={[-1.02, -0.095, 0.008]}
        >{`${position.probability.toFixed(2)}% odds`}</Text>
        <Text
          anchorX="right"
          anchorY="middle"
          color={position.accent}
          fontSize={0.09}
          position={[1.02, -0.095, 0.008]}
        >
          {backing}
        </Text>
      </group>
    </>
  )
}

function FocusCard({
  position,
  asset,
  reveal,
  reduced,
}: {
  position: Position
  asset: Market["asset"]
  reveal: boolean
  reduced: boolean
}) {
  const spring = useSpring({
    from: reveal
      ? { rotation: [0.025, Math.PI, 0] as [number, number, number], scale: 0.92 }
      : undefined,
    to: { rotation: [0.025, 0, 0] as [number, number, number], scale: 1.06 },
    config: { tension: 170, friction: 20 },
    immediate: reduced,
  })

  return (
    <a.group rotation={spring.rotation as never} scale={spring.scale}>
      <CardFace asset={asset} position={position} />
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

function SpinningRing({
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
  const step = (Math.PI * 2) / positions.length
  const previousRotation = useRef(-activeIndex * step)
  const applyMotionBlur = useMotionBlur(reduced)
  const spin = useSpring({
    from: { rotation: -activeIndex * step, scale: 0.96 },
    to: {
      rotation: -activeIndex * step + (reduced ? 0 : Math.PI * 2),
      scale: 1.015,
    },
    config: { mass: 1.5, tension: 28, friction: 12 },
    immediate: reduced,
    onRest: () => spinAudio.settle(),
  })

  useFrame((_, delta) => {
    const currentRotation = spin.rotation.get()
    const speed = (currentRotation - previousRotation.current) / Math.max(delta, 0.001)
    previousRotation.current = currentRotation
    applyMotionBlur(speed, delta)
    spinAudio.update(speed, currentRotation, step)
  })

  useEffect(() => () => spinAudio.stop(), [])

  return (
    <a.group scale={spin.scale}>
      <CircularRing
        asset={asset}
        hovered={null}
        onHover={() => undefined}
        onSelect={() => undefined}
        positions={positions}
        reduced={reduced}
        rotation={spin.rotation}
      />
    </a.group>
  )
}

function ArtifactOrbit({
  market,
  activeIndex,
  stage,
  revealedPosition,
  onSelect,
}: NftCardSceneProps) {
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
        positions={positions}
        reduced={reduced}
      />
    )
  }
  if (stage === "revealed" || stage === "settled") {
    return (
      <FocusCard
        asset={market.asset}
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
    if (!current.moved) {
      isSettling.current = false
      audioActive.current = false
      spinAudio.stop()
      return
    }
    rotation.set(current.targetRotation)
    const velocity = releaseVelocity(current.samples)
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
        mass: 1.5,
        tension: 65,
        friction: 17,
        velocity: reduced ? 0 : Math.max(-2.8, Math.min(2.8, velocity)),
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
  )
}

export function NftCardScene(props: NftCardSceneProps) {
  return (
    <Canvas
      camera={{ position: [0, 0.1, 7.7], fov: 38 }}
      dpr={[1, 1.7]}
      gl={{ antialias: true, alpha: true }}
      style={{ cursor: props.stage === "configure" ? "grab" : "default", touchAction: "none" }}
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
      <Suspense fallback={null}>
        <ArtifactOrbit {...props} />
      </Suspense>
    </Canvas>
  )
}
