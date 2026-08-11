const AUDIO_URL = "/audio/spin-tick.mp3"
const MIN_TICK_INTERVAL_MS = 26
const MIN_AUDIBLE_SPEED = 0.35
const FULL_VOLUME_SPEED = 4

type SpinAudioGraph = {
  context: AudioContext
  buffer: AudioBuffer | null
  bufferPromise: Promise<AudioBuffer | null>
}

const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max)

function createSpinAudio() {
  let graph: SpinAudioGraph | null = null
  let active = false
  let lastBucket: number | null = null
  let lastTickAt = 0

  const getGraph = () => {
    if (graph) return graph
    if (typeof window === "undefined" || !window.AudioContext) return null

    const context = new window.AudioContext()
    const nextGraph: SpinAudioGraph = {
      context,
      buffer: null,
      bufferPromise: Promise.resolve(null),
    }
    nextGraph.bufferPromise = fetch(AUDIO_URL)
      .then((response) => {
        if (!response.ok) throw new Error(`Unable to load spin audio: ${response.status}`)
        return response.arrayBuffer()
      })
      .then((data) => context.decodeAudioData(data))
      .then((buffer) => {
        nextGraph.buffer = buffer
        return buffer
      })
      .catch(() => null)
    graph = nextGraph
    return graph
  }

  const playTick = (volume: number, force = false) => {
    if (!graph?.buffer || graph.context.state !== "running") return

    const now = performance.now()
    if (!force && now - lastTickAt < MIN_TICK_INTERVAL_MS) return
    lastTickAt = now

    const source = graph.context.createBufferSource()
    const gain = graph.context.createGain()
    source.buffer = graph.buffer
    gain.gain.value = clamp(volume, 0, 0.55)
    source.connect(gain).connect(graph.context.destination)
    source.start()
    source.addEventListener("ended", () => {
      source.disconnect()
      gain.disconnect()
    })
  }

  return {
    prepare() {
      const audio = getGraph()
      if (!audio) return
      void audio.context.resume().catch(() => undefined)
      void audio.bufferPromise
    },
    start() {
      const audio = getGraph()
      if (!audio) return

      active = true
      lastBucket = null
      void audio.context.resume().catch(() => undefined)
      void audio.bufferPromise
    },
    update(speed: number, rotation: number, step: number) {
      if (!graph || !active || step <= 0) return

      const bucket = Math.round(rotation / step)
      if (lastBucket === null) {
        lastBucket = bucket
        return
      }
      if (bucket === lastBucket) return
      lastBucket = bucket

      const absoluteSpeed = Math.abs(speed)
      if (absoluteSpeed < MIN_AUDIBLE_SPEED) return
      const intensity = clamp(
        (absoluteSpeed - MIN_AUDIBLE_SPEED) / (FULL_VOLUME_SPEED - MIN_AUDIBLE_SPEED),
        0,
        1,
      )
      playTick(0.15 + intensity * 0.4)
    },
    settle() {
      if (!active) return

      playTick(0.45, true)
      active = false
      lastBucket = null
    },
    stop() {
      active = false
      lastBucket = null
    },
  }
}

export const spinAudio = createSpinAudio()
