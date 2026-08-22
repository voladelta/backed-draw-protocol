import { afterEach, describe, expect, it, vi } from "vitest"

const { addConfetti, constructConfetti } = vi.hoisted(() => ({
  addConfetti: vi.fn().mockResolvedValue(undefined),
  constructConfetti: vi.fn(),
}))

vi.mock("js-confetti", () => ({
  default: class MockJSConfetti {
    constructor(config: { canvas: HTMLCanvasElement }) {
      constructConfetti(config)
    }

    addConfetti = addConfetti
  },
}))

afterEach(() => {
  vi.clearAllMocks()
  vi.resetModules()
  vi.unstubAllGlobals()
})

describe("reveal confetti", () => {
  it("reuses one confetti instance for the same stage canvas", async () => {
    vi.stubGlobal("window", {
      matchMedia: vi.fn().mockReturnValue({ matches: false }),
    })
    const { launchRevealConfetti } = await import("./reveal-confetti")
    const canvas = {} as HTMLCanvasElement

    await launchRevealConfetti(canvas)
    await launchRevealConfetti(canvas)

    expect(constructConfetti).toHaveBeenCalledTimes(1)
    expect(constructConfetti).toHaveBeenCalledWith({ canvas })
    expect(addConfetti).toHaveBeenCalledTimes(2)
    expect(addConfetti).toHaveBeenCalledWith({
      confettiColors: ["#caff3a", "#eeffd2", "#70b9ff", "#ffffff", "#ffd166"],
      confettiNumber: 140,
      confettiRadius: 6,
    })
  })

  it("creates a separate instance for each stage canvas", async () => {
    vi.stubGlobal("window", {
      matchMedia: vi.fn().mockReturnValue({ matches: false }),
    })
    const { launchRevealConfetti } = await import("./reveal-confetti")
    const firstCanvas = {} as HTMLCanvasElement
    const secondCanvas = {} as HTMLCanvasElement

    await launchRevealConfetti(firstCanvas)
    await launchRevealConfetti(secondCanvas)

    expect(constructConfetti).toHaveBeenCalledTimes(2)
    expect(constructConfetti).toHaveBeenNthCalledWith(1, { canvas: firstCanvas })
    expect(constructConfetti).toHaveBeenNthCalledWith(2, { canvas: secondCanvas })
  })

  it("does not load confetti when reduced motion is requested", async () => {
    vi.stubGlobal("window", {
      matchMedia: vi.fn().mockReturnValue({ matches: true }),
    })
    const { launchRevealConfetti } = await import("./reveal-confetti")

    await launchRevealConfetti({} as HTMLCanvasElement)

    expect(constructConfetti).not.toHaveBeenCalled()
    expect(addConfetti).not.toHaveBeenCalled()
  })
})
